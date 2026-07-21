#!/usr/bin/env bash
# Fix deprecated cursor.color in foot.ini (foot >= 1.17)
# In modern foot, cursor color belongs in [colors-dark] as "cursor=" not in [cursor] as "color="
# This script migrates any legacy configs that still have the old format.

fix_foot_ini() {
    local FOOT_INI="$1"
    
    if [ ! -f "$FOOT_INI" ]; then
        return
    fi

    # Extract cursor color value from [cursor] section (between [cursor] and next section)
    cursor_value=$(sed -n '/^\[cursor\]/,/^\[/ { /^color=/ { s/^color=//p } }' "$FOOT_INI")
    
    if [ -n "$cursor_value" ]; then
        # Remove color= from [cursor] section
        sed -i '/^\[cursor\]/,/^\[/ { /^color=/d }' "$FOOT_INI"
        
        # Add cursor= to [colors-dark] section if not already there
        if ! grep -q "^cursor=" "$FOOT_INI"; then
            sed -i "/^\[colors-dark\]/a cursor=$cursor_value" "$FOOT_INI"
        fi
    fi
}

# Fix both the generated and main foot.ini files
fix_foot_ini "$HOME/.local/state/quickshell/user/generated/foot/foot.ini"
fix_foot_ini "$HOME/.config/foot/foot.ini"
