#!/usr/bin/env bash
echo "🧪 Testing quickshell with dots-hyprland config..."

if [[ ! -d "$HOME/.config/quickshell" ]]; then
  echo "❌ No quickshell configuration found"
  echo "💡 Run: home-manager switch"
  exit 1
fi

cd "$HOME/.config/quickshell"
echo "🚀 Starting quickshell (timeout 10s)..."
timeout 10 quickshell 2>&1 | head -20
