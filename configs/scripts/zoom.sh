#!/usr/bin/env bash
# Screen magnification script for accessibility
# Bound to SUPER + ALT + = in Hyprland

set -euo pipefail

# Configuration
ZOOM_LEVELS=(1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0)
CONFIG_DIR="$HOME/.config/dots-hyprland"
STATE_FILE="$CONFIG_DIR/zoom_state"
TEMP_DIR="/tmp/dots-hyprland-zoom"

# Ensure directories exist
mkdir -p "$CONFIG_DIR"
mkdir -p "$TEMP_DIR"

# Function to show notification
notify_user() {
    local title="$1"
    local message="$2"
    local icon="${3:-zoom-in}"
    local timeout="${4:-2000}"
    
    notify-send "$title" "$message" --icon="$icon" --timeout="$timeout"
}

# Function to get current zoom level
get_current_zoom() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo "1.0"
    fi
}

# Function to save zoom level
save_zoom_level() {
    local level="$1"
    echo "$level" > "$STATE_FILE"
}

# Function to find next zoom level
get_next_zoom_level() {
    local current="$1"
    local direction="${2:-up}" # up or down
    
    # Find current index
    local current_index=-1
    for i in "${!ZOOM_LEVELS[@]}"; do
        if [[ "${ZOOM_LEVELS[$i]}" == "$current" ]]; then
            current_index=$i
            break
        fi
    done
    
    # If current level not found, start from 1.0
    if [[ $current_index -eq -1 ]]; then
        current_index=0
    fi
    
    # Calculate next index
    local next_index
    if [[ "$direction" == "up" ]]; then
        next_index=$((current_index + 1))
        if [[ $next_index -ge ${#ZOOM_LEVELS[@]} ]]; then
            next_index=$((${#ZOOM_LEVELS[@]} - 1))
        fi
    else
        next_index=$((current_index - 1))
        if [[ $next_index -lt 0 ]]; then
            next_index=0
        fi
    fi
    
    echo "${ZOOM_LEVELS[$next_index]}"
}

# Function to apply zoom using Hyprland
apply_hyprland_zoom() {
    local zoom_level="$1"
    
    # Use hyprctl to set zoom
    if command -v hyprctl >/dev/null; then
        # Get current monitor
        local monitor
        monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name' 2>/dev/null || echo "")
        
        if [[ -n "$monitor" ]]; then
            # Apply zoom to the focused monitor
            hyprctl keyword monitor "$monitor,preferred,auto,$zoom_level" 2>/dev/null || {
                # Fallback: try to set global zoom
                hyprctl keyword misc:cursor_zoom_factor "$zoom_level" 2>/dev/null || true
            }
        fi
    fi
}

# Function to apply zoom using wlr-randr (fallback)
apply_wlr_zoom() {
    local zoom_level="$1"
    
    if command -v wlr-randr >/dev/null; then
        # Get current output
        local output
        output=$(wlr-randr | grep -E "^[A-Z]" | head -n1 | cut -d' ' -f1)
        
        if [[ -n "$output" ]]; then
            wlr-randr --output "$output" --scale "$zoom_level" 2>/dev/null || true
        fi
    fi
}

# Function to set zoom level
set_zoom() {
    local zoom_level="$1"
    
    # Validate zoom level
    local valid=false
    for level in "${ZOOM_LEVELS[@]}"; do
        if [[ "$level" == "$zoom_level" ]]; then
            valid=true
            break
        fi
    done
    
    if [[ "$valid" != "true" ]]; then
        notify_user "Zoom Error" "Invalid zoom level: $zoom_level" "dialog-error"
        return 1
    fi
    
    # Apply zoom
    apply_hyprland_zoom "$zoom_level"
    
    # Save state
    save_zoom_level "$zoom_level"
    
    # Show notification
    local percentage
    percentage=$(echo "$zoom_level * 100" | bc -l | cut -d. -f1)
    
    if [[ "$zoom_level" == "1.0" ]]; then
        notify_user "Zoom Reset" "Zoom level: ${percentage}% (Normal)" "zoom-original"
    else
        notify_user "Zoom Level" "Zoom level: ${percentage}%" "zoom-in"
    fi
}

# Function to zoom in
zoom_in() {
    local current
    current=$(get_current_zoom)
    local next
    next=$(get_next_zoom_level "$current" "up")
    
    if [[ "$next" == "$current" ]]; then
        notify_user "Maximum Zoom" "Already at maximum zoom level" "zoom-in"
    else
        set_zoom "$next"
    fi
}

# Function to zoom out
zoom_out() {
    local current
    current=$(get_current_zoom)
    local next
    next=$(get_next_zoom_level "$current" "down")
    
    if [[ "$next" == "$current" ]]; then
        notify_user "Minimum Zoom" "Already at minimum zoom level" "zoom-out"
    else
        set_zoom "$next"
    fi
}

# Function to reset zoom
reset_zoom() {
    set_zoom "1.0"
}

# Function to show zoom menu
show_menu() {
    local current
    current=$(get_current_zoom)
    local current_percentage
    current_percentage=$(echo "$current * 100" | bc -l | cut -d. -f1)
    
    # Build menu options
    local menu_options=""
    for level in "${ZOOM_LEVELS[@]}"; do
        local percentage
        percentage=$(echo "$level * 100" | bc -l | cut -d. -f1)
        local marker=""
        
        if [[ "$level" == "$current" ]]; then
            marker=" ✓"
        fi
        
        if [[ "$level" == "1.0" ]]; then
            menu_options+="🔍 ${percentage}% (Normal)${marker}\n"
        else
            menu_options+="🔍 ${percentage}%${marker}\n"
        fi
    done
    
    # Add control options
    menu_options+="\n➕ Zoom In\n➖ Zoom Out\n🔄 Reset Zoom\n📊 Current: ${current_percentage}%"
    
    local choice
    choice=$(echo -e "$menu_options" | fuzzel --dmenu --prompt="Zoom: " --width=30 --lines=12)
    
    case "$choice" in
        *"Zoom In")
            zoom_in
            ;;
        *"Zoom Out")
            zoom_out
            ;;
        *"Reset Zoom")
            reset_zoom
            ;;
        *"Current:"*)
            # Just show current status
            notify_user "Current Zoom" "Zoom level: ${current_percentage}%" "zoom-in"
            ;;
        🔍*)
            # Extract percentage and convert to decimal
            local selected_percentage
            selected_percentage=$(echo "$choice" | grep -o '[0-9]\+%' | tr -d '%')
            local selected_level
            selected_level=$(echo "scale=2; $selected_percentage / 100" | bc -l)
            set_zoom "$selected_level"
            ;;
        "")
            # User cancelled
            exit 0
            ;;
        *)
            notify_user "Invalid Choice" "Unknown option selected" "dialog-error"
            ;;
    esac
}

