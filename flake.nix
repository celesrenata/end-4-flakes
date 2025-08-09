{
  description = "NixOS adaptation of end-4's dots-hyprland using installer replication";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Official quickshell flake (our breakthrough discovery!)
    quickshell.url = "github:outfoxxed/quickshell";
    
    # Original dots-hyprland source from GitHub - tracks installer-replication branch
    dots-hyprland = {
      url = "github:celesrenata/dots-hyprland/installer-replication";
      flake = false; # Use as source only, don't build
    };
  };

  outputs = { self, nixpkgs, home-manager, quickshell, dots-hyprland, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      };
    in
    {
      # Package overlays
      overlays.default = final: prev: {
        # Make quickshell available from official flake
        quickshell = quickshell.packages.${system}.default;
      };

      # Packages
      packages.${system} = {
        # Flake management utilities
        update-flake = pkgs.writeShellScriptBin "update-flake" ''
          # dots-hyprland Flake Update Utility
          # Manages flake input updates and GitHub synchronization
          
          set -e
          
          # Colors for output
          RED='\033[0;31m'
          GREEN='\033[0;32m'
          YELLOW='\033[1;33m'
          BLUE='\033[0;34m'
          CYAN='\033[0;36m'
          NC='\033[0m' # No Color
          
          log() {
              echo -e "''${GREEN}[update-flake]''${NC} $1"
          }
          
          warn() {
              echo -e "''${YELLOW}[update-flake]''${NC} WARNING: $1"
          }
          
          error() {
              echo -e "''${RED}[update-flake]''${NC} ERROR: $1"
              exit 1
          }
          
          info() {
              echo -e "''${BLUE}[update-flake]''${NC} $1"
          }
          
          header() {
              echo -e "''${CYAN}=== $1 ===''${NC}"
          }
          
          show_help() {
              cat << EOF
          dots-hyprland Flake Update Utility
          
          USAGE:
              update-flake [OPTIONS] [COMMAND]
          
          COMMANDS:
              update          Update all flake inputs (default)
              update-source   Update only dots-hyprland source input
              pin <commit>    Pin dots-hyprland to specific commit
              branch <name>   Switch to tracking a specific branch
              status          Show current flake input status
              verify          Verify flake builds after update
              help            Show this help message
          
          OPTIONS:
              --auto-verify   Automatically verify builds after update
              --dry-run       Show what would be done without executing
          
          EXAMPLES:
              update-flake                    # Update all inputs
              update-flake update-source      # Update only dots-hyprland source
              update-flake pin abc123def      # Pin to specific commit
              update-flake branch main        # Track main branch
              update-flake status             # Show current status
              update-flake update --auto-verify  # Update and verify builds
          
          EOF
          }
          
          get_current_commit() {
              git rev-parse HEAD
          }
          
          get_current_branch() {
              git branch --show-current
          }
          
          get_flake_source_info() {
              if [[ -f flake.lock ]]; then
                  local rev=$(${pkgs.jq}/bin/jq -r '.nodes."dots-hyprland".locked.rev // "unknown"' flake.lock)
                  local ref=$(${pkgs.jq}/bin/jq -r '.nodes."dots-hyprland".original.ref // .nodes."dots-hyprland".original.rev // "unknown"' flake.lock)
                  echo "$rev|$ref"
              else
                  echo "unknown|unknown"
              fi
          }
          
          show_status() {
              header "Flake Status"
              
              local current_commit=$(get_current_commit)
              local current_branch=$(get_current_branch)
              local flake_info=$(get_flake_source_info)
              local flake_rev=$(echo "$flake_info" | cut -d'|' -f1)
              local flake_ref=$(echo "$flake_info" | cut -d'|' -f2)
              
              echo "📁 Project Directory: $(pwd)"
              echo "🌿 Current Branch: $current_branch"
              echo "📝 Current Commit: ''${current_commit:0:12}..."
              echo "🔒 Flake Locked To: ''${flake_rev:0:12}..."
              echo "🎯 Flake Tracking: $flake_ref"
              echo ""
              
              if [[ "$flake_rev" == "$current_commit" ]]; then
                  log "✅ Flake is synchronized with current commit"
              elif [[ "$flake_ref" == "$current_branch" ]]; then
                  warn "🔄 Flake tracks branch but may need update"
                  info "Run 'update-flake update' to sync with latest commits"
              else
                  warn "⚠️  Flake is out of sync"
                  info "Flake: $flake_ref (''${flake_rev:0:12}...)"
                  info "Local: $current_branch (''${current_commit:0:12}...)"
              fi
          }
          
          update_all_inputs() {
              header "Updating All Flake Inputs"
              
              log "Running nix flake update..."
              if nix flake update; then
                  log "✅ All inputs updated successfully"
              else
                  error "Failed to update flake inputs"
              fi
          }
          
          update_source_only() {
              header "Updating dots-hyprland Source Input"
              
              log "Running nix flake lock --update-input dots-hyprland..."
              if nix flake lock --update-input dots-hyprland; then
                  log "✅ dots-hyprland source updated successfully"
              else
                  error "Failed to update dots-hyprland source input"
              fi
          }
          
          verify_builds() {
              header "Verifying Flake Builds"
              
              local configs=("declarative" "writable")
              local success=true
              
              for config in "''${configs[@]}"; do
                  info "🔨 Testing $config configuration..."
                  if nix build ".#homeConfigurations.$config.activationPackage" --no-link --quiet; then
                      log "✅ $config configuration builds successfully"
                  else
                      error "❌ $config configuration failed to build"
                      success=false
                  fi
              done
              
              if $success; then
                  log "🎉 All configurations build successfully!"
              else
                  error "Some configurations failed to build"
              fi
          }
          
          # Parse command line arguments
          AUTO_VERIFY=false
          DRY_RUN=false
          COMMAND="update"
          
          while [[ $# -gt 0 ]]; do
              case $1 in
                  --auto-verify)
                      AUTO_VERIFY=true
                      shift
                      ;;
                  --dry-run)
                      DRY_RUN=true
                      shift
                      ;;
                  update|update-source|status|verify|help)
                      COMMAND="$1"
                      shift
                      ;;
                  *)
                      if [[ "$1" != -* ]]; then
                          COMMAND="$1"
                          shift
                      else
                          error "Unknown option: $1"
                      fi
                      ;;
              esac
          done
          
          # Main execution
          case "$COMMAND" in
              help)
                  show_help
                  ;;
              status)
                  show_status
                  ;;
              update)
                  if $DRY_RUN; then
                      info "DRY RUN: Would update all flake inputs"
                      show_status
                  else
                      update_all_inputs
                      if $AUTO_VERIFY; then
                          verify_builds
                      fi
                  fi
                  ;;
              update-source)
                  if $DRY_RUN; then
                      info "DRY RUN: Would update dots-hyprland source input"
                      show_status
                  else
                      update_source_only
                      if $AUTO_VERIFY; then
                          verify_builds
                      fi
                  fi
                  ;;
              verify)
                  verify_builds
                  ;;
              *)
                  show_help
                  ;;
          esac
        '';
        
        # Test utilities
        test-python-env = pkgs.writeShellScriptBin "test-python-env" ''
          #!/usr/bin/env bash
          echo "🧪 Testing dots-hyprland Python environment..."
          
          VENV_PATH="$HOME/.local/state/quickshell/.venv"
          
          if [[ ! -d "$VENV_PATH" ]]; then
            echo "❌ Virtual environment not found at $VENV_PATH"
            echo "💡 Run: home-manager switch"
            exit 1
          fi
          
          source "$VENV_PATH/bin/activate"
          python -c "
