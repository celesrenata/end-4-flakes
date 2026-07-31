# end-4-flakes — NixOS Flakes for dots-hyprland with AI & Theming Extensions

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](LICENSE)
[![NixOS](https://img.shields.io/badge/NixOS-flake-orange)](https://nixos.org/)
[![Hyprland](https://img.shields.io/badge/Hyprland-wayland-purple)](https://hyprland.org/)

NixOS flake packaging for [end-4's dots-hyprland](https://github.com/end-4/dots-hyprland), with heavy modifications to theming and the addition of a full AI/voice assistant layer. This wraps the upstream "illogical-impulse" Quickshell desktop into declarative Nix modules and extends it with streaming voice dictation, an AI action palette, vision analysis, multi-provider model discovery, an MCP server for desktop control, and deep Material You theming integration.

**Target platform:** Baremetal NixOS (x86_64-linux, aarch64-linux). No VM, container, or T2/Mac support.

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [**NIXOS_CONFIGURATION_GUIDE.md**](./NIXOS_CONFIGURATION_GUIDE.md) | Complete Home Manager option reference with examples |
| [**CONFIGURATION_GUIDE.md**](./CONFIGURATION_GUIDE.md) | Direct config file editing guide (writable mode) |
| [**docs/ARCHITECTURE.md**](./docs/ARCHITECTURE.md) | System architecture, data flow, and component diagram |
| [**docs/upstream-quickshell-architecture.md**](./docs/upstream-quickshell-architecture.md) | Detailed Quickshell QML module structure |
| [**docs/keybinds-reference.md**](./docs/keybinds-reference.md) | Complete keybind reference (both repos) |
| [**docs/hyprland-config-structure.md**](./docs/hyprland-config-structure.md) | Hyprland config file organization and format |
| [**docs/python-environment-and-voice-assistant.md**](./docs/python-environment-and-voice-assistant.md) | Python venv, voice assistant, and AI architecture |
| [**docs/troubleshooting.md**](./docs/troubleshooting.md) | Common issues and fixes |
| [**docs/upstream-sync.md**](./docs/upstream-sync.md) | Upstream sync procedure and verification |

---

## 🚀 Quick Start

### Prerequisites

- **NixOS** (baremetal) with flakes enabled (`experimental-features = nix-command flakes` in `/etc/nix/nix.conf`)
- **Home Manager** integrated into system flake (not standalone)
- **Hyprland** compositor installed: `programs.hyprland.enable = true;`
- **PipeWire** audio: `services.pipewire.enable = true;`

### Add to Your Flake

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
            packageSet = "essential";  # minimal | essential | all
            mode = "hybrid";           # hybrid | declarative | writable

            quickshell = {
              appearance.transparency = false;
              bar.workspaces.shown = 10;
              bar.workspaces.variant = "hefty";
            };

            hyprland = {
              general.gapsIn = 4;
              general.gapsOut = 7;
              decoration.rounding = 16;
              decoration.blurEnabled = true;
              night.colorTemperature = 4500;
            };
          };
        }
      ];
    };
  };
}
```

### Apply Configuration

```bash
# For Home Manager only:
home-manager switch

