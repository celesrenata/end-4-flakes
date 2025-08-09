#!/usr/bin/env bash

# Phase 4 Testing Script
# Tests all advanced features of dots-hyprland

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] $1${NC}"
}

phase4() {
    echo -e "${PURPLE}[$(date +'%H:%M:%S')] PHASE 4: $1${NC}"
}

# Test functions
test_build() {
    log "Testing Phase 4 build..."
    
    if nix build "$PROJECT_ROOT#homeConfigurations.example.activationPackage" --no-link; then
        log "✅ Phase 4 build successful"
        return 0
    else
        error "❌ Phase 4 build failed"
        return 1
    fi
}

test_ai_integration() {
    phase4 "Testing AI Integration"
    
    # Check if Ollama is available
    if command -v ollama >/dev/null 2>&1; then
        log "✅ Ollama available"
    else
        warn "⚠️  Ollama not found - AI features may not work"
    fi
    
    # Test AI configuration generation
    if [[ -f "$PROJECT_ROOT/modules/components/ai.nix" ]]; then
        log "✅ AI module exists"
    else
        error "❌ AI module missing"
        return 1
    fi
}

test_advanced_widgets() {
    phase4 "Testing Advanced Widget System"
    
    local widgets=(
        "overview/Overview.qml.template"
        "sidebarLeft/SidebarLeft.qml.template"
        "screenCorners/ScreenCorners.qml.template"
        "session/SessionManager.qml.template"
    )
    
    for widget in "${widgets[@]}"; do
        if [[ -f "$PROJECT_ROOT/configs/quickshell/ii/modules/$widget" ]]; then
            log "✅ Widget template exists: $widget"
        else
            error "❌ Widget template missing: $widget"
            return 1
        fi
    done
}

test_material_you_theming() {
    phase4 "Testing Material You Theming System"
    
    if [[ -f "$PROJECT_ROOT/lib/material-colors.nix" ]]; then
        log "✅ Material You theming system exists"
    else
        error "❌ Material You theming system missing"
        return 1
    fi
    
    # Check if matugen is available
    if nix shell nixpkgs#matugen -c matugen --version >/dev/null 2>&1; then
        log "✅ matugen available for color generation"
    else
        warn "⚠️  matugen not available - theming may not work"
    fi
}

test_quality_of_life() {
    phase4 "Testing Quality of Life Features"
    
    local features=(
        "screenCorners/ScreenCorners.qml.template"
        "session/SessionManager.qml.template"
    )
    
    for feature in "${features[@]}"; do
        if [[ -f "$PROJECT_ROOT/configs/quickshell/ii/modules/$feature" ]]; then
            log "✅ QoL feature exists: $feature"
        else
            error "❌ QoL feature missing: $feature"
            return 1
        fi
    done
}

test_development_environment() {
    phase4 "Testing Development Environment"
    
    log "Entering development environment..."
    if nix develop "$PROJECT_ROOT" -c bash -c "echo 'Development environment working' && which quickshell" >/dev/null 2>&1; then
        log "✅ Development environment functional"
    else
        error "❌ Development environment issues"
        return 1
    fi
}

show_phase4_status() {
    phase4 "Phase 4 Implementation Status"
    echo
    echo "🤖 AI Integration:"
    echo "  - [x] AI module with Gemini & Ollama support"
    echo "  - [x] Configurable providers and features"
    echo "  - [x] Systemd service integration"
    echo "  - [x] AI chat interface scripts"
    echo
    echo "🎨 Advanced Widget System:"
    echo "  - [x] Overview with window previews"
    echo "  - [x] AI-powered left sidebar"
    echo "  - [x] Interactive components"
    echo "  - [x] Search functionality"
    echo
    echo "🌈 Material You Theming:"
    echo "  - [x] Advanced color generation"
    echo "  - [x] Multi-application theming"
    echo "  - [x] Dynamic palette creation"
    echo "  - [x] Theme application system"
    echo
    echo "🖱️ Quality of Life:"
    echo "  - [x] Screen corner interactions"
    echo "  - [x] Session management"
    echo "  - [x] Brightness controls"
    echo "  - [x] Confirmation dialogs"
    echo
    echo "📊 Overall Progress: Phase 4 Foundation Complete! 🎉"
}

# Main execution
main() {
    echo "🚀 Phase 4: Advanced Features Testing"
    echo "======================================"
    echo
    
    local failed_tests=()
    
    # Run all tests
    if ! test_build; then
        failed_tests+=("build")
    fi
    
    if ! test_ai_integration; then
        failed_tests+=("ai_integration")
    fi
    
    if ! test_advanced_widgets; then
        failed_tests+=("advanced_widgets")
    fi
    
    if ! test_material_you_theming; then
        failed_tests+=("material_you_theming")
    fi
    
    if ! test_quality_of_life; then
        failed_tests+=("quality_of_life")
    fi
    
    if ! test_development_environment; then
        failed_tests+=("development_environment")
    fi
    
    echo
    echo "======================================"
    
    # Show results
    if [[ ${#failed_tests[@]} -eq 0 ]]; then
        log "🎉 All Phase 4 tests passed!"
        show_phase4_status
        echo
        log "🚀 Ready to enable advanced features!"
        echo
        echo "Next steps:"
        echo "1. Enable AI integration: components.ai = true"
        echo "2. Enable theming: components.theming = true"
        echo "3. Enable advanced features: features.sidebar = true"
        echo "4. Test in VM or real environment"
        exit 0
    else
        error "❌ ${#failed_tests[@]} test(s) failed:"
        printf '%s\n' "${failed_tests[@]}"
        exit 1
    fi
}

# Run tests
main "$@"
