# Main Home Manager module for dots-hyprland
# Supports both declarative and writable modes
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.dots-hyprland;
in
{
  imports = [
    ./python-environment.nix
    ./configuration.nix
    ./writable-mode.nix
    ./components/quickshell-service.nix
    ./components/touchegg.nix
  ];

  options.programs.dots-hyprland = {
    enable = mkEnableOption "dots-hyprland desktop environment";
    
    source = mkOption {
      type = types.path;
      description = "Source path for clean dots-hyprland configuration";
      example = "inputs.dots-hyprland";
    };
    
    packageSet = mkOption {
      type = types.enum [ "minimal" "essential" "all" ];
      default = "essential";
      description = "Which package set to install";
    };
    
    mode = mkOption {
      type = types.enum [ "declarative" "writable" ];
      default = "declarative";
      description = ''
        Configuration mode:
        - declarative: Files managed by Home Manager (read-only)
        - writable: Files staged to .configstaging, user copies and modifies
      '';
    };
    
    writable = mkOption {
      type = types.submodule {
        options = {
          stagingDir = mkOption {
            type = types.str;
            default = ".configstaging";
            description = "Directory to stage configuration files";
          };
          
          setupScript = mkOption {
            type = types.str;
            default = "initialSetup.sh";
            description = "Name of the setup script in ~/.local/bin/";
          };
          
          backupExisting = mkOption {
            type = types.bool;
            default = true;
            description = "Backup existing configuration files";
          };
          
          symlinkMode = mkOption {
            type = types.bool;
            default = false;
            description = "Create symlinks instead of copying files";
          };
        };
      };
      default = {};
      description = "Writable mode configuration";
    };
  };

  config = mkIf cfg.enable {
    # Install packages based on selected set
    home.packages = 
      let
        packageSets = import ../packages/dots-hyprland-packages.nix { inherit lib pkgs; };
      in
      if cfg.packageSet == "minimal" then packageSets.minimalPackages
      else if cfg.packageSet == "essential" then packageSets.essentialPackages
      else packageSets.allPackages;

    # Enable Python virtual environment (CRITICAL for both modes)
    programs.dots-hyprland.python = {
      enable = true;
      autoSetup = true;
    };

    # Enable configuration management based on mode
    programs.dots-hyprland.configuration = mkIf (cfg.mode == "declarative") {
      enable = true;
      source = cfg.source;
    };
    
    # Enable writable mode
    programs.dots-hyprland.writable-mode = mkIf (cfg.mode == "writable") {
      enable = true;
      source = cfg.source;
      inherit (cfg.writable) stagingDir setupScript backupExisting symlinkMode;
    };
    
    # Enable quickshell service (works with both modes)
    programs.dots-hyprland.quickshell = {
      enable = true;
      autoStart = true;
      restartOnFailure = true;
      logLevel = "info";
    };
    
    # Enable touchegg gesture support
    programs.dots-hyprland.touchegg = {
      enable = true;
    };
    
    # Enable custom keybindings

    # Set critical environment variable (required for both modes)
    home.sessionVariables = {
      ILLOGICAL_IMPULSE_VIRTUAL_ENV = "$HOME/.local/state/quickshell/.venv";
    };

    # Ensure XDG directories exist (installer requirement)
    xdg.enable = true;
    xdg.userDirs.enable = true;
  };
}
