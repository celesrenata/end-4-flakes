#!/usr/bin/env bash
# Wrapper to set up environment for switchwall.sh

[ -f "$HOME/.config/quickshell/env.sh" ] && source "$HOME/.config/quickshell/env.sh"
export ILLOGICAL_IMPULSE_VIRTUAL_ENV="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}"

echo "[wrapper] Called with args: $@" >> /tmp/switchwall-wrapper.log

# Run the ii version of switchwall.sh (which has the NixOS-adapted color pipeline)
exec "$HOME/.config/quickshell/ii/scripts/colors/switchwall.sh" "$@"
