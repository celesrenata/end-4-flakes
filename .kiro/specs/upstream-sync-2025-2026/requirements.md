# Requirements Document

## Introduction

This specification covers syncing the NixOS fork (`end-4-flakes`) of end-4/dots-hyprland with ~11 months of upstream changes (August 2025 → July 2026). The sync must import new features, critical bug fixes, and structural changes while preserving all custom NixOS adaptations including the template system, Home Manager modules, custom color management, RGB lighting sync, idle/power management panel, and AppLauncher PATH compatibility.

## Glossary

- **Upstream**: The original end-4/dots-hyprland repository (source of truth for non-NixOS features)
- **Fork**: The user's custom NixOS adaptation at `/home/celes/sources/celesrenata/dots-hyprland` (branch `quickshell-locked`)
- **Flake_Wrapper**: The NixOS flake at `/home/celes/sources/celesrenata/end-4-flakes` that wraps fork configs into Home Manager modules
- **Template_System**: The `.conf.template` file convention using `@VARIABLE@` placeholders processed by Nix at build time
- **Quickshell**: The Qt/QML-based desktop shell used by dots-hyprland for bar, sidebars, overview, and notifications
- **Matugen**: Material You color generation tool that produces color schemes from wallpaper images
- **Applycolor_Pipeline**: The custom script pipeline (`applycolor.sh`, `switchwall.sh`) that applies generated colors to foot, fuzzel, wofi, and terminal escape sequences
- **Keybinds_Lua**: The new upstream format (`.lua`) for Hyprland keybindings, replacing the legacy `.conf` format
- **Home_Manager_Module**: The Nix module system (`home-manager.nix` and component modules) that declaratively manages configuration
- **Anti_Flashbang**: A feature that displays a dark overlay during workspace transitions to prevent bright flashes

## Requirements

### Requirement 1: Branch Management for Sync Work

**User Story:** As a developer, I want all sync work performed on dedicated new branches in both repositories, so that my existing working configurations remain untouched until the sync is verified.

#### Acceptance Criteria

1. WHEN the upstream sync begins, THE Fork SHALL create a new branch (e.g., `upstream-sync-2026`) from the current `quickshell-locked` branch in the dots-hyprland repository
2. WHEN the upstream sync begins, THE Flake_Wrapper SHALL create a new branch (e.g., `upstream-sync-2026`) from the current working branch in the end-4-flakes repository
3. THE Fork SHALL NOT modify the `quickshell-locked` branch until the sync branch is tested and explicitly merged
4. THE Flake_Wrapper SHALL NOT modify its main working branch until the sync branch is tested and explicitly merged
5. WHEN all sync changes are verified, THE Fork SHALL be mergeable back into `quickshell-locked` via a standard merge or rebase workflow

### Requirement 2: Import Qt 6.11 NotificationItem Fix

**User Story:** As a user, I want the Qt 6.11 `NotificationItem` infinite loop fix applied, so that my right sidebar does not freeze when receiving notifications.

#### Acceptance Criteria

1. WHEN the Quickshell notification sidebar receives a notification on Qt 6.11+, THE Flake_Wrapper SHALL render the notification without triggering a `polish()` infinite loop
2. WHEN the notification fix is applied, THE Flake_Wrapper SHALL preserve existing notification display behavior for Qt versions below 6.11
3. IF a notification causes excessive `polish()` calls, THEN THE Quickshell SHALL break the recursion cycle and display the notification in a degraded but functional state

### Requirement 3: Import XDG_DATA_DIRS Fix

**User Story:** As a NixOS user, I want the XDG_DATA_DIRS expansion fix applied, so that application launchers and gsettings schemas resolve correctly on NixOS.

#### Acceptance Criteria

1. THE Flake_Wrapper SHALL NOT override the `XDG_DATA_DIRS` environment variable when it is already set by the system
2. WHEN `XDG_DATA_DIRS` is referenced in Quickshell scripts or Hyprland configs, THE Flake_Wrapper SHALL expand the variable correctly without shell-quoting issues
3. THE Home_Manager_Module SHALL append to `XDG_DATA_DIRS` using proper Nix path concatenation rather than overwriting it

### Requirement 4: Import Hyprland Lua-Schema Compatibility

**User Story:** As a user, I want hypridle and hyprsunset dispatch commands updated, so that idle management and night light work with current Hyprland versions.

