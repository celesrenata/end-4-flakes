# Main Home Manager module for dots-hyprland
# Supports both declarative and writable modes
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.dots-hyprland;
  packages = import ../packages { inherit pkgs; };
in
{
  imports = [
    ./python-environment.nix
    ./configuration.nix
    ./writable-mode.nix
    ./components/quickshell-service.nix
    ./components/quickshell-config.nix
    ./components/hyprland-config.nix
    ./components/terminal-config.nix
    ./components/touchegg.nix
    ./components/config-override.nix
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
      type = types.enum [ "declarative" "writable" "hybrid" ];
      default = "hybrid";
      description = ''
        Configuration mode:
        - hybrid: Hyprland declarative + Quickshell copied (recommended)
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
    # Enable Python environment for color generation
    programs.dots-hyprland.python = {
      enable = true;
      autoSetup = true;
    };
    
    # Install packages based on selected set
    home.packages = 
      let
        packageSets = import ../packages/dots-hyprland-packages.nix { inherit lib pkgs; };
      in
      if cfg.packageSet == "minimal" then packageSets.minimalPackages
      else if cfg.packageSet == "essential" then packageSets.essentialPackages
      else packageSets.allPackages;

    # Enable configuration management based on mode
    programs.dots-hyprland.configuration = mkIf (cfg.mode == "declarative" || cfg.mode == "hybrid") {
      enable = mkDefault (cfg.mode == "hybrid");  # Enable copying for hybrid mode
      source = cfg.source;
      # In hybrid mode, copy Quickshell but not Hyprland (use overrides instead)
      copyMiscConfig = mkDefault (cfg.mode == "hybrid");
      copyFishConfig = mkDefault true;
      copyHyprlandConfig = mkDefault (cfg.mode == "declarative");  # Only copy in pure declarative mode
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

    # Set critical environment variables (required for both modes)
    home.sessionVariables = {
      ILLOGICAL_IMPULSE_VIRTUAL_ENV = "$HOME/.local/state/quickshell/.venv";
      # Ensure GNOME schemas are available for gsettings
      XDG_DATA_DIRS = "$XDG_DATA_DIRS:${pkgs.gsettings-desktop-schemas}/share";
    };
    
    # Ensure ~/.local/bin is in PATH for user scripts
    home.sessionPath = [ "$HOME/.local/bin" ];

    # Generate qmldir files for all modes (runs after all config is in place)
    home.activation.generateQmldirFiles = lib.hm.dag.entryAfter ["linkGeneration"] ''
      if [[ -d "$HOME/.config/quickshell/ii" ]]; then
        $DRY_RUN_CMD echo "🔧 Generating qmldir files with singleton detection..."
        $DRY_RUN_CMD ${packages.generate-qmldir}/bin/generate-qmldir "$HOME/.config/quickshell/ii"
        $DRY_RUN_CMD echo "✅ qmldir files generated successfully for ${cfg.mode} mode"
      else
        $DRY_RUN_CMD echo "⚠️  Warning: quickshell/ii directory not found, skipping qmldir generation"
      fi
    '';

    # Use quickshell directly with proper environment
    home.activation.createWorkingQsScript = lib.hm.dag.entryAfter ["linkGeneration"] ''
      $DRY_RUN_CMD echo "✅ Using quickshell directly (no wrapper script needed)"
      
      # Also install the quickshell reset script
      $DRY_RUN_CMD echo "🔧 Installing quickshell reset script..."
      $DRY_RUN_CMD cp "${packages.quickshell-reset}/bin/quickshell-reset.sh" "$HOME/.local/bin/"
      $DRY_RUN_CMD chmod +x "$HOME/.local/bin/quickshell-reset.sh"
      $DRY_RUN_CMD echo "✅ Quickshell reset script installed successfully"
    '';

    # Custom activation script to copy quickshell configs (needed for relative imports)
    home.activation.copyQuickshellConfigs = lib.hm.dag.entryBefore ["linkGeneration"] ''
      $DRY_RUN_CMD echo "🔧 Setting up quickshell configuration for ${cfg.mode} mode..."
      
      # Remove any existing symlinked configs to avoid conflicts with system home-manager
      if [[ -L "$HOME/.config/quickshell" ]]; then
        $DRY_RUN_CMD rm "$HOME/.config/quickshell"
        $DRY_RUN_CMD echo "  → Removed conflicting symlinked quickshell config"
      fi
      
      # Handle conflicting .local/share symlinks that may interfere with home-manager
      if [[ -L "$HOME/.local/share/icons" ]]; then
        $DRY_RUN_CMD rm "$HOME/.local/share/icons"
        $DRY_RUN_CMD echo "  → Removed conflicting symlinked icons directory"
      fi
      
      if [[ -L "$HOME/.local/share/konsole" ]]; then
        $DRY_RUN_CMD rm "$HOME/.local/share/konsole"
        $DRY_RUN_CMD echo "  → Removed conflicting symlinked konsole directory"
      fi
      
      # Handle conflicting .config directories
      if [[ -L "$HOME/.config/fish" ]]; then
        $DRY_RUN_CMD rm "$HOME/.config/fish"
        $DRY_RUN_CMD echo "  → Removed conflicting symlinked fish config"
      fi
      
      if [[ -L "$HOME/.config/matugen" ]]; then
        $DRY_RUN_CMD rm "$HOME/.config/matugen"
        $DRY_RUN_CMD echo "  → Removed conflicting symlinked matugen config"
      fi
      
      # Also handle if they exist as regular directories
      if [[ -d "$HOME/.local/share/konsole" && ! -L "$HOME/.local/share/konsole" ]]; then
        $DRY_RUN_CMD mv "$HOME/.local/share/konsole" "$HOME/.local/share/konsole.backup-$(date +%Y%m%d-%H%M%S)"
        $DRY_RUN_CMD echo "  → Backed up existing konsole directory"
      fi
      
      if [[ -d "$HOME/.config/fish" && ! -L "$HOME/.config/fish" ]]; then
        $DRY_RUN_CMD mv "$HOME/.config/fish" "$HOME/.config/fish.backup-$(date +%Y%m%d-%H%M%S)"
        $DRY_RUN_CMD echo "  → Backed up existing fish config directory"
      fi
      
      if [[ -d "$HOME/.config/matugen" && ! -L "$HOME/.config/matugen" ]]; then
        $DRY_RUN_CMD mv "$HOME/.config/matugen" "$HOME/.config/matugen.backup-$(date +%Y%m%d-%H%M%S)"
        $DRY_RUN_CMD echo "  → Backed up existing matugen config directory"
      fi
    '';

    # Copy quickshell config after link generation
    home.activation.setupQuickshellConfig = lib.hm.dag.entryAfter ["linkGeneration"] ''
      ${optionalString (cfg.mode == "hybrid") ''
        # Copy quickshell config to enable relative imports
        if [[ ! -d "$HOME/.config/quickshell" ]] || [[ -L "$HOME/.config/quickshell" ]]; then
          $DRY_RUN_CMD mkdir -p "$HOME/.config"
          $DRY_RUN_CMD cp -r "${cfg.source}/.config/quickshell" "$HOME/.config/"
          $DRY_RUN_CMD chmod -R u+w "$HOME/.config/quickshell"
          $DRY_RUN_CMD echo "✅ Quickshell configuration copied successfully"
        else
          $DRY_RUN_CMD echo "✅ Quickshell configuration already exists"
        fi
        
        # Ensure quickshell uses the proper environment variables
        $DRY_RUN_CMD mkdir -p "$HOME/.local/bin"
        $DRY_RUN_CMD echo "  → Ensuring ~/.local/bin is in PATH for hybrid mode"
      ''}
    '';

    # Ensure XDG directories exist (installer requirement)
    xdg.enable = true;
    xdg.userDirs.enable = true;
  };
}
