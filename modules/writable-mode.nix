# Writable mode for dots-hyprland
# Stages configuration to .configstaging and provides setup script
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.dots-hyprland.writable-mode;
  mainCfg = config.programs.dots-hyprland;
  
  # Create the initial setup script
  setupScript = pkgs.writeShellScript "dots-hyprland-setup" ''
    #!/usr/bin/env bash
    set -e
    
    # Colors for output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
    
    log() {
        echo -e "''${GREEN}[dots-hyprland]''${NC} $1"
    }
    
    warn() {
        echo -e "''${YELLOW}[dots-hyprland]''${NC} WARNING: $1"
    }
    
    error() {
        echo -e "''${RED}[dots-hyprland]''${NC} ERROR: $1"
    }
    
    info() {
        echo -e "''${BLUE}[dots-hyprland]''${NC} $1"
    }
    
    STAGING_DIR="$HOME/${cfg.stagingDir}"
    CONFIG_DIR="$HOME/.config"
    BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
    
    log "🚀 dots-hyprland Initial Setup"
    log "📁 Staging: $STAGING_DIR"
    log "🎯 Target: $CONFIG_DIR"
    
    # Check if staging directory exists
    if [[ ! -d "$STAGING_DIR" ]]; then
        error "Staging directory not found: $STAGING_DIR"
        error "Please run 'home-manager switch' first to create the staging area"
        exit 1
    fi
    
    # Backup existing configuration if requested
    ${optionalString cfg.backupExisting ''
    if [[ -d "$CONFIG_DIR" ]]; then
        log "💾 Creating backup at $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
        
        # Backup specific directories that will be overwritten
        for dir in quickshell hypr fish foot kitty fuzzel wlogout matugen; do
            if [[ -d "$CONFIG_DIR/$dir" ]]; then
                info "  Backing up $dir"
                cp -r "$CONFIG_DIR/$dir" "$BACKUP_DIR/" 2>/dev/null || true
            fi
        done
        
        log "✅ Backup complete"
    fi
    ''}
    
    # Function to copy or symlink files
    copy_config() {
        local src="$1"
        local dst="$2"
        local name="$(basename "$src")"
        
        if [[ -d "$src" ]]; then
            info "📂 Processing directory: $name"
            mkdir -p "$dst"
            
            ${if cfg.symlinkMode then ''
            # Create symlink
            if [[ -L "$dst" ]]; then
                rm "$dst"
            elif [[ -d "$dst" ]]; then
                rm -rf "$dst"
            fi
            ln -sf "$src" "$dst"
            info "  🔗 Symlinked: $name"
            '' else ''
            # Copy files
            cp -rf "$src"/* "$dst/" 2>/dev/null || true
            info "  📋 Copied: $name"
            ''}
        elif [[ -f "$src" ]]; then
            info "📄 Processing file: $name"
            mkdir -p "$(dirname "$dst")"
            
            ${if cfg.symlinkMode then ''
            # Create symlink
            if [[ -L "$dst" ]] || [[ -f "$dst" ]]; then
                rm "$dst"
            fi
            ln -sf "$src" "$dst"
            info "  🔗 Symlinked: $name"
            '' else ''
            # Copy file
            cp "$src" "$dst"
            info "  📋 Copied: $name"
            ''}
        fi
    }
    
    # Copy/symlink all staged configuration
    log "🔄 ${if cfg.symlinkMode then "Symlinking" else "Copying"} configuration files..."
    
    # Process all directories in staging
    for item in "$STAGING_DIR"/*; do
        if [[ -e "$item" ]]; then
            name="$(basename "$item")"
            copy_config "$item" "$CONFIG_DIR/$name"
        fi
    done
    
    # Copy .local/share files if they exist
    if [[ -d "$STAGING_DIR/.local/share" ]]; then
        log "📦 Processing .local/share files..."
        mkdir -p "$HOME/.local/share"
        copy_config "$STAGING_DIR/.local/share/icons" "$HOME/.local/share/icons"
        copy_config "$STAGING_DIR/.local/share/konsole" "$HOME/.local/share/konsole"
    fi
    
    log "✅ Configuration setup complete!"
    log ""
    log "📋 Next steps:"
    log "  1. Your configuration is now ${if cfg.symlinkMode then "symlinked" else "copied"} to ~/.config/"
    log "  2. ${if cfg.symlinkMode then "Files are symlinked - changes to staging will reflect immediately" else "Files are copied - you can now modify them freely"}"
    log "  3. Test quickshell: quickshell"
    log "  4. Test Python environment: test-dots-hyprland-venv"
    ${optionalString cfg.backupExisting ''
    log "  5. Your original config was backed up to: $BACKUP_DIR"
    ''}
    log ""
    log "🎉 Enjoy your dots-hyprland setup!"
  '';
  
  # Create a status/info script
  statusScript = pkgs.writeShellScript "dots-hyprland-status" ''
    #!/usr/bin/env bash
    
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
    
    echo -e "''${GREEN}dots-hyprland Status''${NC}"
    echo "===================="
    
    # Check staging directory
    STAGING_DIR="$HOME/${cfg.stagingDir}"
    if [[ -d "$STAGING_DIR" ]]; then
        echo -e "✅ Staging directory: ''${GREEN}$STAGING_DIR''${NC}"
        echo "   $(find "$STAGING_DIR" -type f | wc -l) files staged"
    else
        echo -e "❌ Staging directory: ''${RED}Not found''${NC}"
    fi
    
    # Check Python virtual environment
    VENV_PATH="$HOME/.local/state/quickshell/.venv"
    if [[ -d "$VENV_PATH" ]]; then
        echo -e "✅ Python venv: ''${GREEN}$VENV_PATH''${NC}"
        if [[ -f "$VENV_PATH/bin/python" ]]; then
            VERSION=$("$VENV_PATH/bin/python" --version 2>&1)
            echo "   $VERSION"
        fi
    else
        echo -e "❌ Python venv: ''${RED}Not found''${NC}"
    fi
    
    # Check quickshell config
    if [[ -d "$HOME/.config/quickshell" ]]; then
        echo -e "✅ Quickshell config: ''${GREEN}~/.config/quickshell''${NC}"
        if [[ -L "$HOME/.config/quickshell" ]]; then
            echo "   (symlinked to staging)"
        else
            echo "   (copied from staging)"
        fi
    else
        echo -e "❌ Quickshell config: ''${RED}Not found''${NC}"
    fi
    
    # Check environment variable
    if [[ -n "$ILLOGICAL_IMPULSE_VIRTUAL_ENV" ]]; then
        echo -e "✅ Environment variable: ''${GREEN}ILLOGICAL_IMPULSE_VIRTUAL_ENV''${NC}"
        echo "   $ILLOGICAL_IMPULSE_VIRTUAL_ENV"
    else
        echo -e "❌ Environment variable: ''${RED}ILLOGICAL_IMPULSE_VIRTUAL_ENV not set''${NC}"
    fi
    
    echo ""
    echo "Commands:"
    echo "  ${cfg.setupScript}     - Run initial setup"
    echo "  dots-hyprland-status  - Show this status"
    echo "  test-dots-hyprland-venv - Test Python environment"
  '';
in
{
  options.programs.dots-hyprland.writable-mode = {
    enable = mkEnableOption "Writable mode for dots-hyprland configuration";
    
    source = mkOption {
      type = types.path;
      description = "Source path for dots-hyprland configuration";
    };
    
    stagingDir = mkOption {
      type = types.str;
      default = ".configstaging";
      description = "Directory to stage configuration files";
    };
    
    setupScript = mkOption {
      type = types.str;
      default = "initialSetup.sh";
      description = "Name of the setup script";
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

  config = mkIf cfg.enable {
    # Stage all configuration files and install scripts
    home.file = 
      let
        # Get all config directories from source
        configDirs = [
          "quickshell" "hypr" "fish" "foot" "kitty" "fuzzel" "wlogout" "matugen"
        ];
        
        # Create staging entries for each config directory
        stagingEntries = listToAttrs (map (dir: {
          name = "${cfg.stagingDir}/${dir}";
          value = {
            source = "${cfg.source}/.config/${dir}";
            recursive = true;
          };
        }) configDirs);
        
        # Add NixOS-specific patches
        nixosPatches = {
        };
        
        # Add .local/share files to staging
        localShareEntries = {
          "${cfg.stagingDir}/.local/share/icons" = {
            source = "${cfg.source}/.local/share/icons";
            recursive = true;
          };
          "${cfg.stagingDir}/.local/share/konsole" = {
            source = "${cfg.source}/.local/share/konsole";
            recursive = true;
          };
        };
        
        # Scripts and utilities
        scriptEntries = {
          ".local/bin/${cfg.setupScript}" = {
            source = setupScript;
            executable = true;
          };
          
          ".local/bin/dots-hyprland-status" = {
            source = statusScript;
            executable = true;
          };
          
          "${cfg.stagingDir}/README.md" = {
            text = ''
              # dots-hyprland Configuration Staging
              
              This directory contains the staged configuration files from the original dots-hyprland repository.
              
              ## Setup
              
              Run the setup script to copy/symlink these files to your ~/.config directory:
              
              ```bash
              ~/.local/bin/${cfg.setupScript}
              ```
              
              ## Mode: ${if cfg.symlinkMode then "Symlink" else "Copy"}
              
              ${if cfg.symlinkMode then ''
              **Symlink Mode**: Files will be symlinked to ~/.config/
              - Changes to files in staging will reflect immediately
              - Useful for development and testing
              - Files remain managed by Home Manager
              '' else ''
              **Copy Mode**: Files will be copied to ~/.config/
              - You can modify the copied files freely
              - Changes won't affect the staging area
              - Full user control over configuration
              ''}
              
              ## Status
              
              Check the current status with:
              
              ```bash
              dots-hyprland-status
              ```
              
              ## Files Staged
              
              - quickshell/ - Widget system configuration
              - hypr/ - Hyprland window manager configuration  
              - fish/ - Fish shell configuration
              - foot/ - Foot terminal configuration
              - kitty/ - Kitty terminal configuration
              - fuzzel/ - Fuzzel launcher configuration
              - wlogout/ - Logout menu configuration
              - .local/share/icons/ - Custom icons
              - .local/share/konsole/ - Konsole profiles
              
              ## Python Environment
              
              The Python virtual environment is managed separately and will be created at:
              `~/.local/state/quickshell/.venv`
              
              Test it with: `test-dots-hyprland-venv`
            '';
          };
        };
      in
      stagingEntries // localShareEntries // scriptEntries // nixosPatches;
  };
}
