# Implementation Plan: AI Desktop Control

## Overview

Extend the ii-desktop-mcp Python server with seven new tool modules providing comprehensive desktop environment control: Material You theming, Hyprland runtime configuration, disaster recovery/rollback, monitor layout, Bluetooth management, application integration discovery, and device awareness with event reactions. All mutating tools share a central Change Ledger for unified undo/redo. Property-based tests validate 19 correctness properties using Hypothesis.

## Tasks

- [x] 1. Create the Change Ledger core module
  - [x] 1.1 Implement `core/ledger.py` with `ChangeLedger` class and `ChangeEntry` dataclass
    - Create `/home/celes/sources/celesrenata/hyprmcp/src/ii_desktop_mcp/core/ledger.py`
    - Implement `ChangeEntry` dataclass with fields: id (UUID4), timestamp (ISO 8601), tool_name, params, previous_state, description
    - Implement `ChangeLedger` class with async methods: `record()`, `get_entries()`, `get_by_id()`, `remove()`, `remove_many()`
    - Ledger persists at `~/.local/state/ii-desktop/change-ledger.json`
    - Enforce 50-entry max with FIFO eviction
    - Handle corrupt JSON: backup to `.bak`, log warning, start fresh
    - Create parent directories with `os.makedirs(exist_ok=True)` on first write
    - _Requirements: 3.1, 3.2, 3.3, 8.4, 8.5_

  - [x] 1.2 Write property tests for ledger FIFO eviction (Property 2)
    - **Property 2: Ledger FIFO eviction at capacity**
    - Create `/home/celes/sources/celesrenata/end-4-flakes/tests/test_ledger.py`
    - Generate sequences of N > 50 entries and assert ledger contains exactly 50 most recent
    - **Validates: Requirements 3.2**

  - [x] 1.3 Write property tests for change entry structural completeness (Property 3)
    - **Property 3: Change entry structural completeness**
    - For any recorded entry, assert all required fields present: valid UUID4, ISO 8601 timestamp, non-empty tool_name, params dict, previous_state dict with ≥1 key, non-empty description
    - **Validates: Requirements 3.3**

  - [x] 1.4 Write property test for corrupt ledger recovery (Property 17)
    - **Property 17: Corrupt ledger recovery**
    - Generate arbitrary malformed JSON, write to ledger path, assert recovery: `.bak` created, fresh ledger usable
    - **Validates: Requirements 8.5**

  - [x] 1.5 Write property test for ledger ordering (Property 18)
    - **Property 18: Ledger ordering is reverse chronological**
    - Record entries with varying timestamps, assert `get_entries()` returns newest first
    - **Validates: Requirements 3.9**

- [x] 2. Implement Material You theming tools
  - [x] 2.1 Implement `tools/theme.py` with `theme_apply_wallpaper`, `theme_apply_color`, and `theme_get_current` tools
    - Create `/home/celes/sources/celesrenata/hyprmcp/src/ii_desktop_mcp/tools/theme.py`
    - Implement path validation: reject `..` traversal, symlinks outside `$HOME`, non-image extensions (.png, .jpg, .jpeg, .webp, .bmp, .gif, .tiff)
    - Implement hex color validation: must match `^#[0-9A-Fa-f]{6}$`
    - Implement token-bucket rate limiter: 5 tokens, 1 token per 12 seconds refill
    - Call `switchwall.sh` and `matugen` via `run_command` helper (never `shell=True`)
    - Record changes in Change Ledger before applying (wallpaper path + scheme as previous state)
    - `theme_get_current` reads from color config files to return active palette, wallpaper, scheme
    - Register tools via `register(mcp)` pattern
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 9.2, 9.3, 9.8_

  - [x] 2.2 Write property test for invalid hex color rejection (Property 9)
    - **Property 9: Invalid hex color rejection**
    - Generate strings not matching `^#[0-9A-Fa-f]{6}$`, assert `theme_apply_color` returns validation_error
    - **Validates: Requirements 1.6**

  - [x] 2.3 Write property test for path traversal and extension validation (Property 10)
    - **Property 10: Path traversal and extension validation**
    - Create `/home/celes/sources/celesrenata/end-4-flakes/tests/test_theme_validation.py`
    - Generate paths with `..` sequences or invalid extensions, assert rejection
    - **Validates: Requirements 9.2, 9.3**

  - [x] 2.4 Write property test for theme rate limiting (Property 12)
    - **Property 12: Theme rate limiting**
    - Simulate >5 requests within 60 seconds, assert 6th+ are rejected with rate-limit error
    - **Validates: Requirements 9.8**

