pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * A service that provides access to Hyprland keybinds.
 * Uses `hyprctl binds -j` to get keybinds directly from the running Hyprland instance.
 * Keybinds are grouped by category based on the "Category: Description" format in bind descriptions.
 */
Singleton {
    id: root
    property var keybinds: []
    property var keybindCategories: []

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                getKeybinds.running = true
            }
        }
    }

    Process {
        id: getKeybinds
        running: true
        command: ["hyprctl", "binds", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.keybinds = JSON.parse(text)
                    var groups = []
                    for (var i = 0; i < root.keybinds.length; i++) {
                        var bind = root.keybinds[i].description
                        if (!bind) continue
                        var colonIdx = bind.indexOf(":")
                        if (colonIdx === -1) continue
                        var group = bind.substring(0, colonIdx)
                        if (!groups.includes(group) && group.length > 0) {
                            groups.push(group)
                        }
                    }
                    root.keybindCategories = groups
                } catch (e) {
                    console.error("[HyprlandKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }
}
