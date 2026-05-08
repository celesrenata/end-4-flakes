#!/usr/bin/env bash

# Quickshell reset script for end-4-flakes
# This script resets quickshell and regenerates qmldir files

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[quickshell-reset]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[quickshell-reset]${NC} WARNING: $1"
}

error() {
    echo -e "${RED}[quickshell-reset]${NC} ERROR: $1"
}

log "Starting quickshell reset..."

# Kill any running quickshell processes
log "Stopping quickshell processes..."
pkill -f quickshell || true
pkill -f qs || true

# Wait a moment for processes to stop
sleep 1

# Regenerate qmldir files if the generator exists
if command -v generate-qmldir >/dev/null 2>&1; then
    if [[ -d "$HOME/.config/quickshell/ii" ]]; then
        log "Regenerating qmldir files..."
        generate-qmldir "$HOME/.config/quickshell/ii"
        log "qmldir files regenerated successfully"
    else
        warn "Quickshell config directory not found, skipping qmldir generation"
    fi
else
    warn "qmldir generator not found in PATH, skipping regeneration"
fi

# Clear any cached QML modules
log "Clearing QML cache..."
rm -rf "$HOME/.cache/quickshell" 2>/dev/null || true
rm -rf "$HOME/.cache/qml" 2>/dev/null || true

# Using quickshell directly (no wrapper script needed)
log "Using quickshell directly"

log "Quickshell reset complete!"
log "You can now start quickshell with: qs"
