#!/usr/bin/env bash
# Wrapper to set up environment for switchwall.sh

# Source environment config
[ -f "$HOME/.config/quickshell/env.sh" ] && source "$HOME/.config/quickshell/env.sh"

export ILLOGICAL_IMPULSE_VIRTUAL_ENV="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}"

echo "[wrapper] Called with args: $@" >> /tmp/switchwall-wrapper.log
echo "[wrapper] LD_LIBRARY_PATH: $LD_LIBRARY_PATH" >> /tmp/switchwall-wrapper.log

# Run switchwall.sh with all arguments
"$(dirname "$0")/switchwall.sh" "$@"

# Fix deprecated cursor.color in foot.ini after color generation
"$(dirname "$0")/fix-foot-cursor.sh"
