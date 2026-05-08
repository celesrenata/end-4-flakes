#!/usr/bin/env bash
# Dynamic qmldir generator for quickshell configurations
# This script automatically generates qmldir files based on actual QML files present

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[qmldir-gen]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[qmldir-gen]${NC} WARNING: $1" >&2
}

error() {
    echo -e "${RED}[qmldir-gen]${NC} ERROR: $1" >&2
}

# Function to check if a QML file is a singleton
is_singleton() {
    local file="$1"
    grep -q "pragma Singleton" "$file" 2>/dev/null
}

# Function to generate qmldir for a directory
generate_qmldir() {
    local dir="$1"
    local module_name="$2"
    local qmldir_file="$dir/qmldir"
    
    if [[ ! -d "$dir" ]]; then
        warn "Directory $dir does not exist, skipping"
        return 0
    fi
    
    log "Generating qmldir for $dir (module: $module_name)"
    
    # Start with module declaration
    echo "module $module_name" > "$qmldir_file"
    echo "" >> "$qmldir_file"
    
    # Find all QML files and add them
    local count=0
    local singleton_count=0
    while IFS= read -r -d '' file; do
        local basename=$(basename "$file" .qml)
        # Skip files that start with lowercase (usually internal components)
        if [[ "$basename" =~ ^[A-Z] ]]; then
            if is_singleton "$file"; then
                echo "singleton $basename 1.0 $(basename "$file")" >> "$qmldir_file"
                ((singleton_count++))
            else
                echo "$basename 1.0 $(basename "$file")" >> "$qmldir_file"
            fi
            ((count++))
        fi
    done < <(find "$dir" -maxdepth 1 -name "*.qml" -type f -print0 | sort -z) || true
    
    log "  → Registered $count components ($singleton_count singletons) in $qmldir_file"
}

