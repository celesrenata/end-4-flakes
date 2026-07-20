#!/bin/bash
export ILLOGICAL_IMPULSE_VIRTUAL_ENV="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}"
"$ILLOGICAL_IMPULSE_VIRTUAL_ENV/bin/python" ~/.config/quickshell/ii/scripts/hyprland/get_keybinds.py "$@"
