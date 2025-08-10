# Quickshell service integration with staging system
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.dots-hyprland.quickshell;
  mainCfg = config.programs.dots-hyprland;
  
  # Use the wrapped quickshell from our overlay (includes Qt5Compat support)
  workingQuickshell = pkgs.quickshell;
  
  # Service startup script that handles initial setup
  quickshellStartup = pkgs.writeShellScript "quickshell-startup" ''
    #!/usr/bin/env bash
    set -e
    
    # Colors for logging
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    NC='\033[0m'
    
    log() {
        echo -e "''${GREEN}[quickshell-service]''${NC} $1" >&2
    }
    
    warn() {
        echo -e "''${YELLOW}[quickshell-service]''${NC} WARNING: $1" >&2
    }
    
    error() {
        echo -e "''${RED}[quickshell-service]''${NC} ERROR: $1" >&2
    }
    
    STAGING_DIR="$HOME/${mainCfg.writable-mode.stagingDir}"
    CONFIG_DIR="$HOME/.config"
    SETUP_SCRIPT="$HOME/${mainCfg.writable-mode.setupScript}"
    SETUP_MARKER="$HOME/.cache/dots-hyprland/setup-complete"
    
    # Ensure cache directory exists
    mkdir -p "$(dirname "$SETUP_MARKER")"
    
    # Check if initial setup has been run
    if [[ ! -f "$SETUP_MARKER" ]]; then
        log "🚀 First run detected - running initial setup"
        
        # Check if staging directory exists
        if [[ ! -d "$STAGING_DIR" ]]; then
            error "Staging directory not found: $STAGING_DIR"
            error "Please run 'home-manager switch' first"
            exit 1
        fi
        
        # Check if setup script exists
        if [[ ! -x "$SETUP_SCRIPT" ]]; then
            error "Setup script not found or not executable: $SETUP_SCRIPT"
            exit 1
        fi
        
        log "📋 Running initial setup script..."
        if "$SETUP_SCRIPT"; then
            # Mark setup as complete
            echo "$(date)" > "$SETUP_MARKER"
            log "✅ Initial setup completed successfully"
        else
            error "❌ Initial setup failed"
            exit 1
        fi
    else
        log "✅ Setup already completed ($(cat "$SETUP_MARKER"))"
    fi
    
    # Verify quickshell configuration exists
    if [[ ! -d "$CONFIG_DIR/quickshell" ]]; then
        error "Quickshell configuration not found at $CONFIG_DIR/quickshell"
        error "Initial setup may have failed"
        exit 1
    fi
    
    # Set up environment variables
    export ILLOGICAL_IMPULSE_VIRTUAL_ENV="$HOME/.local/state/quickshell/.venv"
    export QT_SCALE_FACTOR="${toString cfg.scaling}"
    export QT_QUICK_CONTROLS_STYLE="Basic"
    export QT_QUICK_FLICKABLE_WHEEL_DECELERATION="10000"
    
    # Ensure PATH includes user applications - CRITICAL for app launching
    export PATH="${config.home.profileDirectory}/bin:/run/wrappers/bin:${config.home.homeDirectory}/.nix-profile/bin:/etc/profiles/per-user/${config.home.username}/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:$PATH"
    export XDG_DATA_DIRS="${config.home.profileDirectory}/share:${config.home.homeDirectory}/.nix-profile/share:/etc/profiles/per-user/${config.home.username}/share:/nix/var/nix/profiles/default/share:/run/current-system/sw/share:$XDG_DATA_DIRS"
    
    # Create application launcher wrapper that quickshell can use
    LAUNCHER_WRAPPER="$HOME/.cache/dots-hyprland/app-launcher"
    mkdir -p "$(dirname "$LAUNCHER_WRAPPER")"
    cat > "$LAUNCHER_WRAPPER" << 'EOF'
#!/usr/bin/env bash
# Application launcher wrapper for quickshell
# Ensures proper PATH and environment for launched applications

# Use the same PATH that quickshell has
export PATH="${config.home.profileDirectory}/bin:/run/wrappers/bin:${config.home.homeDirectory}/.nix-profile/bin:/etc/profiles/per-user/${config.home.username}/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
export XDG_DATA_DIRS="${config.home.profileDirectory}/share:${config.home.homeDirectory}/.nix-profile/share:/etc/profiles/per-user/${config.home.username}/share:/nix/var/nix/profiles/default/share:/run/current-system/sw/share"

