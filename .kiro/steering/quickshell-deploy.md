# Quickshell Deploy Workflow

inclusion: auto

## Critical Rule: Deployed Config ↔ Repo Sync

The Quickshell config lives in TWO places:
- **Repo (source of truth):** `configs/quickshell/ii/` in end-4-flakes
- **Deployed (runtime):** `~/.config/quickshell/ii/` — what Quickshell actually reads

### After editing repo files:
1. Copy changed files to `~/.config/quickshell/ii/` (matching paths)
2. Run `systemctl --user restart quickshell`
3. Check logs: `journalctl --user -u quickshell --since "10 sec ago" --no-pager`

### After testing works in deployed:
1. Ensure repo matches deployed: `diff <(find ~/.config/quickshell/ii/ -name "*.qml" | sort) <(find configs/quickshell/ii/ -name "*.qml" | sort)`
2. Copy any new/changed deployed files back to repo
3. `git add` and commit

### Before committing:
- Always check the `qmldir` files — new `.qml` singletons MUST be registered
- The `ii/services/qmldir` must list ALL singleton services
- Module qmldirs must list all public components

### Key files that get out of sync:
- `configs/quickshell/ii/services/qmldir` — singleton registrations
- `configs/quickshell/ii/services/Ai.qml` — frequently edited
- `configs/quickshell/ii/modules/sidebarLeft/AiChat.qml` — UI changes
- `configs/quickshell/ii/modules/sidebarLeft/SidebarLeft.qml` — pop-out, layout
- `configs/quickshell/ii/modules/common/Config.qml` — config schema
- `configs/quickshell/ii/modules/common/Persistent.qml` — persistent state schema

### Deploy all at once (full sync):
```bash
rsync -av --delete configs/quickshell/ii/ ~/.config/quickshell/ii/
systemctl --user restart quickshell
```

### Hyprland keybinds:
- Keybinds template: `configs/hypr/keybinds.conf.template`
- Deployed: `~/.config/hypr/hyprland/keybinds.conf`
- After editing template, manually add to deployed or rebuild NixOS
