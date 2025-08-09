# Gaming-optimized configuration for dots-hyprland
{ config, lib, pkgs, ... }:

{
  programs.dots-hyprland = {
    enable = true;
    source = ./configs;
    packageSet = "essential";
    mode = "declarative";
    
    # 🎮 Gaming-optimized settings
    quickshell = {
      appearance = {
        transparency = false;  # Disable for performance
        fakeScreenRounding = 0;  # No rounding
      };
      
      bar = {
        bottom = true;  # Bottom bar for gaming
        showBackground = false;  # Minimal UI
        verbose = false;  # Less clutter
        
        utilButtons = {
          showScreenSnip = false;
          showColorPicker = false;
          showMicToggle = true;  # Useful for gaming
          showKeyboardToggle = false;
          showDarkModeToggle = false;
          showPerformanceProfileToggle = true;  # Gaming profiles
        };
        
        workspaces = {
          shown = 3;  # Only 3 workspaces for gaming
          showAppIcons = false;  # Minimal
          alwaysShowNumbers = true;
        };
      };
      
      battery = {
        low = 15;  # Lower threshold for gaming
        critical = 5;
        automaticSuspend = false;  # Never suspend while gaming
      };
      
      apps = {
        terminal = "foot";
        taskManager = "htop";  # Lightweight task manager
      };
    };
    
    hyprland = {
      general = {
        gapsIn = 0;  # No gaps for fullscreen gaming
        gapsOut = 0;
        borderSize = 1;  # Minimal borders
        allowTearing = true;  # Enable for competitive gaming
      };
      
      decoration = {
        rounding = 0;  # No rounding for performance
        blurEnabled = false;  # Disable blur for performance
      };
      
      gestures = {
        workspaceSwipe = false;  # Disable gestures
      };
    };
    
    terminal = {
      colors = {
        alpha = 1.0;  # No transparency for performance
      };
    };
  };
}
