#!/usr/bin/env bash
# Workspace action script for dots-hyprland
hyprctl dispatch "$1" $(((($(hyprctl activeworkspace -j | jq -r .id) - 1)  / 10) * 10 + $2))
