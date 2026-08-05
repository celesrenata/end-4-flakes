pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * A service that provides access to Hyprland keybinds.
 * Reads directly from `hyprctl binds -j` which reflects the actual
 * loaded Lua configuration with descriptions.
 */
Singleton {
    id: root
    property var keybinds: []
    property var keybindCategories: []

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                loadProcess.running = true;
            }
        }
    }

    Process {
        id: loadProcess
        running: true
        command: ["env", "-u", "LD_LIBRARY_PATH", "hyprctl", "binds", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const allBinds = JSON.parse(text);
                    // Filter to only binds with descriptions (non-hidden)
                    const described = allBinds.filter(b => b.description && b.description.length > 0);
                    root.keybinds = described;

                    // Extract categories from "Category: Description" format
                    var categories = [];
                    for (var i = 0; i < described.length; i++) {
                        var desc = described[i].description;
                        var colonIdx = desc.indexOf(": ");
                        if (colonIdx !== -1) {
                            var cat = desc.substring(0, colonIdx);
                            if (!categories.includes(cat) && cat.length > 0) {
                                categories.push(cat);
                            }
                        }
                    }
                    root.keybindCategories = categories;
                    console.log("[HyprlandKeybinds] Loaded " + described.length + " described keybinds in " + categories.length + " categories from hyprctl");
                } catch (e) {
                    console.error("[HyprlandKeybinds] Error parsing hyprctl binds:", e);
                }
            }
        }
    }
}
