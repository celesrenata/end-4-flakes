# dots-hyprland for NixOS (Self-Contained)

A complete, self-contained NixOS adaptation of [end-4's dots-hyprland](https://github.com/end-4/dots-hyprland) desktop environment, bringing the beautiful "illogical-impulse" style to NixOS with full declarative configuration.

## 🎯 Project Status: Self-Contained & Complete ✅

**Current Achievement: Fully Self-Contained Desktop Environment**

- ✅ **Self-Contained**: All configurations included locally (no external dependencies)
- ✅ **Quickshell Integration** - Official flake support with local configs
- ✅ **Hyprland Configuration** - Complete window manager setup with Material You theming
- ✅ **Essential Applications** - foot terminal, fuzzel launcher, nautilus file manager
- ✅ **Home Manager Integration** - Fully declarative configuration
- ✅ **Package Management** - All dependencies properly integrated
- ✅ **Development Environment** - Ready for advanced features

## 🚀 Quick Start

### Prerequisites
- NixOS with flakes enabled
- Home Manager (optional but recommended)

### Installation

```bash
# Clone the repository
git clone git@github.com:celesrenata/end-4-flakes.git
cd end-4-flakes

# Build and activate Home Manager configuration
nix build .#homeConfigurations.declarative.activationPackage
./result/activate

# Or use with your existing Home Manager setup
# Add to your flake inputs:
# dots-hyprland.url = "github:celesrenata/end-4-flakes";
```

### Development

```bash
# Enter development environment
nix develop

# Available development tools:
# - update-flake: Manage flake inputs
# - compare-modes: Compare declarative vs writable configuration modes
# - test-python-env: Test Python virtual environment setup
# - test-quickshell: Test quickshell configuration

# Flake management examples:
update-flake status           # Show current flake status
update-flake update           # Update all flake inputs
update-flake verify           # Test that configurations build
update-flake help             # Show all available options
```

## 📋 Features

### ✅ Implemented (Phase 3)
- **Hyprland Window Manager** - Complete configuration with Material You theming
- **foot Terminal** - Tokyo Night color scheme, JetBrainsMono Nerd Font
- **fuzzel Launcher** - Material You themed application launcher
- **Essential Keybinds** - All core window management and application shortcuts
- **Package Integration** - Declarative package management through Nix
- **Home Manager Support** - Full integration with Home Manager modules

### 🔄 In Progress (Phase 4)
- **AI Integration** - Gemini and Ollama support
- **Advanced Widgets** - Overview with live previews, sidebars
- **Comprehensive Theming** - Dynamic Material You color generation
- **Quality of Life** - Screen corners, session management, cheatsheet

### 📅 Planned (Future Phases)
- **NixOS System Integration** - Full system-level configuration
- **Testing & Validation** - Comprehensive test suite
- **Community & Maintenance** - Documentation, contribution guidelines

## 🔄 Flake Management

The project includes a comprehensive flake management utility for keeping your configuration synchronized with GitHub:

### Quick Commands

```bash
# Check current status
update-flake status

# Update all flake inputs
update-flake update

# Update only dots-hyprland source
update-flake update-source

# Verify configurations build
update-flake verify

# Update and verify in one command
update-flake update --auto-verify
```

### Advanced Usage

```bash
# Pin to a specific commit
update-flake pin abc123def

# Switch to tracking a different branch
update-flake branch main

# Dry run to see what would happen
update-flake update --dry-run
```

The utility automatically detects synchronization status and provides clear feedback about your flake's relationship to the GitHub repository.

## 🎨 Configuration

### Basic Configuration

```nix
{
  programs.dots-hyprland = {
    enable = true;
    style = "illogical-impulse";
    
    components = {
      hyprland = true;
      quickshell = true;
      theming = false;  # Phase 4
      ai = false;       # Phase 4
      audio = true;
    };
    
    features = {
      overview = true;
      sidebar = false;  # Phase 4
      notifications = true;
      mediaControls = true;
    };
    
    keybinds = {
      modifier = "SUPER";
      terminal = "foot";
    };
  };
}
```

### Keybinds

| Key Combination | Action |
|----------------|--------|
| `SUPER + Return` | Open terminal |
| `SUPER + Space` | Open application launcher |
| `SUPER + Q` | Close window |
| `SUPER + E` | Open file manager |
| `SUPER + F` | Toggle fullscreen |
| `SUPER + V` | Toggle floating |
| `SUPER + 1-0` | Switch to workspace |
| `SUPER + Shift + 1-0` | Move window to workspace |

## 🏗️ Architecture

### Self-Contained Structure
```
├── flake.nix                 # Main flake definition (clean & minimal)
├── flake.lock                # Locked dependencies
├── configs/                  # All dots-hyprland configurations
│   ├── hypr/                 # Hyprland configuration
│   ├── quickshell/           # Quickshell widgets and config
│   ├── applications/         # Application configurations
│   ├── scripts/              # Utility scripts
│   └── matugen/              # Material You theming
├── modules/                  # NixOS/Home Manager modules
│   ├── home-manager.nix      # Main Home Manager integration
│   ├── python-environment.nix # Python venv setup
│   ├── configuration.nix     # Declarative config management
│   ├── writable-mode.nix     # Writable mode setup
│   └── components/           # Component modules
└── packages/                 # Utility packages and scripts
    ├── default.nix           # Package definitions
    ├── dots-hyprland-packages.nix # Package mappings
    └── scripts/              # Development utilities
```

### Key Benefits
- **🔒 Self-Contained**: No external repository dependencies
- **📦 Version Controlled**: All configs tracked in single repository
- **🔧 Maintainable**: Clean separation of concerns
- **🚀 Fast**: No network dependencies during build
- **🎯 Focused**: Only essential files included

## 🎯 Gameplan Progress

This project follows a systematic 7-phase development approach:

- [x] **Phase 1: Dependency Analysis** - All dependencies mapped to NixOS
- [x] **Phase 2: Module Structure** - Complete flake and module architecture
- [x] **Phase 3: Core Implementation** - ✅ **CURRENT MILESTONE**
- [ ] **Phase 4: Advanced Features** - AI, advanced widgets, comprehensive theming
- [ ] **Phase 5: NixOS Adaptations** - Full NixOS integration patterns
- [ ] **Phase 6: Testing & Validation** - Comprehensive testing suite
- [ ] **Phase 7: Community & Maintenance** - Documentation, contribution guidelines

## 🤝 Contributing

This project is in active development. Contributions are welcome!

### Development Setup
1. Clone the repository
2. Run `nix develop` to enter the development environment
3. Make your changes
4. Test with `nix build .#homeConfigurations.example.activationPackage`
5. Submit a pull request

## 📄 License

This project is licensed under the GPL-3.0 License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **end-4** - Original dots-hyprland creator
- **outfoxxed** - Quickshell developer (official Nix flake support was crucial!)
- **NixOS Community** - For the amazing ecosystem
- **Hyprland Team** - For the fantastic window manager

## 📞 Support

- **Issues**: Report bugs and request features via GitHub Issues
- **Discussions**: General questions and ideas via GitHub Discussions
- **Community**: Join the NixOS and Hyprland communities for broader support

---

**Status**: Phase 3 Complete - Core desktop environment functional and ready for advanced features! 🚀
