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

### 1. Fetch Upstream Changes

```bash
# Clone or fetch upstream
cd /path/to/dots-hyprland
git fetch origin
git log --oneline -20  # Review recent commits
```

### 2. Compare with Our Fork

Use the analysis docs to understand differences:
- [`docs/keybind-analysis.md`](./keybind-analysis.md) — Keybind comparison
- [`docs/keybind-equivalence-verification.md`](./keybind-equivalence-verification.md) — Detailed bind-by-bind verification

### 3. Cherry-pick Adaptations

For each upstream change:

1. **Identify the change** in upstream Lua/config
2. **Translate to `.conf.template` format** (if keybinds)
3. **Replace hardcoded paths** with `@VARIABLE@` placeholders
4. **Verify equivalence** using the verification matrix
5. **Update Nix module options** if new config features are added

### 4. Update Flake Input

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

### 5. Test the Sync

```bash
# Run VM test
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
