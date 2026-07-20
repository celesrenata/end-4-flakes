# Implementation Plan: Upstream Sync 2025–2026

## Overview

Selective cherry-pick of ~11 months of upstream `end-4/dots-hyprland` changes into the NixOS fork and flake wrapper. Work proceeds in phases: branch setup → bug fixes → structural cleanups → new features → Lua keybinds adaptation → Home Manager extensions → build verification. Each phase builds on the previous, ensuring incremental testability.

## Tasks

- [x] 1. Branch creation and upstream remote setup
  - [x] 1.1 Create sync branch in dots-hyprland fork
    - In `/home/celes/sources/celesrenata/dots-hyprland`, add upstream remote if not present: `git remote add upstream https://github.com/end-4/dots-hyprland.git`
    - Fetch upstream: `git fetch upstream`
    - Create branch: `git checkout -b upstream-sync-2026 quickshell-locked`
    - _Requirements: 1.1, 1.3_

  - [x] 1.2 Create sync branch in end-4-flakes
    - In `/home/celes/sources/celesrenata/end-4-flakes`, create branch: `git checkout -b upstream-sync-2026`
    - _Requirements: 1.2, 1.4_

- [x] 2. Cherry-pick bug fixes (smallest diffs first)
  - [x] 2.1 Cherry-pick Qt 6.11 NotificationItem infinite loop fix
    - Identify the upstream commit(s) fixing `NotificationItem` `polish()` recursion
    - Cherry-pick into fork sync branch, resolve any QML conflicts
    - Verify the recursion guard is present in the notification QML files
    - _Requirements: 2.1, 2.2, 2.3_

  - [x] 2.2 Cherry-pick XDG_DATA_DIRS expansion fix
    - Identify upstream commit fixing XDG_DATA_DIRS shell-quoting
    - Cherry-pick into fork, verify no conflict with our Nix session variable setup
    - _Requirements: 3.1, 3.2_

  - [x] 2.3 Cherry-pick DPMS syntax and monitor scale type fixes
    - Apply corrected `dispatch dpms` syntax to hypridle configuration
    - Fix monitor scale passed as float instead of integer
    - Apply changes to `hypridle.conf.template`, preserving `@VARIABLE@` placeholders
    - _Requirements: 6.1, 6.2, 4.1_

  - [x] 2.4 Cherry-pick multi-monitor screen corners fix
    - Cherry-pick the QML fix for per-monitor corner rendering
    - Verify the fix respects per-monitor scale values
    - _Requirements: 5.1, 5.2_

  - [x] 2.5 Cherry-pick clipboard escaped text fix
    - Cherry-pick fix for clipboard history special character display
    - _Requirements: 8.1, 8.2_

  - [x] 2.6 Cherry-pick Super key hold state fix
    - Cherry-pick the workspace number display on Super hold
    - Verify overview toggle is not triggered on Super+key release
    - _Requirements: 9.1, 9.2, 9.3_

  - [x] 2.7 Cherry-pick Konachan/waifu.im User-Agent and tag search fixes
    - Cherry-pick User-Agent header fix for booru panel
    - Cherry-pick multi-word tag encoding fix
    - _Requirements: 10.1, 10.2_

  - [x] 2.8 Cherry-pick HOME environment variable fix for Lua configs
    - Ensure HOME is available in Lua config context
    - Verify template system handles HOME references in both `.conf.template` and `.lua` files
    - _Requirements: 11.1, 11.2_

  - [x] 2.9 Cherry-pick keybind syntax fixes
    - Apply raw keycode `code:` prefix correction
    - Apply fullscreen/fullscreenstate dispatcher syntax update
    - Apply Super+Alt+workspace `movetoworkspacesilent` argument format fix
    - Verify all `@VARIABLE@` placeholders preserved in `keybinds.conf.template`
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [x] 2.10 Cherry-pick hyprsunset default color temperature fix
    - Update the default color temperature value to 4500K in relevant config
    - _Requirements: 23.1_

- [x] 3. Checkpoint — Bug fixes verified
  - Ensure all cherry-picked bug fixes apply cleanly, ask the user if questions arise.

- [x] 4. Cherry-pick structural cleanups
  - [x] 4.1 Remove JetBrains windowrule from rules configuration
    - Remove the JetBrains-specific windowrule from `rules.conf.template`
    - Verify no Nix module references the removed rule
    - _Requirements: 22.1, 22.5_

  - [x] 4.2 Remove unlock refocus hack
    - Cherry-pick the removal of the unnecessary unlock refocus workaround
    - _Requirements: 22.2_

  - [x] 4.3 Cherry-pick "custom stuff made optional" pattern
    - Import upstream pattern where user customizations don't conflict with base config
    - Update `source` directives to gracefully handle missing custom files
    - _Requirements: 22.3, 25.1, 25.2_

  - [x] 4.4 Remove redundant sleep delays from color pipeline
    - Remove `sleep 0` and zero-duration delays from `applycolor.sh` and `switchwall.sh`
    - Verify the pipeline still applies colors correctly without timing issues
    - _Requirements: 12.1, 12.2_

  - [x] 4.5 Remove deprecated scripts identified by upstream
    - Identify and remove scripts upstream has deprecated
    - Update any Nix module references to removed scripts
    - _Requirements: 22.4, 22.5_

