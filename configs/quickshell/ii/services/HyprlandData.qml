pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})

    function updateWindowList() {
        if (!getClients.running)
            getClients.running = true;
    }

    function updateLayers() {
        if (!getLayers.running)
            getLayers.running = true;
    }

    function updateMonitors() {
        if (!getMonitors.running)
            getMonitors.running = true;
    }

    function updateWorkspaces() {
        if (!getWorkspaces.running)
            getWorkspaces.running = true;
        if (!getActiveWorkspace.running)
            getActiveWorkspace.running = true;
    }

    function updateAll() {
        updateWindowList();
        updateMonitors();
        updateLayers();
        updateWorkspaces();
    }

    Timer {
        id: updateDebounce
        interval: 100
        repeat: false
        onTriggered: root.updateAll()
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    Component.onCompleted: {
        updateAll();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            // console.log("Hyprland raw event:", event.name);
            updateDebounce.restart()
        }
    }

    // Use Hyprland socket directly (hyprctl binary may have library issues)
    readonly property string _hyprSocket: "/run/user/" + Quickshell.processId.toString().replace(/.*/, () => {
        // Get UID via env
        return "";
    }) + ""

    function _socketCommand(query) {
        return ["bash", "-c", 'echo -n "j/' + query + '" | socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock']
    }

    Process {
        id: getClients
        command: root._socketCommand("clients")
        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                try {
                    root.windowList = JSON.parse(clientsCollector.text)
                    let tempWinByAddress = {};
                    for (var i = 0; i < root.windowList.length; ++i) {
                        var win = root.windowList[i];
                        tempWinByAddress[win.address] = win;
                    }
                    root.windowByAddress = tempWinByAddress;
                    root.addresses = root.windowList.map(win => win.address);
                } catch (e) {}
            }
        }
    }

    Process {
        id: getMonitors
        command: root._socketCommand("monitors")
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(monitorsCollector.text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: getLayers
        command: root._socketCommand("layers")
        stdout: StdioCollector {
            id: layersCollector
            onStreamFinished: {
                try {
                    root.layers = JSON.parse(layersCollector.text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: getWorkspaces
        command: root._socketCommand("workspaces")
        stdout: StdioCollector {
            id: workspacesCollector
            onStreamFinished: {
                try {
                    root.workspaces = JSON.parse(workspacesCollector.text);
                    let tempWorkspaceById = {};
                    for (var i = 0; i < root.workspaces.length; ++i) {
                        var ws = root.workspaces[i];
                        tempWorkspaceById[ws.id] = ws;
                    }
                    root.workspaceById = tempWorkspaceById;
                    root.workspaceIds = root.workspaces.map(ws => ws.id);
                } catch (e) {}
            }
        }
    }

    Process {
        id: getActiveWorkspace
        command: root._socketCommand("activeworkspace")
        stdout: StdioCollector {
            id: activeWorkspaceCollector
            onStreamFinished: {
                try {
                    root.activeWorkspace = JSON.parse(activeWorkspaceCollector.text);
                } catch (e) {}
            }
        }
    }
}