- [x] 3. Implement Hyprland runtime configuration tools
  - [x] 3.1 Implement `tools/hypr_config.py` with `hypr_set_option`, `hypr_get_option`, `hypr_add_window_rule`, `hypr_remove_window_rule`, and `hypr_set_animation` tools
    - Create `/home/celes/sources/celesrenata/hyprmcp/src/ii_desktop_mcp/tools/hypr_config.py`
    - Implement keyword denylist: {"exec", "exec-once", "bind", "unbind", "plugin", "source"}
    - `hypr_set_option`: validate keyword not in denylist, record previous value in ledger, apply via `hyprctl keyword`
    - `hypr_get_option`: parse `hyprctl getoption` output, return not_found on error
    - `hypr_add_window_rule`: apply via `hyprctl keyword windowrulev2`, record for rollback
    - `hypr_remove_window_rule`: remove via `hyprctl keyword windowrulev2 unset`
    - `hypr_set_animation`: record previous config, apply via `hyprctl keyword animation`
    - Register tools via `register(mcp)` pattern
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 9.5_

  - [x] 3.2 Write property test for keyword denylist enforcement (Property 11)
    - **Property 11: Hyprland keyword denylist enforcement**
    - Create `/home/celes/sources/celesrenata/end-4-flakes/tests/test_hypr_config.py`
    - Generate keywords containing denylist segments, assert validation_error returned and hyprctl never called
    - **Validates: Requirements 9.5**

- [x] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement rollback and disaster recovery tools
  - [x] 5.1 Implement `tools/rollback.py` with `rollback_last`, `rollback_by_id`, and `rollback_list` tools
    - Create `/home/celes/sources/celesrenata/hyprmcp/src/ii_desktop_mcp/tools/rollback.py`
    - Implement `RollbackEngine` with inverse operation map for all mutating tools
    - `rollback_last`: reverse N most recent entries (1-50, default 1) in reverse chronological order
    - `rollback_by_id`: reverse a specific entry by UUID
    - `rollback_list`: return all ledger entries (id, timestamp, description, tool)
    - On success: remove entries from ledger
    - On failure: preserve entry, report error, stop multi-rollback at failure point
    - Rollbacks are NOT recorded as new ledger entries
    - Return not_found for non-existent IDs
    - Register tools via `register(mcp)` pattern
    - _Requirements: 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10, 3.11_

  - [x] 5.2 Write property test for rollback removes entries on success (Property 5)
    - **Property 5: Rollback removes entries on success**
    - Create `/home/celes/sources/celesrenata/end-4-flakes/tests/test_rollback.py`
    - Record entries, perform rollback, assert entries removed and ledger size decreases accordingly
    - **Validates: Requirements 3.5, 3.7**

  - [x] 5.3 Write property test for failed rollback preserves entries (Property 6)
    - **Property 6: Failed rollback preserves entries**
    - Mock inverse operations to fail, assert entries remain in ledger unchanged
    - **Validates: Requirements 3.8**

  - [x] 5.4 Write property test for rollbacks not recorded (Property 7)
    - **Property 7: Rollbacks are not recorded as new entries**
    - Perform rollbacks (successful and failed), assert ledger gains no new entries from rollback itself
    - **Validates: Requirements 3.10**

  - [x] 5.5 Write property test for non-existent identifier returns not_found (Property 8)
    - **Property 8: Non-existent identifier returns not_found**
    - Generate random UUIDs not in ledger, assert rollback_by_id returns not_found error
    - **Validates: Requirements 3.11, 4.5, 4.8, 6.6**

