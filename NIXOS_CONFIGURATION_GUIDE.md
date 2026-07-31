# NixOS Configuration Guide for dots-hyprland

This guide documents all available Home Manager options for configuring the dots-hyprland desktop environment on NixOS. All configuration is done through **Nix expressions** — you don't edit config files directly (except in writable mode).

## Table of Contents

- [Quick Start](#quick-start)
- [Deployment Modes](#deployment-modes)
- [Package Sets](#package-sets)
- [Quickshell Options Reference](#quickshell-options-reference)
  - [Appearance](#appearance)
  - [Bar](#bar)
  - [Battery](#battery)
  - [Applications](#applications)
  - [Notifications](#notifications)
  - [Time Format](#time-format)
- [Hyprland Options Reference](#hyprland-options-reference)
  - [General](#general)
  - [Decoration](#decoration)
  - [Gestures](#gestures)
  - [Monitors](#monitors)
  - [Night Light](#night-light)
  - [Keybinds](#keybinds)
- [Terminal Options Reference](#terminal-options-reference)
- [Config Override System](#config-override-system)
- [Development Workflow](#development-workflow)
- [Complete Configuration Examples](#complete-configuration-examples)

---

## Quick Start

Add the flake input to your system's `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    dots-hyprland.url = "github:celesrenata/end-4-flakes/upstream-sync-2026";
  };

  outputs = { self, nixpkgs, home-manager, dots-hyprland }: {
    homeConfigurations.your-user = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        dots-hyprland.homeManagerModules.default
        {
          home.username = "your-username";
          home.homeDirectory = "/home/your-username";
          home.stateVersion = "24.05";

          programs.dots-hyprland = {
            enable = true;
            source = dots-hyprland + "/configs";
            packageSet = "essential";
            mode = "hybrid";  # Recommended: Hyprland declarative, Quickshell editable

            quickshell = {
              appearance.transparency = false;
              bar.bottom = false;
              bar.workspaces.shown = 10;
            };

            hyprland = {
              general.gapsIn = 4;
              general.gapsOut = 7;
              decoration.rounding = 16;
              decoration.blurEnabled = true;
            };
          };
        }
      ];
    };
  };
}
```

Then apply:
```bash
home-manager switch
# or
nixos-rebuild switch  # if using NixOS module
```

---

## Deployment Modes

The `mode` option controls how configuration files are deployed:

### Hybrid Mode (Recommended)

- **Hyprland configs**: Managed declaratively by Home Manager (read-only in store)
- **Quickshell configs**: Copied to `~/.config/quickshell/` (editable at runtime)
- **Best for**: Most users — stable compositor config, flexible UI customization

```nix
programs.dots-hyprland = {
  mode = "hybrid";
};
```

### Declarative Mode

- Everything managed by Home Manager
- All files read-only in Nix store
- Changes require `home-manager switch` or `nixos-rebuild switch`

```nix
programs.dots-hyprland = {
  mode = "declarative";
};
```

### Writable Mode

- Files staged to a staging directory (default: `~/.configstaging/`)
- Setup script copies files to `~/.config/` for manual editing
- Useful for development and testing

```nix
programs.dots-hyprland = {
  mode = "writable";
  writable = {
    stagingDir = ".configstaging";        # Where files are staged
    setupScript = "initialSetup.sh";       # Name of the setup script
    backupExisting = true;                 # Backup existing configs before copying
    symlinkMode = false;                   # Use copy (true) or symlink (false)
  };
};
```

After switching to writable mode, run:
```bash
~/.local/bin/initialSetup.sh
# Then edit configs in ~/.config/quickshell/ and ~/.config/hypr/
```

---

## Package Sets

The `packageSet` option controls which packages are installed:

| Set | Contents | Best For |
|-----|----------|----------|
| `"minimal"` | Basic utilities (curl, jq, cliphist) + fuzzel + quickshell | Testing, minimal installs |
| `"essential"` (default) | Minimal + Hyprland tools + KDE components + fonts | Most users (recommended) |
| `"all"` | Essential + Python deps + audio tools + theme tools + nwg-displays | Full-featured setup |

```nix
programs.dots-hyprland.packageSet = "essential";  # or "minimal" or "all"
```

Additional package options:
```nix
programs.dots-hyprland.packages.includeNwgDisplays = true;  # Graphical monitor layout tool
```

---

## Quickshell Options Reference

### Appearance

Controls visual aspects of the Quickshell UI:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `appearance.extraBackgroundTint` | `bool` | `true` | Enable extra background tinting for depth |
| `appearance.fakeScreenRounding` | `enum [0, 1, 2]` | `2` | Screen rounding: `0`=None, `1`=Always, `2`=When not fullscreen |
| `appearance.transparency` | `bool` | `false` | Enable transparency effects on UI elements |
| `appearance.antiFlashbang` | `enum ["off", "weak", "strong"]` | `"off"` | Overlay during workspace transitions: `off`=none, `weak`=semi-transparent, `strong`=opaque |

```nix
programs.dots-hyprland.quickshell = {
  appearance.transparency = true;
  appearance.fakeScreenRounding = 2;
  appearance.antiFlashbang = "weak";
};
```

### Bar

Controls the status bar configuration:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `bar.bottom` | `bool` | `false` | Place bar at bottom instead of top |
| `bar.cornerStyle` | `enum [0, 1, 2]` | `0` | Corner style: `0`=Hug (follows screen edge), `1`=Float (floating), `2`=Plain rectangle |
| `bar.borderless` | `bool` | `false` | Remove grouping borders between bar sections |
| `bar.topLeftIcon` | `enum ["distro", "spark"]` | `"spark"` | Icon in top-left of bar: distro logo or spark icon |
| `bar.showBackground` | `bool` | `true` | Show bar background (solid/gradient) |
| `bar.verbose` | `bool` | `true` | Show detailed information (full date, CPU/RAM values) — set `false` for compact mode on smaller screens |

#### Utility Buttons

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `bar.utilButtons.showScreenSnip` | `bool` | `true` | Show screenshot button in bar |
| `bar.utilButtons.showColorPicker` | `bool` | `false` | Show color picker button in bar |
| `bar.utilButtons.showMicToggle` | `bool` | `false` | Show microphone toggle button in bar |
| `bar.utilButtons.showKeyboardToggle` | `bool` | `true` | Show keyboard layout toggle button |
| `bar.utilButtons.showDarkModeToggle` | `bool` | `true` | Show dark/light mode toggle button |
| `bar.utilButtons.showPerformanceProfileToggle` | `bool` | `false` | Show performance profile toggle (gaming vs battery) |

#### Workspace Indicators

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `bar.workspaces.variant` | `enum ["default", "hefty"]` | `"default"` | Workspace widget style: `default`=standard dots/bars, `hefty`=enhanced with app icons |
| `bar.workspaces.monochromeIcons` | `bool` | `true` | Use monochrome (single-color) workspace icons |
| `bar.workspaces.shown` | `int` | `10` | Number of workspaces to display in the bar |
| `bar.workspaces.showAppIcons` | `bool` | `true` | Show application icons on workspace indicators |
| `bar.workspaces.alwaysShowNumbers` | `bool` | `false` | Always show workspace numbers (vs. showing on hover) |
| `bar.workspaces.showNumberDelay` | `int` | `300` | Delay before showing workspace numbers (milliseconds) |

```nix
programs.dots-hyprland.quickshell = {
  bar.bottom = false;
  bar.cornerStyle = 1;  # Float style
  bar.topLeftIcon = "spark";
  bar.showBackground = true;
  bar.verbose = true;

  bar.utilButtons = {
    showScreenSnip = true;
    showColorPicker = true;
    showMicToggle = false;
    showKeyboardToggle = true;
    showDarkModeToggle = true;
  };

  bar.workspaces = {
    variant = "hefty";
    monochromeIcons = true;
    shown = 10;
    showAppIcons = true;
    alwaysShowNumbers = false;
    showNumberDelay = 300;
  };
};
```

### Battery

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `battery.low` | `int` | `20` | Low battery threshold (percentage) — shows warning icon |
| `battery.critical` | `int` | `5` | Critical battery threshold (percentage) — shows danger icon |
| `battery.automaticSuspend` | `bool` | `true` | Enable automatic suspend when battery reaches critical level |
| `battery.suspend` | `int` | `3` | Minutes to wait after critical threshold before suspending |

```nix
programs.dots-hyprland.quickshell.battery = {
  low = 20;
  critical = 5;
  automaticSuspend = true;
  suspend = 3;
};
```

### Applications

Commands launched by various UI elements:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `apps.terminal` | `str` | `"foot"` | Terminal emulator command (used in shell actions and keybinds) |
| `apps.bluetooth` | `str` | `"kcmshell6 kcm_bluetooth"` | Bluetooth settings command |
| `apps.network` | `str` | `"plasmawindowed org.kde.plasma.networkmanagement"` | Network settings command (windowed Plasma applet) |
| `apps.networkEthernet` | `str` | `"kcmshell6 kcm_networkmanagement"` | Wired network settings command |
| `apps.taskManager` | `str` | `"plasma-systemmonitor --page-name Processes"` | System monitor/task manager command |

```nix
programs.dots-hyprland.quickshell.apps = {
  terminal = "foot";
  bluetooth = "kcmshell6 kcm_bluetooth";
  network = "plasmawindowed org.kde.plasma.networkmanagement";
};
```

### Notifications

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `notifications.forceMonitor` | `nullOr str` | `null` | Force notifications to appear on a specific monitor (e.g., `"DP-1"`). When `null`, notifications appear on the focused monitor |

```nix
programs.dots-hyprland.quickshell.notifications.forceMonitor = "DP-1";  # or null for default
```

### Time Format

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `time.format` | `str` | `"hh:mm"` | Time format string (Qt date/time format) |
| `time.dateFormat` | `str` | `"ddd, dd/MM"` | Date format string (Qt date format) |

Common format examples:
- Time: `"HH:mm:ss"` (24h with seconds), `"hh:mm AP"` (12h with AM/PM)
- Date: `"dddd, MMMM dd, yyyy"` (full date), `"ddd, dd/MM"` (short date)

```nix
programs.dots-hyprland.quickshell.time = {
  format = "HH:mm:ss";
  dateFormat = "dddd, MMMM dd, yyyy";
};
```

---

## Hyprland Options Reference

### General

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hyprland.general.gapsIn` | `int` | `4` | Inner gaps between windows (pixels) |
| `hyprland.general.gapsOut` | `int` | `7` | Outer gaps around windows (pixels, between windows and screen edge) |
| `hyprland.general.borderSize` | `int` | `2` | Border width around windows (pixels) |
| `hyprland.general.allowTearing` | `bool` | `false` | Allow screen tearing (useful for gaming — disables vsync) |

```nix
programs.dots-hyprland.hyprland = {
  general.gapsIn = 4;
  general.gapsOut = 7;
  general.borderSize = 2;
  general.allowTearing = false;  # Set true for gaming
};
```

### Decoration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hyprland.decoration.rounding` | `int` | `16` | Corner rounding radius (pixels) — set to `0` for sharp corners |
| `hyprland.decoration.blurEnabled` | `bool` | `true` | Enable background blur effect on windows |

```nix
programs.dots-hyprland.hyprland = {
  decoration.rounding = 16;   # 0 for no rounding, higher for more rounded
  decoration.blurEnabled = true;  # Set false for better performance
};
```

### Gestures

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hyprland.gestures.workspaceSwipe` | `bool` | `true` | Enable 3-finger horizontal workspace swipe gesture on touchpad |

```nix
programs.dots-hyprland.hyprland.gestures.workspaceSwipe = true;
```

### Monitors

Per-monitor configuration strings. Each string follows the format:
```
<monitor-name>,<resolution>@<refresh-rate>,<position-x>x<position-y>,<scale>
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hyprland.monitors` | `list of str` | `[]` (auto-detect) | Monitor configuration strings |

Example:
```nix
programs.dots-hyprland.hyprland.monitors = [
  "eDP-1,1920x1080@60,0x0,1.0"           # Laptop screen
  "HDMI-A-1,2560x1440@144,1920x0,1.5"     # External monitor at 1.5x scale
];
```

Monitor string format:
```
<name>,<resolution>@<refresh-rate>,<position-x>x<position-y>,<scale>
```

- `name`: Output name from `hyprctl monitors` (e.g., `eDP-1`, `HDMI-A-1`, `DP-2`)
- `resolution`: WidthxHeight in pixels
- `refresh-rate`: In Hz (e.g., `60`, `144`, `120`)
- `position`: XxY offset from top-left of virtual screen
- `scale`: Scale factor (e.g., `1.0`, `1.5`, `2.0` for HiDPI)

### Night Light

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hyprland.night.colorTemperature` | `int` | `4500` | Night light color temperature in Kelvin (lower = warmer/redder, higher = cooler/bluer) |

```nix
programs.dots-hyprland.hyprland.night.colorTemperature = 4500;  # Warm amber
# Common values: 3000K (very warm), 4500K (default), 6500K (daylight)
```

### Keybinds

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hyprland.keybinds.darkLightToggle` | `bool` | `true` | Enable `Ctrl+Super+Shift+D` keybind for dark/light mode toggle |

```nix
programs.dots-hyprland.hyprland.keybinds.darkLightToggle = true;
```

---

## Terminal Options Reference

Controls the foot terminal emulator configuration:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `terminal.scrollback.lines` | `int` | `1000` | Scrollback buffer size (number of lines) |
| `terminal.scrollback.multiplier` | `float` | `3.0` | Multiplier for scrollback calculation |
| `terminal.cursor.style` | `str` | `"beam"` | Cursor style: `block`, `beam`, `underline` |
| `terminal.cursor.blink` | `bool` | `false` | Enable cursor blinking |
| `terminal.cursor.beamThickness` | `float` | `1.5` | Beam cursor thickness (0.0-2.0) |
| `terminal.colors.alpha` | `float` | `0.95` | Terminal transparency (0.0=fully transparent, 1.0=opaque) |
| `terminal.mouse.hideWhenTyping` | `bool` | `false` | Hide mouse cursor while typing |
| `terminal.mouse.alternateScrollMode` | `bool` | `true` | Enable alternate scroll mode for terminal apps |

```nix
programs.dots-hyprland.terminal = {
  scrollback.lines = 1000;
  scrollback.multiplier = 3.0;
  cursor.style = "beam";
  cursor.blink = false;
  cursor.beamThickness = 1.5;
  colors.alpha = 0.95;
};
```

---

## Config Override System

For complete control over specific config files, use the override system:

### File-Level Override

Replace an entire config file with your own content:

```nix
programs.dots-hyprland.overrides.hyprlandConf = pkgs.writeText "hyprland.conf" ''
  # Your custom hyprland.conf here
  source = ~/.config/hypr/custom/general.conf
'';
```

### Directory-Level Override

Replace an entire directory of config files:

```nix
programs.dots-hyprland.overrides.hyprDirectory = pkgs.runCommand "hypr-config" {} ''
  mkdir -p $out
  cp ${your-custom-config}/general.conf $out/general.conf
  cp ${your-custom-config}/keybinds.conf $out/keybinds.conf
'';
```

### Quickshell Config Override

Replace the generated `Config.qml` with your own:

```nix
programs.dots-hyprland.overrides.quickshellConfig = pkgs.writeText "Config.qml" ''
  // Your custom Config.qml here
  pragma Singleton
  import QtQuick
  // ...
'';
```

### When to Use Overrides

Use overrides when:
- You need complete control over a config file
- The Nix options don't cover your use case
- You want to preserve upstream config structure with minimal changes

**Note:** When an override is set, the corresponding auto-generated config is skipped.

---

## Development Workflow

### Adding New Configuration Options

1. **Define the option** in `modules/components/quickshell-config.nix`:

```nix
newFeature = mkOption {
  type = types.bool;
  default = false;
  description = "Enable new feature";
};
```

2. **Use the option** in config generation:

```qml
property bool newFeature: ${boolToString cfg.newFeature}
```

3. **Test the configuration**:

```bash
# Build and test
nix build .#homeConfigurations.declarative.activationPackage

# Apply changes
./result/activate

# Or use home-manager directly
home-manager switch
```

### Testing Changes Locally

For quick iteration without full rebuilds:

```bash
# 1. Enter dev shell
nix develop

# 2. Sync configs to runtime location (temporary)
rsync -av configs/quickshell/ii/ ~/.config/quickshell/ii/

# 3. Restart Quickshell
systemctl --user restart quickshell

# 4. Check logs
journalctl --user -u quickshell.service -f
```

### Using the VM Test for Validation

```bash
# Build and run the VM test (interactive)
nix run .#vm

# Run headless integration tests
nix flake check

# Or specifically the VM test
nix build .#checks.x86_64-linux.vm-integration
```

---

## Complete Configuration Examples

### Gaming Setup

Optimized for gaming performance:

```nix
{
  programs.dots-hyprland = {
    enable = true;
    source = inputs.dots-hyprland + "/configs";
    packageSet = "essential";
    mode = "hybrid";

    quickshell = {
      appearance.transparency = false;        # Disable transparency for performance
      bar.showBackground = false;             # Remove bar background
      bar.workspaces.shown = 3;               # Fewer workspace indicators

      bar.utilButtons = {
        showScreenSnip = true;
        showColorPicker = false;              # Not needed for gaming
        showMicToggle = false;
      };
    };

    hyprland = {
      general.allowTearing = true;            # Enable tearing for games
      decoration.blurEnabled = false;         # Disable blur for performance
      decoration.rounding = 0;                # Sharp corners
    };
  };
}
```

### Productivity Setup

Optimized for work and multitasking:

```nix
{
  programs.dots-hyprland = {
    enable = true;
    source = inputs.dots-hyprland + "/configs";
    packageSet = "essential";
    mode = "hybrid";

    quickshell = {
      bar.utilButtons = {
        showScreenSnip = true;
        showColorPicker = true;
        showMicToggle = true;                 # For voice dictation
        showKeyboardToggle = true;
        showDarkModeToggle = true;
      };

      bar.workspaces = {
        shown = 10;
        variant = "hefty";                    # Show app icons on workspaces
        showAppIcons = true;
      };

      time = {
        format = "HH:mm:ss";                  # 24-hour with seconds
        dateFormat = "dddd, MMMM dd, yyyy";   # Full date
      };
    };

    hyprland = {
      general.gapsIn = 2;                     # Smaller gaps for more screen space
      general.gapsOut = 4;
      decoration.rounding = 8;                # Subtle rounding
    };
  };
}
```

### Minimalist Setup

Clean, uncluttered interface:

```nix
{
  programs.dots-hyprland = {
    enable = true;
    source = inputs.dots-hyprland + "/configs";
    packageSet = "minimal";                 # Fewer packages
    mode = "declarative";                   # Fully managed by Nix

    quickshell = {
      bar.borderless = true;                  # No borders between sections
      bar.showBackground = false;             # Transparent bar
      bar.verbose = false;                    # Compact mode
      bar.workspaces.monochromeIcons = true;
      bar.workspaces.showAppIcons = false;

      appearance.transparency = true;         # Full transparency
    };

    hyprland = {
      decoration.rounding = 0;                # No rounding
      decoration.blurEnabled = false;         # No blur
    };
  };
}
```

### Multi-Monitor Setup

For users with multiple displays:

```nix
{
  programs.dots-hyprland = {
    enable = true;
    source = inputs.dots-hyprland + "/configs";
    packageSet = "essential";
    mode = "hybrid";

    hyprland.monitors = [
      "eDP-1,1920x1080@60,0x0,1.0"           # Laptop screen at 1x scale
      "HDMI-A-1,2560x1440@144,1920x0,1.5"    # External monitor at 1.5x scale (HiDPI)
      "DP-2,1920x1080@60,-1920x0,1.0"         # Second external monitor to the left
    ];

    quickshell = {
      notifications.forceMonitor = "HDMI-A-1";  # Show notifications on main monitor
    };
  };
}
```

### Touchpad-Only Setup (No Keyboard)

For users who prefer touchpad gestures:

```nix
{
  programs.dots-hyprland = {
    enable = true;
    source = inputs.dots-hyprland + "/configs";
    packageSet = "essential";
    mode = "hybrid";

    hyprland.gestures.workspaceSwipe = true;  # 3-finger swipe to change workspaces

    quickshell = {
      bar.workspaces.shown = 5;               # Fewer workspaces for touchpad navigation
      bar.utilButtons.showKeyboardToggle = false;  # No physical keyboard
    };
  };
}
```

---

## Option Reference Summary

### Quickshell Options Tree

```
programs.dots-hyprland.quickshell
├── appearance
│   ├── extraBackgroundTint: bool (default: true)
│   ├── fakeScreenRounding: enum [0,1,2] (default: 2)
│   ├── transparency: bool (default: false)
│   └── antiFlashbang: enum ["off","weak","strong"] (default: "off")
├── bar
│   ├── bottom: bool (default: false)
│   ├── cornerStyle: enum [0,1,2] (default: 0)
│   ├── borderless: bool (default: false)
│   ├── topLeftIcon: enum ["distro","spark"] (default: "spark")
│   ├── showBackground: bool (default: true)
│   ├── verbose: bool (default: true)
│   ├── utilButtons
│   │   ├── showScreenSnip: bool (default: true)
│   │   ├── showColorPicker: bool (default: false)
│   │   ├── showMicToggle: bool (default: false)
│   │   ├── showKeyboardToggle: bool (default: true)
│   │   ├── showDarkModeToggle: bool (default: true)
│   │   └── showPerformanceProfileToggle: bool (default: false)
│   └── workspaces
│       ├── variant: enum ["default","hefty"] (default: "default")
│       ├── monochromeIcons: bool (default: true)
│       ├── shown: int (default: 10)
│       ├── showAppIcons: bool (default: true)
│       ├── alwaysShowNumbers: bool (default: false)
│       └── showNumberDelay: int (default: 300)
├── battery
│   ├── low: int (default: 20)
│   ├── critical: int (default: 5)
│   ├── automaticSuspend: bool (default: true)
│   └── suspend: int (default: 3)
├── apps
│   ├── terminal: str (default: "foot")
│   ├── bluetooth: str (default: "kcmshell6 kcm_bluetooth")
│   ├── network: str (default: "plasmawindowed org.kde.plasma.networkmanagement")
│   ├── networkEthernet: str (default: "kcmshell6 kcm_networkmanagement")
│   └── taskManager: str (default: "plasma-systemmonitor --page-name Processes")
├── notifications
│   └── forceMonitor: nullOr str (default: null)
└── time
    ├── format: str (default: "hh:mm")
    └── dateFormat: str (default: "ddd, dd/MM")
```

### Hyprland Options Tree

```
programs.dots-hyprland.hyprland
├── general
│   ├── gapsIn: int (default: 4)
│   ├── gapsOut: int (default: 7)
│   ├── borderSize: int (default: 2)
│   └── allowTearing: bool (default: false)
├── decoration
│   ├── rounding: int (default: 16)
│   └── blurEnabled: bool (default: true)
├── gestures
│   └── workspaceSwipe: bool (default: true)
├── monitors: list of str (default: [])
├── night
│   └── colorTemperature: int (default: 4500)
└── keybinds
    └── darkLightToggle: bool (default: true)
```

### Terminal Options Tree

```
programs.dots-hyprland.terminal
├── scrollback
│   ├── lines: int (default: 1000)
│   └── multiplier: float (default: 3.0)
├── cursor
│   ├── style: str (default: "beam") [block, beam, underline]
│   ├── blink: bool (default: false)
│   └── beamThickness: float (default: 1.5)
├── colors
│   └── alpha: float (default: 0.95)
└── mouse
    ├── hideWhenTyping: bool (default: false)
    └── alternateScrollMode: bool (default: true)
```

---

## Benefits of This Approach

1. **Type Safety**: Nix validates your configuration at build time — invalid values are caught before deployment
2. **Documentation**: All options have built-in descriptions (run `nix show-config-doc` to view)
3. **Defaults**: Sensible defaults that work out of the box, easily overridden
4. **Reproducibility**: Same config = same result, every time
5. **Rollbacks**: Easy to revert changes via NixOS generations (`nix-env --rollback`)
6. **Modularity**: Mix and match configurations across different machines/users

---

## Related Documentation

- [`README.md`](./README.md) — Project overview and quick start
- [`CONFIGURATION_GUIDE.md`](./CONFIGURATION_GUIDE.md) — Static config file editing (for writable mode)
- [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) — System architecture and data flow
- [`docs/upstream-sync.md`](./docs/upstream-sync.md) — Upstream sync procedure
- [`docs/keybinds-reference.md`](./docs/keybinds-reference.md) — Complete keybind reference
- [`docs/hyprland-config-structure.md`](./docs/hyprland-config-structure.md) — Hyprland config file details
- [`docs/troubleshooting.md`](./docs/troubleshooting.md) — Common issues and fixes