# Launch the application
exec "$@"
EOF
    chmod +x "$LAUNCHER_WRAPPER"
    
    # Export the launcher wrapper path for quickshell to use
    export DOTS_HYPRLAND_APP_LAUNCHER="$LAUNCHER_WRAPPER"
    
    # Verify Python virtual environment
    if [[ ! -d "$ILLOGICAL_IMPULSE_VIRTUAL_ENV" ]]; then
        warn "Python virtual environment not found at $ILLOGICAL_IMPULSE_VIRTUAL_ENV"
        warn "Some features may not work correctly"
    fi
    
    log "🎯 Starting quickshell with dots-hyprland configuration"
    log "📁 Config: $CONFIG_DIR/quickshell/ii/shell.qml"
    log "🐍 Python venv: $ILLOGICAL_IMPULSE_VIRTUAL_ENV"
    log "🚀 App launcher: $LAUNCHER_WRAPPER"
    
    # Start quickshell
    exec ${workingQuickshell}/bin/qs -p "$CONFIG_DIR/quickshell/ii/shell.qml"
  '';
  
in
{
  options.programs.dots-hyprland.quickshell = {
    enable = mkEnableOption "Quickshell service with staging integration";
    
    autoStart = mkEnableOption "Auto-start with Hyprland session" // { default = true; };
    
    restartOnFailure = mkEnableOption "Restart service on failure" // { default = true; };
    
    scaling = mkOption {
      type = types.float;
      default = 1.0;
      description = "UI scaling factor";
    };
    
    logLevel = mkOption {
      type = types.enum [ "debug" "info" "warning" "error" ];
      default = "info";
      description = "Logging level for quickshell service";
    };
  };
  
  config = mkIf cfg.enable {
    # Install the working quickshell build and service management scripts
    home.packages = [ workingQuickshell ] ++ (with pkgs; [
      (writeShellScriptBin "quickshell-restart" ''
        systemctl --user restart quickshell.service
        echo "✅ Quickshell service restarted"
      '')
      
      (writeShellScriptBin "quickshell-status" ''
        echo "🔍 Quickshell Service Status"
        echo "=========================="
        systemctl --user status quickshell.service --no-pager
        echo ""
        echo "📋 Recent logs:"
        journalctl --user -u quickshell.service -n 10 --no-pager
      '')
      
      (writeShellScriptBin "quickshell-logs" ''
        echo "📋 Following quickshell logs (Ctrl+C to exit):"
        journalctl --user -u quickshell.service -f
      '')
      
      (writeShellScriptBin "quickshell-debug" ''
        echo "🐛 Starting quickshell in debug mode..."
        systemctl --user stop quickshell.service
        QT_LOGGING_RULES="quickshell.*=true" ${quickshellStartup}
      '')
    ]);
    
    # Systemd user service for quickshell
    systemd.user.services.quickshell = {
      Unit = {
        Description = "Quickshell - QtQuick based desktop shell with dots-hyprland";
        Documentation = [ "https://quickshell.org" "https://end-4.github.io/dots-hyprland-wiki/" ];
        PartOf = [ "hyprland-session.target" ];
        After = [ "hyprland-session.target" "graphical-session.target" ];
        Wants = [ "hyprland-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = quickshellStartup;
        ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR2 $MAINPID";
        Restart = if cfg.restartOnFailure then "on-failure" else "no";
        RestartSec = 2;
        TimeoutStartSec = 30;
        TimeoutStopSec = 10;
        
        # Environment variables - include full user environment
        Environment = [
          "QT_SCALE_FACTOR=${toString cfg.scaling}"
          "QT_QUICK_CONTROLS_STYLE=Basic"
          "QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000"
          "QT_LOGGING_RULES=${
            if cfg.logLevel == "debug" then "quickshell.*=true"
            else if cfg.logLevel == "warning" then "*.warning=true"
            else if cfg.logLevel == "error" then "*.critical=true"
            else "*.info=true"
          }"
          # Include user's full PATH so applications can be launched
          "PATH=${config.home.profileDirectory}/bin:/run/wrappers/bin:${config.home.homeDirectory}/.nix-profile/bin:/etc/profiles/per-user/${config.home.username}/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
          # Include XDG data directories for application discovery
          "XDG_DATA_DIRS=${config.home.profileDirectory}/share:${config.home.homeDirectory}/.nix-profile/share:/etc/profiles/per-user/${config.home.username}/share:/nix/var/nix/profiles/default/share:/run/current-system/sw/share"
          # Application launcher wrapper path
          "DOTS_HYPRLAND_APP_LAUNCHER=%h/.cache/dots-hyprland/app-launcher"
        ];
        
        # Working directory
        WorkingDirectory = "%h";
        
        # Security settings
        PrivateNetwork = false;
        ProtectSystem = "strict";
        ProtectHome = false; # Need access to home directory
        NoNewPrivileges = true;
        
        # Resource limits
        MemoryMax = "2G";
        CPUQuota = "200%";
      };

      Install = mkIf cfg.autoStart {
        WantedBy = [ "hyprland-session.target" ];
      };
    };
    
    # Create hyprland session target if it doesn't exist
    systemd.user.targets.hyprland-session = {
      Unit = {
        Description = "Hyprland compositor session";
        Documentation = [ "man:systemd.special(7)" ];
        BindsTo = [ "graphical-session.target" ];
        Wants = [ "graphical-session-pre.target" ];
        After = [ "graphical-session-pre.target" ];
      };
    };
  };
}
