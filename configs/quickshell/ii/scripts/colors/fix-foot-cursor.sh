#!/usr/bin/env bash
# Fix deprecated cursor.color in foot.ini

fix_foot_ini() {
    local FOOT_INI="$1"
    
    if [ -f "$FOOT_INI" ]; then
        # Extract cursor color value from [cursor] section
        cursor_value=$(sed -n '/^\[cursor\]/,/^\[colors\]/ { /^color=/ { s/^color=//p } }' "$FOOT_INI")
        
        if [ -n "$cursor_value" ]; then
            # Remove color= from [cursor] section
            sed -i '/^\[cursor\]/,/^\[colors\]/ { /^color=/d }' "$FOOT_INI"
            
            # Add cursor= to [colors] section if not already there
            if ! grep -q "^cursor=" "$FOOT_INI"; then
                sed -i "/^\[colors\]/a cursor=$cursor_value" "$FOOT_INI"
            fi
        fi
    fi
}

# Fix both the generated and main foot.ini files
fix_foot_ini "$HOME/.local/state/quickshell/user/generated/foot/foot.ini"
fix_foot_ini "$HOME/.config/foot/foot.ini"
