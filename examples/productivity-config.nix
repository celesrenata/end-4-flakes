# Productivity-focused configuration for dots-hyprland
{ config, lib, pkgs, ... }:

{
  programs.dots-hyprland = {
    enable = true;
    source = ./configs;
    packageSet = "essential";
    mode = "declarative";
    
    # 💼 Productivity-optimized settings
    quickshell = {
      appearance = {
        transparency = true;  # Nice visual effects
        fakeScreenRounding = 2;
      };
      
      bar = {
        bottom = false;  # Top bar for traditional feel
        cornerStyle = 1;  # Float style
        showBackground = true;
        verbose = true;  # Show detailed info
        
        utilButtons = {
          showScreenSnip = true;  # Essential for productivity
          showColorPicker = true;  # Useful for design work
          showMicToggle = true;  # For meetings
          showKeyboardToggle = true;
          showDarkModeToggle = true;
          showPerformanceProfileToggle = false;
        };
        
        workspaces = {
          shown = 10;  # Many workspaces for organization
          showAppIcons = true;
          alwaysShowNumbers = true;  # Always show for quick navigation
          showNumberDelay = 100;  # Quick response
        };
      };
      
      battery = {
        low = 25;  # Higher threshold for work
        critical = 10;
        automaticSuspend = true;
        suspend = 5;  # Longer suspend delay
      };
      
      apps = {
        terminal = "foot";
        taskManager = "plasma-systemmonitor --page-name Processes";
      };
      
      time = {
        format = "HH:mm:ss";  # 24-hour with seconds
        dateFormat = "dddd, MMMM dd, yyyy";  # Full date
      };
    };
    
    hyprland = {
      general = {
        gapsIn = 6;  # Comfortable gaps
        gapsOut = 10;
        borderSize = 2;
        allowTearing = false;  # Smooth visuals
      };
      
      decoration = {
        rounding = 12;  # Moderate rounding
        blurEnabled = true;  # Nice visual effects
      };
      
      gestures = {
        workspaceSwipe = true;  # Efficient navigation
      };
    };
    
    terminal = {
      scrollback = {
        lines = 10000;  # Large scrollback for logs
        multiplier = 3.0;
      };
      
      cursor = {
        style = "beam";
        blink = true;  # Visible cursor
      };
      
      colors = {
        alpha = 0.90;  # Slight transparency
      };
    };
  };
}
