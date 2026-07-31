# Hyprland Configuration Structure

This document describes how Hyprland configuration is organized in both the **upstream dots-hyprland** and the **NixOS fork (end-4-flakes)**.

## Upstream Configuration Layout

```
.config/hypr/
├── hyprland.conf              # Entry point — sources all other .conf files
├── general.conf               # Layout, decoration, animations, input settings
├── keybinds.conf               # ~200+ keybind entries (Lua hl.bind() in upstream)
├── rules.conf                  # Window rules, layer rules, workspace rules
├── colors.conf                 # Border colors, hyprbars plugin styling
├── env.conf                    # Environment variables (IM, themes, venv path)
├── execs.conf                  # Autostart programs (Quickshell, hypridle, clipboard)
├── hypridle.conf               # Idle/power cascade timeouts
├── hyprlock/
│   ├── check-capslock.sh       # Caps Lock status indicator script
│   └── status.sh               # Battery status display for lock screen
├── custom/                     # User overrides (survive reinstall)
│   ├── env.conf
│   ├── execs.conf
│   ├── general.conf
│   ├── keybinds.conf
│   └── rules.conf
├── scripts/                    # Helper shell scripts
│   ├── launch_first_available.sh  # Try multiple app commands, run first found
│   ├── workspace_action.sh        # Workspace focus/send via hyprctl dispatch
│   ├── zoom.sh                   # Zoom in/out fallback script
│   ├── record.sh                 # Screen recording (ffmpeg + slurp)
│   ├── fuzzel-emoji.sh           # Emoji search → clipboard copy
│   ├── start_geoclue_agent.sh    # Location service for weather widget
│   └── ai/
│       ├── primary-buffer-query.sh  # AI summary of selected text
│       └── show-loaded-ollama-models.sh
├── shaders/                    # Custom Hyprland shaders
│   ├── chromatic_abberation.frag
│   ├── crt.frag
│   ├── drugs.frag
│   ├── extradark.frag
│   ├── invert.frag
│   └── solarized.frag
```

## NixOS Fork Configuration Layout

```
configs/hypr/                          # Source templates (Nix build-time)
├── hyprland.conf.template             # Entry point — sources all .conf.template files
├── general.conf.template              # Gaps, borders, blur, animations, input
├── keybinds.conf.template             # ~145 keybind entries with @VARIABLE@ paths
├── rules.conf.template                # Window/layer/workspace rules
├── colors.conf.template               # Material You border/plugin colors
├── env.conf.template                  # Environment variables (IM, themes, venv)
├── execs.conf.template                # Autostart programs
├── hypridle.conf.template             # Idle/power cascade
├── scripts/                           # Helper shell scripts (same as upstream)
│   ├── workspace_action.sh
│   └── launch_first_available.sh
└── custom/                            # User overrides (survive rebuilds)
    ├── env.conf
    ├── general.conf
    ├── keybinds.conf
    ├── rules.conf
    └── scripts/

~/.config/hypr/                        # Runtime (generated from templates)
├── hyprland.conf                      # Resolved entry point
├── general.conf                       # Resolved general settings
├── keybinds.conf                      # Resolved keybinds with Nix store paths
├── rules.conf                         # Resolved window/layer rules
├── colors.conf                        # Resolved Material You colors
├── env.conf                           # Resolved environment variables
├── execs.conf                         # Resolved autostart programs
├── hypridle.conf                      # Idle/power cascade config
└── custom/                            # User overrides (preserved across rebuilds)
```

## Configuration File Details

### `hyprland.conf` — Entry Point

The main config file that sources all other configuration files:

**Upstream:**
```conf
source = ~/.config/hypr/hyprland/general.conf
source = ~/.config/hypr/hyprland/keybinds.conf
source = ~/.config/hypr/hyprland/rules.conf
source = ~/.config/hypr/hyprland/colors.conf
source = ~/.config/hypr/hyprland/env.conf
source = ~/.config/hypr/hyprland/execs.conf
source = ~/.config/hypr/hypridle.conf
```

**NixOS Fork (template):**
```conf
# hyprland.conf.template — sourced by Nix at build time
source = @HYPRLAND_GENERAL_CONF@
source = @HYPRLAND_KEYBINDS_CONF@
source = @HYPRLAND_RULES_CONF@
source = @HYPRLAND_COLORS_CONF@
source = @HYPRLAND_ENV_CONF@
source = @HYPRLAND_EXECS_CONF@
source = @HYPRLAND_HYPRIDLE_CONF@

# Custom user overrides (survive rebuilds)
source = ~/.config/hypr/custom/general.conf
source = ~/.config/hypr/custom/keybinds.conf
source = ~/.config/hypr/custom/rules.conf
source = ~/.config/hypr/custom/env.conf
source = ~/.config/hypr/custom/execs.conf
```

### `general.conf` — Layout & Behavior

Controls window management, animations, input, and plugins:

