import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemdUser

// Transparency and Blur Settings Module
// Based on AGS configuration from ~/.config/ags/modules/sideright/centermodules/configure.js

Rectangle {
    id: transparencySettings
    
    property bool globalTransparency: false
    property int terminalOpacity: 100
    property bool blurEnabled: false
    property bool blurXray: true
    property int blurSize: 8
    property int blurPasses: 4
    
    // Storage paths (matching AGS structure)
    property string colorModeFile: StandardPaths.writableLocation(StandardPaths.CacheLocation) + "/ags/user/colormode.txt"
    property string terminalTransparencyFile: StandardPaths.writableLocation(StandardPaths.CacheLocation) + "/ags/user/generated/terminal/transparency"
    
    color: "transparent"
    
    Component.onCompleted: {
        loadSettings()
    }
    
    // Load settings from files (AGS compatibility)
    function loadSettings() {
        // Load global transparency mode
        Process.exec("bash", ["-c", `mkdir -p $(dirname "${colorModeFile}")`])
        let colorModeResult = Process.exec("bash", ["-c", `sed -n '2p' "${colorModeFile}" 2>/dev/null || echo "opaque"`])
        globalTransparency = (colorModeResult.stdout.trim() === "transparent")
        
        // Load terminal opacity
        Process.exec("bash", ["-c", `mkdir -p $(dirname "${terminalTransparencyFile}")`])
        let termOpacityResult = Process.exec("bash", ["-c", `cat "${terminalTransparencyFile}" 2>/dev/null || echo "100"`])
        terminalOpacity = parseInt(termOpacityResult.stdout.trim()) || 100
        
        // Load Hyprland blur settings
        loadHyprlandSettings()
    }
    
    function loadHyprlandSettings() {
        // Load blur enabled
        let blurResult = Process.exec("hyprctl", ["getoption", "-j", "decoration:blur:enabled"])
        try {
            let blurData = JSON.parse(blurResult.stdout)
            blurEnabled = blurData.int !== 0
        } catch (e) {
            console.log("Failed to load blur enabled setting:", e)
        }
        
        // Load blur xray
        let xrayResult = Process.exec("hyprctl", ["getoption", "-j", "decoration:blur:xray"])
        try {
            let xrayData = JSON.parse(xrayResult.stdout)
            blurXray = xrayData.int !== 0
        } catch (e) {
            console.log("Failed to load blur xray setting:", e)
        }
        
        // Load blur size
        let sizeResult = Process.exec("hyprctl", ["getoption", "-j", "decoration:blur:size"])
        try {
            let sizeData = JSON.parse(sizeResult.stdout)
            blurSize = sizeData.int
        } catch (e) {
            console.log("Failed to load blur size setting:", e)
        }
        
        // Load blur passes
        let passesResult = Process.exec("hyprctl", ["getoption", "-j", "decoration:blur:passes"])
        try {
            let passesData = JSON.parse(passesResult.stdout)
            blurPasses = passesData.int
        } catch (e) {
            console.log("Failed to load blur passes setting:", e)
        }
    }
    
    // Save and apply global transparency
    function setGlobalTransparency(enabled) {
        globalTransparency = enabled
        let mode = enabled ? "transparent" : "opaque"
        
        // Save to colormode.txt (line 2)
        Process.exec("bash", ["-c", `mkdir -p $(dirname "${colorModeFile}")
            if [ ! -f "${colorModeFile}" ]; then
                echo "dark" > "${colorModeFile}"
                echo "${mode}" >> "${colorModeFile}"
            else
                sed -i "2s/.*/${mode}/" "${colorModeFile}"
            fi`])
        
        // Apply color changes (equivalent to AGS switchcolor.sh)
        applyColorChanges()
    }
    
    // Save and apply terminal opacity
    function setTerminalOpacity(opacity) {
        terminalOpacity = opacity
        
        // Save to terminal transparency file
        Process.exec("bash", ["-c", `mkdir -p $(dirname "${terminalTransparencyFile}")
            echo "${opacity}" > "${terminalTransparencyFile}"`])
        
        // Apply terminal colors (equivalent to AGS applycolor.sh term)
        applyTerminalColors()
    }
    
    // Apply Hyprland blur settings
    function setBlurEnabled(enabled) {
        blurEnabled = enabled
        Process.exec("hyprctl", ["keyword", "decoration:blur:enabled", enabled ? "1" : "0"])
    }
    
    function setBlurXray(enabled) {
        blurXray = enabled
        Process.exec("hyprctl", ["keyword", "decoration:blur:xray", enabled ? "1" : "0"])
    }
    
    function setBlurSize(size) {
        blurSize = size
        Process.exec("hyprctl", ["keyword", "decoration:blur:size", size.toString()])
    }
    
    function setBlurPasses(passes) {
        blurPasses = passes
        Process.exec("hyprctl", ["keyword", "decoration:blur:passes", passes.toString()])
    }
    
    // Apply color changes (equivalent to AGS color generation)
    function applyColorChanges() {
        // This would call the equivalent of AGS color generation scripts
        Process.exec("bash", ["-c", `
            # Apply transparency mode to all shell elements
            # This is where we'd integrate with the quickshell theming system
            echo "Applying transparency mode: ${globalTransparency ? 'transparent' : 'opaque'}"
            
            # Reload quickshell to apply changes
            quickshell ipc call settings reload || true
        `])
    }
    
    // Apply terminal colors (equivalent to AGS applycolor.sh term)
    function applyTerminalColors() {
        let alpha = terminalOpacity / 100.0
        
        Process.exec("bash", ["-c", `
            # Update foot terminal configuration with new opacity
            FOOT_CONFIG="$HOME/.config/foot/foot.ini"
            if [ -f "$FOOT_CONFIG" ]; then
                # Update alpha value in foot.ini
                sed -i "s/^alpha=.*/alpha=${alpha}/" "$FOOT_CONFIG" || echo "alpha=${alpha}" >> "$FOOT_CONFIG"
            fi
            
            # Send terminal escape sequence to update running terminals
            # This matches the AGS terminal sequences functionality
            echo "Applied terminal opacity: ${terminalOpacity}%"
        `])
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
            transparencySettings.loadSettings()
        }
    }
}
