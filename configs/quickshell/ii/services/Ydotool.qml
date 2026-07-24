pragma Singleton

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property int shiftMode: 0 // 0: off, 1: on, 2: lock
    property list<int> shiftKeys: [42, 54] // Keycodes for Shift keys (left and right)
    property list<int> altKeys: [56, 100] // Keycodes for Alt keys (left and right)
    property list<int> ctrlKeys: [29, 97] // Keycodes for Ctrl keys (left and right)

    // ydotool daemon availability
    property bool available: false
    property string lastError: ""

    // ─── Existing Keyboard Functions ───

    function releaseAllKeys() {
        const keycodes = Array.from(Array(249).keys());
        Quickshell.execDetached([
            "ydotool",
            "key", "--key-delay", "0",
            ...keycodes.map(keycode => `${keycode}:0`)
        ])
        root.shiftMode = 0; // Reset shift mode
    }

    function releaseShiftKeys() {
        Quickshell.execDetached([
            "ydotool",
            "key", "--key-delay", "0",
            ...root.shiftKeys.map(keycode => `${keycode}:0`)
        ])
        root.shiftMode = 0; // Reset shift mode
    }

    function press(keycode) {
        Quickshell.execDetached([
            "ydotool",
            "key", "--key-delay", "0",
            `${keycode}:1`
        ]);
    }

    function release(keycode) {
        Quickshell.execDetached([
            "ydotool",
            "key", "--key-delay", "0",
            `${keycode}:0`
        ]);
    }

    // ─── Mouse Emulation Functions ───

    function moveMouse(x, y) {
        if (!root.available) { _logUnavailable("moveMouse"); return; }
        Quickshell.execDetached(["ydotool", "mousemove", "--absolute",
            "-x", x.toString(), "-y", y.toString()])
    }

    function moveMouseRelative(dx, dy) {
        if (!root.available) { _logUnavailable("moveMouseRelative"); return; }
        Quickshell.execDetached(["ydotool", "mousemove",
            "-x", dx.toString(), "-y", dy.toString()])
    }

    function click(button) {
        if (!root.available) { _logUnavailable("click"); return; }
        // ydotool click: button codes 0xC0=left, 0xC1=right, 0xC2=middle
        var code = [0xC0, 0xC1, 0xC2][button] || 0xC0
        Quickshell.execDetached(["ydotool", "click",
            "0x" + code.toString(16).toUpperCase()])
    }

    function doubleClick(button) {
        if (!root.available) { _logUnavailable("doubleClick"); return; }
        var code = [0xC0, 0xC1, 0xC2][button] || 0xC0
        Quickshell.execDetached(["ydotool", "click", "--repeat", "2",
            "--next-delay", "50", "0x" + code.toString(16).toUpperCase()])
    }

    function scroll(direction, amount) {
        if (!root.available) { _logUnavailable("scroll"); return; }
        // direction: "up", "down", "left", "right"
        var dx = 0, dy = 0
        switch (direction) {
            case "up":    dy = -amount; break
            case "down":  dy = amount;  break
            case "left":  dx = -amount; break
            case "right": dx = amount;  break
        }
        Quickshell.execDetached(["ydotool", "mousemove",
            "--wheel", "-x", dx.toString(), "-y", dy.toString()])
    }

    function drag(startX, startY, endX, endY, button) {
        if (!root.available) { _logUnavailable("drag"); return; }
        // Multi-step: move to start, press, move to end, release
        var code = [0xC0, 0xC1, 0xC2][button] || 0xC0
        var hexCode = "0x" + code.toString(16).toUpperCase()
        Quickshell.execDetached(["bash", "-c",
            "ydotool mousemove --absolute -x " + startX + " -y " + startY +
            " && sleep 0.05" +
            " && ydotool mousedown " + hexCode +
            " && sleep 0.05" +
            " && ydotool mousemove --absolute -x " + endX + " -y " + endY +
            " && sleep 0.05" +
            " && ydotool mouseup " + hexCode
        ])
    }

    // ─── Key Combo Function ───

    function keyCombo(keycodes) {
        if (!root.available) { _logUnavailable("keyCombo"); return; }
        // Press all keys, then release in reverse order
        var args = ["ydotool", "key", "--key-delay", "20"]
        for (var i = 0; i < keycodes.length; i++)
            args.push(keycodes[i] + ":1")
        for (var j = keycodes.length - 1; j >= 0; j--)
            args.push(keycodes[j] + ":0")
        Quickshell.execDetached(args)
    }

    // ─── Internal Helpers ───

    function _logUnavailable(fn) {
        root.lastError = "ydotool unavailable, cannot execute: " + fn
        console.warn("[Ydotool] " + root.lastError)
    }

    // ─── Availability Check ───

    Process {
        id: checkProcess
        command: ["ydotool", "--help"]
        onExited: (exitCode, exitStatus) => {
            root.available = (exitCode === 0)
            if (!root.available)
                console.warn("[Ydotool] ydotoold not running or ydotool not found")
        }
    }

    Component.onCompleted: checkProcess.running = true
}