#### Acceptance Criteria

1. WHEN the `hypridle.conf.template` references dispatch commands, THE Template_System SHALL use the Lua-schema compatible syntax (e.g., `dispatch dpms` instead of legacy format)
2. WHEN `hyprsunset` is dispatched, THE Template_System SHALL use the corrected default color temperature value
3. THE Flake_Wrapper SHALL preserve the existing `@VARIABLE@` placeholder pattern in the updated `hypridle.conf.template`

### Requirement 5: Import Multi-Monitor Screen Corners Fix

**User Story:** As a multi-monitor user, I want screen corner rendering fixed, so that decorative corners display correctly across all connected displays.

#### Acceptance Criteria

1. WHEN multiple monitors are connected, THE Quickshell SHALL render screen corner decorations on each monitor independently
2. WHEN monitor scale differs between displays, THE Quickshell SHALL adjust corner rendering to respect per-monitor scale values

### Requirement 6: Import DPMS and Monitor Scale Fixes

**User Story:** As a user, I want DPMS syntax and monitor scale type fixes applied, so that display power management and fractional scaling work correctly.

#### Acceptance Criteria

1. WHEN a DPMS command is issued via keybind or idle timeout, THE Template_System SHALL use the corrected DPMS dispatch syntax
2. WHEN monitors use fractional scaling, THE Flake_Wrapper SHALL pass scale values as the correct numeric type (float, not integer)

### Requirement 7: Import Keybind Fixes

**User Story:** As a user, I want all upstream keybind fixes applied, so that raw keycodes, fullscreen/maximize syntax, and super+alt+workspace bindings work correctly.

#### Acceptance Criteria

1. WHEN raw keycodes are used in keybinds, THE Template_System SHALL use the corrected `code:` prefix syntax
2. WHEN the fullscreen or maximize keybind is pressed, THE Template_System SHALL use the updated `fullscreen`/`fullscreenstate` dispatcher syntax
3. WHEN Super+Alt+workspace number is pressed, THE Template_System SHALL dispatch `movetoworkspacesilent` using the corrected argument format
4. THE Template_System SHALL preserve all custom `@VARIABLE@` placeholders in keybind entries

### Requirement 8: Import Clipboard Escaped Text Fix

**User Story:** As a user, I want the clipboard escaped text display fix applied, so that copied text with special characters displays correctly in the clipboard history.

#### Acceptance Criteria

1. WHEN clipboard history contains text with escape sequences or special characters, THE Quickshell SHALL display the text with proper escaping in the clipboard viewer
2. WHEN a clipboard entry with special characters is selected, THE Quickshell SHALL paste the original unescaped content

### Requirement 9: Import Super Key Hold State Fix

**User Story:** As a user, I want the Super key hold state fix applied, so that the overview/workspace number display responds correctly to key press and release events.

#### Acceptance Criteria

1. WHEN the Super key is held down, THE Quickshell SHALL display workspace numbers on the bar
2. WHEN the Super key is released without pressing another key, THE Quickshell SHALL dismiss the workspace number display
3. WHEN the Super key is released after pressing another key (e.g., Super+1), THE Quickshell SHALL NOT trigger the overview toggle

### Requirement 10: Import Konachan/Waifu.im Fixes

**User Story:** As a user, I want the booru image search fixes applied, so that Konachan and waifu.im tag searches and User-Agent headers work correctly.

#### Acceptance Criteria

1. WHEN the sidebar booru panel queries Konachan or waifu.im, THE Quickshell SHALL send a valid User-Agent header that is accepted by the remote service
2. WHEN a tag search is performed, THE Quickshell SHALL correctly encode and transmit multi-word tags

### Requirement 11: Import HOME Environment Fix for Lua Configs

**User Story:** As a user, I want the HOME environment variable fix applied to Lua configs, so that path expansion works correctly in Hyprland Lua configuration files.

#### Acceptance Criteria

1. WHEN Hyprland Lua configuration files reference the user's home directory, THE Flake_Wrapper SHALL ensure the `HOME` environment variable is available and correctly resolved
2. THE Template_System SHALL handle HOME path references in both `.conf.template` and any new `.lua` configuration files

### Requirement 12: Remove Redundant Sleep Delays

**User Story:** As a user, I want the unnecessary `sleep 0` delays removed, so that wallpaper switching and color application complete faster.

