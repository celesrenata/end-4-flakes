# Keybind Analysis: Upstream `keybinds.lua` vs Our `keybinds.conf.template`

**Date:** 2025-07-17  
**Upstream source:** [`dots/.config/hypr/hyprland/keybinds.lua`](https://github.com/end-4/dots-hyprland/blob/main/dots/.config/hypr/hyprland/keybinds.lua)  
**Our file:** `configs/hypr/keybinds.conf.template`  
**Validates:** Requirement 20.1

---

## Summary

The upstream `keybinds.lua` has diverged significantly from our `.conf.template`. Key changes include:
- 10 new keybinds/features not in our template
- 4 groups of removed keybinds (overview interrupt mechanism, Alt+Tab cycling, etc.)
- 15 changed keybinds (key combos, signals, or behavior)
- A completely new "Virtual Machines" submap section
- Structural migration from `.conf` flags to Lua options tables

Our strategy (per design.md) is to keep `.conf.template` as authoritative and import the *logical* changes without migrating to Lua format.

---

## New Keybinds (upstream Lua, absent from our template)

| # | Key Combo | Dispatcher/Signal | Description | NixOS Compatible? | Notes |
|---|-----------|-------------------|-------------|-------------------|-------|
| 1 | `SUPER + G` | global `quickshell:overlayToggle` | Toggle widget overlay | ✅ Yes | New QS feature |
| 2 | `CTRL + SUPER + ALT + T` | global `quickshell:wallpaperSelectorRandom` | Random wallpaper | ✅ Yes | New QS feature |
| 3 | `CTRL + SUPER + P` | global `quickshell:panelFamilyCycle` | Cycle panel family | ✅ Yes | New QS feature |
| 4 | `SUPER + SHIFT + A` | global `quickshell:regionSearch` | Google Lens (search by screenshot) | ✅ Yes | New QS feature |
| 5 | `SUPER + SHIFT + A` | exec (fallback) | `snip_to_search.sh` fallback | ⚠️ Needs script | Requires new script |
| 6 | `SUPER + SHIFT + T` | global `quickshell:screenTranslate` | Translate screen content | ✅ Yes | Key reused (was OCR) |
| 7 | `SUPER + SHIFT + R` | global `quickshell:regionRecord` | Record region (primary) | ✅ Yes | Previously only SUPER+ALT+R |
| 8 | `SUPER + ALT + F1` | submap toggle | Virtual Machine submap | ⚠️ Needs adaptation | Lua submap syntax → `.conf` submap |
| 9 | `SUPER + code:87-90,79-81,83-85` | focus workspace | Keypad numbers for workspace focus | ✅ Yes | Standard keycodes |
| 10 | `SUPER + ALT + code:87-90,79-81,83-85` | movetoworkspacesilent | Keypad numbers for send-to-workspace | ✅ Yes | Standard keycodes |

---

## Removed Keybinds (in our template, absent from upstream)

### 1. Overview Toggle Release Interrupt Mechanism (REMOVED)

The entire interrupt system that prevented accidental overview toggles is gone:

```conf
# ALL REMOVED in upstream:
binditn = Super, catchall, global, quickshell:overviewToggleReleaseInterrupt
bind = Ctrl, Super_L, global, quickshell:overviewToggleReleaseInterrupt
bind = Super, mouse:272, global, quickshell:overviewToggleReleaseInterrupt
bind = Super, mouse:273, global, quickshell:overviewToggleReleaseInterrupt
bind = Super, mouse:274, global, quickshell:overviewToggleReleaseInterrupt
bind = Super, mouse:275, global, quickshell:overviewToggleReleaseInterrupt
bind = Super, mouse:276, global, quickshell:overviewToggleReleaseInterrupt
bind = Super, mouse:277, global, quickshell:overviewToggleReleaseInterrupt
bind = Super, mouse_up, global, quickshell:overviewToggleReleaseInterrupt
bind = Super, mouse_down, global, quickshell:overviewToggleReleaseInterrupt
```

**Reason:** Upstream redesigned the overview mechanism. The new `searchToggleRelease` signal handles this differently.

### 2. Alt+Tab Window Cycling (REMOVED)

```conf
# REMOVED in upstream:
bind = Alt, Tab, cyclenext
bind = Alt, Tab, bringactivetotop,
```

**Reason:** Not present in upstream Lua at all. May have been moved to a different mechanism or deemed unnecessary.

### 3. Raw Keycodes for Send-to-Workspace (COMMENTED OUT)

```conf
# COMMENTED OUT in upstream (replaced by keypad numpad binds):
# bind = Super+Alt, code:10-19 → workspace_action.sh movetoworkspacesilent
```

**Reason:** Upstream commented these out, replacing them with numpad keycodes (87-90, 79-81, 83-85). The regular number keys still work via the non-code binding.

### 4. $Secondary+Space Overview Toggle (REPLACED)

```conf
# REPLACED by SUPER_L/R release mechanism:
bindid = $Secondary, Space, Toggle overview, global, quickshell:overviewToggleRelease
bind = $Secondary, Space, exec, ... fuzzel fallback
```

**Reason:** Upstream now triggers the launcher/search on Super key release instead of Super+Space.

---

## Changed Keybinds

| # | Key Combo | What Changed | Our Template (old) | Upstream (new) |
|---|-----------|--------------|-------------------|----------------|
| 1 | Overview trigger | Key + signal | `$Secondary, Space` → `quickshell:overviewToggleRelease` | `SUPER + SUPER_L` → `quickshell:searchToggleRelease` |
| 2 | `SUPER + Tab` | Signal name | `quickshell:overviewToggle` | `quickshell:overviewWorkspacesToggle` |
| 3 | Volume raise | Limit value | `-l 1` (100%) | `-l 1.5` (150%) |
| 4 | `CTRL + SUPER + T` | Primary action | `exec, switchwall.sh` | `global, quickshell:wallpaperSelectorToggle` |
| 5 | `CTRL + SUPER + R` | Kill command | `killall ags agsv1 gjs ydotool qs quickshell` | `killall ydotool qs quickshell` |
| 6 | OCR keybind | Key changed | `SUPER + SHIFT + T` | `SUPER + SHIFT + X` |
| 7 | Fullscreen screenshot | Command | `grim -` (all monitors) | `grim -o "$(hyprctl activeworkspace -j \| jq -r '.monitor')"` (active monitor) |
| 8 | Record region | Primary key | `SUPER + ALT + R` | `SUPER + SHIFT + R` (ALT kept as secondary) |
| 9 | Record fullscreen+sound | Flag syntax | `--fullscreen-sound` | `--fullscreen --sound` |
| 10 | Zoom | Implementation | IPC call `zoom zoomIn/zoomOut` + script fallback | Native Lua `cursor:zoom_factor` (step 0.3, max 3.0) |
| 11 | `ALT + F4` | Behavior | `killactive` | Notification "Wrong close keybind" (non_consuming) |
| 12 | Workspace switch | Mechanism | `exec workspace_action.sh workspace N` | `hl.dsp.focus({ workspace = workspace_in_group(i) })` |
| 13 | Send to scratchpad | Workspace name | `movetoworkspacesilent, special` | `move({ workspace = "special:special" })` |
| 14 | `SUPER + SHIFT + L` | Suspend command | `sleep 0.1 && systemctl suspend` | `systemctl suspend \|\| loginctl suspend` |
| 15 | Office app keybind | Key combo | `Super + Shift + W` | `CTRL + SUPER + SHIFT + ALT + W` |

---

## Detailed Change Analysis

### Overview/Launcher Trigger Redesign

**Old (our template):**
- `$Secondary + Space` activates the overview/launcher
- A complex interrupt mechanism prevents accidental triggers

**New (upstream):**
- Releasing `SUPER_L` or `SUPER_R` (when pressed with another key combo) triggers the search
- The signal is now `quickshell:searchToggleRelease` (was `overviewToggleRelease`)
- No more interrupt mechanism needed

**Impact:** This is the most significant behavioral change. The `$Secondary` variable in our template may already handle this if it maps to Super, but the Space key is no longer involved.

### Zoom Implementation Change

**Old (our template):**
```conf
binde = Super, Minus, exec, @QUICKSHELL_BIN@ -c $qsConfig ipc call zoom zoomOut
binde = Super, Equal, exec, @QUICKSHELL_BIN@ -c $qsConfig ipc call zoom zoomIn
binde = Super, Minus, exec, @QUICKSHELL_BIN@ -c $qsConfig ipc call TEST_ALIVE || ~/.config/hypr/scripts/zoom.sh decrease 0.1
binde = Super, Equal, exec, @QUICKSHELL_BIN@ -c $qsConfig ipc call TEST_ALIVE || ~/.config/hypr/scripts/zoom.sh increase 0.1
```

**New (upstream):**
```lua
local function zoomfunction(value)
    local zoomvalue = hl.get_config("cursor:zoom_factor")
    if (zoomvalue + value) > 3.0 then
        hl.config({ cursor = { zoom_factor = 3.0 } })
    elseif (zoomvalue + value) < 1.0 then
        hl.config({ cursor = { zoom_factor = 1.0 } })
    else
        hl.config({ cursor = { zoom_factor = zoomvalue + value } })
    end
end
hl.bind("SUPER + Minus", function() zoomfunction(-0.3) end, { repeating = true })
hl.bind("SUPER + Equal", function() zoomfunction(0.3) end, { repeating = true })
```

**Impact:** Cannot be directly translated to `.conf` format since it requires runtime state (reading current zoom factor). Options:
1. Keep our IPC-based approach (quickshell handles the logic)
2. Write a helper script that reads `hyprctl getoption cursor:zoom_factor` and dispatches the new value
3. If Quickshell's zoom IPC still works, keep as-is

### Alt+F4 Behavior Change

**Old:** `bind = Alt, F4, killactive,` — closes the window  
**New:** Shows notification "Wrong close keybind, Super+Q to close" and passes the key through (non_consuming)

**Impact:** This is a deliberate UX decision by upstream. The `non_consuming` flag means the key still reaches the focused app (useful for VMs/games that use Alt+F4). We should adopt this.

### Virtual Machine Submap (New)

Upstream added a dedicated submap for VM passthrough:

```lua
hl.define_submap("virtual-machine", function()
    hl.bind("SUPER + ALT + F1", function()
        -- Toggle between normal and VM submap
        -- In VM submap: all keybinds disabled, keys pass to VM
    end, { submap_universal = true })
end)
```

**`.conf` equivalent:**
```conf
bind = Super+Alt, F1, submap, virtual-machine
submap = virtual-machine
bind = Super+Alt, F1, submap, reset
submap = reset
```

### Workspace Groups

Upstream uses `workspace_in_group(i)` which supports a `workspaceGroupSize` variable (default 10). This means workspace numbers are offset-based rather than absolute. For our NixOS setup, this maps directly to workspaces 1-10, so the behavior is equivalent when `workspaceGroupSize = 10`.

---

## Arch-Specific / Incompatible Elements

| Element | Why Incompatible | Adaptation |
|---------|-----------------|------------|
| Lua `zoomfunction()` with `hl.get_config` | Requires Lua runtime; no .conf equivalent | Keep IPC-based zoom or write helper script |
| `workspace_in_group()` function | Lua function for workspace offsetting | Use direct workspace numbers (equivalent for group size 10) |
| `hl.define_submap()` | Lua submap syntax | Convert to standard `submap = name` / `submap = reset` blocks |
| Direct variable references (`terminal`, `browser`) | Lua variables from `variables.lua` | Keep `@VARIABLE@` placeholder system |
| `$HOME/.config/hypr/hyprland/scripts/` paths | Different directory structure on NixOS | Keep our `~/.config/hypr/scripts/` paths |
| `qs` command (short for quickshell) | May not be available as `qs` on NixOS | Keep `@QUICKSHELL_BIN@` placeholder |
| `snip_to_search.sh` script | Not present in our fork | Need to port or skip |

---

## Recommendations for Task 8.2 (Template Update)

### Must-Have Changes

1. **Add `SUPER + G` overlay toggle** — simple global signal addition
2. **Add `CTRL + SUPER + ALT + T` random wallpaper** — simple global signal
3. **Add `CTRL + SUPER + P` panel family cycle** — simple global signal
4. **Change OCR from `SUPER+SHIFT+T` to `SUPER+SHIFT+X`**
5. **Add `SUPER+SHIFT+T` screen translate** — uses the freed key
6. **Add `SUPER+SHIFT+A` region search (Google Lens)**
7. **Update `SUPER+Tab` signal** to `quickshell:overviewWorkspacesToggle`
8. **Update volume limit** from `-l 1` to `-l 1.5`
9. **Update widget restart** — remove `ags agsv1 gjs` from killall
10. **Update `CTRL+SUPER+T`** primary to global signal (keep exec as fallback)
11. **Change record primary key** from ALT to SHIFT (`SUPER+SHIFT+R`)
12. **Update record fullscreen-sound flags** to `--fullscreen --sound`
13. **Update fullscreen screenshot** to per-monitor (`grim -o ...`)
14. **Change Alt+F4 behavior** to notification + non_consuming
15. **Update suspend** — remove `sleep 0.1` prefix
16. **Change office keybind** from `Super+Shift+W` to `Ctrl+Super+Shift+Alt+W`
17. **Add virtual machine submap** section
18. **Add keypad workspace binds** (codes 87-90, 79-81, 83-85)
19. **Update scratchpad workspace name** to `special:special`

### Should-Have Changes

1. **Remove overview interrupt mechanism** — entire block of mouse/catchall interrupts
2. **Reconsider $Secondary+Space** vs SUPER_L/R release for overview trigger
3. **Update zoom step** from 0.1 to 0.3 (in IPC call or script)

### Defer / Skip

1. **Alt+Tab removal** — keep for now, useful shortcut even if upstream removed it
2. **workspace_in_group() migration** — our `workspace_action.sh` approach works fine
3. **Full Lua zoom implementation** — keep IPC-based approach

### Preserve (NixOS-specific)

1. `@CUSTOM_KEYBINDS@` injection point at end of file
2. All `@VARIABLE@` placeholders
3. `@QUICKSHELL_BIN@` instead of bare `qs`
4. Our directory structure (`scripts/` paths)
5. `launch_first_available.sh "@APP_LIST@"` pattern

---

## File Comparison Statistics

| Metric | Our Template | Upstream Lua |
|--------|-------------|--------------|
| Total bind entries | ~145 | ~120 (but loops expand to more) |
| Sections | Shell, Utilities, Window, Workspace, Testing, Session, Screen, Media, Apps | Same + Virtual Machines |
| Format | `.conf` with flags (bind, bindd, bindle, bindl, etc.) | Lua `hl.bind()` with options table |
| Variables | `@PLACEHOLDER@` system | Lua variables from `variables.lua` |
| Custom injection | `@CUSTOM_KEYBINDS@` | `custom/variables.lua` require |
| Repetitive binds | Individual lines | Lua for-loops |
