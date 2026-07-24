pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs.modules.common
import qs.services

Singleton {
    id: root

    // ─── State Enum ───
    enum State { Idle, Running, Paused }

    // ─── Public Properties ───
    property int state: DemoDriverService.State.Idle
    property string currentSceneName: ""
    property string currentSceneDescription: ""
    property int scenesCompleted: 0
    property int scenesTotal: 0
    property real speedMultiplier: 1.0

    // Pacing configuration
    property int actionDelay: 800      // ms between actions within a scene
    property int sceneDelay: 2000      // ms between scenes in a tour
    readonly property real minSpeed: 0.5
    readonly property real maxSpeed: 3.0

    // ─── Signals ───
    signal sceneStarted(string name, string description)
    signal sceneCompleted(string name, bool success)
    signal tourStarted(int totalScenes)
    signal tourCompleted(bool cancelled)

    // ─── Desktop State Snapshot ───
    property var _preState: null

    // ─── Execution Queue ───
    property var _queue: []
    property int _queueIndex: 0
    property var _currentActions: []
    property int _actionIndex: 0

    // ─── Public API ───

    function start(filter, filterType) {
        if (root.state !== DemoDriverService.State.Idle) stop()

        _captureDesktopState()
        root.speedMultiplier = Math.max(root.minSpeed,
                                Math.min(root.maxSpeed, root.speedMultiplier))

        var scenes = DemoScenes.getScenes(filter, filterType)
        root._queue = scenes
        root._queueIndex = 0
        root.scenesTotal = scenes.length
        root.scenesCompleted = 0
        root.state = DemoDriverService.State.Running
        root.tourStarted(scenes.length)
        _executeNextScene()
    }

    function stop() {
        _actionTimer.stop()
        _sceneTimer.stop()
        root.state = DemoDriverService.State.Idle
        root.currentSceneName = ""
        _restoreDesktopState()
        root.tourCompleted(true)
    }

    function pause() {
        if (root.state === DemoDriverService.State.Running) {
            _actionTimer.stop()
            root.state = DemoDriverService.State.Paused
        }
    }

    function resume() {
        if (root.state === DemoDriverService.State.Paused) {
            root.state = DemoDriverService.State.Running
            _advanceAction()
        }
    }

    function toggle() {
        if (root.state === DemoDriverService.State.Idle) start()
        else stop()
    }

    function listScenes() {
        return JSON.stringify(DemoScenes.registry)
    }

    function estimatedDuration() {
        return DemoScenes.getTotalDuration(root.speedMultiplier)
    }

    // ─── Internal: Scene Execution ───

    function _executeNextScene() {
        if (root._queueIndex >= root._queue.length) {
            // Tour complete
            root.state = DemoDriverService.State.Idle
            root.currentSceneName = ""
            _restoreDesktopState()
            root.tourCompleted(false)
            return
        }

        var scene = root._queue[root._queueIndex]

        // State guard check
        if (!_checkGuards(scene)) {
            console.warn("[DemoDriver] Guard failed for: " + scene.name)
            root.sceneCompleted(scene.name, false)
            root._queueIndex++
            root.scenesCompleted++
            _sceneTimer.interval = _effectiveDelay(root.sceneDelay)
            _sceneTimer.start()
            return
        }

        root.currentSceneName = scene.name
        root.currentSceneDescription = scene.description
        root._currentActions = scene.actions
        root._actionIndex = 0
        root.sceneStarted(scene.name, scene.description)
        _advanceAction()
    }

    function _advanceAction() {
        if (root.state !== DemoDriverService.State.Running) return
        if (root._actionIndex >= root._currentActions.length) {
            // Scene complete — verify post-conditions
            _verifyPostConditions(root._queue[root._queueIndex])
            root.sceneCompleted(root.currentSceneName, true)
            root._queueIndex++
            root.scenesCompleted++
            _sceneTimer.interval = _effectiveDelay(root.sceneDelay)
            _sceneTimer.start()
            return
        }

        var action = root._currentActions[root._actionIndex]
        _executeAction(action)
        root._actionIndex++
        _actionTimer.interval = _effectiveDelay(
            action.delay !== undefined ? action.delay : root.actionDelay)
        _actionTimer.start()
    }

    function _executeAction(action) {
        switch (action.type) {
            case "ipc":
                Quickshell.execDetached(["quickshell", "-c", "ii",
                    "ipc", "call", action.target, action.method || "toggle"])
                break
            case "globalShortcut":
                Quickshell.execDetached(["hyprctl", "dispatch", "global",
                    "quickshell:" + action.name])
                break
            case "key":
                Ydotool.keyCombo(action.keycodes)
                break
            case "mouseMove":
                Ydotool.moveMouse(action.x, action.y)
                break
            case "mouseMoveRelative":
                Ydotool.moveMouseRelative(action.dx, action.dy)
                break
            case "click":
                Ydotool.click(action.button || 0)
                break
            case "scroll":
                Ydotool.scroll(action.direction, action.amount)
                break
            case "drag":
                Ydotool.drag(action.startX, action.startY,
                             action.endX, action.endY, action.button || 0)
                break
            case "notify":
                _sendNotification(action.title, action.body)
                break
            case "mcp":
                _executeMcpAction(action)
                break
            case "exec":
                Quickshell.execDetached(action.command)
                break
        }
    }

    function _executeMcpAction(action) {
        _mcpProcess.command = ["python3", "-c",
            "import json, subprocess; " +
            "r = subprocess.run(['ii-desktop-mcp', 'call', '" + action.tool + "'" +
            (action.args ? ", '--args', '" + JSON.stringify(action.args) + "'" : "") +
            "], capture_output=True, text=True); " +
            "print(r.stdout[:200])"]
        _mcpProcess.running = true
    }

    function _effectiveDelay(baseDelay) {
        return Math.round(baseDelay / root.speedMultiplier)
    }

    // ─── Internal: State Guards (stubs for task 3.3) ───

    function _checkGuards(scene) {
        return true  // Will be implemented in task 3.3
    }

    function _verifyPostConditions(scene) {
        // Will be implemented in task 3.3
    }

    // ─── Internal: State Snapshot ───

    function _captureDesktopState() {
        root._preState = {
            workspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1,
            zoom: GlobalStates.screenZoom || 1.0,
            volume: Audio.sink ? Audio.sink.volume : 0.5,
            muted: Audio.sink ? Audio.sink.muted : false,
            darkMode: true
        }
        _darkModeCheck.running = true
    }

    function _restoreDesktopState() {
        if (!root._preState) return
        var s = root._preState

        // Restore workspace
        Quickshell.execDetached(["hyprctl", "dispatch", "workspace",
            s.workspace.toString()])

        // Restore zoom
        if (typeof GlobalStates.screenZoom !== "undefined") {
            GlobalStates.screenZoom = s.zoom
        }

        // Restore volume + mute
        Quickshell.execDetached(["wpctl", "set-volume",
            "@DEFAULT_AUDIO_SINK@", s.volume.toString()])
        Quickshell.execDetached(["wpctl", "set-mute",
            "@DEFAULT_AUDIO_SINK@", s.muted ? "1" : "0"])

        root._preState = null
    }

    // ─── Internal: Notification Helper ───

    function _sendNotification(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Desktop Demo",
            "-t", "3000", title, body])
    }

    // ─── Timers ───
    Timer {
        id: _actionTimer
        repeat: false
        onTriggered: root._advanceAction()
    }

    Timer {
        id: _sceneTimer
        repeat: false
        onTriggered: root._executeNextScene()
    }

    // ─── MCP Process ───
    Process {
        id: _mcpProcess
        stdout: SplitParser {
            onRead: line => {
                root._sendNotification("MCP: " + root.currentSceneName, line)
            }
        }
    }

    // ─── Dark Mode Detection ───
    Process {
        id: _darkModeCheck
        command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
        stdout: SplitParser {
            onRead: line => {
                if (root._preState)
                    root._preState.darkMode = (line.indexOf("dark") !== -1)
            }
        }
    }

    // ─── Triggers ───

    GlobalShortcut {
        name: "demoToggle"
        description: "Toggle desktop demo tour"
        onPressed: root.toggle()
    }

    GlobalShortcut {
        name: "demoStart"
        description: "Start desktop demo via IPC"
        onPressed: root.start()
    }

    GlobalShortcut {
        name: "demoStop"
        description: "Stop desktop demo via IPC"
        onPressed: root.stop()
    }

    IpcHandler {
        target: "demo"

        function start(sceneName) {
            if (sceneName && sceneName.length > 0) {
                if (DemoScenes.categories.indexOf(sceneName) !== -1)
                    root.start(sceneName, "category")
                else
                    root.start(sceneName, "scene")
            } else {
                root.start()
            }
        }

        function stop() { root.stop() }
        function pause() { root.pause() }
        function resume() { root.resume() }

        function list() { return root.listScenes() }

        function speed(multiplier) {
            root.speedMultiplier = Math.max(root.minSpeed,
                Math.min(root.maxSpeed, parseFloat(multiplier)))
        }
    }
}
