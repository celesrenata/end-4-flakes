# Configuration override system - allows complete manual control
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.dots-hyprland;
in
{
  options.programs.dots-hyprland.overrides = {
    # Complete file overrides - when set, completely replaces any generated config
    hyprlandConf = mkOption {
      type = types.nullOr types.lines;
      default = null;
      description = ''
        Complete hyprland.conf content. When set, completely overrides:
        - Any rich hyprland.* configuration options
        - Any copied hyprland.conf from source
        - Generates the entire file from this content
      '';
      example = ''
        # Custom Hyprland configuration
        general {
          gaps_in = 10
          gaps_out = 20
        }
      '';
    };

    quickshellConfig = mkOption {
      type = types.nullOr types.lines;
      default = null;
      description = ''
        Complete Config.qml content. When set, completely overrides:
        - Any rich quickshell.* configuration options  
        - Any copied Config.qml from source
        - Generates the entire file from this content
      '';
    };

    footConfig = mkOption {
      type = types.nullOr types.lines;
      default = null;
      description = ''
        Complete foot.ini content. When set, completely overrides:
        - Any rich terminal.* configuration options
        - Any copied foot.ini from source  
        - Generates the entire file from this content
      '';
    };

    toucheggConf = mkOption {
      type = types.nullOr types.lines;
      default = null;
      description = ''
        Complete touchegg.conf content. When set, completely overrides:
        - Any copied touchegg.conf from source
        - Generates the entire file from this content
      '';
    };

    # Directory-level overrides
    hyprDirectory = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Complete hypr directory override. When set, copies entire directory
        and ignores all hyprland configuration options.
      '';
    };

    quickshellDirectory = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Complete quickshell directory override. When set, copies entire directory
        and ignores all quickshell configuration options.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Override warnings
    warnings = 
      (optional (cfg.overrides.hyprlandConf != null && cfg.hyprland != {}) 
        "dots-hyprland: overrides.hyprlandConf is set, ignoring all hyprland.* options") ++
      (optional (cfg.overrides.quickshellConfig != null && cfg.quickshell != {}) 
        "dots-hyprland: overrides.quickshellConfig is set, ignoring all quickshell.* options") ++
      (optional (cfg.overrides.footConfig != null && cfg.terminal != {}) 
        "dots-hyprland: overrides.footConfig is set, ignoring all terminal.* options");

    # File overrides take absolute priority
    xdg.configFile = mkMerge [
      # Hyprland complete override
      (mkIf (cfg.overrides.hyprlandConf != null) {
        "hypr/hyprland.conf".text = cfg.overrides.hyprlandConf;
      })

      # Quickshell complete override  
      (mkIf (cfg.overrides.quickshellConfig != null) {
        "quickshell/ii/modules/common/Config.qml".text = cfg.overrides.quickshellConfig;
      })

      # Terminal complete override
      (mkIf (cfg.overrides.footConfig != null) {
        "foot/foot.ini".text = cfg.overrides.footConfig;
      })

      # Touchegg complete override
      (mkIf (cfg.overrides.toucheggConf != null) {
        "touchegg/touchegg.conf".text = cfg.overrides.toucheggConf;
      })

      # Directory overrides
      (mkIf (cfg.overrides.hyprDirectory != null) {
        "hypr" = {
          source = cfg.overrides.hyprDirectory;
          recursive = true;
        };
      })

      (mkIf (cfg.overrides.quickshellDirectory != null) {
        "quickshell" = {
          source = cfg.overrides.quickshellDirectory;
          recursive = true;
        };
      })
    ];
  };
}
