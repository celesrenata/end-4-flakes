#!/usr/bin/env bash
echo "🧪 Testing dots-hyprland Python environment..."

VENV_PATH="$HOME/.local/state/quickshell/.venv"

if [[ ! -d "$VENV_PATH" ]]; then
  echo "❌ Virtual environment not found at $VENV_PATH"
  echo "💡 Run: home-manager switch"
  exit 1
fi

source "$VENV_PATH/bin/activate"
python -c "
import sys
print(f'✅ Python {sys.version}')

try:
    import material_color_utilities
    print('✅ material-color-utilities')
except ImportError:
    print('❌ material-color-utilities')

try:
    import materialyoucolor
    print('✅ materialyoucolor')
except ImportError:
    print('❌ materialyoucolor')

try:
    import pywayland
    print('✅ pywayland')
except ImportError:
    print('❌ pywayland')
"
deactivate