# Main function
main() {
    local quickshell_dir="${1:-$HOME/.config/quickshell/ii}"
    
    if [[ ! -d "$quickshell_dir" ]]; then
        error "Quickshell directory $quickshell_dir does not exist"
        exit 1
    fi
    
    log "Generating qmldir files for quickshell configuration at $quickshell_dir"
    
    # Generate main qmldir (root level components)
    log "Processing root directory..."
    generate_qmldir "$quickshell_dir" "qs"
    
    # Copy main qmldir to qs subdirectory for proper module resolution
    if [[ -f "$quickshell_dir/qmldir" && -d "$quickshell_dir/qs" ]]; then
        log "Copying main qmldir to qs subdirectory for module resolution..."
        cp "$quickshell_dir/qmldir" "$quickshell_dir/qs/qmldir"
        log "  → Main qmldir copied to qs/qmldir"
        
        # Also copy the root-level QML files that are referenced in the qmldir
        log "Copying root-level QML files to qs subdirectory..."
        while IFS= read -r qml_file; do
            if [[ -f "$quickshell_dir/$qml_file" ]]; then
                cp "$quickshell_dir/$qml_file" "$quickshell_dir/qs/$qml_file"
                log "  → Copied $qml_file to qs/$qml_file"
            fi
        done < <(grep "\.qml$" "$quickshell_dir/qmldir" | awk '{print $NF}' || true)
    fi
    
    # Generate qmldir for modules directory
    if [[ -d "$quickshell_dir/modules" ]]; then
        log "Processing modules directory..."
        generate_qmldir "$quickshell_dir/modules" "qs.modules"
        
        # Generate qmldir for each module subdirectory
        while IFS= read -r -d '' module_dir; do
            local module_name=$(basename "$module_dir")
            log "Processing module: $module_name"
            generate_qmldir "$module_dir" "qs.modules.$module_name"
            
            # Handle nested subdirectories (like common/functions, common/widgets)
            while IFS= read -r -d '' nested_dir; do
                local nested_name=$(basename "$nested_dir")
                log "Processing nested module: $module_name/$nested_name"
                generate_qmldir "$nested_dir" "qs.modules.$module_name.$nested_name"
            done < <(find "$module_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z) || true
        done < <(find "$quickshell_dir/modules" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    fi
    
    # Generate qmldir for services directory
    if [[ -d "$quickshell_dir/services" ]]; then
        log "Processing services directory..."
        generate_qmldir "$quickshell_dir/services" "qs.services"
        
        # Generate qmldir for each service subdirectory
        while IFS= read -r -d '' service_dir; do
            local service_name=$(basename "$service_dir")
            log "Processing service: $service_name"
            generate_qmldir "$service_dir" "qs.services.$service_name"
        done < <(find "$quickshell_dir/services" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    fi
    
    # Generate qmldir for qs directory (if it exists)
    if [[ -d "$quickshell_dir/qs" ]]; then
        log "Processing qs directory..."
        # Don't overwrite the main qmldir file we copied earlier
        # Only generate qmldir for subdirectories of qs
        
        # Generate qmldir for qs subdirectories
        while IFS= read -r -d '' qs_subdir; do
            local subdir_name=$(basename "$qs_subdir")
            log "Processing qs/$subdir_name"
            generate_qmldir "$qs_subdir" "qs.qs.$subdir_name"
            
            # Handle nested qs subdirectories (like qs/modules/common, qs/services/ai)
            while IFS= read -r -d '' nested_qs_dir; do
                local nested_name=$(basename "$nested_qs_dir")
                log "Processing nested qs: $subdir_name/$nested_name"
                generate_qmldir "$nested_qs_dir" "qs.qs.$subdir_name.$nested_name"
                
                # Handle deeply nested directories (like qs/modules/common/functions)
                while IFS= read -r -d '' deep_nested_dir; do
                    local deep_name=$(basename "$deep_nested_dir")
                    log "Processing deep nested qs: $subdir_name/$nested_name/$deep_name"
                    generate_qmldir "$deep_nested_dir" "qs.qs.$subdir_name.$nested_name.$deep_name"
                done < <(find "$nested_qs_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z) || true
            done < <(find "$qs_subdir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z) || true
        done < <(find "$quickshell_dir/qs" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    fi
    
    log "✅ qmldir generation complete!"
    log "📊 Summary:"
    find "$quickshell_dir" -name "qmldir" -type f | while read -r qmldir_file; do
        local component_count=$(grep -c "\.qml$" "$qmldir_file" || echo "0")
        local singleton_count=$(grep -c "^singleton" "$qmldir_file" || echo "0")
        local relative_path=${qmldir_file#$quickshell_dir/}
        log "  → $relative_path: $component_count components ($singleton_count singletons)"
    done
}

# Help function
show_help() {
    cat << EOF
Dynamic qmldir Generator for Quickshell

USAGE:
    $(basename "$0") [QUICKSHELL_DIR]

ARGUMENTS:
    QUICKSHELL_DIR    Path to quickshell configuration directory
                      Default: \$HOME/.config/quickshell/ii

DESCRIPTION:
    This script automatically generates qmldir files for quickshell configurations
    by scanning for QML files and registering them appropriately. This ensures
    that all components are properly registered and available for import.

    The script handles:
    - Root level components (ReloadPopup, etc.)
    - Module components (bar, overview, etc.)
    - Service components
    - Nested subdirectories (functions, widgets, etc.)
    - Automatic singleton detection via "pragma Singleton"
    - Complex nested directory structures (qs/modules/common/functions)

    Singleton Detection:
    The script automatically detects QML files with "pragma Singleton" declarations
    and registers them with the "singleton" keyword in qmldir files. This is
    essential for proper Material You theming and service registration.

EXAMPLES:
    # Generate for default location
    $(basename "$0")
    
    # Generate for custom location
    $(basename "$0") /path/to/quickshell/config
    
    # Use in automation
    $(basename "$0") && quickshell -c ii

EOF
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
