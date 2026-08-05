-- Hyprland 0.55+ Lua configuration entry point
-- Sub-modules are loaded in dependency order from hyprland/
-- Hosts can override any file by deploying their own version.

require("hyprland/env")
require("hyprland/general")
require("hyprland/colors")
require("hyprland/rules")
require("hyprland/execs")
require("hyprland/keybinds")

-- Host-specific overrides (optional — no error if missing)
pcall(require, "hyprland/host")
