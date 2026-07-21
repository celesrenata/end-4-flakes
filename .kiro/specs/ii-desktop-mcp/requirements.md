# Requirements Document

## Introduction

The ii-desktop-mcp server is a comprehensive desktop intelligence MCP (Model Context Protocol) server for the Quickshell-based Hyprland desktop environment. It extends the existing hyprmcp project (which provides Hyprland compositor control via hyprctl) with tools for querying and managing the broader desktop state: Quickshell configuration, audio, networking, systemd services, clipboard history, application discovery, diagnostics, shell logs, screenshots, and system information.

The server enables AI clients (the Quickshell sidebar chat, the Action Palette, and external MCP clients like Kiro) to query structured desktop state and safely perform configuration changes without resorting to arbitrary shell commands. It runs as a systemd user service communicating over stdio transport.

## Glossary

- **MCP_Server**: The ii-desktop-mcp Python process that exposes tools over the Model Context Protocol stdio transport
- **MCP_Client**: Any consumer connecting to the MCP_Server (Quickshell sidebar AI, Action Palette, Kiro IDE, or other MCP-compatible clients)
- **Shell_Config**: The JSON configuration file at ~/.config/quickshell/ii/user/config.json managed by Quickshell's Config.qml FileView, containing namespaced settings (appearance, bar, search, apps, ai, policies, sidebar, time, etc.)
- **Tool**: A discrete MCP tool exposed by the MCP_Server that performs a single well-defined operation and returns structured JSON
- **PipeWire**: The audio server used on the system, accessed via wpctl (WirePlumber) or pactl commands
- **NetworkManager**: The system network management daemon, accessed via nmcli
- **Cliphist**: The clipboard history manager for Wayland compositors, storing clipboard entries accessible via the cliphist command
- **Desktop_Entry**: A .desktop file conforming to the freedesktop.org Desktop Entry Specification, used for application discovery and launching
- **Diagnostic_Bundle**: A comprehensive JSON snapshot combining system state from multiple tools for troubleshooting
- **Quickshell**: The QML-based shell framework running on Hyprland that provides the status bar, sidebar, overview, and action palette
- **Grim**: A screenshot utility for Wayland compositors that captures screen regions, windows, or full monitors

## Requirements

### Requirement 1: Quickshell Config Read

**User Story:** As an MCP_Client, I want to read the current Quickshell configuration state, so that I can understand the user's desktop settings and provide context-aware responses.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `config_read` tool that accepts an optional `namespace` string parameter representing a dot-separated config path prefix (e.g., "appearance", "bar.workspaces") with a maximum length of 256 characters
2. WHEN the `config_read` tool is invoked without a `namespace` parameter, THE MCP_Server SHALL return the entire Shell_Config as a JSON object
3. WHEN the `config_read` tool is invoked with a valid `namespace` parameter, THE MCP_Server SHALL return only the subset of the Shell_Config rooted at that namespace path
4. WHEN the `config_read` tool is invoked with a `namespace` that does not exist in the Shell_Config, THE MCP_Server SHALL return an error response with code "not_found" indicating the namespace was not found
5. THE MCP_Server SHALL read the Shell_Config from the file at ~/.config/quickshell/ii/user/config.json
6. THE MCP_Server SHALL redact the values of keys matching `ai.systemPrompt`, any key containing `key` or `secret` (case-insensitive), and any key within `sidebar.booru.zerochan` by replacing each redacted value with the string "[REDACTED]" before returning the config to the MCP_Client
7. IF the Shell_Config file does not exist or is not readable, THEN THE MCP_Server SHALL return an error response with code "unavailable" indicating the config file could not be accessed
8. IF the Shell_Config file contains malformed JSON that cannot be parsed, THEN THE MCP_Server SHALL return an error response with code "internal_error" indicating the config file is corrupt

### Requirement 2: Quickshell Config Write

