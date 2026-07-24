# Requirements Document

## Introduction

The AI Desktop Control feature extends the ii-desktop MCP server and Quickshell sidebar AI with comprehensive desktop environment control capabilities. The AI gains the ability to modify visual theming (Material You colors, wallpapers), Hyprland compositor settings (gaps, borders, animations, window rules, keybinds), monitor layout, and Bluetooth device management. A disaster recovery system maintains a rolling history of changes with rollback support, ensuring safe experimentation. The feature also includes device awareness (monitors, audio, input, USB) with event-driven reactions, and an application integration registry that catalogs programmable interfaces across installed software.

This builds on the existing ii-desktop MCP infrastructure (config_read, config_set, set_keyword, dispatch_command, audio tools, network tools) and the McpClient.qml tool dispatch pipeline in Quickshell.

## Glossary

- **MCP_Server**: The ii-desktop-mcp Python process that exposes tools over the Model Context Protocol
- **MCP_Client**: Any consumer connecting to the MCP_Server (Quickshell sidebar AI, external MCP clients)
- **Change_Ledger**: A persistent JSON file that records the last N applied changes with sufficient metadata to reverse each one
- **Change_Entry**: A single record in the Change_Ledger containing the tool invoked, parameters used, the previous state captured before modification, and a timestamp
- **Rollback_Engine**: The subsystem responsible for reading the Change_Ledger and applying inverse operations to restore previous state
- **Theme_Controller**: The component that manages Material You color scheme generation via matugen and wallpaper changes via switchwall
- **Matugen**: The Material You color scheme generator that derives a full color palette from a source image or color
- **Switchwall**: The script/tool that sets wallpapers and optionally triggers matugen for derived theming
- **Hyprland_Keyword**: A Hyprland configuration keyword that can be set at runtime via `hyprctl keyword` without reloading the full config
- **Monitor_Profile**: A named configuration specifying resolution, refresh rate, position, and scale for a specific monitor identified by name or description
- **Bluetooth_Controller**: The subsystem that interfaces with bluetoothctl or D-Bus to manage Bluetooth device pairing, connecting, and disconnecting
- **Device_Registry**: A live inventory of connected hardware (monitors, audio sinks/sources, input devices, USB peripherals) maintained by polling or event subscription
- **App_Integration_Registry**: A persistent catalog of installed applications with their programmable interfaces (D-Bus, CLI, socket, API) that the AI can use for automation
- **Shell_Config**: The JSON configuration file at ~/.config/quickshell/ii/user/config.json managed by Quickshell

## Requirements

### Requirement 1: Material You Theming Control