# Function to toggle zoom (between 1.0 and 2.0)
toggle_zoom() {
    local current
    current=$(get_current_zoom)
    
    if [[ "$current" == "1.0" ]]; then
        set_zoom "2.0"
    else
        set_zoom "1.0"
    fi
}

# Function to show current zoom status
show_status() {
    local current
    current=$(get_current_zoom)
    local percentage
    percentage=$(echo "$current * 100" | bc -l | cut -d. -f1)
    
    notify_user "Zoom Status" "Current zoom level: ${percentage}%" "zoom-in" 3000
}

# Main logic
main() {
    # Check if required tools are available
    local missing_tools=()
    
    command -v bc >/dev/null || missing_tools+=("bc")
    command -v notify-send >/dev/null || missing_tools+=("libnotify")
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "Error: Missing required tools: ${missing_tools[*]}"
        notify_user "Zoom Error" "Missing tools: ${missing_tools[*]}" "dialog-error"
        exit 1
    fi
    
    # Parse command line arguments
    case "${1:-menu}" in
        "in"|"zoom-in"|"+")
            zoom_in
            ;;
        "out"|"zoom-out"|"-")
            zoom_out
            ;;
        "reset"|"normal"|"1")
            reset_zoom
            ;;
        "toggle")
            toggle_zoom
            ;;
        "status")
            show_status
            ;;
        "set")
            if [[ -n "${2:-}" ]]; then
                set_zoom "$2"
            else
                echo "Usage: $0 set <zoom_level>"
                exit 1
            fi
            ;;
        "menu"|*)
            show_menu
            ;;
    esac
}

# Run main function
main "$@"
