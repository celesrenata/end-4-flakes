# Hyprland configuration options for dots-hyprland
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.dots-hyprland.hyprland;
in
{
  options.programs.dots-hyprland.hyprland = {
    # General settings
    general = {
      gapsIn = mkOption {
        type = types.int;
        default = 4;
        description = "Inner gaps between windows";
      };
      
      gapsOut = mkOption {
        type = types.int;
        default = 7;
        description = "Outer gaps around windows";
      };
      
      borderSize = mkOption {
        type = types.int;
        default = 2;
        description = "Border width around windows";
      };
      
      allowTearing = mkOption {
        type = types.bool;
        default = false;
        description = "Allow screen tearing (useful for gaming)";
      };
    };
    
    # Decoration settings
    decoration = {
      rounding = mkOption {
        type = types.int;
        default = 16;
        description = "Corner rounding radius";
      };
      
      blurEnabled = mkOption {
        type = types.bool;
        default = true;
        description = "Enable background blur";
      };
    };
    
    # Gesture settings
    gestures = {
      workspaceSwipe = mkOption {
        type = types.bool;
        default = true;
        description = "Enable workspace swipe gestures";
      };
    };
    
    # Monitor configuration
    monitors = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Monitor configuration strings";
      example = [ "eDP-1,1920x1080@60,0x0,1" ];
    };
  };
  
  config = mkIf (config.programs.dots-hyprland.enable && config.programs.dots-hyprland.overrides.hyprlandConf == null) {
    # Only generate if no manual override is set
    xdg.configFile."hypr/general.conf".text = ''
      # General Hyprland configuration for dots-hyprland (NixOS-managed)
      
      ${optionalString (cfg.monitors != []) ''
      # Monitor configuration
      ${concatMapStringsSep "\n" (monitor: "monitor=${monitor}") cfg.monitors}
      ''}
      
      # Gestures
      gestures {
          workspace_swipe = ${boolToString cfg.gestures.workspaceSwipe}
          workspace_swipe_distance = 700
          workspace_swipe_fingers = 3
          workspace_swipe_min_fingers = true
          workspace_swipe_cancel_ratio = 0.2
          workspace_swipe_min_speed_to_force = 5
          workspace_swipe_direction_lock = true
          workspace_swipe_direction_lock_threshold = 10
          workspace_swipe_create_new = true
      }

      general {
          # Gaps and border
          gaps_in = ${toString cfg.general.gapsIn}
          gaps_out = ${toString cfg.general.gapsOut}
          gaps_workspaces = 50
          
          border_size = ${toString cfg.general.borderSize}
          col.active_border = rgba(cba6f7ff)
          col.inactive_border = rgba(313244ff)
          resize_on_border = true

          no_focus_fallback = true
          
          allow_tearing = ${boolToString cfg.general.allowTearing}
          
          snap {
              enabled = true
          }
      }

      dwindle {
          preserve_split = true
          smart_split = false
          smart_resizing = false
      }

      decoration {
          rounding = ${toString cfg.decoration.rounding}
          
          blur {
              enabled = ${boolToString cfg.decoration.blurEnabled}
              xray = true
              special = false
              new_optimizations = true
              size = 14
              passes = 4
              brightness = 1
              noise = 0.01
              contrast = 1
              popups = true
              popups_ignorealpha = 0.6
          }
          
          drop_shadow = true
          shadow_ignore_window = true
          shadow_offset = 0 2
          shadow_range = 20
          shadow_render_power = 3
          col.shadow = rgba(00000055)
      }
    '';
  };
}
