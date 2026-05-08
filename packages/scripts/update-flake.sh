#!/usr/bin/env bash
# dots-hyprland Flake Update Utility
# Manages flake input updates for self-contained installer replication

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[update-flake]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[update-flake]${NC} WARNING: $1"
}

error() {
    echo -e "${RED}[update-flake]${NC} ERROR: $1"
    exit 1
}

info() {
    echo -e "${BLUE}[update-flake]${NC} $1"
}

header() {
    echo -e "${CYAN}=== $1 ===${NC}"
}

show_help() {
    cat << EOF
dots-hyprland Flake Update Utility (Self-Contained)

USAGE:
    update-flake [OPTIONS] [COMMAND]

COMMANDS:
    update          Update all flake inputs (default)
    status          Show current flake input status
    verify          Verify flake builds after update
    help            Show this help message

OPTIONS:
    --auto-verify   Automatically verify builds after update
    --dry-run       Show what would be done without executing

EXAMPLES:
    update-flake                    # Update all inputs
    update-flake status             # Show current status
    update-flake update --auto-verify  # Update and verify builds

NOTE: This flake is now self-contained and doesn't depend on external
      dots-hyprland repository. All configs are included locally.

EOF
}

get_current_commit() {
    git rev-parse HEAD
}

get_current_branch() {
    git branch --show-current
}

show_status() {
    header "Flake Status"
    
    local current_commit=$(get_current_commit)
    local current_branch=$(get_current_branch)
    
    echo "📁 Project Directory: $(pwd)"
    echo "🌿 Current Branch: $current_branch"
    echo "📝 Current Commit: ${current_commit:0:12}..."
    echo "🎯 Mode: Self-contained (no external dependencies)"
    echo ""
    
    log "✅ Flake is self-contained with local configs"
    info "All dots-hyprland configurations are included in ./configs/"
}

update_all_inputs() {
    header "Updating All Flake Inputs"
    
    log "Running nix flake update..."
    if nix flake update; then
        log "✅ All inputs updated successfully"
        info "Updated: nixpkgs, home-manager, quickshell"
    else
        error "Failed to update flake inputs"
    fi
}

verify_builds() {
    header "Verifying Flake Builds"
    
    local configs=("declarative" "writable")
    local success=true
    
    for config in "${configs[@]}"; do
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
        update|status|verify|help)
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
    verify)
        verify_builds
        ;;
    *)
        show_help
        ;;
esac
