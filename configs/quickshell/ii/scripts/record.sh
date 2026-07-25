#!/usr/bin/env bash

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}
getaudiooutput() {
    pactl list sources | grep 'Name' | grep 'monitor' | cut -d ' ' -f2
}
getaudioinput() {
    pactl get-default-source
}
getactivemonitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
}

# Create a virtual combined source mixing mic + system audio via PipeWire
# Returns the monitor source name of the combined sink
create_mixed_source() {
    # Load a null sink to act as the mix target
    local sink_id
    sink_id=$(pw-cli create-node adapter \
        '{ factory.name=support.null-audio-sink node.name=recording-mix media.class=Audio/Sink object.linger=false audio.position=[FL FR] }' 2>/dev/null | grep -o 'id:[0-9]*' | cut -d: -f2)

    if [[ -z "$sink_id" ]]; then
        # Fallback: just use system monitor
        getaudiooutput
        return
    fi

    # Wait for PipeWire to register the node
    sleep 0.3

    # Loopback system audio (default sink monitor) into the mix sink
    pw-loopback --capture-props='media.class=Audio/Sink' \
        --playback-props="target.object=recording-mix media.class=Audio/Sink" \
        --daemon &
    local lb_system=$!

    # Loopback mic (default source) into the mix sink
    pw-loopback \
        --playback-props="target.object=recording-mix media.class=Audio/Sink" \
        --daemon &
    local lb_mic=$!

    # Store PIDs for cleanup
    echo "$lb_system $lb_mic $sink_id" > /tmp/.recording-mix-pids

    sleep 0.3
    echo "recording-mix.monitor"
}

# Clean up the virtual combined source
cleanup_mixed_source() {
    if [[ -f /tmp/.recording-mix-pids ]]; then
        read -r lb_system lb_mic sink_id < /tmp/.recording-mix-pids
        kill "$lb_system" "$lb_mic" 2>/dev/null
        pw-cli destroy "$sink_id" 2>/dev/null
        rm -f /tmp/.recording-mix-pids
    fi
}

xdgvideo="$(xdg-user-dir VIDEOS)"
if [[ $xdgvideo = "$HOME" ]]; then
  unset xdgvideo
fi
mkdir -p "${xdgvideo:-$HOME/Videos}"
cd "${xdgvideo:-$HOME/Videos}" || exit

if pgrep wf-recorder > /dev/null; then
    notify-send "Recording Stopped" "Stopped" -a 'Recorder' &
    pkill wf-recorder &
    cleanup_mixed_source
else
    if [[ "$1" == "--fullscreen-mixed" ]]; then
        mixed_source="$(create_mixed_source)"
        notify-send "Starting recording" "Fullscreen + mic + system audio" -a 'Recorder' & disown
        wf-recorder -o "$(getactivemonitor)" --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' -t --audio="$mixed_source"
        cleanup_mixed_source
    elif [[ "$1" == "--fullscreen-sound" ]]; then
        notify-send "Starting recording" 'recording_'"$(getdate)"'.mp4' -a 'Recorder' & disown
        wf-recorder -o "$(getactivemonitor)" --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' -t --audio="$(getaudiooutput)"
    elif [[ "$1" == "--fullscreen" ]]; then
        notify-send "Starting recording" 'recording_'"$(getdate)"'.mp4' -a 'Recorder' & disown
        wf-recorder -o "$(getactivemonitor)" --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' -t
    else
        if ! region="$(slurp 2>&1)"; then
            notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
            exit 1
        fi
        notify-send "Starting recording" 'recording_'"$(getdate)"'.mp4' -a 'Recorder' & disown
        if [[ "$1" == "--sound" ]]; then
            wf-recorder --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' -t --geometry "$region" --audio="$(getaudiooutput)"
        else
            wf-recorder --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' -t --geometry "$region"
        fi
    fi
fi
