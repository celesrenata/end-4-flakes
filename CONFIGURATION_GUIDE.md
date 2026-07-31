# Static Configuration Guide for dots-hyprland

This guide covers **direct configuration file editing** for users who prefer to modify configs without rebuilding the Nix flake. This is useful in **writable mode** or when you need quick changes that don't require a full rebuild.

## Table of Contents

- [When to Use This Guide](#when-to-use-this-guide)
- [Quickshell Configuration (Config.qml)](#quickshell-configuration-configqml)
  - [Appearance Settings](#appearance-settings)
  - [Bar Configuration](#bar-configuration)
  - [Battery Settings](#battery-settings)
  - [Application Commands](#application-commands)
  - [Time Format](#time-format)
- [Hyprland Configuration](#hyprland-configuration)
  - [General Settings (general.conf)](#general-settings-generalconf)
  - [Keybinds (keybinds.conf)](#keybinds-keybindsconf)
  - [Window Rules (rules.conf)](#window-rules-rulesconf)
  - [Colors (colors.conf)](#colors-colorsconf)
  - [Environment Variables (env.conf)](#environment-variables-envconf)
  - [Autostart Programs (execs.conf)](#autostart-programs-execsconf)
- [Terminal Configuration (foot.ini)](#terminal-configuration-footini)
- [How to Apply Changes](#how-to-apply-changes)
- [Common Customizations](#common-customizations)
- [Finding More Options](#finding-more-options)

---

## When to Use This Guide

Use this guide when:

- You're in **writable mode** and want to edit configs directly
- You need **quick changes** without a full Nix rebuild
- You prefer **visual editing** of QML/config files
- You're **debugging** a specific configuration issue

For **declarative/hybrid modes**, use the [NixOS Configuration Guide](./NIXOS_CONFIGURATION_GUIDE.md) instead, which generates configs from Nix options.

---

## Quickshell Configuration (Config.qml)

The main Quickshell configuration file is located at:
```
~/.config/quickshell/ii/modules/common/Config.qml
```

This file uses a **JsonAdapter** pattern — properties are defined as QML `JsonObject` types that map to JSON configuration.

### Appearance Settings

Controls visual aspects of the Quickshell UI:

```qml
property JsonObject appearance: JsonObject {
    property bool extraBackgroundTint: true      // Enable background tinting for depth
    property int fakeScreenRounding: 2            // 0=None, 1=Always, 2=When not fullscreen
    property bool transparency: false              // Enable transparency effects
    
    property JsonObject wallpaperTheming: JsonObject {
        property bool enableAppsAndShell: true    // Apply colors to Quickshell UI
        property bool enableQtApps: true          // Apply colors to Qt applications
        property bool enableTerminal: true        // Apply colors to terminal emulator
    }
}
```

**Changing appearance:**
```qml
// Disable transparency
property bool transparency: true

// Always use rounded corners (even when fullscreen)
property int fakeScreenRounding: 1

// Disable anti-flashbang overlay during workspace transitions
property string antiFlashbang: "off"   // Options: "off", "weak", "strong"
```

### Bar Configuration

Controls the status bar layout and content:

```qml
property JsonObject bar: JsonObject {
    property bool bottom: false              // true = bar at bottom, false = top
    property int cornerStyle: 0               // 0=Hug (follows screen), 1=Float, 2=Plain rectangle
    property bool borderless: false           // Remove borders between bar sections
    property string topLeftIcon: "spark"      // "distro" or "spark" icon in top-left
    
    property bool showBackground: true        // Show solid/gradient background behind bar
    property bool verbose: true               // Show detailed info (full date, CPU/RAM values)
                                              // Set false for compact mode on smaller screens
    
    // Utility buttons in the bar
    property JsonObject utilButtons: JsonObject {
        property bool showScreenSnip: true    // Screenshot button
        property bool showColorPicker: false  // Color picker button
        property bool showMicToggle: false    // Microphone toggle button
        property bool showKeyboardToggle: true // Keyboard layout toggle
        property bool showDarkModeToggle: true // Dark/light mode toggle
        property bool showPerformanceProfileToggle: false  // Gaming vs battery profile
    }
    
    // Workspace indicators in the bar
    property JsonObject workspaces: JsonObject {
        property string variant: "default"    // "default" or "hefty" (enhanced with app icons)
        property bool monochromeIcons: true   // Single-color workspace icons
        property int shown: 10                // Number of workspaces to display
        property bool showAppIcons: true      // Show running app icons on workspaces
        property bool alwaysShowNumbers: false // Always show numbers (vs. on hover)
        property int showNumberDelay: 300     // Delay before showing workspace numbers (ms)
    }
}
```

**Moving bar to bottom:**
```qml
property bool bottom: true
```

**Changing corner style:**
```qml
// Float style (bar doesn't touch screen edges)
property int cornerStyle: 1

// Plain rectangle (no rounding)
property int cornerStyle: 2
```

**Adjusting workspace count:**
```qml
property JsonObject workspaces: JsonObject {
    property int shown: 5   // Show only 5 workspaces
}
```

### Battery Settings

```qml
property JsonObject battery: JsonObject {
    property int low: 20                    // Low battery warning threshold (%)
    property int critical: 5                // Critical battery threshold (%)
    property bool automaticSuspend: true    // Auto-suspend when critical
    property int suspend: 3                 // Minutes to wait after critical before suspending
}
```

**Example — change thresholds:**
```qml
property JsonObject battery: JsonObject {
    property int low: 25                    // Warn at 25%
    property int critical: 10               // Critical at 10%
    property bool automaticSuspend: false   // Don't auto-suspend
}
```

### Application Commands

Commands launched by various UI elements (bar buttons, sidebar apps, etc.):

```qml
property JsonObject apps: JsonObject {
    property string bluetooth: "kcmshell6 kcm_bluetooth"           // Bluetooth settings
    property string network: "plasmawindowed org.kde.plasma.networkmanagement"  // Network settings
    property string networkEthernet: "kcmshell6 kcm_networkmanagement"   // Wired network settings
    property string taskManager: "plasma-systemmonitor --page-name Processes"  // System monitor
    property string terminal: "foot"                               // Terminal emulator (for shell actions)
}
```

**Changing terminal:**
```qml
property string terminal: "kitty -1"     // Use kitty instead of foot
// Or use a different terminal:
property string terminal: "alacritty"
property string terminal: "wezterm"
```

**Changing network settings app:**
```qml
// Use GNOME Settings instead of KDE Plasma
property string network: "gnome-control-center"
```

### Time Format

Controls how the clock displays time and date in the bar:

```qml
property JsonObject time: JsonObject {
    property string format: "hh:mm"           // Time format (Qt format strings)
    property string dateFormat: "ddd, dd/MM"  // Date format
}
```

**Common format examples:**

| Format | Description | Example Output |
|--------|-------------|----------------|
| `"HH:mm:ss"` | 24-hour with seconds | `14:30:45` |
| `"hh:mm AP"` | 12-hour with AM/PM | `02:30 PM` |
| `"ddd, dd/MM"` | Short date | `Mon, 15/07` |
| `"dddd, MMMM dd, yyyy"` | Full date | `Monday, July 15, 2026` |

**Changing to 24-hour format with seconds:**
```qml
property JsonObject time: JsonObject {
    property string format: "HH:mm:ss"
    property string dateFormat: "dddd, MMMM dd, yyyy"
}
```

---

## Hyprland Configuration

Hyprland configs are located in `~/.config/hypr/`. Each config file controls a specific aspect of the compositor.

### General Settings (general.conf)

Controls window management, animations, input, and plugins:

```conf
# Monitor configuration (auto-detect by default)
monitor=,preferred,auto,1,transform,0

# Gestures (3-finger workspace swipe)
gestures {
    workspace_swipe = true
    workspace_swipe_distance = 700
    workspace_swipe_fingers = 3
}

general {
    gaps_in = 4           # Inner gaps between windows (pixels)
    gaps_out = 7          # Outer gaps around windows (pixels)
    gaps_workspaces = 50  # Gap between workspaces
    
    border_size = 2       # Border width (pixels)
    col.active_border = rgba(0DB7D4FF)     # Active window border color
    col.inactive_border = rgba(31313600)   # Inactive window border color
    resize_on_border = true                   # Resize by dragging borders
    
    no_focus_fallback = true                    # Don't focus empty workspaces
    allow_tearing = false                       # Enable for gaming (disables vsync)
    
    snap {
        enabled = true                          # Enable window snapping
    }
}

dwindle {
    preserve_split = true                       # Keep split ratio on new windows
    smart_split = false                         # Don't auto-split based on size
    smart_resizing = false                      # Don't auto-resize
}

decoration {
    rounding = 16                               # Corner rounding (pixels) — 0 for sharp corners
    
    blur {
        enabled = true                          # Enable background blur
        xray = true                             # Blur through the window (shows desktop behind)
        special = false                         # Don't blur special workspace
        new_optimizations = true                # Use newer blur algorithm
        size = 14                               # Blur radius
        passes = 3                              # Number of blur passes (higher = smoother but slower)
        brightness = 1                          # Brightness multiplier for blurred background
        noise = 0.01                            # Noise added to blur (reduces banding)
        contrast = 1                            # Contrast multiplier
        popups = true                           # Blur popup windows too
        popups_ignorealpha = 0.6                # Ignore alpha below this threshold for popups
    }
    
    shadow {
        enabled = true                          # Enable window shadows
        ignore_window = true                    # Don't draw shadow for focused window
        range = 30                              # Shadow radius (pixels)
        offset = 0 2                            # Shadow offset (x y)
        render_power = 4                        # Shadow rendering quality (higher = better but slower)
        color = rgba(00000010)                  # Shadow color with alpha
    }
    
    dim_inactive = true                         # Dim inactive windows slightly
    dim_strength = 0.025                        # Dim amount for inactive windows
    dim_special = 0.07                          # Dim amount for special workspace
}

animations {
    enabled = true                              # Enable all animations
    
    # Material Design bezier curves
    bezier = emphasizedDecel, 0.05, 0.7, 0.1, 1      # Snappy start, smooth end
    bezier = emphasizedAccel, 0.3, 0, 0.8, 0.15     # Slow start, snappy end
    bezier = standardDecel, 0, 0, 0, 1                # Standard deceleration
    bezier = menu_decel, 0.1, 1, 0, 1                 # Menu/overlay animations
    bezier = menu_accel, 0.52, 0.03, 0.72, 0.08       # Menu open acceleration
    
    # Window animations
    animation = windowsIn, 1, 3, emphasizedDecel, popin 80%   # Window open: 3s, pop-in 80% scale
    animation = windowsOut, 1, 2, emphasizedDecel, popin 90%  # Window close: 2s, pop-out 90% scale
    animation = windowsMove, 1, 3, emphasizedDecel, slide       # Window move: 3s, slide effect
    
    # Layer animations (sidebars, bar, etc.)
    animation = layersIn, 1, 2.7, emphasizedDecel, popin 93%   # Layer open
    animation = layersOut, 1, 2.4, menu_accel, popin 94%       # Layer close
    
    # Workspace animations
    animation = workspaces, 1, 7, menu_decel, slide             # Workspace switch: 7s slide
}

input {
    kb_layout = us                          # Keyboard layout (change for your region)
    numlock_by_default = true               # Enable NumLock on startup
    
    repeat_delay = 250                      # Key repeat delay (ms)
    repeat_rate = 35                        # Key repeat rate (events per second)
    
    follow_mouse = 1                        # Focus window under cursor on move
    off_window_axis_events = 2              # Send scroll events to focused window even when over non-focused
    
    touchpad {
        natural_scroll = yes                # Scroll direction matches finger movement
        disable_while_typing = true         # Disable touchpad while typing
        clickfinger_behavior = true         # Bottom area of touchpad acts as physical button
        scroll_factor = 0.5                 # Touchpad scroll sensitivity (0.0-1.0)
    }
}

misc {
    disable_hyprland_logo = true            # Hide Hyprland startup logo
    disable_splash_rendering = true         # Skip splash screen animation
    vfr = 1                                 # Variable refresh rate (requires monitor support)
    vrr = 1                                 # Enable VRR (FreeSync/G-Sync)
    mouse_move_enables_dpms = true          # Move mouse to wake display from DPMS
    key_press_enables_dpms = true           # Press key to wake display from DPMS
    animate_manual_resizes = false          # Don't animate manual window resizes
    animate_mouse_windowdragging = false    # Don't animate window dragging with mouse
    enable_swallow = false                  # Enable window "swallowing" (embedded terminals)
    swallow_regex = (foot|kitty|alacritty)  # Regex for windows to swallow
    
    new_window_takes_over_fullscreen = 2    # New fullscreen window replaces old one
    allow_session_lock_restore = true       # Allow restoring session after lock
    session_lock_xray = true                # X-ray effect during session lock
    initial_workspace_tracking = false      # Don't track which workspace windows were on
    focus_on_activate = true                # Focus window when activated by another app
}

binds {
    scroll_event_delay = 0                  # No delay between scroll events (smooth scrolling)
    hide_special_on_workspace_change = true # Hide special workspace content when switching away
}

cursor {
    zoom_factor = 1                         # Initial cursor zoom (1.0 = normal, higher = larger)
    zoom_rigid = false                      # Rigid zoom (no smooth animation)
}

# Plugin: Workspace overview grid (hyprexpo)
plugin {
    hyprexpo {
        columns = 3                         # Number of columns in overview grid
        gap_size = 5                        # Gap between workspace previews (pixels)
        bg_col = rgb(000000)                # Background color behind overview
        workspace_method = first 1          # How to select workspace: "first N" or "center m+N"
        
        enable_gesture = false              # Enable 4-finger swipe for overview (laptop touchpad)
        gesture_distance = 300              # Distance for 4-finger gesture to trigger overview
        gesture_positive = false            # Positive = swipe up, negative = swipe down
    }
}
```

**Common changes:**

| Setting | Change To | Effect |
|---------|-----------|--------|
| `gaps_in` / `gaps_out` | Smaller values (e.g., `2` / `4`) | More screen space for windows |
| `decoration.rounding` | `0` | Sharp corners (no rounding) |
| `decoration.blur.enabled` | `false` | Better performance on low-end hardware |
| `general.allow_tearing` | `true` | Enable for gaming (disables vsync) |
| `kb_layout` | `"us"` → `"gb"` / `"de"` / etc. | Match your keyboard layout |

### Keybinds (keybinds.conf)

The keybinds file contains ~145+ keyboard shortcuts organized by section. Each line follows this format:

```conf
# Section header (shown in cheatsheet)
#!
##! Shell

# Basic bind: key combo → action
bindd = Super, A, ..., global, quickshell:sidebarLeftToggle  # Toggle left sidebar

# Hold-to-repeat bind (for volume/brightness hardware keys)
bindle = , XF86MonBrightnessUp, exec, ...                    # Increase brightness

# Auto-repeating bind (hold for continuous action)
binde = Super, Semicolon, splitratio, -0.1                   # Decrease split ratio

# Mouse drag bind
bindm = Super, mouse:272, movewindow                         # Drag to move window

# Comment format for cheatsheet display
# Description text appears in cheatsheet; [hidden] hides it from display
```

**Key types:**
| Type | Trigger | Use Case |
|------|---------|----------|
| `bind` | Press + release | One-time actions (open terminal, close window) |
| `bindd` | Key down | Actions that trigger on key press |
| `bindl` | Key hold | Repeat while held (volume/brightness) |
| `binde` | Hold + repeat | Continuous action (split ratio adjustment) |
| `bindm` | Mouse drag | Move/resize windows with mouse |
| `bindrit` | Key release | Actions on key release (workspace numbers) |
| `binditn` | Ignore all keys | Prevent accidental triggers during overview |

**Adding custom keybinds:**

Edit `~/.config/hypr/custom/keybinds.conf`:
```conf
# My personal keybinds (survive all rebuilds)
bind = Super+Shift, J, exec, foot -e htop          # Open system monitor in terminal
bind = Super+Shift, K, exec, firefox --new-window  # Open new browser window
bind = Super+Alt, P, exec, code                    # Open VS Code
```

### Window Rules (rules.conf)

Controls how specific applications behave in Hyprland:

**Floating windows** (don't tile):
```conf
# Float specific apps (dialogs, settings, PiP)
windowrulev2 = float, class:^(pavucontrol)$          # Volume mixer
windowrulev2 = float, class:^(nm-connection-editor)$  # Network editor
windowrulev2 = float, title:^(illogical-impulse Settings)$  # Quickshell settings
windowrulev2 = float, title:^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$  # PiP windows
```

**Window size/position:**
```conf
# Size and center specific windows
windowrulev2 = size 45%, class:^(pavucontrol)$        # 45% of screen
windowrulev2 = center, class:^(pavucontrol)$          # Center on screen
windowrulev2 = move 73% 72%, title:^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$  # PiP position
```

**Gaming rules** (disable vsync for performance):
```conf
windowrulev2 = immediate, title:.*\.exe               # Windows games
windowrulev2 = immediate, title:.*minecraft.*         # Minecraft
windowrulev2 = immediate, class:^(steam_app).*        # Steam games
```

**No shadow for tiled windows** (performance):
```conf
windowrulev2 = noshadow, floating:0                   # Remove shadow from non-floating windows
```

### Colors (colors.conf)

Controls border colors and title bar styling. Colors are typically auto-generated by the Material You pipeline, but you can customize them:

```conf
general {
    col.active_border = rgba(F7DCDE39)     # Active window border color (hex with alpha)
    col.inactive_border = rgba(A58A8D30)   # Inactive window border color
}

misc {
    background_color = rgba(1D1011FF)      # Background color for special workspace
}

# Hyprbars plugin: title bar buttons
plugin {
    hyprbars {
        bar_text_font = Rubik, Geist, AR One Sans, Inter, Roboto, Ubuntu, Noto Sans, sans-serif
        bar_height = 30                     # Title bar height (pixels)
        bar_padding = 10                    # Horizontal padding inside title bar
        bar_button_padding = 5              # Padding around close/minimize/maximize buttons
        bar_precedence_over_border = true   # Draw bar over window border
        bar_part_of_window = true           # Bar is part of the window (not separate)
        
        bar_color = rgba(1D1011FF)          # Title bar background color
        col.text = rgba(F7DCDEFF)           # Title bar text color
        
        # Buttons: close, fullscreen, minimize (right to left order)
        hyprbars-button = rgb(F7DCDE), 13, <icon>, hyprctl dispatch killactive      # Close
        hyprbars-button = rgb(F7DCDE), 13, <icon>, hyprctl dispatch fullscreen 1    # Maximize
        hyprbars-button = rgb(F7DCDE), 13, <icon>, hyprctl dispatch movetoworkspacesilent special  # Minimize/special
    }
}

# Pinned window border highlight
windowrulev2 = bordercolor rgba(FFB2BCAA) rgba(FFB2BC77), pinned:1
```

### Environment Variables (env.conf)

Sets environment variables for the Hyprland session:

```conf
# Input method configuration (fcitx5)
env = QT_IM_MODULE, fcitx
env = XMODIFIERS, @im=fcitx
env = SDL_IM_MODULE, fcitx
env = GLFW_IM_MODULE, ibus
env = INPUT_METHOD, fcitx

# Wayland-specific settings
env = ELECTRON_OZONE_PLATFORM_HINT, auto    # Fix Electron apps (VS Code, Discord)

# Theme configuration
env = QT_QPA_PLATFORM, wayland              # Force Qt to use Wayland
env = QT_QPA_PLATFORMTHEME, kde             # Use KDE theme for Qt apps
env = XDG_MENU_PREFIX, plasma-              # Use Plasma menu prefix

# Virtual environment for Material You color generation
env = ILLOGICAL_IMPULSE_VIRTUAL_ENV, ~/.local/state/quickshell/.venv

# Default terminal application (used by launch_first_available.sh)
env = TERMINAL, kitty -1
```

**Adding custom environment variables:**
```conf
# Example: Set a custom variable for your workflow
env = MY_CUSTOM_VAR, some_value

# Example: Override Qt theme
env = QT_STYLE_OVERRIDE, kvantum
```

### Autostart Programs (execs.conf)

Programs that start automatically when Hyprland launches:

```conf
# Quickshell desktop environment
exec-once = qs -c $qsConfig &

# Idle manager (screen dimming, locking, suspend)
exec-once = hypridle

# Clipboard history monitor (captures text and image clipboard)
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store

# Audio processing (EasyEffects for equalizer/reverb)
exec-once = easyeffects --gapplication-service

# Input method
exec-once = fcitx5

# Authentication agents (for password prompts in apps)
exec-once = gnome-keyring-daemon --start --components=secrets
exec-once = /usr/lib/polkit-kde-authentication-agent-1

# D-Bus environment synchronization
exec-once = dbus-update-activation-environment --all
```

**Adding custom autostart programs:**
```conf
# Example: Start a system tray app
exec-once = blueman-applet &

# Example: Start a notification daemon
exec-once = dunst &
```

---

## Terminal Configuration (foot.ini)

The foot terminal emulator configuration is at `~/.config/foot/foot.ini`. It's auto-generated from the Material You color pipeline, but you can customize it:

```ini
[main]
term=xterm-256color          # Terminal type (for compatibility)
login-shell=yes              # Run as login shell
app-id=foot                  # Application ID for Hyprland window rules
title=foot                   # Window title

[scrollback]
lines=1000                   # Scrollback buffer size (number of lines)
multiplier=3.0               # Multiplier for scrollback calculation

[cursor]
style=beam                   # Cursor style: block, beam, underline
blink=no                     # Enable cursor blinking
beam-thickness=1.5           # Beam cursor thickness (0.0-2.0)

[colors]
alpha=0.95                   # Terminal transparency (0.0=transparent, 1.0=opaque)
# Foreground/background colors are auto-generated by Material You pipeline
```

**Common customizations:**

| Setting | Change To | Effect |
|---------|-----------|--------|
| `scrollback.lines` | `5000` | More scrollback history |
| `cursor.style` | `block` | Block cursor instead of beam |
| `colors.alpha` | `1.0` | Fully opaque terminal |

---

## How to Apply Changes

### Method 1: Direct Edit (Writable Mode)

1. **Edit the config file** directly in `~/.config/`:
   ```bash
   nano ~/.config/hypr/custom/keybinds.conf
   # or
   nano ~/.config/quickshell/ii/modules/common/Config.qml
   ```

2. **Reload Hyprland** to apply Hyprland config changes:
   ```bash
   hyprctl reload
   ```

3. **Restart Quickshell** to apply QML config changes:
   ```bash
   systemctl --user restart quickshell
   # or
   killall qs quickshell && qs -c $qsConfig &
   ```

### Method 2: Nix Rebuild (Declarative/Hybrid Mode)

1. **Edit your flake.nix** with the desired options:
   ```nix
   programs.dots-hyprland = {
     enable = true;
     quickshell.bar.bottom = true;
     hyprland.decoration.rounding = 0;
   };
   ```

2. **Rebuild and apply**:
   ```bash
   home-manager switch
   # or
   nixos-rebuild switch
   ```

3. **Verify changes**:
   ```bash
   cat ~/.config/hypr/general.conf | grep rounding  # Should show new value
   hyprctl getoption decoration:rounding             # Runtime verification
   ```

### Method 3: Template Edit (Advanced)

For changes that require modifying the source templates:

1. **Edit the template file** in the flake source:
   ```bash
   nano configs/hypr/general.conf.template
   ```

2. **Commit and rebuild**:
   ```bash
   git add configs/
   git commit -m "Update general.conf template"
   home-manager switch
   ```

---

## Common Customizations

### Change Terminal to Kitty

In `Config.qml`:
```qml
property JsonObject apps: JsonObject {
    property string terminal: "kitty -1"
}
```

Or in Hyprland keybinds, change the `@TERMINAL_APPS@` variable to include kitty first.

### Move Bar to Bottom

In `Config.qml`:
```qml
property JsonObject bar: JsonObject {
    property bool bottom: true
}
```

### Disable Transparency

In `Config.qml`:
```qml
property JsonObject appearance: JsonObject {
    property bool transparency: false
}
```

### Change Time Format to 12-Hour

In `Config.qml`:
```qml
property JsonObject time: JsonObject {
    property string format: "hh:mm AP"
    property string dateFormat: "dddd, MMMM dd, yyyy"
}
```

### Increase Terminal Scrollback

In `~/.config/foot/foot.ini`:
```ini
[scrollback]
lines=10000
multiplier=5.0
```

### Change Workspace Count

In `Config.qml`:
```qml
property JsonObject bar: JsonObject {
    property JsonObject workspaces: JsonObject {
        property int shown: 5  # Show only 5 workspaces
    }
}
```

### Disable Blur for Better Performance

In `~/.config/hypr/general.conf`:
```conf
decoration {
    blur {
        enabled = false
    }
}
```

### Change Corner Rounding to Zero (Sharp Corners)

In `~/.config/hypr/general.conf`:
```conf
decoration {
    rounding = 0
}
```

---

## Finding More Options

### Quickshell Config

- **Main config**: `~/.config/quickshell/ii/modules/common/Config.qml` (lines 1-300)
- **Search for settings**: `grep -r "property.*terminal" ~/.config/quickshell/`

### Hyprland Settings

- **General**: `~/.config/hypr/general.conf`
- **Keybinds**: `~/.config/hypr/keybinds.conf` (or `~/.config/hypr/custom/keybinds.conf`)
- **Rules**: `~/.config/hypr/rules.conf`
- **Colors**: `~/.config/hypr/colors.conf`

### Template Files (for Nix rebuild)

- **Templates**: `configs/hypr/*.conf.template` in the flake source
- **Search for variables**: `grep -r '@[A-Z_]*@' configs/`

---

## Pro Tips

1. **Custom config survives rebuilds**: Edits to `~/.config/hypr/custom/*.conf` are preserved across Nix rebuilds (they're sourced after the main config)

2. **Check template variables**: Look for `@VARIABLE@` patterns in `.template` files — these are resolved at build time by Nix

3. **Test changes safely**: Use writable mode for quick testing, then apply to declarative mode for production:
   ```bash
   # Test in writable mode
   programs.dots-hyprland.mode = "writable";
   
   # Apply to production
   programs.dots-hyprland.mode = "hybrid";
   ```

4. **Backup configs**: Git tracks all changes, so you can always revert:
   ```bash
   git log --oneline configs/
   git diff HEAD~1 configs/hypr/general.conf
   ```

5. **Reload without restart**: Use `hyprctl reload` for Hyprland config changes and `systemctl --user restart quickshell` for Quickshell changes — no need to log out/in

6. **Debug with cheatsheet**: Press `Super+/` to see all keybinds and verify your custom keybinds are loaded

---

## Related Documentation

- [`NIXOS_CONFIGURATION_GUIDE.md`](./NIXOS_CONFIGURATION_GUIDE.md) — Nix option reference (for declarative/hybrid modes)
- [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) — System architecture and data flow
- [`docs/keybinds-reference.md`](./docs/keybinds-reference.md) — Complete keybind reference with both formats
- [`docs/hyprland-config-structure.md`](./docs/hyprland-config-structure.md) — Hyprland config file details
- [`docs/troubleshooting.md`](./docs/troubleshooting.md) — Common issues and fixes