**User Story:** As an MCP_Client, I want to modify specific configuration values, so that I can apply user-requested desktop customizations.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `config_set` tool that accepts a `key` string (dot-separated path, maximum depth of 4 segments) and a `value` parameter (string, number, or boolean) targeting only scalar config properties
2. WHEN the `config_set` tool is invoked with a valid `key` and `value`, THE MCP_Server SHALL write the updated value to the Shell_Config file at the specified path and persist the change to disk before returning the response
3. WHEN the `config_set` tool is invoked with a `key` that does not correspond to a known scalar config path in the Shell_Config schema, THE MCP_Server SHALL return an error response indicating the key is not recognized
4. THE MCP_Server SHALL validate that the `value` type matches the expected type for the target key (boolean for boolean keys, integer for integer keys, string for string keys, real number for real-typed keys)
5. IF the `value` type does not match the expected type for the key, THEN THE MCP_Server SHALL return an error response indicating the type mismatch and specifying the expected type
6. IF the `config_set` tool is invoked with a `key` within the `policies` namespace, THEN THE MCP_Server SHALL return an error response indicating that policy keys are read-only and SHALL NOT modify the Shell_Config file
7. WHEN a successful write occurs, THE MCP_Server SHALL return a confirmation containing the key, the previous value, and the new value
8. THE MCP_Server SHALL ensure that writing a value and then reading the same key via `config_read` returns the written value (round-trip property)
9. IF the Shell_Config file does not exist or contains malformed JSON when `config_set` is invoked, THEN THE MCP_Server SHALL return an error response indicating the configuration file is unreadable and SHALL NOT create or overwrite the file
8. THE MCP_Server SHALL ensure that writing a value and then reading the same key returns the written value (round-trip property)

### Requirement 3: Audio State Query

**User Story:** As an MCP_Client, I want to query the current audio state, so that I can report volume levels, active sinks/sources, and mute status to the user.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `audio_status` tool that accepts no parameters
2. WHEN the `audio_status` tool is invoked, THE MCP_Server SHALL return a JSON object containing: the default sink name, volume percentage, and mute state; the default source name, volume percentage, and mute state; and a list of all available sinks and sources with their names, descriptions, and active status
3. THE MCP_Server SHALL obtain audio state by invoking wpctl or pactl commands and parsing their output
4. IF PipeWire or WirePlumber is not running, THEN THE MCP_Server SHALL return an error response indicating the audio subsystem is unavailable

### Requirement 4: Audio Volume Control

**User Story:** As an MCP_Client, I want to adjust volume and mute state, so that I can execute user-requested audio changes.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `audio_set_volume` tool that accepts a `target` string (sink or source name, or "@DEFAULT_SINK@"/"@DEFAULT_SOURCE@"), a `volume` parameter (integer 0-150 representing percentage, or a string like "+5%" or "-5%"), and an optional `mute` parameter (boolean or "toggle")
2. WHEN the `audio_set_volume` tool is invoked with a valid target and volume, THE MCP_Server SHALL set the volume using wpctl and return the resulting volume level and mute state
3. WHEN the `audio_set_volume` tool is invoked with the `mute` parameter, THE MCP_Server SHALL set the mute state of the target accordingly
4. IF the specified `target` does not exist, THEN THE MCP_Server SHALL return an error response indicating the target was not found
5. WHEN the `volume` integer exceeds 150, THE MCP_Server SHALL clamp the value to 150 and include a notice in the response that the value was clamped

### Requirement 5: Network State Query

**User Story:** As an MCP_Client, I want to query network connectivity status, so that I can report connection state, active interfaces, and WiFi information.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `network_status` tool that accepts no parameters
2. WHEN the `network_status` tool is invoked, THE MCP_Server SHALL return a JSON object containing: overall connectivity state (full, limited, portal, none), a list of active connections with their type (wifi, ethernet, vpn), device name, and connection name, and for WiFi connections the SSID and signal strength
3. THE MCP_Server SHALL obtain network state by invoking nmcli commands and parsing their output
4. IF NetworkManager is not running, THEN THE MCP_Server SHALL return an error response indicating NetworkManager is unavailable

### Requirement 6: Network WiFi Scanning

**User Story:** As an MCP_Client, I want to list available WiFi networks, so that I can help the user connect to a network.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `network_wifi_list` tool that accepts no parameters
2. WHEN the `network_wifi_list` tool is invoked, THE MCP_Server SHALL return a JSON array of visible WiFi access points containing: SSID, signal strength percentage, security type, and whether the network is currently connected
3. IF no WiFi device is available, THEN THE MCP_Server SHALL return an error response indicating no WiFi adapter was found
4. THE MCP_Server SHALL NOT expose WiFi passwords or PSK values in the response

