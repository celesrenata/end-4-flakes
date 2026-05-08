# Minimalist configuration for dots-hyprland
{ config, lib, pkgs, ... }:

{
  programs.dots-hyprland = {
    enable = true;
    source = ./configs;
    packageSet = "minimal";
    mode = "declarative";
    
    # 🎯 Minimalist settings
    quickshell = {
      appearance = {
        transparency = false;
        fakeScreenRounding = 0;  # No rounding
      };
      
      bar = {
        bottom = false;
        cornerStyle = 2;  # Plain rectangle
        borderless = true;  # No grouping
        showBackground = false;  # No background
        verbose = false;  # Minimal info
        
        utilButtons = {
          showScreenSnip = false;
          showColorPicker = false;
          showMicToggle = false;
          showKeyboardToggle = false;
          showDarkModeToggle = false;
          showPerformanceProfileToggle = false;
        };
        
        workspaces = {
          monochromeIcons = true;
          shown = 5;  # Only 5 workspaces
          showAppIcons = false;  # No app icons
          alwaysShowNumbers = true;
        };
      };
      
      battery = {
        low = 20;
        critical = 5;
        automaticSuspend = true;
        suspend = 3;
      };
      
      apps = {
        terminal = "foot";
        taskManager = "htop";
      };
      
      time = {
        format = "HH:mm";  # Simple 24-hour
        dateFormat = "dd/MM";  # Minimal date
      };
    };
    
    hyprland = {
      general = {
        gapsIn = 2;  # Minimal gaps
        gapsOut = 4;
        borderSize = 1;  # Thin borders
        allowTearing = false;
      };
      
      decoration = {
        rounding = 0;  # No rounding
        blurEnabled = false;  # No blur
      };
      
      gestures = {
        workspaceSwipe = true;
      };
    };
    
    terminal = {
      scrollback = {
        lines = 500;  # Smaller scrollback
      };
      
      cursor = {
        style = "block";  # Simple block cursor
        blink = false;
      };
      
      colors = {
        alpha = 1.0;  # No transparency
      };
      
      mouse = {
        hideWhenTyping = true;  # Clean interface
      };
    };
  };
}
