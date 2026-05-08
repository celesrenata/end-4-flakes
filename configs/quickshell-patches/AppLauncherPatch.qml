pragma Singleton

import Quickshell

/**
 * Application launcher patch for NixOS integration
 * Ensures applications are launched with proper PATH environment
 */
Singleton {
    id: root
    
    // Get the launcher wrapper path from environment
    readonly property string launcherWrapper: Quickshell.env("DOTS_HYPRLAND_APP_LAUNCHER") || ""
    
    /**
     * Launch an application using the NixOS-compatible launcher wrapper
     * @param command - The command to execute (can be string or array)
     */
    function launchApp(command) {
        if (launcherWrapper === "") {
            console.warn("AppLauncherPatch: No launcher wrapper found, falling back to direct execution");
            if (Array.isArray(command)) {
                Quickshell.execDetached(command);
            } else {
                Quickshell.execDetached(["bash", "-c", command]);
            }
            return;
        }
        
        console.log("AppLauncherPatch: Launching app with wrapper:", command);
        
        if (Array.isArray(command)) {
            // If command is an array, prepend the launcher wrapper
            Quickshell.execDetached([launcherWrapper].concat(command));
        } else {
            // If command is a string, use bash to execute it through the wrapper
            Quickshell.execDetached([launcherWrapper, "bash", "-c", command]);
        }
    }
    
    /**
     * Launch a desktop entry using the launcher wrapper
     * @param desktopEntry - The DesktopEntry object
     */
    function launchDesktopEntry(desktopEntry) {
        if (!desktopEntry) {
            console.warn("AppLauncherPatch: No desktop entry provided");
            return;
        }
        
        console.log("AppLauncherPatch: Launching desktop entry:", desktopEntry.name);
        
        // Try to use the desktop entry's execute method first
        try {
            desktopEntry.execute();
        } catch (error) {
            console.warn("AppLauncherPatch: Desktop entry execute failed, trying wrapper approach:", error);
            
            // Fallback: extract the Exec command and use our wrapper
            if (desktopEntry.exec) {
                launchApp(desktopEntry.exec);
            } else {
                console.error("AppLauncherPatch: No exec command found in desktop entry");
            }
        }
    }
}
