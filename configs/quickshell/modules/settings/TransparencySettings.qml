import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Transparency and Blur Settings Module
// Uses applycolor.sh for terminal opacity and hyprctl for blur settings.

Rectangle {
    id: transparencySettings
    
    property bool globalTransparency: false
    property int terminalOpacity: 60
    property bool blurEnabled: false
    property bool blurXray: true
    property int blurSize: 8
    property int blurPasses: 4

    readonly property string stateDir: (Qt.resolvedUrl("").toString().indexOf("/.config/") !== -1)
        ? (Qt.resolvedUrl("").toString().split("/.config/")[0].replace("file://", "") + "/.local/state/quickshell")
        : ""
    readonly property string scriptDir: (Qt.resolvedUrl("").toString().indexOf("/.config/") !== -1)
        ? (Qt.resolvedUrl("").toString().split("/.config/")[0].replace("file://", "") + "/.config/quickshell/scripts/colors")
        : ""

    color: "transparent"
    
    Component.onCompleted: {
        loadOpacity.running = true
        loadBlur.running = true
    }

    // Load terminal opacity from file
    Process {
        id: loadOpacity
        command: ["bash", "-c", "cat '" + transparencySettings.stateDir + "/user/generated/terminal/opacity' 2>/dev/null || echo '60'"]
        stdout: SplitParser {
            onRead: data => {
                let val = parseInt(data.trim())
                if (!isNaN(val) && val >= 0 && val <= 100) {
                    transparencySettings.terminalOpacity = val
                }
            }
        }
    }

    // Load blur settings from Hyprland
    Process {
        id: loadBlur
        command: ["hyprctl", "getoption", "-j", "decoration:blur:enabled"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    let d = JSON.parse(data)
                    transparencySettings.blurEnabled = d.int !== 0
                } catch(e) {}
            }
        }
    }

    // Save and apply terminal opacity
    function setTerminalOpacity(opacity) {
        terminalOpacity = opacity
        applyOpacity.command = ["bash", "-c",
            "mkdir -p '" + stateDir + "/user/generated/terminal' && " +
            "echo '" + opacity + "' > '" + stateDir + "/user/generated/terminal/opacity' && " +
            "cd '" + scriptDir + "' && bash applycolor.sh foot && bash applycolor.sh term"
        ]
        applyOpacity.running = true
    }

    Process {
        id: applyOpacity
    }

    // Save and apply global transparency
    function setGlobalTransparency(enabled) {
        globalTransparency = enabled
        let mode = enabled ? "transparent" : "opaque"
        applyTransparency.command = ["bash", "-c",
            "mkdir -p '" + stateDir + "/user/generated/terminal' && " +
            "echo '" + mode + "' > '" + stateDir + "/user/generated/terminal/transparency' && " +
            "cd '" + scriptDir + "' && bash applycolor.sh foot && bash applycolor.sh term"
        ]
        applyTransparency.running = true
    }

    Process {
        id: applyTransparency
    }

    // Apply Hyprland blur settings
    function setBlurEnabled(enabled) {
        blurEnabled = enabled
        Quickshell.execDetached(["hyprctl", "keyword", "decoration:blur:enabled", enabled ? "1" : "0"])
    }
    
    function setBlurXray(enabled) {
        blurXray = enabled
        Quickshell.execDetached(["hyprctl", "keyword", "decoration:blur:xray", enabled ? "1" : "0"])
    }
    
    function setBlurSize(size) {
        blurSize = size
        Quickshell.execDetached(["hyprctl", "keyword", "decoration:blur:size", size.toString()])
    }
    
    function setBlurPasses(passes) {
        blurPasses = passes
        Quickshell.execDetached(["hyprctl", "keyword", "decoration:blur:passes", passes.toString()])
    }

    // IPC Handler for external control
    IpcHandler {
        target: "transparencySettings"
        
        function setTransparency(enabled) {
            transparencySettings.setGlobalTransparency(enabled)
        }
        
        function setTerminalOpacity(opacity) {
            transparencySettings.setTerminalOpacity(opacity)
        }
        
        function setBlur(enabled) {
            transparencySettings.setBlurEnabled(enabled)
        }
        
        function setBlurXray(enabled) {
            transparencySettings.setBlurXray(enabled)
        }
        
        function setBlurSize(size) {
            transparencySettings.setBlurSize(size)
        }
        
        function setBlurPasses(passes) {
            transparencySettings.setBlurPasses(passes)
        }
        
        function getSettings() {
            return {
                globalTransparency: transparencySettings.globalTransparency,
                terminalOpacity: transparencySettings.terminalOpacity,
                blurEnabled: transparencySettings.blurEnabled,
                blurXray: transparencySettings.blurXray,
                blurSize: transparencySettings.blurSize,
                blurPasses: transparencySettings.blurPasses
            }
        }
        
        function reload() {
            loadOpacity.running = true
            loadBlur.running = true
        }
    }
}
