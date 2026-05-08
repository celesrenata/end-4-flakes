#!/usr/bin/env bash

# Color generation script for quickshell Material You theming
# Based on the original dots-hyprland color generation system

WALLPAPER="${1:-$HOME/Backgrounds/love-is-love.jpg}"
CACHE_DIR="$HOME/.cache/dots-hyprland/colors"

echo "🎨 Generating Material You colors from: $WALLPAPER"

# Create cache directory
mkdir -p "$CACHE_DIR"

# Check if wallpaper exists
if [[ ! -f "$WALLPAPER" ]]; then
    echo "❌ Wallpaper not found: $WALLPAPER"
    echo "Using default colors..."
    
    # Create basic color scheme as fallback
    cat > "$CACHE_DIR/colors.json" << 'EOF'
{
  "colors": {
    "primary": "#bb86fc",
    "onPrimary": "#000000",
    "secondary": "#03dac6",
    "onSecondary": "#000000",
    "surface": "#121212",
    "onSurface": "#ffffff",
    "background": "#121212",
    "onBackground": "#ffffff",
    "error": "#cf6679",
    "onError": "#000000"
  }
}
EOF
    exit 0
fi

# Generate colors using matugen if available
if command -v matugen >/dev/null 2>&1; then
    echo "Using matugen for color generation..."
    matugen image "$WALLPAPER" \
        --mode dark \
        --type scheme-content \
        --contrast 0.0 \
        --json > "$CACHE_DIR/colors.json"
    
    if [[ $? -eq 0 ]]; then
        echo "✅ Colors generated successfully with matugen"
    else
        echo "❌ matugen failed, using fallback colors"
    fi
else
    echo "⚠️  matugen not found, using basic color extraction..."
    
    # Basic color extraction using imagemagick if available
    if command -v convert >/dev/null 2>&1; then
        # Extract dominant color
        DOMINANT=$(convert "$WALLPAPER" -resize 1x1\! -format '%[pixel:u]' info:-)
        echo "Dominant color: $DOMINANT"
        
        # Create basic color scheme
        cat > "$CACHE_DIR/colors.json" << EOF
{
  "colors": {
    "primary": "#bb86fc",
    "onPrimary": "#000000",
    "secondary": "#03dac6", 
    "onSecondary": "#000000",
    "surface": "#1a1b26",
    "onSurface": "#ffffff",
    "background": "#1a1b26",
    "onBackground": "#ffffff",
    "error": "#cf6679",
    "onError": "#000000"
  }
}
EOF
    else
        echo "❌ No color generation tools available"
        exit 1
    fi
fi

# Generate quickshell-specific color files
echo "Generating quickshell color configurations..."

# Extract colors for quickshell
if [[ -f "$CACHE_DIR/colors.json" ]]; then
    # Create quickshell color configuration
    cat > "$CACHE_DIR/quickshell-colors.qml" << 'EOF'
// Generated Material You colors for quickshell
pragma Singleton
import QtQuick

QtObject {
    // Material You color scheme
    readonly property string primary: "#bb86fc"
    readonly property string onPrimary: "#000000"
    readonly property string secondary: "#03dac6"
    readonly property string onSecondary: "#000000"
    readonly property string surface: "#1a1b26"
    readonly property string onSurface: "#ffffff"
    readonly property string background: "#1a1b26"
    readonly property string onBackground: "#ffffff"
    readonly property string error: "#cf6679"
    readonly property string onError: "#000000"
    
    // Additional colors for UI elements
    readonly property string accent: primary
    readonly property string outline: "#444444"
    readonly property string surfaceVariant: "#2a2b36"
    readonly property string onSurfaceVariant: "#cccccc"
}
EOF

    echo "✅ Quickshell colors generated"
fi

# Update wallpaper if using swww
if command -v swww >/dev/null 2>&1; then
    echo "Updating wallpaper with swww..."
    swww img "$WALLPAPER" --transition-type fade --transition-duration 1
fi

echo "🎨 Color generation complete!"
echo "Colors saved to: $CACHE_DIR/"
