# Upstream Sync Guide

## Overview

This flake wraps [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland). Periodic syncs bring in upstream changes while maintaining NixOS adaptations.

## Current Sync Status

**Last synced:** August 2025 → July 2026 (ongoing)
**Branch:** `upstream-sync-2026`

## What Gets Adapted

When syncing, the following upstream elements are adapted for NixOS:

### Configuration Templates
- Lua keybinds → `.conf.template` format with `@VARIABLE@` substitution
- Hardcoded paths → Nix store path placeholders (`@TERMINAL_APPS@`, `@QUICKSHELL_BIN@`, etc.)
- Arch-specific packages → Nix package equivalents

### Quickshell QML
- Service imports → qmldir generation via [`packages/scripts/generate-qmldir.sh`](../packages/scripts/generate-qmldir.sh)
- Config paths → `xdg.configFile` symlinks in Home Manager
- Python dependencies → managed venv at `~/.local/state/quickshell/.venv`

### Overlays
- quickshell: Add Qt5Compat + Qtpositioning QML imports
- kde-material-you-colors: Patch for non-Plasma systems (exist_ok, KWin skip, plasma stub)

## Sync Procedure

```mermaid
flowchart TD
    subgraph Step1["Step 1: Fetch Upstream"]
        A["git fetch origin\ngit log --oneline -20"] --> B{"Review recent commits"}
    end

    subgraph Step2["Step 2: Compare with Fork"]
        B --> C["Use analysis docs:\nkeybind-analysis.md\nkeybind-equivalence-verification.md"]
    end

    subgraph Step3["Step 3: Adapt Changes"]
        C --> D{"Change type?"}
        D -->|Keybind (Lua)| E["Translate to .conf.template format\nReplace hl.bind with bindd/bindle/etc."]
        D -->|Path reference| F["Replace hardcoded paths with @VARIABLE@ placeholders"]
        D -->|New feature| G["Update Nix module options in components/"]
        D -->|Python script| H["Check venv deps in python-environment.nix\nVerify no system Python references"]
    end

    subgraph Step4["Step 4: Update Flake Input"]
        E --> I["Update flake.nix:\ndots-hyprland = { url = github:end-4/dots-hyprland/<hash>; };"]
        F --> I
        G --> I
        H --> I
        I --> J["nix flake lock --update-input dots-hyprland"]
    end

    subgraph Step5["Step 5: Test Sync"]
        J --> K["Run VM test:\nnix build .#checks.x86_64-linux.vm-integration"]
        K --> L{"Tests pass?"}
        L -->|yes| M["Sync complete ✓"]
        L -->|no| N["Debug failures\nCheck template substitution\nVerify keybind equivalence"]
    end

    style Step1 fill:#5c6bc0,color:#fff
    style Step2 fill:#26a69a,color:#fff
    style Step3 fill:#ef6c00,color:#fff
    style Step4 fill:#7e57c2,color:#fff
    style Step5 fill:#43a047,color:#fff
```

### Detailed Steps

**1. Fetch Upstream Changes:**
```bash
cd /path/to/dots-hyprland
git fetch origin
git log --oneline -20  # Review recent commits
```

**2. Compare with Our Fork:**
Use the analysis docs to understand differences:
- [`docs/keybind-analysis.md`](./keybind-analysis.md) — Keybind comparison
- [`docs/keybind-equivalence-verification.md`](./keybind-equivalence-verification.md) — Detailed bind-by-bind verification

**3. Cherry-pick Adaptations:**

For each upstream change, follow this decision tree:

| Change Type | Adaptation Required |
|-------------|-------------------|
| New keybind (Lua `hl.bind`) | Translate to `.conf.template` format with proper flags (`bindd`, `bindle`, etc.) |
| Path reference | Replace hardcoded paths with `@VARIABLE@` placeholders |
| New config feature | Update Nix module options in relevant `components/*.nix` |
| Python script added | Check deps in `modules/python-environment.nix`; verify no system Python refs |

**4. Update Flake Input:**
```nix
# In flake.nix, update the dots-hyprland input:
dots-hyprland = {
  url = "github:end-4/dots-hyprland/<commit-hash>";
  flake = false;
};
```

Then run:
```bash
nix flake lock --update-input dots-hyprland
```