# For full NixOS system:
nixos-rebuild switch
```

---

## ✨ Features

### 🎨 Theming & Appearance

Deep Material You integration driven by wallpaper images:

- **Material You color pipeline** — Wallpaper → matugen generates palette → applied to terminal, launcher, Hyprland borders, Qt apps
- **Dark/Light mode** — `Ctrl+Super+Shift+D` toggles instantly with automatic wallpaper variant detection
- **Terminal theming** — foot.ini auto-generated from wallpaper colors (16-color palette + opacity)
- **Anti-flashbang overlays** — Configurable during workspace transitions (off/weak/strong)
- **Bar styles** — Top/bottom placement, corner styles, verbose/compact modes
- **Screen corners** — Per-monitor decorative rounded corners

See [NIXOS_CONFIGURATION_GUIDE.md](./NIXOS_CONFIGURATION_GUIDE.md#quickshell-options-reference) for all appearance options.

### 🤖 AI & Voice Assistant

Complete voice assistant and AI integration layer:

- **Multi-provider LLM support** — 7 providers (OpenAI, Anthropic, Gemini, Mistral, OpenRouter, AWS Bedrock, Ollama) + custom endpoints
- **Streaming dictation** — Real-time transcription via WebSocket or chunked HTTP with graceful fallback
- **Bidirectional voice agent** — Full duplex conversations via Amazon Nova Sonic or OpenAI Realtime API
- **Text-to-Speech** — Piper (local), espeak-ng, Coqui, Mimic3, or OpenAI TTS
- **AI Action Palette** — Type `?` in launcher for natural language → structured desktop actions
- **Context Lens** — `Super+Shift+A` captures screen region for AI vision analysis
- **HyprMCP server** — Model Context Protocol for programmatic desktop control

See [docs/python-environment-and-voice-assistant.md](./docs/python-environment-and-voice-assistant.md) for architecture details.

### 🖥️ Desktop Environment

Full-featured Quickshell desktop with:

- **Status bar** — Resource monitors, media controls, workspace indicators, system tray
- **Sidebars** — Left (AI chat, providers, translator, anime), Right (toggles, notifications, volume mixer)
- **Overview/Launcher** — Multi-mode search (apps, math, commands, web, clipboard, emoji, AI actions)
- **Cheatsheet** — `Super+/` shows all keybinds organized by section
- **On-screen keyboard** — QWERTY full layout, pinnable
- **Session menu** — Shutdown, reboot, suspend, lock (hyprlock)
- **Dock** — Auto-hide with pinned apps and hover-to-reveal

See [docs/keybinds-reference.md](./docs/keybinds-reference.md) for complete keybind reference.

### 🔧 NixOS Integration

Everything declared in Nix:

- **Three deployment modes** — `hybrid` (recommended), `declarative`, `writable`
- **Rich Home Manager options** — Type-safe configuration for all aspects
- **Template system** — `.conf.template` files with `@VARIABLE@` placeholders resolved at build time
- **Python venv management** — Declarative dependency management via [`modules/python-environment.nix`](./modules/python-environment.nix)
- **Systemd services** — Quickshell managed by Home Manager with security sandboxing
- **Config override system** — Complete file-level or directory-level overrides

See [NIXOS_CONFIGURATION_GUIDE.md](./NIXOS_CONFIGURATION_GUIDE.md) for full option reference.

---

## 📁 Repository Structure

```
end-4-flakes/
├── configs/                          # Configuration templates and runtime files
│   ├── hypr/                         # Hyprland .conf.template files
│   │   ├── hyprland.conf.template    # Entry point (sources all others)
│   │   ├── general.conf.template     # Layout, decoration, animations, input
│   │   ├── keybinds.conf.template    # ~145 keybinds with @BIN@ paths
│   │   ├── rules.conf.template       # Window/layer/workspace rules
│   │   ├── colors.conf.template      # Material You border/plugin colors
│   │   ├── env.conf.template         # Environment variables
│   │   ├── execs.conf.template       # Autostart programs
│   │   ├── hypridle.conf.template    # Idle/power cascade
│   │   └── scripts/                  # workspace_action.sh, launch_first_available.sh
│   │
│   ├── quickshell/ii/                # Quickshell QML desktop environment
│   │   ├── services/                 # 41 singleton services (AI, voice, audio, etc.)
│   │   ├── modules/                  # UI components (bar, sidebars, launcher, etc.)
│   │   │   ├── bar/                  # Status bar with resources, media, workspaces
│   │   │   ├── sidebarLeft/          # AI chat, providers, translator, anime
│   │   │   ├── sidebarRight/         # Toggles, notifications, volume, calendar
│   │   │   ├── overview/             # Launcher + multi-mode search
│   │   │   ├── common/               # Config.qml, Persistent.qml, widgets
│   │   │   └── ...                   # cheatsheet, dock, osk, session, etc.
│   │   └── scripts/                  # Voice agent, dictation, color generation
│   │       ├── voice-agent-stream.py     # Bidirectional voice (Nova Sonic / OpenAI)
│   │       ├── dictation-stream.py       # Streaming/chunked STT helper
│   │       ├── colors/                   # switchwall, generate_colors_material.py
│   │       └── voice_agent_backends/     # Backend implementations + tool manager
│   │
│   ├── applications/                 # foot.ini.template (Material You terminal colors)
│   ├── matugen/templates/            # Color templates: foot, fuzzel, gtk, hyprland, kde
│   └── scripts/                      # generate-colors.sh, record.sh, zoom.sh
│
├── modules/                          # Home Manager and NixOS modules
│   ├── home-manager.nix              # Main HM module (mode, packages, activation)
│   ├── configuration.nix             # File copying + custom config placeholders
│   ├── python-environment.nix        # Python venv (materialyoucolor, pywayland, boto3)
│   ├── writable-mode.nix             # Staging + setup script for editable mode
│   └── components/                   # Configuration generation modules
│       ├── quickshell-config.nix     # Generates Config.qml from Nix options
│       ├── quickshell-service.nix    # systemd service + voice-agent wrapper + PATH
│       ├── hyprland-config.nix       # Generates general.conf from Nix options
│       ├── terminal-config.nix       # foot terminal options
│       ├── touchegg.nix              # Touchpad gesture definitions
│       ├── config-override.nix       # Escape hatch: complete file/directory overrides
│       └── system-services.nix       # NixOS-level: UPower for battery
│
├── packages/                         # Package sets and utility scripts
│   ├── default.nix                   # Utility scripts (update-flake, generate-qmldir, etc.)
│   ├── dots-hyprland-packages.nix    # Package sets (minimal/essential/all)
│   └── scripts/                      # Development and maintenance scripts
│       ├── compare-modes.sh          # Compare deployment modes
│       ├── dev-shell-hook.sh         # Dev shell initialization
│       ├── generate-qmldir.sh        # QML directory generator for quickshell
│       ├── quickshell-reset.sh       # Reset Quickshell state
│       ├── test-python-env.sh        # Test Python venv setup
│       ├── test-quickshell.sh        # Test Quickshell startup
│       └── update-flake.sh           # Update flake inputs
│
├── tests/                            # Test suites
│   ├── vm-test.nix                   # NixOS VM integration test
│   ├── *.py                          # 34 Python test files (Hypothesis property-based)
│   └── js/                           # Quickshell UI logic tests (Vitest)
│       ├── package.json
│       ├── vitest.config.js
│       └── src/                      # Test source files
│
├── docs/                             # Detailed documentation
│   ├── ARCHITECTURE.md               # System architecture and data flow
│   ├── upstream-sync.md              # Upstream sync procedure
│   ├── upstream-quickshell-architecture.md  # Quickshell QML structure
│   ├── keybinds-reference.md         # Complete keybind reference
│   ├── hyprland-config-structure.md  # Hyprland config file details
│   ├── python-environment-and-voice-assistant.md  # Python venv and voice assistant
│   └── troubleshooting.md            # Common issues and fixes
│
├── examples/                         # Example configurations
│   ├── gaming-config.nix             # Gaming-optimized setup
│   ├── minimalist-config.nix         # Minimal package set
│   └── productivity-config.nix       # Productivity-focused configuration
│
├── flake.nix                         # Flake definition (overlays, HM modules, dev shells)
├── flake.lock                        # Pinned flake inputs
├── NIXOS_CONFIGURATION_GUIDE.md      # Home Manager option reference
├── CONFIGURATION_GUIDE.md            # Static config file editing guide
└── README.md                         # This file