**User Story:** As a user, I want the AI to change my desktop color scheme and wallpaper through natural language commands, so that I can restyle my environment without manual configuration.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `theme_apply_wallpaper` tool that accepts a required `path` string parameter (absolute path to an image file) and an optional `scheme` parameter (one of "tonalSpot", "content", "expressive", "fidelity", "neutral", "monochrome", "vibrant", "rainbow", "fruitSalad") defaulting to "tonalSpot"
2. WHEN the `theme_apply_wallpaper` tool is invoked with a valid image path, THE Theme_Controller SHALL execute switchwall with the specified image and matugen with the specified scheme variant, applying the resulting color palette to the desktop environment
3. IF the specified image path does not exist or is not a readable image file, THEN THE MCP_Server SHALL return an error response with code "not_found" indicating the image file was not accessible
4. THE MCP_Server SHALL expose a `theme_apply_color` tool that accepts a required `color` string parameter (hex color code in #RRGGBB format) and an optional `scheme` parameter (same variants as above) defaulting to "tonalSpot"
5. WHEN the `theme_apply_color` tool is invoked with a valid hex color, THE Theme_Controller SHALL execute matugen with the specified color as the seed, generating and applying a Material You color palette without changing the wallpaper
6. IF the `color` parameter does not match the pattern `#[0-9A-Fa-f]{6}`, THEN THE MCP_Server SHALL return an error response with code "validation_error" indicating the color format is invalid
7. THE MCP_Server SHALL expose a `theme_get_current` tool that accepts no parameters and returns the current active color palette (primary, secondary, tertiary, surface, background colors), the current wallpaper path, and the active scheme variant
8. WHEN a theme change is applied, THE Theme_Controller SHALL record the change in the Change_Ledger before applying, capturing the previous wallpaper path and color palette as the rollback state

### Requirement 2: Hyprland Runtime Configuration

**User Story:** As a user, I want the AI to adjust Hyprland compositor settings at runtime, so that I can tweak gaps, borders, animations, and window rules through conversation.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `hypr_set_option` tool that accepts a required `keyword` string parameter (a valid Hyprland keyword path such as "general:gaps_in", "decoration:rounding", "animations:enabled") and a required `value` string parameter
2. WHEN the `hypr_set_option` tool is invoked, THE MCP_Server SHALL record the current value of the keyword in the Change_Ledger before applying the new value via `hyprctl keyword`
3. THE MCP_Server SHALL expose a `hypr_get_option` tool that accepts a required `keyword` string parameter and returns the current runtime value of that Hyprland keyword by parsing `hyprctl getoption` output
4. THE MCP_Server SHALL expose a `hypr_add_window_rule` tool that accepts a required `rule` string parameter (e.g., "float") and a required `match` string parameter (e.g., "class:^(pavucontrol)$") and applies the rule via `hyprctl keyword windowrulev2`
5. WHEN the `hypr_add_window_rule` tool is invoked, THE MCP_Server SHALL record the rule in the Change_Ledger so it can be removed on rollback
6. THE MCP_Server SHALL expose a `hypr_remove_window_rule` tool that accepts a required `rule` string parameter and a required `match` string parameter and removes the rule via `hyprctl keyword windowrulev2 unset`
7. THE MCP_Server SHALL expose a `hypr_set_animation` tool that accepts a required `name` string parameter (animation name such as "windows", "fade", "border"), a required `enabled` boolean parameter, and optional `speed` (float), `curve` (string), and `style` (string) parameters
8. WHEN the `hypr_set_animation` tool is invoked, THE MCP_Server SHALL record the previous animation configuration in the Change_Ledger and apply the new animation via `hyprctl keyword animation`
9. IF `hyprctl getoption` returns an error for a given keyword, THEN THE MCP_Server SHALL return an error response with code "not_found" indicating the keyword is not recognized by Hyprland

### Requirement 3: Disaster Recovery and Rollback

**User Story:** As a user, I want to undo recent AI-applied changes to my desktop, so that I can safely experiment knowing I can always go back.

#### Acceptance Criteria

1. THE Change_Ledger SHALL persist as a JSON file at ~/.local/state/ii-desktop/change-ledger.json
2. THE Change_Ledger SHALL store a maximum of 50 change entries, removing the oldest entries when the limit is exceeded (FIFO eviction)
3. EACH Change_Entry SHALL contain: a unique ID (UUID), a timestamp (ISO 8601), the tool name that was invoked, the parameters that were passed, the captured previous state sufficient to reverse the change, and a human-readable description of the change
4. THE MCP_Server SHALL expose a `rollback_last` tool that accepts an optional `count` integer parameter (1 to 50) defaulting to 1, and reverses the most recent N changes in reverse chronological order
5. WHEN the `rollback_last` tool is invoked, THE Rollback_Engine SHALL apply the inverse operation for each Change_Entry being rolled back, verify the rollback succeeded, and remove the entries from the Change_Ledger
6. THE MCP_Server SHALL expose a `rollback_by_id` tool that accepts a required `id` string parameter (UUID) and reverses only the specified Change_Entry regardless of its position in the history
7. WHEN the `rollback_by_id` tool is invoked with a valid ID, THE Rollback_Engine SHALL apply the inverse operation, verify success, and remove the entry from the Change_Ledger
8. IF a rollback operation fails (the inverse command returns an error), THEN THE Rollback_Engine SHALL return an error response describing which change could not be reversed and preserve the Change_Entry in the ledger
9. THE MCP_Server SHALL expose a `rollback_list` tool that accepts no parameters and returns the current Change_Ledger entries (ID, timestamp, description, tool name) in reverse chronological order
10. WHEN a rollback is performed, THE Rollback_Engine SHALL NOT record the rollback itself as a new Change_Entry (rollbacks are not themselves rollbackable)
11. IF the `rollback_by_id` tool is invoked with an ID that does not exist in the Change_Ledger, THEN THE MCP_Server SHALL return an error response with code "not_found"

### Requirement 4: Monitor Layout Control

**User Story:** As a user, I want the AI to manage my monitor configuration (resolution, position, scale, refresh rate), so that I can adjust my display setup through conversation.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `monitor_list` tool that accepts no parameters and returns a JSON array of connected monitors with their name, description, current resolution, refresh rate, position (x, y), scale, and active status
2. THE MCP_Server SHALL expose a `monitor_set` tool that accepts a required `name` string parameter (monitor name as reported by Hyprland, e.g., "DP-1", "HDMI-A-1"), and optional parameters: `resolution` (string, e.g., "2560x1440"), `refresh_rate` (float, e.g., 144.0), `position` (string, e.g., "0x0" or "auto"), and `scale` (float, e.g., 1.0 or 1.5)
3. WHEN the `monitor_set` tool is invoked, THE MCP_Server SHALL record the current monitor configuration in the Change_Ledger before applying the new configuration via `hyprctl keyword monitor`
4. WHEN the `monitor_set` tool is invoked with valid parameters, THE MCP_Server SHALL construct and execute the appropriate `hyprctl keyword monitor` command combining the specified parameters with current values for unspecified parameters
5. IF the specified monitor `name` does not match any connected monitor, THEN THE MCP_Server SHALL return an error response with code "not_found" indicating the monitor is not connected
6. THE MCP_Server SHALL expose a `monitor_save_profile` tool that accepts a required `profile_name` string parameter and saves the current multi-monitor layout as a named Monitor_Profile in ~/.local/state/ii-desktop/monitor-profiles.json
7. THE MCP_Server SHALL expose a `monitor_load_profile` tool that accepts a required `profile_name` string parameter and applies the saved Monitor_Profile, recording the pre-application state in the Change_Ledger
8. IF the `monitor_load_profile` tool is invoked with a profile name that does not exist, THEN THE MCP_Server SHALL return an error response with code "not_found"

### Requirement 5: Bluetooth Device Management

**User Story:** As a user, I want the AI to manage my Bluetooth devices (scan, pair, connect, disconnect), so that I can control peripherals through natural language.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `bluetooth_status` tool that accepts no parameters and returns the Bluetooth adapter state (powered on/off, discovering yes/no) and a list of known (paired) devices with their name, MAC address, connection status, and device type (audio, input, other)
2. THE MCP_Server SHALL expose a `bluetooth_scan` tool that accepts an optional `duration` integer parameter (seconds, default 10, maximum 30) and initiates a discovery scan, returning newly discovered devices with their name, MAC address, and signal strength
3. THE MCP_Server SHALL expose a `bluetooth_connect` tool that accepts a required `address` string parameter (MAC address) and attempts to connect to the specified device
4. WHEN the `bluetooth_connect` tool is invoked for a device that is not yet paired, THE Bluetooth_Controller SHALL attempt to pair first and then connect
5. THE MCP_Server SHALL expose a `bluetooth_disconnect` tool that accepts a required `address` string parameter and disconnects the specified device
6. THE MCP_Server SHALL expose a `bluetooth_remove` tool that accepts a required `address` string parameter and removes the device from the paired devices list
7. IF the Bluetooth adapter is powered off, THEN THE MCP_Server SHALL return an error response with code "unavailable" indicating Bluetooth is disabled
8. IF the specified device address is not reachable or pairing fails, THEN THE MCP_Server SHALL return an error response with code "internal_error" including the bluetoothctl error output
9. WHEN a Bluetooth connection or disconnection succeeds, THE Bluetooth_Controller SHALL record the state change in the Change_Ledger (capturing the previous connection state for rollback)

### Requirement 6: Application Integration Discovery

**User Story:** As a user, I want the AI to discover which installed applications have programmable interfaces, so that it can automate interactions with my software ecosystem.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose an `apps_discover_interfaces` tool that accepts an optional `rescan` boolean parameter (default false) and returns the App_Integration_Registry contents
2. WHEN `rescan` is true, THE MCP_Server SHALL scan the system for application integration points by: enumerating D-Bus session services and their interfaces, searching for CLI tools associated with installed .desktop entries, checking for known socket or API endpoints (e.g., ~/.mozilla for Firefox, playerctl for MPRIS)
3. THE App_Integration_Registry SHALL persist as a JSON file at ~/.local/state/ii-desktop/app-registry.json
4. EACH entry in the App_Integration_Registry SHALL contain: the application name, desktop entry ID (if applicable), a list of integration interfaces (type: "dbus" | "cli" | "socket" | "api"), interface details (bus name, object path, CLI command, socket path), and a list of supported operations described in plain text
5. THE MCP_Server SHALL expose an `apps_get_interface` tool that accepts a required `app_name` string parameter and returns the detailed integration information for that specific application from the registry
6. IF the requested application is not in the registry, THEN THE MCP_Server SHALL return an error response with code "not_found"
7. WHEN performing a rescan, THE MCP_Server SHALL complete the discovery within 30 seconds, returning partial results with a warning if the scan times out
8. THE App_Integration_Registry SHALL include at minimum: media players (MPRIS via D-Bus), terminal emulators (CLI), file managers (D-Bus and CLI), browsers (CLI), and system services (systemctl CLI)

### Requirement 7: Device Awareness and Event Reactions

**User Story:** As a user, I want the AI to maintain awareness of connected devices and react to hardware events, so that my desktop adapts automatically when peripherals change.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `devices_list` tool that accepts an optional `category` parameter (one of "monitors", "audio", "input", "usb", "bluetooth", "all" defaulting to "all") and returns the current Device_Registry contents for the specified category
2. THE Device_Registry SHALL include: connected monitors (from hyprctl monitors), audio sinks and sources (from wpctl/pactl), input devices (keyboards, mice, tablets from hyprctl devices), USB devices (from lsusb or /sys/bus/usb), and paired Bluetooth devices
3. THE MCP_Server SHALL expose a `devices_set_reaction` tool that accepts a required `event` string parameter (one of "monitor_connected", "monitor_disconnected", "audio_device_connected", "audio_device_disconnected", "bluetooth_connected", "bluetooth_disconnected"), a required `action` string parameter (a tool name to invoke), and a required `action_args` object parameter (arguments to pass to the tool)
4. WHEN a configured device event occurs, THE MCP_Server SHALL automatically invoke the specified action tool with the specified arguments
5. THE MCP_Server SHALL expose a `devices_list_reactions` tool that returns all configured event reactions
6. THE MCP_Server SHALL expose a `devices_remove_reaction` tool that accepts a required `event` string parameter and removes the configured reaction for that event
7. Device reactions SHALL persist in ~/.local/state/ii-desktop/device-reactions.json so they survive service restarts
8. IF a reaction tool invocation fails, THEN THE MCP_Server SHALL log the failure and emit a notification but SHALL NOT crash or disable the reaction

### Requirement 8: Change Ledger Integration for All Mutations

**User Story:** As a developer, I want all state-mutating MCP tools to record their changes in the Change_Ledger, so that any AI-initiated modification can be tracked and reversed.

#### Acceptance Criteria

1. WHEN any of the following tools are invoked successfully, THE MCP_Server SHALL create a Change_Entry in the Change_Ledger before returning: theme_apply_wallpaper, theme_apply_color, hypr_set_option, hypr_add_window_rule, hypr_set_animation, monitor_set, monitor_load_profile, bluetooth_connect, bluetooth_disconnect, config_set, audio_set_volume
2. EACH Change_Entry SHALL capture sufficient previous state to fully reverse the operation (the prior wallpaper path, prior keyword value, prior monitor config, prior connection state, prior config value, prior volume level)
3. THE Rollback_Engine SHALL support inverse operations for each recorded tool: restoring wallpaper/color, resetting hyprctl keywords, re-applying monitor config, reconnecting/disconnecting Bluetooth, resetting config values, and restoring volume
4. IF the Change_Ledger file does not exist when a write is attempted, THEN THE MCP_Server SHALL create the file and its parent directory
5. IF the Change_Ledger file is corrupt (malformed JSON), THEN THE MCP_Server SHALL log a warning, move the corrupt file to a .bak suffix, and start a fresh ledger

### Requirement 9: Security and Safety Constraints

**User Story:** As a user, I want the AI desktop control to operate within safe boundaries, so that automation cannot damage my system or expose sensitive data.

#### Acceptance Criteria

1. THE MCP_Server SHALL NOT execute arbitrary shell commands through any tool exposed by this feature
2. THE MCP_Server SHALL validate all file path parameters to reject paths containing ".." traversal sequences or symlinks pointing outside the user's home directory
3. THE theme_apply_wallpaper tool SHALL only accept image files with extensions matching: .png, .jpg, .jpeg, .webp, .bmp, .gif, .tiff
4. THE MCP_Server SHALL NOT expose Bluetooth device PINs, pairing keys, or link keys in any tool response
5. THE hypr_set_option tool SHALL maintain a denylist of dangerous keywords that cannot be modified (including but not limited to: "exec", "exec-once", "bind", "plugin") and SHALL return an error with code "validation_error" if a denylisted keyword is targeted
6. THE monitor_set tool SHALL validate that the specified resolution and refresh rate are supported by the monitor (by checking against `hyprctl monitors` available modes) before applying
7. IF a Bluetooth scan discovers devices, THE MCP_Server SHALL NOT automatically pair or connect without an explicit bluetooth_connect tool invocation
8. THE MCP_Server SHALL rate-limit theme changes to a maximum of 5 per minute to prevent rapid flickering or resource exhaustion from matugen executions