**Key sections:**
- **monitors** — Per-monitor configuration (resolution, refresh rate, position, scale)
- **gestures** — 3-finger workspace swipe settings
- **general** — Gaps (in/out/workspace), border size/color, tearing, snap
- **dwindle** — Tiling algorithm settings (preserve_split, smart_split)
- **decoration** — Rounding, blur (xray, popups, noise), shadows
- **animations** — Material Design bezier curves, window in/out/move animations, workspace transitions
- **input** — Keyboard layout, repeat rate, touchpad (natural scroll, disable while typing)
- **misc** — VFR/VRR, cursor zoom, window swallowing regex, session lock behavior
- **binds** — Scroll delay, hidden workspace behavior on switch
- **plugin** — hyprexpo (workspace overview grid), hyprbars (title bar buttons)

### `keybinds.conf` — Keyboard Shortcuts

The largest config file (~200+ entries). Organized into sections:

```conf
#!
##! Shell          # Launcher, sidebar toggles, cheatsheet, session menu
##! Utilities      # Screenshot, record, OCR, color picker, clipboard
##! Window         # Focus, move, resize, split ratio, float/tile
##! Workspace      # Switch, send-to, special workspace (scratchpad)
##! Screen         # Zoom in/out
##! Media          # Play/pause, next/prev, mute
##! Apps           # Terminal, browser, file manager, settings
##! Session        # Lock, suspend, power off
##! Testing        # Notification tests
```

**Upstream uses Lua `hl.bind()` syntax; NixOS fork uses `.conf` format with template variables.**

### `rules.conf` — Window & Layer Rules

**Window rules** control how specific applications behave:

| Rule Type | Purpose | Examples |
|-----------|---------|----------|
| `float` | Force floating mode | pavucontrol, nm-connection-editor, Zotero, PiP windows |
| `size` | Set window dimensions | pavucontrol 45%, PiP 25% |
| `center` | Center on screen | File dialogs, settings windows |
| `move` | Position window | PiP at 73%/72%, Dolphin copy dialog at 40/80 |
| `pin` | Always on top | PiP windows |
| `immediate` | Disable vsync for gaming | `.exe`, minecraft, steam_app |
| `no_shadow` | Remove shadow from tiled windows | Improves performance |
| `tile` | Force tiling mode | Warp (browser extension) |

**Layer rules** control how Quickshell layer-shell surfaces behave:

| Rule Type | Purpose | Examples |
|-----------|---------|----------|
| `blur on` | Apply blur effect | Sidebars, bar, dock, notifications |
| `noanim` / `animation fade/slide` | Control animations | Overview (fast), sidebars (slide), session (fade) |
| `ignorealpha` | Set transparency level | Bar 0.6, notifications 0.69, background widgets 0.05 |
| `xray on` | Render through the layer | Global xray for all layers |

### `colors.conf` — Material You Colors

Controls border colors and hyprbars plugin styling:

```conf
general {
    col.active_border = rgba(@PRIMARY_COLOR@)     # Active window border
    col.inactive_border = rgba(@SURFACE_COLOR@)    # Inactive window border
}

plugin {
    hyprbars {
        bar_color = rgba(@BACKGROUND_COLOR@)       # Title bar background
        col.text = rgba(@ON_SURFACE@)              # Title bar text
        bar_text_font = Rubik, Geist, Inter, ...   # Font stack
        bar_height = 30                            # Title bar height
        hyprbars-button = rgb(...), 13, icon, action  # Close/minimize/maximize buttons
    }
}

# Pinned window border highlight
windowrulev2 = bordercolor rgba(FFB2BCAA) rgba(FFB2BC77), pinned:1
```

### `env.conf` — Environment Variables

**Upstream (static):**
```conf
env = QT_IM_MODULE, fcitx
env = ILLOGICAL_IMPULSE_VIRTUAL_ENV, ~/.local/state/quickshell/.venv
env = TERMINAL, kitty -1
```

**NixOS Fork (template with @VARIABLE@ substitution):**
```conf
# @QT_THEME@ → qt6ct / kvantum / etc.
# @NVIDIA_ENV@ → __GLX_VENDOR_LIBRARY_NAME=nvidia (if applicable)
# @AMD_ENV@ → RADV_VEGA10_TEMP_LIMIT=85 (if AMD)
env = ILLOGICAL_IMPULSE_VIRTUAL_ENV, @DATA_DIR@/quickshell/.venv
```

### `execs.conf` — Autostart Programs

**Upstream:**
```conf
exec-once = qs -c $qsConfig &                    # Quickshell
exec-once = hypridle                             # Idle manager
exec-once = wl-paste --type text --watch cliphist store  # Clipboard monitor
exec-once = easyeffects --gapplication-service   # Audio processing
exec-once = fcitx5                               # Input method
```

**NixOS Fork (template):**
```conf
# @HYPRIDLE_BIN@ → hypridle path
# @GNOME_KEYRING_BIN@ → gnome-keyring-daemon path
# @POLKIT_AGENT_BIN@ → polkit authentication agent path
exec-once = @HYPRIDLE_BIN@
exec-once = @QUICKSHELL_BIN@ -p ~/.config/quickshell/ii/shell.qml
```

### `hypridle.conf` — Power Management

5-stage idle cascade:

