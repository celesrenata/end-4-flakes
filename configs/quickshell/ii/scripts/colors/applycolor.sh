#!/usr/bin/env bash

# Parse arguments
TERM_ONLY=false
if [[ "$1" == "--term" ]]; then
  TERM_ONLY=true
fi

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read terminal alpha from file or default
if [ -f "$STATE_DIR/user/generated/terminal/opacity" ]; then
  term_alpha=$(cat "$STATE_DIR/user/generated/terminal/opacity")
else
  term_alpha=60
fi

if [ ! -d "$STATE_DIR"/user/generated ]; then
  mkdir -p "$STATE_DIR"/user/generated
fi
cd "$CONFIG_DIR" || exit

colornames=''
colorstrings=''
colorlist=()
colorvalues=()

# If material_colors.scss is empty or doesn't exist, generate colors first
if [ ! -f "$STATE_DIR/user/generated/material_colors.scss" ] || [ ! -s "$STATE_DIR/user/generated/material_colors.scss" ]; then
  echo "material_colors.scss is missing or empty, generating colors..."
  "$SCRIPT_DIR/switchwall.sh" --noswitch
fi

colornames=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f1)
colorstrings=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f2 | cut -d ' ' -f2 | cut -d ";" -f1)
IFS=$'\n'
colorlist=($colornames)     # Array of color names
colorvalues=($colorstrings) # Array of color values

apply_term() {
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/sequences.txt" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi
  # Copy template (install -m ensures writable even if source is from nix store)
  mkdir -p "$STATE_DIR"/user/generated/terminal
  install -m 644 "$SCRIPT_DIR/terminal/sequences.txt" "$STATE_DIR"/user/generated/terminal/sequences.txt
  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$STATE_DIR"/user/generated/terminal/sequences.txt
  done

  sed -i "s/\$alpha/$term_alpha/g" "$STATE_DIR/user/generated/terminal/sequences.txt"

  for file in /dev/pts/*; do
    if [[ $file =~ ^/dev/pts/[0-9]+$ ]]; then
      {
      cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file"
      } & disown || true
    fi
  done
}

apply_foot() {
  if [ ! -f "$SCRIPT_DIR/foot/foot.ini" ]; then
    echo "Template file not found for Foot. Skipping that."
    return
  fi
  mkdir -p "$STATE_DIR"/user/generated/foot
  install -m 644 "$SCRIPT_DIR/foot/foot.ini" "$STATE_DIR"/user/generated/foot/foot.ini
  for i in "${!colorlist[@]}"; do
    sed -i "s/{{ ${colorlist[$i]} }}/${colorvalues[$i]#\#}/g" "$STATE_DIR"/user/generated/foot/foot.ini
  done
  # Substitute alpha value (convert percentage to decimal)
  local alpha_decimal=$(awk "BEGIN {printf \"%.2f\", $term_alpha/100}")
  sed -i "s/{{ \$alpha }}/$alpha_decimal/g" "$STATE_DIR"/user/generated/foot/foot.ini
  cp "$STATE_DIR"/user/generated/foot/foot.ini "$XDG_CONFIG_HOME/foot/foot.ini"

  # Signal running foot instances to reload config (colors hot-reload on new terminals)
  pkill -USR1 foot 2>/dev/null || true
}

apply_wofi() {
  if [ ! -f "$SCRIPT_DIR/wofi/style.css" ]; then
    echo "Template file not found for Wofi. Skipping that."
    return
  fi
  mkdir -p "$STATE_DIR"/user/generated/wofi
  install -m 644 "$SCRIPT_DIR/wofi/style.css" "$STATE_DIR"/user/generated/wofi/style.css
  for i in "${!colorlist[@]}"; do
    sed -i "s/{{ ${colorlist[$i]} }}/${colorvalues[$i]#\#}/g" "$STATE_DIR"/user/generated/wofi/style.css
  done
  cp "$STATE_DIR"/user/generated/wofi/style.css "$XDG_CONFIG_HOME/wofi/style.css"
}


# If --term flag is set, only update terminal
if [ "$TERM_ONLY" = true ]; then
  apply_term
  apply_foot
  exit 0
fi

# Check if terminal theming is enabled in config
CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
if [ -f "$CONFIG_FILE" ]; then
  enable_terminal=$(jq -r '.appearance.wallpaperTheming.enableTerminal' "$CONFIG_FILE")
  if [ "$enable_terminal" = "true" ]; then
    apply_term &
  fi
else
  echo "Config file not found at $CONFIG_FILE. Applying terminal theming by default."
  apply_term &
fi

apply_foot &
apply_wofi &
