#!/usr/bin/env bash
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
        local rev=$(jq -r '.nodes."dots-hyprland".locked.rev // "unknown"' flake.lock)
        local ref=$(jq -r '.nodes."dots-hyprland".original.ref // .nodes."dots-hyprland".original.rev // "unknown"' flake.lock)
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
    echo "📝 Current Commit: ${current_commit:0:12}..."
    echo "🔒 Flake Locked To: ${flake_rev:0:12}..."
    echo "🎯 Flake Tracking: $flake_ref"
    echo ""
    
    if [[ "$flake_rev" == "$current_commit" ]]; then
        log "✅ Flake is synchronized with current commit"
    elif [[ "$flake_ref" == "$current_branch" ]]; then
        warn "🔄 Flake tracks branch but may need update"
        info "Run 'update-flake update' to sync with latest commits"
    else
        warn "⚠️  Flake is out of sync"
        info "Flake: $flake_ref (${flake_rev:0:12}...)"
        info "Local: $current_branch (${current_commit:0:12}...)"
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