- [x] 5. Checkpoint — Structural cleanups verified
  - Ensure all structural changes are clean, ask the user if questions arise.

- [ ] 6. Cherry-pick new features
  - [x] 6.1 Import hefty bar workspaces widget
    - Cherry-pick the new workspace widget QML files
    - Verify the widget renders with application icons per workspace
    - _Requirements: 13.1, 13.2_

  - [x] 6.2 Import light/dark wallpaper variant switching
    - Cherry-pick the wallpaper variant logic into `switchwall.sh`
    - Implement filename suffix detection (`-dark`, `-light`) and mode-based selection
    - Preserve custom `apply_foot()`, `apply_fuzzel()`, `apply_wofi()` functions
    - _Requirements: 14.1, 14.2, 14.3_

  - [x] 6.3 Import anti-flashbang weak variant
    - Cherry-pick the semi-transparent overlay QML for workspace transitions
    - _Requirements: 15.1_

  - [x] 6.4 Import notification force monitor feature
    - Cherry-pick the QML changes for forced notification monitor placement
    - _Requirements: 16.1, 16.2_

  - [x] 6.5 Import dark/light toggle keybind
    - Add `Ctrl+Super+Shift+D` toggle to `keybinds.conf.template`
    - Wire the toggle to the Applycolor_Pipeline mode regeneration
    - Preserve `@VARIABLE@` pattern in the template
    - _Requirements: 17.1, 17.2, 17.3_

  - [x] 6.6 Import Emoji 17.0 data update
    - Replace the emoji data file with the Unicode 17.0 version from upstream
    - Verify emoji picker (Super+Period) loads the new data
    - _Requirements: 18.1, 18.2_

  - [x] 6.7 Import cheatsheet category improvements
    - Cherry-pick QML changes for improved category headers and grouping
    - _Requirements: 19.1, 19.2_

  - [x] 6.8 Import nwg-displays integration
    - Cherry-pick the monitor management configuration hooks
    - Add nwg-displays as an optional package (not in default set)
    - _Requirements: 24.1, 24.2_

  - [x] 6.9 Import custom config auto-creation
    - Add empty placeholder creation for custom config files on first run
    - Update `source` directives in `execs.conf.template` to handle missing files gracefully
    - _Requirements: 25.1, 25.2, 25.3_

- [x] 7. Checkpoint — New features imported
  - Ensure all feature cherry-picks apply cleanly, ask the user if questions arise.

- [x] 8. Lua keybinds migration adaptation
  - [x] 8.1 Analyze upstream keybinds.lua for new/changed bindings
    - Compare upstream `keybinds.lua` against current `keybinds.conf.template`
    - Document new keybinds, removed keybinds, and syntax changes
    - _Requirements: 20.1_

  - [x] 8.2 Update keybinds.conf.template with upstream logical changes
    - Add new keybinds from upstream's Lua format as equivalent `.conf` syntax
    - Remove deprecated binds (equivalents of `hl.unbind()` calls)
    - Preserve all `@VARIABLE@` placeholders and `@CUSTOM_KEYBINDS@` injection point
    - _Requirements: 20.1, 20.2, 20.3_

  - [x] 8.3 Verify keybind equivalence between Lua source and conf.template
    - For each `hl.bind()` in upstream Lua, verify a matching `bind` entry exists in template
    - Document any intentionally skipped binds (Arch-specific, incompatible)
    - _Requirements: 20.1, 20.2_

- [x] 9. Home Manager module extensions
  - [x] 9.1 Add workspace widget variant option to quickshell-config.nix
    - Add `bar.workspaces.variant` option with type `enum [ "default" "hefty" ]`
    - Wire the option into the generated `Config.qml`
    - _Requirements: 13.3_

  - [x] 9.2 Add anti-flashbang strength option to quickshell-config.nix
    - Add `appearance.antiFlashbang` option with type `enum [ "off" "weak" "strong" ]`
    - Wire the option into the generated `Config.qml`
    - _Requirements: 15.2_

  - [x] 9.3 Add notification forceMonitor option to quickshell-config.nix
    - Add `notifications.forceMonitor` option with type `nullOr str`
    - Wire the option into the generated `Config.qml`
    - _Requirements: 16.3_

  - [x] 9.4 Add night light color temperature option to hyprland-config.nix
    - Add `night.colorTemperature` option with default 4500
    - Wire into hypridle/hyprsunset configuration template
    - _Requirements: 23.2_

  - [x] 9.5 Add dark/light toggle keybind option
    - Add `keybinds.darkLightToggle` boolean option
    - Conditionally include the Ctrl+Super+Shift+D bind in template processing
    - _Requirements: 17.1, 17.3_

  - [x] 9.6 Add nwg-displays package option
    - Add `packages.includeNwgDisplays` boolean option to home-manager module
    - Conditionally add `nwg-displays` to the package list when enabled
    - _Requirements: 24.2_

  - [x] 9.7 Update XDG_DATA_DIRS handling in home-manager.nix
    - Ensure session variable appends rather than overrides
    - Use proper Nix path concatenation for the `XDG_DATA_DIRS` value
    - _Requirements: 3.3_

  - [x] 9.8 Verify all existing Home Manager options preserved
    - Confirm all pre-sync options still have compatible types and defaults
    - Ensure no regressions in terminal, hyprland, or quickshell option modules
    - _Requirements: 21.7_