#### Acceptance Criteria

1. THE Applycolor_Pipeline SHALL NOT include `sleep 0` or other zero-duration delays in the color application sequence
2. WHEN wallpaper colors are applied, THE Applycolor_Pipeline SHALL complete the full pipeline without artificial delays

### Requirement 13: Import Bar Workspaces Widget (Hefty)

**User Story:** As a user, I want the new "hefty" bar workspaces widget imported, so that I have access to the improved workspace indicator with app icons.

#### Acceptance Criteria

1. WHEN the bar is displayed, THE Quickshell SHALL render the new workspace widget with application icons per workspace
2. WHEN the workspace widget configuration option is set to "hefty", THE Quickshell SHALL display the enhanced workspace layout
3. THE Home_Manager_Module SHALL expose a configuration option to select between workspace widget variants

### Requirement 14: Import Light/Dark Wallpaper Variant Switching

**User Story:** As a user, I want automatic light/dark wallpaper variant selection based on filename suffix, so that the wallpaper matches my current color scheme mode.

#### Acceptance Criteria

1. WHEN a wallpaper file has a `-dark` or `-light` suffix (e.g., `forest-dark.jpg`, `forest-light.jpg`), THE Applycolor_Pipeline SHALL select the variant matching the current mode
2. WHEN the dark/light mode is toggled, THE Applycolor_Pipeline SHALL switch to the corresponding wallpaper variant if one exists
3. WHEN no variant suffix exists for the current wallpaper, THE Applycolor_Pipeline SHALL use the wallpaper as-is for both modes

### Requirement 15: Import Anti-Flashbang Variant (Weak)

**User Story:** As a user, I want the weak anti-flashbang option available, so that I can reduce bright flashes during workspace transitions without a fully opaque overlay.

#### Acceptance Criteria

1. WHEN the anti-flashbang setting is set to "weak", THE Quickshell SHALL display a semi-transparent dark overlay during workspace transitions
2. THE Home_Manager_Module SHALL expose a configuration option for anti-flashbang strength (off, weak, strong)

### Requirement 16: Import Notification Force Monitor

**User Story:** As a multi-monitor user, I want to configure which monitor displays notifications, so that notifications appear on my preferred screen.

#### Acceptance Criteria

1. WHERE the `forceMonitor` config option is set, THE Quickshell SHALL display all notifications on the specified monitor
2. WHEN `forceMonitor` is not configured, THE Quickshell SHALL display notifications on the focused monitor
3. THE Home_Manager_Module SHALL expose a `forceMonitor` configuration option for notifications

### Requirement 17: Import Dark/Light Toggle Keybind

**User Story:** As a user, I want the Ctrl+Super+Shift+D keybind to toggle dark/light mode, so that I can quickly switch color schemes.

#### Acceptance Criteria

1. WHEN Ctrl+Super+Shift+D is pressed, THE Template_System SHALL dispatch the dark/light mode toggle action
2. WHEN dark/light mode is toggled, THE Applycolor_Pipeline SHALL regenerate colors with the new mode and apply them to all themed applications
3. THE Template_System SHALL include the toggle keybind in the `keybinds.conf.template` with the `@VARIABLE@` pattern preserved

### Requirement 18: Import Emoji 17.0 Update

**User Story:** As a user, I want the emoji list updated to Unicode 17.0, so that I can search and paste the latest emoji characters.

#### Acceptance Criteria

1. WHEN the emoji picker is opened (Super+Period), THE Quickshell SHALL display emoji characters from Unicode Emoji 17.0
2. THE Flake_Wrapper SHALL include the updated emoji data file in the Quickshell configuration

### Requirement 19: Import Cheatsheet Category Improvements

**User Story:** As a user, I want the cheatsheet category display improvements applied, so that keyboard shortcuts are organized clearly by category.

#### Acceptance Criteria

1. WHEN the cheatsheet is opened (Super+Slash), THE Quickshell SHALL display keybinds grouped by their section heading (e.g., Shell, Window, Workspace, Apps)
2. WHEN a category is displayed, THE Quickshell SHALL render category headers with improved visual distinction

### Requirement 20: Adapt Keybinds Lua Format to Template System

**User Story:** As a NixOS user, I want the new upstream Lua keybind format adapted to work with the NixOS template system, so that Nix-managed binary paths and custom keybinds continue to work.

