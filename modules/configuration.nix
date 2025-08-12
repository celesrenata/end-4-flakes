# Configuration management for dots-hyprland
# Replicates the installer's rsync behavior exactly
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.dots-hyprland.configuration;
  mainCfg = config.programs.dots-hyprland;
in
{
  options.programs.dots-hyprland.configuration = {
    enable = mkEnableOption "dots-hyprland configuration management";
    
    source = mkOption {
      type = types.path;
      description = "Source path for dots-hyprland configuration";
      example = "inputs.dots-hyprland";
    };
    
    copyMiscConfig = mkOption {
      type = types.bool;
      default = true;
      description = "Copy miscellaneous config files (everything except fish and hypr)";
    };
    
    copyFishConfig = mkOption {
      type = types.bool;
      default = true;
      description = "Copy fish shell configuration";
    };
    
    copyHyprlandConfig = mkOption {
      type = types.bool;
      default = true;
      description = "Copy Hyprland configuration";
    };
    
    # Individual application enable options
    applications = {
      foot = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable foot terminal configuration";
        };
      };
      
      kitty = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable kitty terminal configuration";
        };
      };
      
      fuzzel = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable fuzzel launcher configuration";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # Replicate installer's MISC config copying
    # "for i in $(find .config/ -mindepth 1 -maxdepth 1 ! -name 'fish' ! -name 'hypr' -exec basename {} \;)"
    xdg.configFile = mkMerge [
      # MISC configs (everything except fish and hypr)
      (mkIf cfg.copyMiscConfig (
        let
          # Get all directories in .config except fish, hypr, and quickshell (quickshell handled specially)
          # Now with individual enable options
          configDirs = lib.optionals cfg.applications.kitty.enable [ "kitty" ] ++
                      lib.optionals cfg.applications.foot.enable [ "foot" ] ++
                      lib.optionals cfg.applications.fuzzel.enable [ "fuzzel" ] ++
                      [ "wlogout" "matugen" ];  # Always enabled applications
          
          configFiles = listToAttrs (map (dir: {
            name = dir;
            value = {
              source = "${cfg.source}/${dir}";
              recursive = true;
            };
          }) configDirs);
        in
        configFiles
      ))
      
      # Fish configuration
      (mkIf cfg.copyFishConfig {
        "fish" = {
          source = "${cfg.source}/.config/fish";
          recursive = true;
        };
      })
      
      # Hyprland configuration (special handling like installer)
      (mkIf cfg.copyHyprlandConfig {
        # Copy hypr directory excluding specific files
        # rsync -av --delete --exclude '/custom' --exclude '/hyprlock.conf' --exclude '/hypridle.conf' --exclude '/hyprland.conf'
        "hypr" = {
          source = pkgs.runCommand "hypr-config-filtered" {} ''
            mkdir -p $out
            
            # Copy everything from source hypr directory
            cp -r ${cfg.source}/.config/hypr/* $out/ 2>/dev/null || true
            
            # Remove excluded files (replicating installer --exclude logic)
            rm -rf $out/custom 2>/dev/null || true
            rm -f $out/hyprlock.conf 2>/dev/null || true
            rm -f $out/hypridle.conf 2>/dev/null || true
            rm -f $out/hyprland.conf 2>/dev/null || true
            
            # Ensure we have the directory structure
            mkdir -p $out
          '';
          recursive = true;
        };
        
        # Copy the main config files separately (installer does this)
        "hypr/hyprland.conf" = {
          source = "${cfg.source}/.config/hypr/hyprland.conf";
        };
        "hypr/hypridle.conf" = {
          source = "${cfg.source}/.config/hypr/hypridle.conf";
        };
        "hypr/hyprlock.conf" = {
          source = "${cfg.source}/.config/hypr/hyprlock.conf";
        };
      })
    ];

    # Copy .local/share files (replicating installer)
    home.file = {
      ".local/share/icons" = mkIf cfg.copyMiscConfig {
        source = "${cfg.source}/.local/share/icons";
        recursive = true;
      };
      
      ".local/share/konsole" = mkIf cfg.copyMiscConfig {
        source = "${cfg.source}/.local/share/konsole";
        recursive = true;
      };
    };
    
    # Ensure XDG directories exist (installer creates these)
    home.activation.createXdgDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -p $HOME/.local/bin
      $DRY_RUN_CMD mkdir -p $HOME/.cache
      $DRY_RUN_CMD mkdir -p $HOME/.config
      $DRY_RUN_CMD mkdir -p $HOME/.local/share
    '';
  };
}