### Requirement 7: Systemd Service Status

**User Story:** As an MCP_Client, I want to query systemd user service status, so that I can help diagnose failed services and system issues.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `systemd_status` tool that accepts an optional `unit` string parameter (service name) and an optional `scope` parameter with values "user" or "system" defaulting to "user"
2. WHEN the `systemd_status` tool is invoked without a `unit` parameter, THE MCP_Server SHALL return a JSON object containing: the count of failed units, the count of running units, and a list of failed unit names with their status and brief description
3. WHEN the `systemd_status` tool is invoked with a `unit` parameter, THE MCP_Server SHALL return detailed status for that unit including: active state, sub-state, main PID, memory usage, and the last 20 lines of journal output
4. IF the specified `unit` does not exist, THEN THE MCP_Server SHALL return an error response indicating the unit was not found
5. WHEN the `scope` is "system", THE MCP_Server SHALL query system-level systemd units using systemctl without the --user flag

### Requirement 8: Systemd Journal Query

**User Story:** As an MCP_Client, I want to read recent journal logs for a service, so that I can help the user debug service failures.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `systemd_logs` tool that accepts a required `unit` string parameter, an optional `lines` integer parameter defaulting to 50, an optional `scope` parameter defaulting to "user", and an optional `priority` parameter (0-7 syslog level)
2. WHEN the `systemd_logs` tool is invoked, THE MCP_Server SHALL return the most recent journal entries for the specified unit, limited to the requested number of lines
3. THE MCP_Server SHALL cap the `lines` parameter to a maximum of 500 entries
4. IF the specified `unit` has no journal entries, THEN THE MCP_Server SHALL return an empty entries array with a message indicating no logs were found

### Requirement 9: Clipboard History Query

**User Story:** As an MCP_Client, I want to search and retrieve clipboard history, so that I can help the user find previously copied content.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `clipboard_list` tool that accepts an optional `search` string parameter and an optional `limit` integer parameter defaulting to 20
2. WHEN the `clipboard_list` tool is invoked without a `search` parameter, THE MCP_Server SHALL return the most recent clipboard entries up to the limit, each containing an index identifier and a text preview (first 200 characters)
3. WHEN the `clipboard_list` tool is invoked with a `search` parameter, THE MCP_Server SHALL return clipboard entries matching the search string, filtered by cliphist's built-in search
4. THE MCP_Server SHALL cap the `limit` parameter to a maximum of 100 entries
5. IF cliphist is not available or has no entries, THEN THE MCP_Server SHALL return an error response indicating clipboard history is unavailable or empty

### Requirement 10: Clipboard Copy

**User Story:** As an MCP_Client, I want to copy a clipboard history entry back to the active clipboard, so that the user can paste previously copied content.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `clipboard_copy` tool that accepts a required `index` integer parameter identifying the clipboard entry
2. WHEN the `clipboard_copy` tool is invoked with a valid `index`, THE MCP_Server SHALL pipe the entry through cliphist decode and wl-copy, and return a success confirmation
3. IF the specified `index` does not correspond to a valid clipboard entry, THEN THE MCP_Server SHALL return an error response indicating the entry was not found

### Requirement 11: Desktop Entry Discovery

**User Story:** As an MCP_Client, I want to search for installed applications, so that I can help the user find and launch programs.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `apps_search` tool that accepts a required `query` string parameter and an optional `limit` integer parameter defaulting to 10
2. WHEN the `apps_search` tool is invoked, THE MCP_Server SHALL search .desktop files in standard XDG data directories and return matching applications containing: the desktop entry ID, display name, generic name, comment/description, executable command, icon name, and categories
3. THE MCP_Server SHALL perform case-insensitive fuzzy matching against the application name, generic name, comment, and keywords fields
4. THE MCP_Server SHALL exclude desktop entries with `NoDisplay=true` or `Hidden=true` from results
5. THE MCP_Server SHALL cap the `limit` parameter to a maximum of 50 entries

### Requirement 12: Application Launch

