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
    property string keybindParserPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/get_keybinds.py`)
    property string defaultKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland.conf`)
    property string userKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.conf`)
    property var defaultKeybinds: {"children": []}
    property var userKeybinds: {"children": []}
    
    function expandModifiers(mods) {
        return mods.map(mod => 
            mod.replace(/\$Primary/g, "Super")
               .replace(/\$Secondary/g, "Control")
               .replace(/\$Tertiary/g, "Shift")
               .replace(/\$Alternate/g, "Alt")
        )
    }
    
    function expandKeybinds(kbs) {
        return kbs.map(kb => {
            var expanded = {}
            for (var key in kb) {
                expanded[key] = kb[key]
            }
            expanded.mods = expandModifiers(kb.mods)
            return expanded
        })
    }
    
    property var keybinds: ({
        children: [],
        keybinds: expandKeybinds((defaultKeybinds.keybinds ?? []).concat(userKeybinds.keybinds ?? []))
    })

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
        command: ["bash", "-c", root.keybindParserPath + " --path \"$(readlink -f " + root.defaultKeybindConfigPath + ")\""]
        
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.defaultKeybinds = JSON.parse(data)
                } catch (e) {
                    console.error("[CheatsheetKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }

    Process {
        id: getUserKeybinds
        running: true
        command: [root.keybindParserPath, "--path", root.userKeybindConfigPath]
        
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