**5. Test the Sync:**
```bash
# Run VM test (headless)
nix build .#checks.x86_64-linux.vm-integration

# Or interactive testing
nix run .#vm
```

## Common Sync Patterns

### New Keybinds (Lua → .conf)

**Upstream Lua:**
```lua
hl.bind("SUPER + G", function()
    quickshell:call("global", "quickshell:overlayToggle")
end, { global = true })
```

**Our .conf.template equivalent:**
```conf
bindd = Super, G, ..., global, quickshell:overlayToggle
```

### Path Adaptations

**Upstream (Arch):**
```lua
exec = "~/.config/hypr/scripts/zoom.sh"
```

**NixOS template:**
```conf
# In keybinds.conf.template, use placeholder:
exec, @QUICKSHELL_BIN@ -c $qsConfig ipc call zoom zoomIn || ~/.config/hypr/scripts/zoom.sh
```

### Python Script Dependencies

When upstream adds a new Python script:
1. Check if dependencies are in the managed venv (`modules/python-environment.nix`)
2. Add missing deps to `python-environment.nix` buildInputs
3. Verify the script works with Nix store paths (no hardcoded `/usr/bin/python3`)

### Sync Pattern Decision Tree

```mermaid
flowchart TD
    A["Upstream change detected"] --> B{"Change type?"}
    
    B -->|Keybind (Lua)| C["Translate to .conf.template\nhl.bind → bindd/bindle/binde/etc."]
    B -->|Path reference| D["Replace hardcoded paths with @VARIABLE@ placeholders"]
    B -->|New Python script| E["Check venv deps in python-environment.nix\nVerify no system Python refs"]
    B -->|Config feature| F["Update Nix module options in components/"]
    B -->|Removed feature| G["Remove from .conf.template and Nix modules"]
    
    C --> H["Verify equivalence with keybind-equivalence-verification.md"]
    D --> H
    E --> H
    F --> H
    G --> H
    
    style A fill:#5c6bc0,color:#fff
    style B fill:#7e57c2,color:#fff
    style C fill:#26a69a,color:#fff
    style D fill:#ef6c00,color:#fff
    style E fill:#fb8c00,color:#fff
    style F fill:#43a047,color:#fff
    style G fill:#e53935,color:#fff
```

## Verification Checklist

After each sync:

- [ ] All keybinds verified against [`keybind-equivalence-verification.md`](./keybind-equivalence-verification.md)
- [ ] Template placeholders (`@VARIABLE@`) resolve correctly in VM test
- [ ] Python scripts use managed venv, not system Python
- [ ] Quickshell QML imports work (qmldir generated correctly)
- [ ] No Arch-specific packages referenced (use Nix equivalents)
- [ ] Home Manager module options cover all new config features
- [ ] Tests pass: `cd tests && python -m pytest`

## Known Divergences

These are intentional differences maintained across syncs:

| Feature | Upstream | Our Fork | Reason |
|---------|----------|----------|--------|
| Overview trigger | SUPER_L/R release | $Secondary + Space | More explicit, avoids accidental triggers |
| Zoom implementation | Lua `hl.get_config()` | IPC via Quickshell | No `.conf` equivalent for stateful zoom |
| Workspace dispatch | `workspace_in_group()` | `workspace_action.sh` | Shell script works in all formats |
| Keybind format | Lua `hl.bind()` | `.conf.template` with flags | Nix template system compatibility |

## Future Sync Considerations

### Pending Upstream Features

- **Virtual Machine submap** — Add to keybinds after adapting Lua submap syntax
- **Google Lens (region search)** — Requires `snip_to_search.sh` port or QS signal adoption
- **Panel family cycle** — New QS feature, add keybind + verify signal works

### Deprecation Tracking

Monitor upstream for:
- Removed features (e.g., `ags`, `agsv1`, `gjs` — already cleaned up)
- API changes in Quickshell services
- Material You color pipeline updates

## Automation

The [`packages/scripts/update-flake.sh`](../packages/scripts/update-flake.sh) script helps manage flake inputs:

```bash
# Update all flake inputs
nix run .#update-flake

# Or manually
./packages/scripts/update-flake.sh <input-name> <new-ref>
```