**User Story:** As an MCP_Client, I want to launch an application by its desktop entry ID, so that I can execute user-requested app launches.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `apps_launch` tool that accepts a required `id` string parameter (the desktop entry ID, e.g., "org.kde.dolphin")
2. WHEN the `apps_launch` tool is invoked with a valid desktop entry ID, THE MCP_Server SHALL launch the application using the appropriate mechanism (gtk-launch, dex, or direct Exec field invocation) and return a success confirmation
3. IF the specified `id` does not correspond to an installed desktop entry, THEN THE MCP_Server SHALL return an error response indicating the application was not found
4. THE MCP_Server SHALL launch applications detached from the MCP_Server process so that the server is not blocked

### Requirement 13: Diagnostic Bundle

**User Story:** As an MCP_Client, I want to collect a comprehensive diagnostic snapshot, so that I can help troubleshoot desktop environment issues (Desktop Doctor).

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `diagnostic_bundle` tool that accepts no parameters
2. WHEN the `diagnostic_bundle` tool is invoked, THE MCP_Server SHALL collect and return a JSON object containing the following components each under a named key: Hyprland version string and compositor state (active monitor count, total window count, and current active workspace ID), list of failed systemd user units (unit name and status for each), PipeWire running status (active or inactive), NetworkManager connectivity state as reported by NetworkManager (one of: full, limited, portal, none, unknown), current Shell_Config (redacted per Requirement 1 criteria), GPU driver name and version, memory usage (total bytes, used bytes, available bytes, and swap total and swap used bytes), disk usage for the root and home partitions (total bytes, used bytes, and available bytes for each), and the last 30 lines of Quickshell stderr from the systemd journal for the Quickshell user service
3. THE MCP_Server SHALL complete the diagnostic bundle collection within 10 seconds
4. IF any individual diagnostic component fails to collect, THEN THE MCP_Server SHALL include that component in the response with a null value for its data and a string field describing the error encountered, and SHALL continue collecting remaining components
5. WHEN the `diagnostic_bundle` tool is invoked, THE MCP_Server SHALL collect all diagnostic components concurrently so that a single slow component does not consume the entire 10-second budget

### Requirement 14: Shell Logs

**User Story:** As an MCP_Client, I want to read recent Quickshell log output, so that I can help debug shell UI issues and QML errors.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `shell_logs` tool that accepts an optional `lines` integer parameter defaulting to 50 and an optional `level` parameter accepting values "all", "warning", "error" defaulting to "all"
2. WHEN the `shell_logs` tool is invoked, THE MCP_Server SHALL return the most recent Quickshell journal entries (from the quickshell systemd unit or the quickshell process stderr), filtered by the specified level
3. THE MCP_Server SHALL cap the `lines` parameter to a maximum of 200 entries
4. WHEN the `level` parameter is "warning", THE MCP_Server SHALL return only entries containing warning or error indicators
5. WHEN the `level` parameter is "error", THE MCP_Server SHALL return only entries containing error indicators

### Requirement 15: Screenshot Capture

**User Story:** As an MCP_Client, I want to capture screenshots, so that I can provide visual context or fulfill user screenshot requests.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `screenshot` tool that accepts a required `mode` parameter with values "monitor", "window", or "region", an optional `output` string parameter specifying the monitor name (for "monitor" mode), and an optional `path` string parameter for the save location defaulting to ~/Pictures/Screenshots/{timestamp}.png
2. WHEN the `screenshot` tool is invoked with mode "monitor", THE MCP_Server SHALL capture the specified monitor (or the focused monitor if `output` is not provided) using grim and return the file path of the saved screenshot
3. WHEN the `screenshot` tool is invoked with mode "window", THE MCP_Server SHALL capture the currently focused window geometry using hyprctl activewindow and grim with the geometry flag, and return the file path
4. WHEN the `screenshot` tool is invoked with mode "region", THE MCP_Server SHALL capture the screen using grim with slurp for interactive region selection, and return the file path
5. IF grim is not available, THEN THE MCP_Server SHALL return an error response indicating the screenshot tool is not installed

### Requirement 16: System Information

**User Story:** As an MCP_Client, I want to query hardware and system resource information, so that I can provide system context and help with performance questions.

#### Acceptance Criteria