| Timeout | Action | Purpose |
|---------|--------|---------|
| 300s (5 min) | Lock session (`loginctl lock-session`) | Security |
| 600s (10 min) | DPMS off (`hyprctl dispatch dpms off`) | Save screen life |
| 900s (15 min) | Suspend (`systemctl suspend \|\| loginctl suspend`) | Save battery |

**NixOS Fork uses a more granular cascade:**
| Timeout | Action |
|---------|--------|
| 150s | Screen dim |
| 300s | Lock (hyprlock) |
| 330s | DPMS off |
| 1800s | System suspend |

## Custom Config Override System

Both upstream and NixOS fork support user customization via `~/.config/hypr/custom/`:

```bash
# Create custom override files (survive rebuilds)
touch ~/.config/hypr/custom/general.conf
touch ~/.config/hypr/custom/keybinds.conf
touch ~/.config/hypr/custom/rules.conf
touch ~/.config/hypr/custom/env.conf
touch ~/.config/hypr/custom/execs.conf

# Add your overrides to these files
# They are sourced AFTER the main config, so they take precedence
```

**Example custom keybinds (`~/.config/hypr/custom/keybinds.conf`):**
```conf
# My personal keybinds (survive all rebuilds)
bind = Super+Shift, J, exec, foot -e htop
bind = Super+Shift, K, exec, firefox --new-window
```

## Template System (NixOS Fork)

The NixOS fork uses a **build-time template system** to resolve `@VARIABLE@` placeholders:

1. Source files in `configs/hypr/*.conf.template` contain `@VARIABLE@` placeholders
2. Home Manager activation script substitutes variables with actual values
3. Resulting `.conf` files are placed in `~/.config/hypr/`
4. Hyprland reads the resolved configs at startup

**Variable resolution examples:**
```
@QUICKSHELL_BIN@ → /nix/store/xxxx-quickshell/bin/quickshell
@TERMINAL_APPS@  → foot,kitty -1,alacritty,wezterm,...
@CUSTOM_KEYBINDS@ → (contents of ~/.config/hypr/custom/keybinds.conf)
```

## Monitor Configuration

**Upstream default:** `monitor=,preferred,auto,1,transform,0` (uses first preferred monitor)

**NixOS Fork template:** Users configure monitors via the Home Manager option:
```nix
programs.dots-hyprland.hyprland.monitors = [
  "eDP-1,1920x1080@60,0x0,1.0"
  "HDMI-A-1,2560x1440@144,1920x0,1.5"
];
```

This generates the appropriate `monitor=` lines in `general.conf`.

## Animation Curves (Material Design)

Both upstream and NixOS fork use Material Design bezier curves:

| Curve Name | Control Points | Use Case |
|-----------|---------------|----------|
| `emphasizedDecel` | 0.05, 0.7, 0.1, 1 | Window open/close (snappy start, smooth end) |
| `emphasizedAccel` | 0.3, 0, 0.8, 0.15 | Window close (slow start, snappy end) |
| `standardDecel` | 0, 0, 0, 1 | General deceleration |
| `menu_decel` | 0.1, 1, 0, 1 | Menu/overlay animations |
| `menu_accel` | 0.52, 0.03, 0.72, 0.08 | Menu open acceleration |

**Animation definitions:**
```conf
animation = windowsIn, 1, 3, emphasizedDecel, popin 80%
animation = windowsOut, 1, 2, emphasizedDecel, popin 90%
animation = layersIn, 1, 2.7, emphasizedDecel, popin 93%
animation = workspaces, 1, 7, menu_decel, slide
```

## Plugin Configuration

### hyprexpo (Workspace Overview Grid)

```conf
plugin {
    hyprexpo {
        columns = 3
        gap_size = 5
        bg_col = rgb(000000)
        workspace_method = first 1
        enable_gesture = false
        gesture_distance = 300
    }
}
```

### hyprbars (Material You Title Bar Buttons)

```conf
plugin {
    hyprbars {
        bar_height = 30
        bar_padding = 10
        bar_button_padding = 5
        bar_precedence_over_border = true
        bar_part_of_window = true
        bar_color = rgba(1D1011FF)
        col.text = rgba(F7DCDEFF)
        # Buttons: close, fullscreen, minimize
        hyprbars-button = rgb(F7DCDE), 13, <icon>, hyprctl dispatch killactive
        hyprbars-button = rgb(F7DCDE), 13, <icon>, hyprctl dispatch fullscreen 1
        hyprbars-button = rgb(F7DCDE), 13, <icon>, hyprctl dispatch movetoworkspacesilent special
    }
}
```

## Keybind File Comments (Cheatsheet Integration)

The cheatsheet (`Super+/`) parses keybind files for display. Comment format controls visibility:

| Comment | Effect on Cheatsheet |
|---------|---------------------|
| `# Description text` | Shown in cheatsheet under that section |
| `# [hidden] Description` | Hidden from cheatsheet (internal bind) |
| `#!` / `##! Section Name` | Section header in cheatsheet |

This allows users to hide technical/internal keybinds while showing user-facing ones.