#### Acceptance Criteria

1. WHEN upstream provides keybinds in `.lua` format, THE Template_System SHALL either adapt the Lua content to use `@VARIABLE@` placeholders or maintain a parallel `.conf.template` that produces equivalent bindings
2. THE Template_System SHALL support the `hl.unbind()` function for removing default keybinds
3. WHEN custom keybinds are defined via `@CUSTOM_KEYBINDS@`, THE Template_System SHALL inject them at the appropriate location in the final keybind configuration
4. THE Home_Manager_Module SHALL continue to resolve `@TERMINAL_APPS@`, `@BROWSER_APPS@`, `@QUICKSHELL_BIN@`, and other binary path placeholders to Nix store paths

### Requirement 21: Preserve or Upgrade Custom NixOS Adaptations

**User Story:** As a NixOS user, I want my custom features preserved during the upstream sync unless upstream provides a superior implementation, so that my desktop environment benefits from the best of both codebases.

#### Acceptance Criteria

1. THE Flake_Wrapper SHALL preserve the custom `applycolor.sh` pipeline with foot, fuzzel, and wofi theming support unless upstream introduces equivalent or better terminal theming
2. THE Flake_Wrapper SHALL preserve the RGB lighting sync functionality (no upstream equivalent exists)
3. THE Flake_Wrapper SHALL preserve the idle/power management settings panel (no upstream equivalent exists)
4. THE Flake_Wrapper SHALL preserve the `AppLauncherPatch` for NixOS PATH compatibility unless upstream resolves PATH handling for non-standard systems
5. THE Flake_Wrapper SHALL preserve the systemd service configuration for Quickshell
6. THE Flake_Wrapper SHALL preserve the `kde-material-you-colors` patches for non-Plasma systems
7. THE Home_Manager_Module SHALL preserve all existing configuration options (terminal settings, hyprland settings, quickshell appearance)
8. WHEN upstream changes conflict with custom adaptations, THE Flake_Wrapper SHALL adopt the upstream implementation if it provides equivalent or superior functionality, and preserve the custom implementation otherwise
9. WHEN an upstream improvement supersedes a custom adaptation, THE Flake_Wrapper SHALL document which custom code was replaced and why in the commit message

### Requirement 22: Import Structural Cleanup

**User Story:** As a user, I want upstream structural cleanups applied, so that unused scripts and redundant configuration are removed.

#### Acceptance Criteria

1. THE Flake_Wrapper SHALL remove the JetBrains windowrule from Hyprland rules configuration
2. THE Flake_Wrapper SHALL remove the unnecessary unlock refocus hack
3. THE Flake_Wrapper SHALL integrate the "custom stuff made optional" pattern so that user customizations do not conflict with base configuration
4. THE Flake_Wrapper SHALL remove redundant scripts that upstream has deprecated
5. WHEN a removed script or config is referenced by a NixOS module, THE Home_Manager_Module SHALL update the reference or remove the dependency

### Requirement 23: Import Hyprsunset Default Color Temperature Fix

**User Story:** As a user, I want the corrected default color temperature for hyprsunset, so that night light activates with a reasonable warmth level.

#### Acceptance Criteria

1. WHEN hyprsunset is activated via night light settings, THE Flake_Wrapper SHALL use the corrected default color temperature value from upstream
2. THE Home_Manager_Module SHALL expose the color temperature as a configurable option with the corrected default

### Requirement 24: Import nwg-displays Integration

**User Story:** As a user, I want nwg-displays integration from upstream, so that I can manage monitor layouts through a graphical tool.

#### Acceptance Criteria

1. WHEN nwg-displays is launched, THE Flake_Wrapper SHALL provide the necessary Hyprland configuration hooks for monitor management
2. THE Home_Manager_Module SHALL optionally include `nwg-displays` in the package set

### Requirement 25: Import Custom Config Auto-Creation

**User Story:** As a user, I want custom config files auto-created on first run, so that Hyprland does not error on missing custom configuration includes.

#### Acceptance Criteria

1. WHEN Hyprland starts and custom config files do not exist, THE Flake_Wrapper SHALL create empty placeholder custom config files
2. THE Template_System SHALL include `source` directives for custom config files that gracefully handle missing files
3. WHEN the user adds content to custom config files, THE Flake_Wrapper SHALL preserve that content across home-manager rebuilds