Deployment chain:
  end-4-flakes → pushed to GitHub
    → nix flake update dots-hyprland (pins commit in system flake's flake.lock)
    → overlay patches quickshell + kde-material-you-colors
    → programs.dots-hyprland module processes templates, generates configs
    → nixos-rebuild switch deploys everything atomically
    → systemd user service starts quickshell with full PATH/env
    → ~/.config/quickshell/ii/ is the live runtime config
    → ~/.config/hypr/ contains resolved Hyprland configs
```

---

## 🏗️ Architecture Overview

The system consists of three main layers:

1. **Nix Module System** — Home Manager modules generate configuration files from Nix options
2. **Template System** — `.conf.template` and QML files with `@VARIABLE@` placeholders resolved at build time
3. **Runtime Deployment** — systemd services, Python venv, and Hyprland/Quickshell processes

See [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) for detailed architecture diagrams and data flow.

### Key Components

| Component | Purpose | Location |
|-----------|---------|----------|
| **Home Manager Module** | Generates configs from Nix options | [`modules/home-manager.nix`](./modules/home-manager.nix) |
| **Quickshell Config Generator** | Creates `Config.qml` from Nix options | [`modules/components/quickshell-config.nix`](./modules/components/quickshell-config.nix) |
| **Hyprland Config Generator** | Creates `general.conf` from Nix options | [`modules/components/hyprland-config.nix`](./modules/components/hyprland-config.nix) |
| **Python Environment Manager** | Manages venv with Material You deps | [`modules/python-environment.nix`](./modules/python-environment.nix) |
| **Quickshell Service** | systemd user service with security sandboxing | [`modules/components/quickshell-service.nix`](./modules/components/quickshell-service.nix) |
| **Package Set Manager** | Defines minimal/essential/all package sets | [`packages/dots-hyprland-packages.nix`](./packages/dots-hyprland-packages.nix) |

---

## 🧪 Testing

### Python Tests (Hypothesis Property-Based)

34 test files covering template placeholders, wallpaper variants, keybind injection, voice assistant intent classification, streaming protocol, capability detection, tool call pairing, demo driver orchestration, audio pipeline, credential handling, and policy enforcement.

```bash
cd tests && python -m pytest
```

### NixOS VM Integration Test

Full integration test verifying config generation, placeholder resolution, systemd service creation, session variables, and package availability.

```bash
# Interactive VM (requires KVM)
nix run .#vm

# Headless check
nix flake check
```

### JavaScript Tests (Vitest)

Quickshell UI logic tests covering action palette, chat sessions, dictation, model discovery, and voice sidebar.

```bash
cd tests/js && npm test
```

---

## 🔄 Upstream Sync

This flake wraps [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland). Periodic syncs bring in upstream changes while maintaining NixOS adaptations.

**Current sync:** August 2025 → July 2026 (ongoing)
**Branch:** `upstream-sync-2026`

See [docs/upstream-sync.md](./docs/upstream-sync.md) for detailed sync procedure and verification checklist.

### Key Differences from Upstream

| Aspect | Upstream (Lua) | NixOS Fork (.conf.template) |
|--------|----------------|----------------------------|
| Keybinds format | `hl.bind("KEY", function() ... end)` | `bind = Key, Modifier, dispatcher, args` |
| Variables | Lua `variables.lua` | `@VARIABLE@` placeholders |
| AI providers | Gemini + Ollama only | 7 providers + custom endpoints |
| Voice assistant | Not included | Streaming dictation + bidirectional agent |
| MCP server | Not included | Full desktop intelligence via HyprMCP |
| Deployment | Imperative install.sh | Declarative Nix modules |

---

## 🛠️ Development

### Enter Dev Shell

```bash
git clone git@github.com:celesrenata/end-4-flakes.git
cd end-4-flakes
nix develop
```

The dev shell provides: `nixpkgs-fmt`, `nil`, `git`, `jq`, and utility scripts (`update-flake`, `test-python-env`, etc.).

### Test Changes Locally

```bash
# Sync configs to runtime location (temporary, wiped on rebuild)
rsync -av configs/quickshell/ii/ ~/.config/quickshell/ii/

# Restart Quickshell
systemctl --user restart quickshell

# Check logs
journalctl --user -u quickshell.service -f
```

### Run Tests

```bash
# Python tests
cd tests && python -m pytest

# JS tests
cd tests/js && npm test

# VM integration test
nix build .#checks.x86_64-linux.vm-integration
```

---

## 📖 Configuration Examples

See [`examples/`](./examples/) for complete configuration examples:

- [**gaming-config.nix**](./examples/gaming-config.nix) — Optimized for gaming performance
- [**minimalist-config.nix**](./examples/minimalist-config.nix) — Minimal package set and clean UI
- [**productivity-config.nix**](./examples/productivity-config.nix) — Productivity-focused with all features

---

## 🙏 Credits

- **[end-4](https://github.com/end-4)** — Original dots-hyprland and the illogical-impulse aesthetic
- **[outfoxxed](https://github.com/outfoxxed)** — Quickshell framework
- **[Hyprland team](https://hyprland.org/)** — The compositor
- **NixOS community** — The ecosystem

---

## 📄 License

GPL-3.0 — See [LICENSE](./LICENSE) for details.

---

## 🔗 Related Projects

- [**dots-hyprland**](https://github.com/end-4/dots-hyprland) — Upstream Hyprland dotfiles by end-4
- [**Quickshell**](https://quickshell.outfoxxed.me/) — QtQuick-based widget system by outfoxxed
- [**Hyprland**](https://hyprland.org/) — Dynamic tiling Wayland compositor
- [**NixOS**](https://nixos.org/) — The purely functional distribution
