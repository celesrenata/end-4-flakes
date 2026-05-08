#!/usr/bin/env bash
# Screen recording script using wf-recorder
# Bound to SUPER + ALT + R in Hyprland

set -euo pipefail

# Configuration
RECORDINGS_DIR="$HOME/Videos/Recordings"
TEMP_DIR="/tmp/dots-hyprland-recording"
PID_FILE="$TEMP_DIR/recording.pid"
STATUS_FILE="$TEMP_DIR/recording.status"

# Ensure directories exist
mkdir -p "$RECORDINGS_DIR"
mkdir -p "$TEMP_DIR"

# Function to show notification
notify_user() {
    local title="$1"
    local message="$2"
    local icon="${3:-video-display}"
    local timeout="${4:-3000}"
    
    notify-send "$title" "$message" --icon="$icon" --timeout="$timeout"
}

# Function to get current timestamp
get_timestamp() {
    date +"%Y-%m-%d_%H-%M-%S"
}

# Function to start recording
start_recording() {
    local mode="$1"
    local output_file="$RECORDINGS_DIR/recording_$(get_timestamp()).mp4"
    
    case "$mode" in
        "fullscreen")
            notify_user "Screen Recording" "Starting fullscreen recording..." "media-record"
            wf-recorder -f "$output_file" &
            ;;
        "region")
            notify_user "Screen Recording" "Select region to record..." "media-record"
            # Use slurp to select region
            local geometry
            geometry=$(slurp 2>/dev/null) || {
                notify_user "Recording Cancelled" "No region selected" "dialog-error"
                return 1
            }
            wf-recorder -g "$geometry" -f "$output_file" &
            ;;
        "window")
            notify_user "Screen Recording" "Click on window to record..." "media-record"
            # Get window geometry using hyprctl
            local window_info
            window_info=$(hyprctl activewindow -j 2>/dev/null) || {
                notify_user "Recording Error" "Could not get window info" "dialog-error"
                return 1
            }
            
            # Extract geometry from JSON
            local x y width height
            x=$(echo "$window_info" | jq -r '.at[0]')
            y=$(echo "$window_info" | jq -r '.at[1]')
            width=$(echo "$window_info" | jq -r '.size[0]')
            height=$(echo "$window_info" | jq -r '.size[1]')
            
            wf-recorder -g "${x},${y} ${width}x${height}" -f "$output_file" &
            ;;
        *)
            notify_user "Recording Error" "Invalid recording mode: $mode" "dialog-error"
            return 1
            ;;
    esac
    
    local pid=$!
    echo "$pid" > "$PID_FILE"
    echo "$output_file" > "$STATUS_FILE"
    
    # Wait a moment to ensure recording started
    sleep 1
    
    if kill -0 "$pid" 2>/dev/null; then
        notify_user "Recording Started" "Recording to: $(basename "$output_file")" "media-record" 5000
        echo "Recording started with PID: $pid"
        echo "Output file: $output_file"
    else
        notify_user "Recording Failed" "Could not start recording" "dialog-error"
        rm -f "$PID_FILE" "$STATUS_FILE"
        return 1
    fi
}

# Function to stop recording
stop_recording() {
    if [[ ! -f "$PID_FILE" ]]; then
        notify_user "No Recording" "No active recording found" "dialog-information"
        return 1
    fi
    
    local pid
    pid=$(cat "$PID_FILE")
    local output_file
    output_file=$(cat "$STATUS_FILE" 2>/dev/null || echo "unknown")
    
    if kill -0 "$pid" 2>/dev/null; then
        # Send SIGINT to gracefully stop recording
        kill -INT "$pid"
        
        # Wait for process to finish
        local count=0
        while kill -0 "$pid" 2>/dev/null && [[ $count -lt 10 ]]; do
            sleep 0.5
            ((count++))
        done
        
        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
        
        rm -f "$PID_FILE" "$STATUS_FILE"
        
        # Check if file was created and has content
        if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
            local file_size
            file_size=$(du -h "$output_file" | cut -f1)
            notify_user "Recording Stopped" "Saved: $(basename "$output_file") ($file_size)" "media-record" 5000
            
            # Optionally open the recordings directory
            # nautilus "$RECORDINGS_DIR" &
        else
            notify_user "Recording Error" "Recording file is empty or missing" "dialog-error"
        fi
    else
        notify_user "Recording Error" "Recording process not found" "dialog-error"
        rm -f "$PID_FILE" "$STATUS_FILE"
    fi
}

# Function to check recording status
check_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            local output_file
            output_file=$(cat "$STATUS_FILE" 2>/dev/null || echo "unknown")
            notify_user "Recording Active" "Currently recording to: $(basename "$output_file")" "media-record"
            return 0
        else
            # Clean up stale files
            rm -f "$PID_FILE" "$STATUS_FILE"
        fi
    fi
    
    notify_user "No Recording" "No active recording" "dialog-information"
    return 1
}

# Function to show recording menu
show_menu() {
    local choice
    choice=$(echo -e "🔴 Start Fullscreen Recording\n📱 Start Region Recording\n🪟 Start Window Recording\n⏹️ Stop Recording\n📊 Check Status\n📁 Open Recordings Folder" | \
        fuzzel --dmenu --prompt="Recording: " --width=40 --lines=6)
    
    case "$choice" in
        "🔴 Start Fullscreen Recording")
            start_recording "fullscreen"
            ;;
        "📱 Start Region Recording")
            start_recording "region"
            ;;
        "🪟 Start Window Recording")
            start_recording "window"
            ;;
        "⏹️ Stop Recording")
            stop_recording
            ;;
        "📊 Check Status")
            check_status
            ;;
        "📁 Open Recordings Folder")
            nautilus "$RECORDINGS_DIR" &
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

# Main logic
main() {
    # Check if required tools are available
    local missing_tools=()
    
    command -v wf-recorder >/dev/null || missing_tools+=("wf-recorder")
    command -v slurp >/dev/null || missing_tools+=("slurp")
    command -v jq >/dev/null || missing_tools+=("jq")
    command -v notify-send >/dev/null || missing_tools+=("libnotify")
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "Error: Missing required tools: ${missing_tools[*]}"
        notify_user "Recording Error" "Missing tools: ${missing_tools[*]}" "dialog-error"
        exit 1
    fi
    
    # Parse command line arguments
    case "${1:-menu}" in
        "start"|"fullscreen")
            start_recording "fullscreen"
            ;;
        "region")
            start_recording "region"
            ;;
        "window")
            start_recording "window"
            ;;
        "stop")
            stop_recording
            ;;
        "status")
            check_status
            ;;
        "toggle")
            if check_status >/dev/null 2>&1; then
                stop_recording
            else
                show_menu
            fi
            ;;
        "menu"|*)
            show_menu
            ;;
    esac
}

# Run main function
main "$@"