import sys
print(f'✅ Python {sys.version}')

try:
    import material_color_utilities
    print('✅ material-color-utilities')
except ImportError:
    print('❌ material-color-utilities')

try:
    import materialyoucolor
    print('✅ materialyoucolor')
except ImportError:
    print('❌ materialyoucolor')

try:
    import pywayland
    print('✅ pywayland')
except ImportError:
    print('❌ pywayland')
"
          deactivate
        '';
        
        # Test quickshell with clean config
        test-quickshell = pkgs.writeShellScriptBin "test-quickshell" ''
          #!/usr/bin/env bash
          echo "🧪 Testing quickshell with dots-hyprland config..."
          
          if [[ ! -d "$HOME/.config/quickshell" ]]; then
            echo "❌ No quickshell configuration found"
            echo "💡 Run: home-manager switch"
            exit 1
          fi
          
          cd "$HOME/.config/quickshell"
          echo "🚀 Starting quickshell (timeout 10s)..."
          timeout 10 ${pkgs.quickshell}/bin/quickshell 2>&1 | head -20
        '';
        
        # Mode comparison utility
        compare-modes = pkgs.writeShellScriptBin "compare-modes" ''
          #!/usr/bin/env bash
          
          echo "🔍 dots-hyprland Configuration Modes"
          echo "===================================="
          echo ""
          echo "📋 Available modes:"
          echo ""
          echo "1. 🔒 DECLARATIVE MODE"
          echo "   • Files managed by Home Manager"
          echo "   • Read-only configuration"
          echo "   • Automatic updates with 'home-manager switch'"
          echo "   • Best for: Set-and-forget users"
          echo "   • Build: nix build .#homeConfigurations.declarative.activationPackage"
          echo ""
          echo "2. ✏️  WRITABLE MODE"
          echo "   • Files staged to ~/.configstaging"
          echo "   • User copies/modifies configuration"
          echo "   • Full control over files"
          echo "   • Best for: Customization and development"
          echo "   • Build: nix build .#homeConfigurations.writable.activationPackage"
          echo ""
          echo "🚀 Quick start:"
          echo "   # For declarative mode:"
          echo "   nix build .#homeConfigurations.declarative.activationPackage && ./result/activate"
          echo ""
          echo "   # For writable mode:"
          echo "   nix build .#homeConfigurations.writable.activationPackage && ./result/activate"
          echo "   ~/.local/bin/initialSetup.sh"
        '';
        
        # Default package for easy testing
        default = self.packages.${system}.update-flake;
      };

      # Development shell
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nixpkgs-fmt
          nil
          git
          
          # Our utilities
          self.packages.${system}.update-flake
          self.packages.${system}.test-python-env
          self.packages.${system}.test-quickshell
          self.packages.${system}.compare-modes
        ];
        
        shellHook = ''
          echo "🚀 dots-hyprland installer replication development environment"
          echo ""
          echo "📋 Available commands:"
          echo "  update-flake          - Manage flake inputs and GitHub sync"
          echo "  compare-modes         - Compare declarative vs writable modes"
          echo "  test-python-env       - Test Python virtual environment"
          echo "  test-quickshell       - Test quickshell with config"
          echo ""
          echo "🔄 Flake management:"
          echo "  update-flake status   - Show current flake status"
          echo "  update-flake update   - Update all flake inputs"
          echo "  update-flake verify   - Test configurations build"
          echo ""
          echo "🎯 Build configurations:"
          echo "  nix build .#homeConfigurations.declarative.activationPackage"
          echo "  nix build .#homeConfigurations.writable.activationPackage"
          echo ""
          echo "🔑 Key insight: Both modes use the same Python venv and packages!"
          echo "📁 Branch: $(git branch --show-current)"
          echo ""
          echo "💡 Run 'update-flake help' for full flake management options"
        '';
      };

      # Home Manager module
      homeManagerModules.default = import ./modules/home-manager.nix;
      homeManagerModules.dots-hyprland = self.homeManagerModules.default;

      # Example Home Manager configurations
      homeConfigurations = {
        # Declarative approach (read-only, managed by Home Manager)
        declarative = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            self.homeManagerModules.default
            {
              home.username = "celes";
              home.homeDirectory = "/home/celes";
              home.stateVersion = "24.05";
              
              programs.dots-hyprland = {
                enable = true;
                source = dots-hyprland;
                packageSet = "essential";
                # Declarative mode (default)
                mode = "declarative";
              };
            }
          ];
        };
        
        # Writable approach (staging + user modification)
        writable = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            self.homeManagerModules.default
            {
              home.username = "celes";
              home.homeDirectory = "/home/celes";
              home.stateVersion = "24.05";
              
              programs.dots-hyprland = {
                enable = true;
                source = dots-hyprland;
                packageSet = "essential";
                # Writable mode - stages to .configstaging
                mode = "writable";
                writable = {
                  stagingDir = ".configstaging";
                  setupScript = "initialSetup.sh";
                  backupExisting = true;
                };
              };
            }
          ];
        };
        
        # Alias for backward compatibility
        example = self.homeConfigurations.declarative;
      };
    };
}
