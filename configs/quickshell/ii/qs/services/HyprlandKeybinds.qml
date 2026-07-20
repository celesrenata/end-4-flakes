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
 * Uses the `get_keybinds.py` script to parse comments in config files in a certain format and convert to JSON.
 */
Singleton {
    id: root
    property string keybindParserPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/qs/services/get_keybinds_wrapper.sh`)
    property string defaultKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland.conf`)
    property string userKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.conf`)
    property var defaultKeybinds: {"children": []}
    property var userKeybinds: {"children": []}
    property var keybinds: ({
        children: [
            ...(defaultKeybinds.children ?? []),
            ...(userKeybinds.children ?? []),
        ],
        keybinds: [
            {
                name: "All Keybinds",
                children: [
                    {
                        name: "Hyprland Keybinds",
                        keybinds: [
                            ...(defaultKeybinds.keybinds ?? []),
                            ...(userKeybinds.keybinds ?? []),
                        ]
                    }
                ],
                keybinds: []
            }
        ]
    })

    Component.onCompleted: {
        console.log("HyprlandKeybinds service loaded - QS/SERVICES VERSION");
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                getDefaultKeybinds.running = true
                getUserKeybinds.running = true
            }
        }
    }

    Process {
        id: getDefaultKeybinds
        running: true
        command: ["bash", root.keybindParserPath, "--path", root.defaultKeybindConfigPath]
        
        stdout: SplitParser {
            onRead: data => {
                console.log("[HyprlandKeybinds] Raw data received, length:", data.length)
                try {
                    root.defaultKeybinds = JSON.parse(data)
                    console.log("[HyprlandKeybinds] Loaded", root.defaultKeybinds.keybinds?.length || 0, "keybinds from hyprland.conf")
                } catch (e) {
                    console.error("[HyprlandKeybinds] Error parsing default keybinds:", e)
                    console.error("[HyprlandKeybinds] Raw data was:", data.substring(0, 500))
                }
            }
        }
    }

    Process {
        id: getUserKeybinds
        running: true
        command: ["bash", root.keybindParserPath, "--path", root.userKeybindConfigPath]
        
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.userKeybinds = JSON.parse(data)
                } catch (e) {
                    console.error("[CheatsheetKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }
}

