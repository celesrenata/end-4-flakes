# Architecture Overview

## System Design

This project implements a declarative NixOS desktop environment using:
- **Hyprland** as the Wayland compositor
- **Quickshell** for the UI layer (bar, sidebar, launcher)
- **NixOS modules** for configuration management
- **Material You theming** via matugen and kde-material-you-colors

## Component Layers

```mermaid
graph TD
    A["User Configuration\nflake.nix → programs.dots-hyprland options"] --> B["Nix Module System\nmodules/home-manager.nix + components/"]
    B --> C["Config Generation\n.conf.template @VARIABLE@ substitution\nConfig.qml from Nix options"]
    C --> D["Runtime Deployment\n~/.config/hypr/\n~/.config/quickshell/ii/\nsystemd user services"]

    style A fill:#4f378b,stroke:#3e2723,color:#fff
    style B fill:#5c6bc0,stroke:#1a237e,color:#fff
    style C fill:#26a69a,stroke:#004d40,color:#fff
    style D fill:#ef6c00,stroke:#bf360c,color:#fff
```

## Data Flow

### Configuration Path

1. **User writes Nix options** in their flake:
   ```nix
   programs.dots-hyprland = {
     enable = true;
     quickshell.bar.bottom = false;
     hyprland.general.gapsIn = 4;
   };
   ```

2. **Home Manager module processes options**:
   - `modules/home-manager.nix` collects all component modules
   - Each component module (e.g., `quickshell-config.nix`) generates config files from Nix options

3. **Template substitution** at build time:
   - `.conf.template` files have `@VARIABLE@` placeholders
   - Nix substitutes these with actual values (binary paths, config content)

4. **Files deployed to user home**:
   - Hyprland configs → `~/.config/hypr/`
   - Quickshell QML → `~/.config/quickshell/ii/`
   - Terminal configs → `~/.config/foot/`

### Theming Pipeline

```mermaid
flowchart TD
    W["Wallpaper Image\n(~/.config/quickshell/user/wallpaper.jpg)"] --> M["matugen\nColor extraction + palette generation"]
    M --> P["Material You Palette\nprimary, secondary, surface, onSurface, ..."]
    P --> T1["foot.ini\nTerminal colors"]
    P --> T2["fuzzel.ini\nLauncher theme"]
    P --> T3["Hyprland borders/shadows\ncolors.conf"]
    P --> T4["kde-material-you-colors\nQt/KDE app theming"]

    style W fill:#7e57c2,color:#fff
    style M fill:#5c6bc0,color:#fff
    style P fill:#26a69a,color:#fff
    style T1 fill:#43a047,color:#fff
    style T2 fill:#1e88e5,color:#fff
    style T3 fill:#e53935,color:#fff
    style T4 fill:#fb8c00,color:#fff
```

### Quickshell Service Flow

```mermaid
sequenceDiagram
    participant HM as Home Manager
    participant systemd as quickshell.service
    participant QS as Quickshell QML Runtime
    participant Svc as Services (Ai, Audio, etc.)
    participant UI as UI Modules (Bar, Sidebar, etc.)

    HM->>systemd: Deploy configs + env vars
    systemd->>QS: Start with full PATH/QML_IMPORT_PATH
    QS->>Svc: Load singleton services
    Svc-->>QS: Provide data (Hyprland state, audio, AI)
    QS->>UI: Render bar, sidebars, launcher
    UI-->>QS: User interactions → dispatch commands
```

## Module System

### Home Manager Module (`modules/home-manager.nix`)

Main entry point. Imports all component modules:

```mermaid
graph TD
    subgraph HM["Home Manager Module"]
        H["programs.dots-hyprland.enable = true;"]
    end

    subgraph Components["Component Modules"]
        QSC["quickshell-config.nix\nConfig.qml generation"]
        QSS["quickshell-service.nix\nsystemd service + PATH setup"]
        HC["hyprland-config.nix\ngeneral.conf generation"]
        TC["terminal-config.nix\nfoot.ini options"]
        TE["touchegg.nix\nGesture config"]
        CO["config-override.nix\nEscape hatch"]
    end

    subgraph Support["Supporting Modules"]
        PE["python-environment.nix\nVenv management"]
        CN["configuration.nix\nFile copying + placeholders"]
        WM["writable-mode.nix\nStaging + setup script"]
    end

    H --> QSC
    H --> QSS
    H --> HC
    H --> TC
    H --> TE
    H --> CO
    H --> PE
    H --> CN
    H --> WM

    style HM fill:#5c6bc0,color:#fff
    style Components fill:#26a69a,color:#fff
    style Support fill:#ef6c00,color:#fff
```

Imports:

```nix
imports = [
  ./python-environment.nix      # Python venv setup
  ./configuration.nix           # File copying logic
  ./writable-mode.nix           # Writable mode support
  ./components/quickshell-service.nix  # systemd service
  ./components/quickshell-config.nix   # Config.qml generation
  ./components/hyprland-config.nix     # general.conf generation
  ./components/terminal-config.nix     # foot.ini options
  ./components/touchegg.nix            # Gesture config
  ./components/config-override.nix     # Escape hatch
];
```

### Component Modules

Each component module defines:
1. **Options** (`options.programs.dots-hyprland.<component>`)
2. **Config generation** (how options become files)
3. **Activation scripts** (post-deployment setup)

Example: `quickshell-config.nix` generates `Config.qml` from Nix options.

## Deployment Modes