1. THE MCP_Server SHALL expose a `system_info` tool that accepts no parameters
2. WHEN the `system_info` tool is invoked, THE MCP_Server SHALL return a JSON object containing: kernel version, hostname, uptime, CPU model and core count, GPU model and driver, total and used memory (in MB), total and used swap (in MB), and disk usage for mounted partitions (path, total, used, available in GB)
3. THE MCP_Server SHALL obtain system information by reading /proc and /sys filesystem entries and invoking standard utilities (uname, lspci, free, df)
4. THE MCP_Server SHALL NOT include serial numbers, MAC addresses, or other hardware identifiers that could fingerprint the system

### Requirement 17: MCP Server Transport and Lifecycle

**User Story:** As a system administrator, I want the MCP server to run reliably as a systemd user service over stdio, so that MCP clients can connect to it predictably.

#### Acceptance Criteria

1. THE MCP_Server SHALL communicate exclusively via stdio transport (JSON-RPC over stdin/stdout) conforming to the MCP specification
2. WHEN the MCP initialization handshake occurs, THE MCP_Server SHALL register all tools with non-empty names, non-empty descriptions, and JSON Schema parameter definitions
3. WHEN the MCP_Server receives a SIGTERM signal, THE MCP_Server SHALL complete any in-flight tool invocation within 5 seconds and then exit with code 0
4. IF an in-flight tool invocation does not complete within 5 seconds of receiving SIGTERM, THEN THE MCP_Server SHALL abort the invocation, return an error response with code "timeout" to the client, and exit with code 0
5. WHEN the MCP_Server detects EOF on stdin, THE MCP_Server SHALL treat it as a client disconnect, complete any in-flight tool invocation within 5 seconds, and then exit with code 0
6. THE MCP_Server SHALL log diagnostic messages to stderr only, keeping stdout reserved for MCP protocol messages
7. THE MCP_Server SHALL be packageable as a Nix flake providing a default package and a NixOS/home-manager module for the systemd user service configured with Restart=on-failure and RestartSec=5

### Requirement 18: Security and Privacy Controls

**User Story:** As a user, I want the MCP server to protect my privacy and prevent dangerous operations, so that I can trust AI clients with desktop access.

#### Acceptance Criteria

1. THE MCP_Server SHALL NOT expose any tool that executes arbitrary shell commands
2. THE MCP_Server SHALL redact values of config keys containing "key", "secret", "password", or "token" (case-insensitive) when returning config data, replacing each redacted value with the string "[REDACTED]" while preserving the key name in the response
3. THE MCP_Server SHALL NOT include WiFi passwords, API keys, or authentication tokens in any tool response
4. THE MCP_Server SHALL validate all tool input parameters against their declared JSON Schema before execution
5. IF a tool input parameter fails schema validation, THEN THE MCP_Server SHALL return an error response with error code "validation_error", a message identifying the parameter name and the constraint that was violated, and SHALL NOT execute the tool
6. THE MCP_Server SHALL restrict file write operations to the Shell_Config file path (~/.config/quickshell/ii/user/config.json) and the screenshots output directory (~/Pictures/Screenshots/) only
7. IF a tool invocation attempts to write to a path outside the Shell_Config file or the screenshots output directory, THEN THE MCP_Server SHALL return an error response with error code "validation_error" indicating the write path is not permitted, and SHALL NOT perform the write
8. THE MCP_Server SHALL reject any file path parameter containing path traversal sequences ("..") that would resolve outside the allowed write directories

### Requirement 19: Error Handling and Resilience

**User Story:** As an MCP_Client, I want consistent, structured error responses when tools fail, so that I can present useful diagnostics to the user.

#### Acceptance Criteria

1. WHEN any tool invocation encounters an error, THE MCP_Server SHALL return a JSON error response containing: an error code string, a human-readable message, and an optional details object with debugging context
2. THE MCP_Server SHALL use consistent error codes across all tools: "not_found" for missing resources, "unavailable" for missing subsystems, "validation_error" for invalid parameters, "timeout" for operations exceeding their time limit, and "internal_error" for unexpected failures
3. WHEN an external command (wpctl, nmcli, systemctl, cliphist, grim) is not found in PATH, THE MCP_Server SHALL return an error with code "unavailable" and a message naming the missing command
4. THE MCP_Server SHALL not crash or hang when an external command produces unexpected output; instead THE MCP_Server SHALL return an "internal_error" with the raw output included in the details for debugging