- [x] 6. Implement monitor layout control tools
  - [x] 6.1 Implement `tools/monitor.py` with `monitor_list`, `monitor_set`, `monitor_save_profile`, and `monitor_load_profile` tools
    - Create `/home/celes/sources/celesrenata/hyprmcp/src/ii_desktop_mcp/tools/monitor.py`
    - `monitor_list`: parse `hyprctl monitors -j` output, return structured monitor info
    - `monitor_set`: validate monitor exists, validate resolution/refresh against available modes, merge specified params with current values for unspecified, record in ledger, apply via `hyprctl keyword monitor`
    - `monitor_save_profile`: save current layout to `~/.local/state/ii-desktop/monitor-profiles.json`
    - `monitor_load_profile`: load and apply named profile, record pre-application state in ledger
    - Return not_found for non-existent monitors or profiles
    - Register tools via `register(mcp)` pattern
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 9.6_

  - [x] 6.2 Write property test for monitor command construction (Property 13)
    - **Property 13: Monitor command construction merges parameters**
    - Create `/home/celes/sources/celesrenata/end-4-flakes/tests/test_monitor.py`
    - Generate partial parameter sets, assert constructed command uses provided values + current values for omitted
    - **Validates: Requirements 4.4**

  - [x] 6.3 Write property test for monitor resolution validation (Property 19)
    - **Property 19: Monitor resolution validation against available modes**
    - Generate resolution/refresh combinations not in available modes, assert validation_error without applying
    - **Validates: Requirements 9.6**

- [x] 7. Implement Bluetooth device management tools
  - [x] 7.1 Implement `tools/bluetooth.py` with `bluetooth_status`, `bluetooth_scan`, `bluetooth_connect`, `bluetooth_disconnect`, and `bluetooth_remove` tools
    - Create `/home/celes/sources/celesrenata/hyprmcp/src/ii_desktop_mcp/tools/bluetooth.py`
    - Interface with `bluetoothctl` in scripted mode via `run_command`
    - `bluetooth_status`: return adapter state and paired devices (sanitize sensitive data from output)
    - `bluetooth_scan`: initiate discovery with configurable duration (default 10s, max 30s)
    - `bluetooth_connect`: pair if needed then connect, record state change in ledger
    - `bluetooth_disconnect`: disconnect device, record state change in ledger
    - `bluetooth_remove`: remove device from paired list
    - Return unavailable if adapter is off, internal_error on pairing/connection failure
    - Never expose PINs, link keys, or pairing keys in responses
    - Register tools via `register(mcp)` pattern
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 9.4_

  - [x] 7.2 Write property test for Bluetooth response sanitization (Property 14)
    - **Property 14: Bluetooth response sanitization**
    - Create `/home/celes/sources/celesrenata/end-4-flakes/tests/test_bluetooth.py`
    - Generate bluetoothctl output containing PIN/key patterns, assert sanitized responses never leak secrets
    - **Validates: Requirements 9.4**

- [x] 8. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Implement application integration discovery tools
  - [x] 9.1 Implement `tools/app_discovery.py` with `apps_discover_interfaces` and `apps_get_interface` tools
    - Create `/home/celes/sources/celesrenata/hyprmcp/src/ii_desktop_mcp/tools/app_discovery.py`
    - `apps_discover_interfaces`: when `rescan=true`, enumerate D-Bus session services, CLI tools from .desktop entries, known socket/API endpoints; persist to `~/.local/state/ii-desktop/app-registry.json`; timeout at 30s with partial results
    - `apps_get_interface`: look up single app by name, return not_found if absent
    - Registry must include at minimum: MPRIS media players, terminal emulators, file managers, browsers, system services
    - Register tools via `register(mcp)` pattern
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8_