```mermaid
graph LR
    subgraph HM["Home Manager Activation"]
        A["flake.nix\nprograms.dots-hyprland"] --> B{"Deployment Mode?"}
    end

    B -->|Hybrid| C["Hybrid Mode (Recommended)"]
    B -->|Declarative| D["Declarative Mode"]
    B -->|Writable| E["Writable Mode"]

    subgraph C ["Hybrid Mode — Best of Both"]
        H1["Hyprland configs → Nix store\n(declarative, stable)"]
        H2["Quickshell QML → ~/.config/\n(copy-on-build, editable)"]
        H3["Custom overrides → ~/.config/hypr/custom/\n(survive rebuilds)"]
    end

    subgraph D ["Declarative Mode — Full Nix Control"]
        D1["All configs in Nix store\n(read-only)"]
        D2["Changes require rebuild\n(home-manager switch)"]
        D3["Maximum reproducibility"]
    end

    subgraph E ["Writable Mode — Development Friendly"]
        W1["Staging dir: ~/.configstaging/"]
        W2["Setup script copies to ~/.config/"]
        W3["Edit configs freely\nrestart Quickshell to apply"]
    end

    H1 --> C
    H2 --> C
    H3 --> C
    D1 --> D
    D2 --> D
    D3 --> D
    W1 --> E
    W2 --> E
    W3 --> E

    style B fill:#5c6bc0,color:#fff
    style C fill:#43a047,color:#fff
    style D fill:#e53935,color:#fff
    style E fill:#fb8c00,color:#fff
```

### Mode Comparison

| Aspect | Hybrid (Recommended) | Declarative | Writable |
|--------|---------------------|-------------|----------|
| Hyprland configs | Nix store (read-only) | Nix store (read-only) | Nix store (read-only) |
| Quickshell QML | Copy to `~/.config/` | Nix store (read-only) | Staging → copy to `~/.config/` |
| Edit at runtime | Yes | No — rebuild required | Yes |
| Reproducibility | High | Maximum | Medium |
| Best for | Production use | CI/testing | Development iteration |

### How Hybrid Mode Works

```mermaid
flowchart LR
    subgraph Nix["Nix Store (immutable)"]
        T1["configs/hypr/*.conf.template"]
        T2["configs/quickshell/**/*.qml"]
    end

    subgraph Build["home-manager switch"]
        S1["Template substitution\n@VARIABLE@ → store paths"]
        S2["Copy QML to ~/.config/\n(editable copy)"]
    end

    subgraph Runtime["~/.config/ (mutable)"]
        R1["hyprland.conf — resolved from templates"]
        R2["quickshell/ii/ — editable QML"]
        R3["custom/ — user overrides"]
    end

    T1 --> S1
    T2 --> S2
    S1 --> R1
    S2 --> R2
    R3 -.->|survives rebuilds| R1

    style Nix fill:#5c6bc0,color:#fff
    style Build fill:#26a69a,color:#fff
    style Runtime fill:#ef6c00,color:#fff
```

## Key Files

| File | Purpose |
|------|---------|
| [`flake.nix`](../flake.nix) | Flake definition, overlays, dev shells |
| [`modules/home-manager.nix`](../modules/home-manager.nix) | Main HM module entry point |
| [`modules/components/quickshell-config.nix`](../modules/components/quickshell-config.nix) | Quickshell Config.qml generation |
| [`modules/components/hyprland-config.nix`](../modules/components/hyprland-config.nix) | Hyprland general.conf generation |
| [`packages/default.nix`](../packages/default.nix) | Utility scripts (generate-qmldir, etc.) |
| [`packages/dots-hyprland-packages.nix`](../packages/dots-hyprland-packages.nix) | Package sets (minimal/essential/all) |

## Upstream Integration

This flake wraps [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland). The integration:

1. **Pins upstream commit** in `flake.lock`
2. **Applies overlays** to patch quickshell + kde-material-you-colors
3. **Adapts configs** for NixOS template system (`@VARIABLE@` substitution)
4. **Adds AI/voice features** on top of upstream Quickshell

### Sync Process

```bash
# Update to latest upstream commit
nix run .#update-flake -- <commit-hash-or-branch>

# Or manually edit flake.nix inputs
```

See [`docs/upstream-sync.md`](./upstream-sync.md) for detailed sync procedure.

## Testing Strategy

### Python Tests (`tests/*.py`)
- 34 test files using Hypothesis property-based testing
- Cover: template placeholders, wallpaper variants, keybind injection, voice assistant
- Run: `cd tests && python -m pytest`

### NixOS VM Test (`tests/vm-test.nix`)
- Full integration test in QEMU VM
- Verifies: config generation, placeholder resolution, service creation
- Run: `nix run .#vm` (interactive) or `nix flake check` (CI)

### JS Tests (`tests/js/`)
- Quickshell UI logic tests using Vitest
- Cover: action palette, chat sessions, dictation, model discovery
- Run: `cd tests/js && npm test`

## Development Workflow

```bash
# Enter dev shell
nix develop

# Test changes (temporary)
rsync -av configs/quickshell/ii/ ~/.config/quickshell/ii/
systemctl --user restart quickshell

# Run tests
cd tests && python -m pytest

# Build and apply
nix build .#homeConfigurations.declarative.activationPackage
./result/activate
```

## Security Considerations

- **Quickshell service sandbox**: `ProtectSystem=strict`, 2GB memory limit
- **API keys**: Stored via libsecret (system keyring), not in config files
- **Python venv**: Isolated dependencies, no system Python pollution
- **No network at build time**: All downloads happen at fetch phase only

## Performance Notes

- **Template compilation**: Happens once at build time, cached in store
- **Quickshell startup**: ~2s on modern hardware (QML cache helps)
- **Color generation**: ~500ms per wallpaper change (matugen + Python scripts)
- **Voice assistant**: Streaming adds ~100ms latency (negligible)
