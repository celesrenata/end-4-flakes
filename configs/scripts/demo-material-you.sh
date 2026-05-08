#!/usr/bin/env bash
# Demo script for Material You theming system

set -euo pipefail

echo "🎨 dots-hyprland Material You Theming Demo"
echo "=========================================="
echo

# Check if system is configured
if [[ ! -f "$HOME/.config/home-manager/home.nix" ]]; then
    echo "❌ Home Manager not configured. Please set up dots-hyprland first."
    exit 1
fi

# Check if wallpaper directory exists
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
if [[ ! -d "$WALLPAPER_DIR" ]]; then
    echo "📁 Creating wallpaper directory: $WALLPAPER_DIR"
    mkdir -p "$WALLPAPER_DIR"
    echo "   Please add some wallpapers to this directory!"
fi

# Check for wallpapers
WALLPAPER_COUNT=$(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | wc -l)
if [[ $WALLPAPER_COUNT -eq 0 ]]; then
    echo "⚠️  No wallpapers found in $WALLPAPER_DIR"
    echo "   Please add some wallpapers and run this script again."
    exit 1
fi

echo "✅ Found $WALLPAPER_COUNT wallpapers in $WALLPAPER_DIR"
echo

# Show available commands
echo "🛠️  Available Material You Commands:"
echo "   theme-switch [directory] [mode]  - Switch to random wallpaper and generate theme"
echo "   theme-toggle                     - Toggle between light/dark mode"
echo "   theme-generate <wallpaper> [mode] - Generate theme from specific wallpaper"
echo

# Demo workflow
echo "🎯 Demo Workflow:"
echo "1. Switch to a random wallpaper with dark theme:"
echo "   $ theme-switch"
echo
echo "2. Toggle to light mode:"
echo "   $ theme-toggle"
echo
echo "3. Generate theme from specific wallpaper:"
echo "   $ theme-generate ~/Pictures/Wallpapers/my-wallpaper.jpg dark"
echo

# Show what gets themed
echo "🎨 What Gets Themed:"
echo "   ✅ Hyprland (borders, backgrounds, shadows)"
echo "   ✅ Fuzzel launcher (colors, selection)"
echo "   ✅ Foot terminal (all colors)"
echo "   ✅ GTK applications (buttons, headers, etc.)"
echo "   ✅ Hyprlock screen (backgrounds, text)"
echo "   ✅ Quickshell widgets (when implemented)"
echo

# Show file locations
echo "📂 Generated Files:"
echo "   ~/.local/share/dots-hyprland/generated/colors.json"
echo "   ~/.config/hypr/colors.conf"
echo "   ~/.config/fuzzel/fuzzel_theme.ini"
echo "   ~/.config/foot/foot.ini"
echo "   ~/.config/gtk-3.0/gtk.css"
echo "   ~/.config/gtk-4.0/gtk.css"
echo "   ~/.config/hypr/hyprlock.conf"
echo

# Interactive demo
read -p "🚀 Would you like to try switching to a random wallpaper now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🎨 Switching to random wallpaper..."
    
    # Find a random wallpaper
    RANDOM_WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | shuf -n 1)
    
    if [[ -n "$RANDOM_WALLPAPER" ]]; then
        echo "📸 Selected: $(basename "$RANDOM_WALLPAPER")"
        
        # Check if theme commands are available
        if command -v theme-switch >/dev/null 2>&1; then
            theme-switch "$WALLPAPER_DIR" dark
            echo "✅ Theme applied! Check your desktop for the new colors."
        else
            echo "⚠️  Theme commands not available. Please activate your Home Manager configuration first:"
            echo "   $ home-manager switch --flake .#example"
        fi
    else
        echo "❌ No wallpapers found"
    fi
else
    echo "👍 Demo complete! Use the commands above to try Material You theming."
fi

echo
echo "🎉 Material You theming is ready to use!"