- [x] 10. Implement device awareness and event reaction tools
  - [x] 10.1 Implement `tools/devices.py` with `devices_list`, `devices_set_reaction`, `devices_list_reactions`, and `devices_remove_reaction` tools
    - Create `/home/celes/sources/celesrenata/hyprmcp/src/ii_desktop_mcp/tools/devices.py`
    - `devices_list`: aggregate from hyprctl monitors, wpctl/pactl, hyprctl devices, lsusb, Bluetooth — filter by category parameter
    - `devices_set_reaction`: configure event→action mappings, persist to `~/.local/state/ii-desktop/device-reactions.json`
    - `devices_list_reactions`: return all configured reactions
    - `devices_remove_reaction`: delete a reaction by event name
    - Background asyncio polling loop (5s interval) detects device changes and triggers configured reactions
    - Failed reaction dispatch: log warning, emit notification, keep reaction configured
    - Register tools via `register(mcp)` pattern
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8_

  - [x] 10.2 Write property test for device list category filtering (Property 15)
    - **Property 15: Device list category filtering**
    - Create `/home/celes/sources/celesrenata/end-4-flakes/tests/test_devices.py`
    - Generate device inventories, assert filtered results contain only devices of requested category; "all" returns everything
    - **Validates: Requirements 7.1**

  - [x] 10.3 Write property test for device reaction persistence round-trip (Property 16)
    - **Property 16: Device reaction persistence round-trip**
    - Set reactions, list them (assert present with correct data), remove them, list again (assert absent)
    - **Validates: Requirements 7.3, 7.5, 7.6**

- [x] 11. Register new modules in server.py and wire integration
  - [x] 11.1 Update `server.py` to import and register all new tool modules
    - Edit `/home/celes/sources/celesrenata/hyprmcp/src/ii_desktop_mcp/server.py`
    - Add imports: `from ii_desktop_mcp.tools import theme, hypr_config, rollback, monitor, bluetooth, app_discovery, devices`
    - Add all new modules to the `_modules` list
    - _Requirements: 8.1_

  - [x] 11.2 Write property test for ledger records all mutations (Property 1)
    - **Property 1: Ledger records all mutations before returning**
    - Create `/home/celes/sources/celesrenata/end-4-flakes/tests/test_ledger_integration.py`
    - For each mutating tool, invoke with valid params (mocked subprocess), assert ledger contains entry with correct tool_name, params, and previous_state
    - **Validates: Requirements 1.8, 2.2, 2.5, 2.8, 4.3, 5.9, 8.1**

  - [x] 11.3 Write property test for rollback reversal round-trip (Property 4)
    - **Property 4: Rollback reversal round-trip**
    - Record a change entry, perform rollback, assert the inverse operation was called with previous_state values
    - **Validates: Requirements 3.4, 3.5, 3.6, 3.7, 8.2**

- [x] 12. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document (19 properties total)
- Unit tests validate specific examples and edge cases
- All new modules follow the existing `register(mcp: FastMCP)` pattern used by current tools
- Subprocess calls use the existing `run_command` helper from `core/subprocess.py` — never `shell=True`
- State files persist in `~/.local/state/ii-desktop/` (ledger, profiles, reactions, app registry)
- The tests directory is `/home/celes/sources/celesrenata/end-4-flakes/tests/` and uses Hypothesis for PBT
- Mock `run_command` for subprocess isolation; use `tmp_path` for file-based state; mock `time.time()` for rate limiter tests

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3", "1.4", "1.5", "2.1", "3.1"] },
    { "id": 2, "tasks": ["2.2", "2.3", "2.4", "3.2", "5.1", "6.1", "7.1"] },
    { "id": 3, "tasks": ["5.2", "5.3", "5.4", "5.5", "6.2", "6.3", "7.2", "9.1"] },
    { "id": 4, "tasks": ["10.1"] },
    { "id": 5, "tasks": ["10.2", "10.3", "11.1"] },
    { "id": 6, "tasks": ["11.2", "11.3"] }
  ]
}
```
