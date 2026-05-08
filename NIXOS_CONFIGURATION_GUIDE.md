# 🎯 NixOS Configuration Guide for dots-hyprland

## 📍 The NixOS Way

In NixOS, you **don't edit configuration files directly**. Instead, you configure everything through **Nix expressions** that generate the configuration files.

## 🔧 Current State vs Ideal State

### ❌ Current State (Basic)
The current module only exposes basic options:
```nix
programs.dots-hyprland = {
  enable = true;
  source = ./configs;
  packageSet = "essential";
  mode = "declarative";
};
```

### ✅ Ideal State (Rich Configuration)
What we're building - full NixOS-style configuration:
```nix
programs.dots-hyprland = {
  enable = true;
  source = ./configs;
  packageSet = "essential";
  mode = "declarative";
  
  # Quickshell configuration
  quickshell = {
    bar = {
      bottom = false;
      topLeftIcon = "spark";
      utilButtons = {
        showColorPicker = true;
        showScreenSnip = true;
        showMicToggle = false;
      };
      workspaces = {
        shown = 10;
        showAppIcons = true;
      };
    };
    
    battery = {
      low = 20;
      critical = 5;
    };
    
    apps = {
      terminal = "foot";
    };
    
    time = {
      format = "hh:mm";
      dateFormat = "ddd, dd/MM";
    };
  };
  
  # Hyprland configuration
  hyprland = {
    general = {
      gapsIn = 4;
      gapsOut = 7;
      borderSize = 2;
    };
    
    decoration = {
      rounding = 16;
      blurEnabled = true;
    };
    
    monitors = [
      "eDP-1,1920x1080@60,0x0,1"
    ];
  };
};
```

## 🚀 How to Configure (The NixOS Way)

### Method 1: In Your Flake Configuration
Edit your flake.nix homeConfigurations:

```nix
homeConfigurations.declarative = home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  modules = [
    self.homeManagerModules.default
    {
      home.username = "celes";
      home.homeDirectory = "/home/celes";
      home.stateVersion = "24.05";
      
      programs.dots-hyprland = {
        enable = true;
        source = ./configs;
        packageSet = "essential";
        mode = "declarative";
        
        # Your custom configuration here
        quickshell.bar.utilButtons.showColorPicker = true;
        quickshell.apps.terminal = "foot";
        hyprland.general.gapsIn = 6;
      };
    }
  ];
};
```

### Method 2: Separate Configuration File
Create `config/my-dots-config.nix`:

```nix
{ config, lib, pkgs, ... }:

{
  programs.dots-hyprland = {
    enable = true;
    source = ./configs;
    packageSet = "essential";
    mode = "declarative";
    
    quickshell = {
      appearance = {
        transparency = true;
        fakeScreenRounding = 1;
      };
      
      bar = {
        bottom = true;  # Move bar to bottom
        topLeftIcon = "distro";
        cornerStyle = 1;  # Float style
        
        utilButtons = {
          showColorPicker = true;
          showScreenSnip = true;
          showMicToggle = true;
          showDarkModeToggle = true;
        };
        
        workspaces = {
          shown = 5;  # Only show 5 workspaces
          monochromeIcons = false;
          alwaysShowNumbers = true;
        };
      };
      
      battery = {
        low = 25;
        critical = 10;
        automaticSuspend = false;
      };
      
      apps = {
        terminal = "foot";
        taskManager = "htop";
      };
      
      time = {
        format = "HH:mm:ss";  # 24-hour with seconds
        dateFormat = "dddd, MMMM dd, yyyy";
      };
    };
    
    hyprland = {
      general = {
        gapsIn = 6;
        gapsOut = 10;
        borderSize = 3;
        allowTearing = true;  # For gaming
      };
      
      decoration = {
        rounding = 12;
        blurEnabled = false;  # Disable for performance
      };
      
      gestures = {
        workspaceSwipe = true;
      };
      
      monitors = [
        "eDP-1,1920x1080@60,0x0,1"
        "HDMI-A-1,1920x1080@60,1920x0,1"
      ];
    };
  };
}
```

Then import it in your flake:
```nix
modules = [
  self.homeManagerModules.default
  ./config/my-dots-config.nix
  {
    home.username = "celes";
    home.homeDirectory = "/home/celes";
    home.stateVersion = "24.05";
  }
];
```

## 🔄 Development Workflow

### 1. Add New Configuration Options
Edit `modules/components/quickshell-config.nix` to add new options:

```nix
newFeature = mkOption {
  type = types.bool;
  default = false;
  description = "Enable new feature";
};
```

### 2. Update Configuration Generation
Update the config generation to use the new option:

```nix
property bool newFeature: ${boolToString cfg.newFeature}
```

### 3. Test and Apply
```bash
# Test the configuration
nix build .#homeConfigurations.declarative.activationPackage

# Apply changes
./result/activate
```

## 🎨 Common Configuration Examples

### Gaming Setup
```nix
programs.dots-hyprland = {
  quickshell = {
    appearance.transparency = false;
    bar = {
      showBackground = false;
      workspaces.shown = 3;
    };
  };
  
  hyprland = {
    general.allowTearing = true;
    decoration.blurEnabled = false;
  };
};
```

### Productivity Setup
```nix
programs.dots-hyprland = {
  quickshell = {
    bar = {
      utilButtons = {
        showScreenSnip = true;
        showColorPicker = true;
      };
      workspaces.shown = 10;
    };
    
    time = {
      format = "HH:mm:ss";
      dateFormat = "dddd, MMMM dd, yyyy";
    };
  };
  
  hyprland = {
    general = {
      gapsIn = 2;
      gapsOut = 4;
    };
  };
};
```

### Minimalist Setup
```nix
programs.dots-hyprland = {
  quickshell = {
    bar = {
      borderless = true;
      showBackground = false;
      verbose = false;
      workspaces = {
        monochromeIcons = true;
        showAppIcons = false;
      };
    };
  };
  
  hyprland = {
    decoration.rounding = 0;
  };
};
```

## 🔍 Available Options

### Quickshell Options
- `appearance.*` - Visual appearance settings
- `bar.*` - Top bar configuration
- `battery.*` - Battery management
- `apps.*` - Application commands
- `time.*` - Time and date formatting

### Hyprland Options
- `general.*` - Window gaps, borders, tearing
- `decoration.*` - Rounding, blur, shadows
- `gestures.*` - Touchpad gestures
- `monitors` - Monitor configuration

## 💡 Benefits of This Approach

1. **Type Safety**: Nix validates your configuration
2. **Documentation**: Built-in option descriptions
3. **Defaults**: Sensible defaults with easy overrides
4. **Reproducibility**: Same config = same result
5. **Rollbacks**: Easy to revert changes
6. **Modularity**: Mix and match configurations

## 🚧 Current Status

The rich configuration system is **partially implemented**. The basic structure is there, but we need to:

1. ✅ Create option definitions (done above)
2. ⏳ Wire up the option values to config generation
3. ⏳ Test all options work correctly
4. ⏳ Add more granular options

## 🎯 Next Steps

1. **Test the new modules**: Add them to your flake and test
2. **Expand options**: Add more configuration options as needed
3. **Generate configs**: Wire up the options to actual config file generation
4. **Document**: Add examples and documentation

This is the **proper NixOS way** - declarative, type-safe, and reproducible! 🎉
