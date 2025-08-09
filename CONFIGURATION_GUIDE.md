# 🎯 dots-hyprland Static Configuration Guide

## 📍 Overview

Since you're using **declarative mode**, configuration files are read-only in the Nix store. To customize static values, modify the source files in your flake and rebuild.

## 🔧 Key Configuration Files

### 1. 📱 Quickshell Main Config
**File**: `configs/quickshell/ii/modules/common/Config.qml`

#### 🎨 Appearance Settings
```qml
property JsonObject appearance: JsonObject {
    property bool extraBackgroundTint: true
    property int fakeScreenRounding: 2 // 0: None | 1: Always | 2: When not fullscreen
    property bool transparency: false
    property JsonObject wallpaperTheming: JsonObject {
        property bool enableAppsAndShell: true
        property bool enableQtApps: true
        property bool enableTerminal: true
    }
}
```

#### 🖥️ Bar Configuration
```qml
property JsonObject bar: JsonObject {
    property bool bottom: false // Instead of top
    property int cornerStyle: 0 // 0: Hug | 1: Float | 2: Plain rectangle
    property bool borderless: false
    property string topLeftIcon: "spark" // Options: distro, spark
    property bool showBackground: true
    property bool verbose: true
    
    property JsonObject utilButtons: JsonObject {
        property bool showScreenSnip: true
        property bool showColorPicker: false
        property bool showMicToggle: false
        property bool showKeyboardToggle: true
        property bool showDarkModeToggle: true
        property bool showPerformanceProfileToggle: false
    }
    
    property JsonObject workspaces: JsonObject {
        property bool monochromeIcons: true
        property int shown: 10
        property bool showAppIcons: true
        property bool alwaysShowNumbers: false
        property int showNumberDelay: 300 // milliseconds
    }
}
```

#### 🔋 Battery Settings
```qml
property JsonObject battery: JsonObject {
    property int low: 20
    property int critical: 5
    property bool automaticSuspend: true
    property int suspend: 3
}
```

#### 🚀 Applications
```qml
property JsonObject apps: JsonObject {
    property string bluetooth: "kcmshell6 kcm_bluetooth"
    property string network: "plasmawindowed org.kde.plasma.networkmanagement"
    property string networkEthernet: "kcmshell6 kcm_networkmanagement"
    property string taskManager: "plasma-systemmonitor --page-name Processes"
    property string terminal: "kitty -1" // This is only for shell actions
}
```

#### ⏰ Time Format
```qml
property JsonObject time: JsonObject {
    property string format: "hh:mm"
    property string dateFormat: "ddd, dd/MM"
}
```

### 2. 🖼️ Hyprland Configuration
**File**: `configs/hypr/general.conf.template`

#### 🎨 Visual Settings
```conf
general {
    gaps_in = @GAPS_IN@           # Inner gaps (default: 4)
    gaps_out = @GAPS_OUT@         # Outer gaps (default: 7)
    gaps_workspaces = 50          # Workspace gaps
    
    border_size = @BORDER_SIZE@   # Border width (default: 2)
    resize_on_border = true
    
    allow_tearing = @ALLOW_TEARING@  # For gaming
}

decoration {
    rounding = @ROUNDING@         # Corner rounding (default: 16)
    
    blur {
        enabled = @BLUR_ENABLED@  # Background blur
        xray = true
    }
}
```

### 3. 🖥️ Terminal Configuration
**File**: `configs/applications/foot.ini.template`

#### 📝 Terminal Settings
```ini
[main]
term=xterm-256color
login-shell=yes
app-id=foot
title=foot

[scrollback]
lines=1000                    # Scrollback buffer size
multiplier=3.0

[cursor]
style=beam                    # Options: block, beam, underline
blink=no
beam-thickness=1.5

[colors]
alpha=0.95                    # Terminal transparency
```

### 4. 🎯 Fuzzel Launcher
**File**: `configs/matugen/templates/fuzzel/fuzzel_theme.ini`

#### 🚀 Launcher Settings
```ini
[main]
terminal=foot
layer=overlay
width=40
horizontal-pad=40
vertical-pad=8
inner-pad=5
```

## 🔄 How to Apply Changes

### Method 1: Edit and Rebuild
1. **Edit** the configuration files in `~/sources/celesrenata/end-4-flakes/configs/`
2. **Commit** your changes: `git add . && git commit -m "Update static config"`
3. **Rebuild**: `nix build .#homeConfigurations.declarative.activationPackage`
4. **Activate**: `./result/activate`

### Method 2: Switch to Writable Mode
If you want to edit configs directly without rebuilding:

```bash
# Build writable configuration
nix build .#homeConfigurations.writable.activationPackage
./result/activate

# Run setup script
~/.local/bin/initialSetup.sh

# Edit configs directly in ~/.config/
```

## 🎨 Common Customizations

### Change Terminal to Kitty
In `configs/quickshell/ii/modules/common/Config.qml`:
```qml
property string terminal: "kitty -1"
```

### Move Bar to Bottom
```qml
property bool bottom: true
```

### Disable Transparency
```qml
property bool transparency: false
```

### Change Time Format to 12-hour
```qml
property string format: "hh:mm AP"
```

### Increase Terminal Scrollback
In `configs/applications/foot.ini.template`:
```ini
[scrollback]
lines=10000
```

### Change Workspace Count
```qml
property int shown: 5  // Show only 5 workspaces
```

## 🔍 Finding More Options

- **Quickshell Config**: `configs/quickshell/ii/modules/common/Config.qml` (lines 1-300)
- **Hyprland Settings**: `configs/hypr/*.conf.template` files
- **Application Configs**: `configs/applications/` directory
- **Theming Templates**: `configs/matugen/templates/` directory

## 💡 Pro Tips

1. **Search for specific settings**: `grep -r "property.*terminal" configs/`
2. **Check template variables**: Look for `@VARIABLE@` patterns in `.template` files
3. **Test changes**: Use writable mode for quick testing, then apply to declarative mode
4. **Backup configs**: Git tracks all changes, so you can always revert

## 🚀 Quick Start Examples

### Minimal Gaming Setup
```qml
// In Config.qml
property bool transparency: false
property bool showBackground: false
property int shown: 3  // Only 3 workspaces
```

### Productivity Setup
```qml
// In Config.qml
property bool showScreenSnip: true
property bool showColorPicker: true
property string format: "HH:mm:ss"
property string dateFormat: "dddd, MMMM dd, yyyy"
```

### Minimalist Setup
```qml
// In Config.qml
property bool borderless: true
property bool showBackground: false
property bool monochromeIcons: true
property bool verbose: false
```