- [x] 10. Checkpoint — Module extensions complete
  - Ensure all new options are wired correctly, ask the user if questions arise.

- [x] 11. Preserve custom NixOS adaptations
  - [x] 11.1 Verify applycolor.sh custom functions intact
    - Confirm `apply_foot()`, `apply_fuzzel()`, `apply_wofi()` still present and functional
    - Confirm `kde-material-you-colors-wrapper.sh` integration preserved
    - _Requirements: 21.1, 21.6_

  - [x] 11.2 Verify RGB lighting, idle panel, and AppLauncher patch preserved
    - Confirm RGB lighting sync files untouched by cherry-picks
    - Confirm idle/power management panel QML present
    - Confirm AppLauncher PATH patch still applied
    - _Requirements: 21.2, 21.3, 21.4_

  - [x] 11.3 Verify systemd service and overlay configurations
    - Confirm quickshell systemd service file still generated
    - Confirm quickshell and kde-material-you-colors overlays still functional
    - _Requirements: 21.5, 21.6_

- [x] 12. Build testing and verification
  - [x] 12.1 Run `home-manager build` on sync branch
    - Execute `home-manager build --flake .#declarative` on the end-4-flakes sync branch
    - Fix any Nix evaluation errors, missing options, or broken references
    - _Requirements: All (build gate)_

  - [x] 12.2 Verify template placeholder integrity
    - Check all `.conf.template` files in `configs/hypr/` contain their required `@VARIABLE@` placeholders
    - Verify no placeholders were corrupted or removed during cherry-picks
    - _Requirements: 4.3, 7.4, 17.3, 20.3_

  - [x] 12.3 Verify custom config persistence mechanism
    - Confirm `source` directives handle missing custom config files without Hyprland errors
    - Confirm user-written content in custom config files survives `home-manager switch`
    - _Requirements: 25.2, 25.3_

  - [x] 12.4 Write property test for template placeholder integrity (Property 1)
    - **Property 1: Template Placeholder Integrity**
    - Generate random edits to template files; verify all required `@VAR@` patterns survive
    - Use `hypothesis` library
    - **Validates: Requirements 4.3, 7.4, 17.3, 20.3**

  - [x] 12.5 Write property test for wallpaper variant selection (Property 2)
    - **Property 2: Wallpaper Variant Selection**
    - Generate random filenames with/without `-dark`/`-light` suffixes and modes; verify correct selection
    - Use `hypothesis` library
    - **Validates: Requirements 14.1, 14.2, 14.3**

  - [x] 12.6 Write property test for custom keybind injection (Property 4)
    - **Property 4: Custom Keybind Injection**
    - Generate random multi-line keybind strings; substitute into template; verify presence
    - Use `hypothesis` library
    - **Validates: Requirements 20.3**

- [x] 13. Final checkpoint — Full verification
  - Ensure all tests pass, `home-manager build` succeeds, ask the user if questions arise.
  - Manual testing on esnixi: verify Quickshell starts, notifications work, keybinds functional, color pipeline runs.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation between phases
- Property tests validate universal correctness properties from the design document
- The sync uses selective cherry-pick — each commit is imported individually to isolate conflicts
- Rollback is always available: `git checkout quickshell-locked` (fork) or `git checkout main` (flake)
- The Lua keybinds migration (phase 8) maintains `.conf.template` as authoritative — no migration to `.lua` format
- Custom NixOS adaptations (RGB, idle panel, AppLauncher patch, color pipeline) are preserved unless upstream provides superior equivalents

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["2.1", "2.2", "2.3", "2.4", "2.5", "2.6", "2.7", "2.8", "2.9", "2.10"] },
    { "id": 2, "tasks": ["4.1", "4.2", "4.3", "4.4", "4.5"] },
    { "id": 3, "tasks": ["6.1", "6.2", "6.3", "6.4", "6.5", "6.6", "6.7", "6.8", "6.9"] },
    { "id": 4, "tasks": ["8.1"] },
    { "id": 5, "tasks": ["8.2", "8.3"] },
    { "id": 6, "tasks": ["9.1", "9.2", "9.3", "9.4", "9.5", "9.6", "9.7", "9.8"] },
    { "id": 7, "tasks": ["11.1", "11.2", "11.3"] },
    { "id": 8, "tasks": ["12.1"] },
    { "id": 9, "tasks": ["12.2", "12.3", "12.4", "12.5", "12.6"] }
  ]
}
```
