#!/usr/bin/env bash
# Wrapper script to export ILLOGICAL_IMPULSE_VIRTUAL_ENV for NixOS environment
export ILLOGICAL_IMPULSE_VIRTUAL_ENV="$HOME/.local/state/quickshell/.venv"

# Source the virtual environment and run the Python script
source "$ILLOGICAL_IMPULSE_VIRTUAL_ENV/bin/activate"
exec python -E "$(dirname "$0")/get_keybinds.py" "$@"
