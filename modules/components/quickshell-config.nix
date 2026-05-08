# Quickshell configuration options for dots-hyprland
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.dots-hyprland.quickshell;
in
{
  options.programs.dots-hyprland.quickshell = {
    # Appearance settings
    appearance = {
      extraBackgroundTint = mkOption {
        type = types.bool;
        default = true;
        description = "Enable extra background tint";
      };
      
      fakeScreenRounding = mkOption {
        type = types.enum [ 0 1 2 ];
        default = 2;
        description = "Screen rounding mode: 0=None, 1=Always, 2=When not fullscreen";
      };
      
      transparency = mkOption {
        type = types.bool;
        default = false;
        description = "Enable transparency effects";
      };
    };
    
    # Bar configuration
    bar = {
      bottom = mkOption {
        type = types.bool;
        default = false;
        description = "Place bar at bottom instead of top";
      };
      
      cornerStyle = mkOption {
        type = types.enum [ 0 1 2 ];
        default = 0;
        description = "Bar corner style: 0=Hug, 1=Float, 2=Plain rectangle";
      };
      
      borderless = mkOption {
        type = types.bool;
        default = false;
        description = "Remove grouping of bar items";
      };
      
      topLeftIcon = mkOption {
        type = types.enum [ "distro" "spark" ];
        default = "spark";
        description = "Icon to show in top-left of bar";
      };
      
      showBackground = mkOption {
        type = types.bool;
        default = true;
        description = "Show bar background";
      };
      
      verbose = mkOption {
        type = types.bool;
        default = true;
        description = "Show detailed information in bar";
      };
      
      utilButtons = {
        showScreenSnip = mkOption {
          type = types.bool;
          default = true;
          description = "Show screen snip button";
        };
        
        showColorPicker = mkOption {
          type = types.bool;
          default = false;
          description = "Show color picker button";
        };
        
        showMicToggle = mkOption {
          type = types.bool;
          default = false;
          description = "Show microphone toggle button";
        };
        
        showKeyboardToggle = mkOption {
          type = types.bool;
          default = true;
          description = "Show keyboard layout toggle";
        };
        
        showDarkModeToggle = mkOption {
          type = types.bool;
          default = true;
          description = "Show dark mode toggle";
        };
        
        showPerformanceProfileToggle = mkOption {
          type = types.bool;
          default = false;
          description = "Show performance profile toggle";
        };
      };
      
      workspaces = {
        monochromeIcons = mkOption {
          type = types.bool;
          default = true;
          description = "Use monochrome workspace icons";
        };
        
        shown = mkOption {
          type = types.int;
          default = 10;
          description = "Number of workspaces to show";
        };
        
        showAppIcons = mkOption {
          type = types.bool;
          default = true;
          description = "Show application icons in workspaces";
        };
        
        alwaysShowNumbers = mkOption {
          type = types.bool;
          default = false;
          description = "Always show workspace numbers";
        };
        
        showNumberDelay = mkOption {
          type = types.int;
          default = 300;
          description = "Delay before showing workspace numbers (milliseconds)";
        };
      };
    };
    
    # Battery settings
    battery = {
      low = mkOption {
        type = types.int;
        default = 20;
        description = "Low battery threshold (%)";
      };
      
      critical = mkOption {
        type = types.int;
        default = 5;
        description = "Critical battery threshold (%)";
      };
      
      automaticSuspend = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic suspend on critical battery";
      };
      
      suspend = mkOption {
        type = types.int;
        default = 3;
        description = "Minutes before suspend on critical battery";
      };
    };
    
    # Application settings
    apps = {
      terminal = mkOption {
        type = types.str;
        default = "kitty -1";
        description = "Terminal command for shell actions";
      };
      
      bluetooth = mkOption {
        type = types.str;
        default = "kcmshell6 kcm_bluetooth";
        description = "Bluetooth settings command";
      };
      
      network = mkOption {
        type = types.str;
        default = "plasmawindowed org.kde.plasma.networkmanagement";
        description = "Network settings command";
      };
      
      taskManager = mkOption {
        type = types.str;
        default = "plasma-systemmonitor --page-name Processes";
        description = "Task manager command";
      };
    };
    
    # Time format
    time = {
      format = mkOption {
        type = types.str;
        default = "hh:mm";
        description = "Time format string";
      };
      
      dateFormat = mkOption {
        type = types.str;
        default = "ddd, dd/MM";
        description = "Date format string";
      };
    };
  };
  
  config = mkIf (config.programs.dots-hyprland.enable && 
                 config.programs.dots-hyprland.overrides.quickshellConfig == null &&
                 !(config.programs.dots-hyprland.configuration.enable or false)) {
    # Only generate if no manual override is set AND configuration copying is disabled
    xdg.configFile."quickshell/ii/modules/common/Config.qml".text = ''
      pragma Singleton
      pragma ComponentBehavior: Bound
      import QtQuick
      import Quickshell
      import Quickshell.Io

      Singleton {
          id: root
          property string filePath: Directories.shellConfigPath
          property alias options: configOptionsJsonAdapter
          property bool ready: true  // Always ready for NixOS-generated config

          function setNestedValue(nestedKey, value) {
              // NixOS-managed config - values are set at build time
              console.log("NixOS-managed configuration - ignoring runtime changes");
          }

          JsonAdapter {
              id: configOptionsJsonAdapter
              
              property JsonObject policies: JsonObject {
                  property int ai: 1
                  property int weeb: 1
              }

              property JsonObject ai: JsonObject {
                  property string systemPrompt: "## Style\n- Use casual tone, don't be formal! Make sure you answer precisely without hallucination and prefer bullet points over walls of text. You can have a friendly greeting at the beginning of the conversation, but don't repeat the user's question\n\n## Context (ignore when irrelevant)\n- You are a helpful and inspiring sidebar assistant on a NixOS Linux system\n- Desktop environment: Hyprland + dots-hyprland\n- Current date & time: {DATETIME}\n- Focused app: {WINDOWCLASS}\n\n## Presentation\n- Use Markdown features in your response"
                  property string tool: "functions"
                  property list<var> extraModels: []
              }
              
              property JsonObject appearance: JsonObject {
                  property bool extraBackgroundTint: ${boolToString cfg.appearance.extraBackgroundTint}
                  property int fakeScreenRounding: ${toString cfg.appearance.fakeScreenRounding}
                  property bool transparency: ${boolToString cfg.appearance.transparency}
                  property JsonObject wallpaperTheming: JsonObject {
                      property bool enableAppsAndShell: true
                      property bool enableQtApps: true
                      property bool enableTerminal: true
                  }
                  property JsonObject palette: JsonObject {
                      property string type: "auto"
                  }
              }

              property JsonObject audio: JsonObject {
                  property JsonObject protection: JsonObject {
                      property bool enable: true
                      property real maxAllowedIncrease: 10
                      property real maxAllowed: 90
                  }
              }
              
              property JsonObject apps: JsonObject {
                  property string bluetooth: "${cfg.apps.bluetooth}"
                  property string network: "${cfg.apps.network}"
                  property string networkEthernet: "kcmshell6 kcm_networkmanagement"
                  property string taskManager: "${cfg.apps.taskManager}"
                  property string terminal: "${cfg.apps.terminal}"
              }

              property JsonObject background: JsonObject {
                  property bool fixedClockPosition: false
                  property real clockX: -500
                  property real clockY: -500
                  property string wallpaperPath: ""
                  property string thumbnailPath: ""
                  property JsonObject parallax: JsonObject {
                      property bool enableWorkspace: true
                      property real workspaceZoom: 1.07
                      property bool enableSidebar: true
                  }
              }
              
              property JsonObject bar: JsonObject {
                  property bool bottom: ${boolToString cfg.bar.bottom}
                  property int cornerStyle: ${toString cfg.bar.cornerStyle}
                  property bool borderless: ${boolToString cfg.bar.borderless}
                  property string topLeftIcon: "${cfg.bar.topLeftIcon}"
                  property bool showBackground: ${boolToString cfg.bar.showBackground}
                  property bool verbose: ${boolToString cfg.bar.verbose}
                  property JsonObject resources: JsonObject {
                      property bool alwaysShowSwap: true
                      property bool alwaysShowCpu: false
                  }
                  property list<string> screenList: []
                  property JsonObject utilButtons: JsonObject {
                      property bool showScreenSnip: ${boolToString cfg.bar.utilButtons.showScreenSnip}
                      property bool showColorPicker: ${boolToString cfg.bar.utilButtons.showColorPicker}
                      property bool showMicToggle: ${boolToString cfg.bar.utilButtons.showMicToggle}
                      property bool showKeyboardToggle: ${boolToString cfg.bar.utilButtons.showKeyboardToggle}
                      property bool showDarkModeToggle: ${boolToString cfg.bar.utilButtons.showDarkModeToggle}
                      property bool showPerformanceProfileToggle: ${boolToString cfg.bar.utilButtons.showPerformanceProfileToggle}
                  }
                  property JsonObject tray: JsonObject {
                      property bool monochromeIcons: true
                  }
                  property JsonObject workspaces: JsonObject {
                      property bool monochromeIcons: ${boolToString cfg.bar.workspaces.monochromeIcons}
                      property int shown: ${toString cfg.bar.workspaces.shown}
                      property bool showAppIcons: ${boolToString cfg.bar.workspaces.showAppIcons}
                      property bool alwaysShowNumbers: ${boolToString cfg.bar.workspaces.alwaysShowNumbers}
                      property int showNumberDelay: ${toString cfg.bar.workspaces.showNumberDelay}
                  }
                  property JsonObject weather: JsonObject {
                      property bool enable: false
                      property bool enableGPS: true
                      property string city: ""
                      property bool useUSCS: false
                      property int fetchInterval: 10
                  }
              }
              
              property JsonObject battery: JsonObject {
                  property int low: ${toString cfg.battery.low}
                  property int critical: ${toString cfg.battery.critical}
                  property bool automaticSuspend: ${boolToString cfg.battery.automaticSuspend}
                  property int suspend: ${toString cfg.battery.suspend}
              }

              property JsonObject dock: JsonObject {
                  property bool enable: false
                  property bool monochromeIcons: true
                  property real height: 60
                  property real hoverRegionHeight: 2
                  property bool pinnedOnStartup: false
                  property bool hoverToReveal: true
                  property list<string> pinnedApps: ["org.kde.dolphin", "kitty"]
                  property list<string> ignoredAppRegexes: []
              }

              property JsonObject language: JsonObject {
                  property JsonObject translator: JsonObject {
                      property string engine: "auto"
                      property string targetLanguage: "auto"
                      property string sourceLanguage: "auto"
                  }
              }

              property JsonObject light: JsonObject {
                  property JsonObject night: JsonObject {
                      property bool automatic: true
                      property string from: "19:00"
                      property string to: "06:30"
                      property int colorTemperature: 5000
                  }
              }

              property JsonObject networking: JsonObject {
                  property string userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
              }

              property JsonObject osd: JsonObject {
                  property int timeout: 1000
              }

              property JsonObject osk: JsonObject {
                  property string layout: "qwerty_full"
                  property bool pinnedOnStartup: false
              }

              property JsonObject overview: JsonObject {
                  property bool enable: true
                  property real scale: 0.18
                  property real rows: 2
                  property real columns: 5
              }

              property JsonObject resources: JsonObject {
                  property int updateInterval: 3000
              }

              property JsonObject search: JsonObject {
                  property int nonAppResultDelay: 30
                  property string engineBaseUrl: "https://www.google.com/search?q="
                  property list<string> excludedSites: ["quora.com"]
                  property bool sloppy: false
                  property JsonObject prefix: JsonObject {
                      property string action: "/"
                      property string clipboard: ";"
                      property string emojis: ":"
                  }
              }

              property JsonObject sidebar: JsonObject {
                  property bool keepRightSidebarLoaded: true
                  property JsonObject translator: JsonObject {
                      property int delay: 300
                  }
                  property JsonObject booru: JsonObject {
                      property bool allowNsfw: false
                      property string defaultProvider: "yandere"
                      property int limit: 20
                      property JsonObject zerochan: JsonObject {
                          property string username: "[unset]"
                      }
                  }
              }
              
              property JsonObject time: JsonObject {
                  property string format: "${cfg.time.format}"
                  property string dateFormat: "${cfg.time.dateFormat}"
              }

              property JsonObject windows: JsonObject {
                  property bool showTitlebar: true
                  property bool centerTitle: true
              }

              property JsonObject hacks: JsonObject {
                  property int arbitraryRaceConditionDelay: 20
              }

              property JsonObject screenshotTool: JsonObject {
                  property bool showContentRegions: true
              }
          }
      }
    '';
  };
}
