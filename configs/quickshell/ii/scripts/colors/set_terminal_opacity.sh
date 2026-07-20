#!/usr/bin/env bash
# Script to set terminal opacity from settings UI

OPACITY=$1
if [ -z "$OPACITY" ]; then
    echo "Usage: $0 <opacity_percentage>"
    exit 1
fi

echo "Setting terminal opacity to $OPACITY%" >> /tmp/terminal_debug.log

# Get background color (you might need to adjust this based on current theme)
BG_COLOR="#1e1e2e"  # Default background color

# Send opacity command directly to all terminal devices
for file in /dev/pts/*; do
  if [[ $file =~ ^/dev/pts/[0-9]+$ ]]; then
    echo -e "\033]11;[${OPACITY}]${BG_COLOR}\033\\" > "$file" 2>/dev/null
  fi
done

echo "Terminal opacity set to $OPACITY% at $(date)" >> /tmp/terminal_debug.log
