# Design Document: ii-desktop-mcp

## Overview

The ii-desktop-mcp server is a Python MCP (Model Context Protocol) server that provides structured desktop intelligence tools for the Quickshell-based Hyprland environment. It extends the upstream [hyprmcp](https://github.com/stefanoamorelli/hyprmcp) project — which wraps `hyprctl` — with comprehensive desktop state management covering configuration, audio, networking, systemd, clipboard, applications, diagnostics, screenshots, and system information.

### Design Goals

- **Structured access**: Expose desktop state as typed JSON rather than raw command output
- **Safety by default**: No arbitrary shell execution; redact secrets; restrict write paths
- **Composability**: Each tool is independent and stateless; the diagnostic bundle composes them
- **Reliability**: Graceful degradation when subsystems are unavailable
- **Packageability**: Single Nix flake providing the server and a systemd user service module

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Use `mcp[cli]` SDK (FastMCP 1.0 bundled) | Same as upstream hyprmcp; well-supported; handles protocol boilerplate |
| Async subprocess for external commands | Non-blocking I/O; enables concurrent diagnostic collection within timeout |
| One module per tool domain | Clear separation of concerns; easy to add/remove domains |
| Config schema derived from QML Config.qml | Single source of truth for allowed keys and types |
| Redaction as reusable utility | Consistent secret handling across config_read and diagnostic_bundle |
| Path validation via allowlist | Prevents write operations outside config file and screenshots dir |

## Architecture

```mermaid
graph TB
    subgraph "MCP Clients"
        QS[Quickshell Sidebar AI]
        AP[Action Palette]
        K[Kiro / External MCP Client]
    end

    subgraph "ii-desktop-mcp (systemd user service)"
        S[FastMCP Server<br/>stdio transport]
        
        subgraph "Tool Modules"
            CFG[config]
            AUD[audio]
            NET[network]
            SYS[systemd_svc]
            CLIP[clipboard]
            APPS[apps]
            DIAG[diagnostics]
            LOGS[shell_logs]
            SS[screenshot]
            SI[system_info]
        end

        subgraph "Core Utilities"
            CMD[subprocess runner]
            RED[redaction]
            VAL[validation]
            ERR[error formatting]
        end
    end

    subgraph "System"
        HC[hyprctl]
        WP[wpctl / pactl]
        NM[nmcli]
        SC[systemctl]
        JC[journalctl]
        CH[cliphist]
        WC[wl-copy]
        GR[grim]
        SL[slurp]
        PROC[/proc, /sys]
        FS[~/.config/quickshell/ii/user/config.json]
    end

    QS & AP & K -->|stdio JSON-RPC| S
    S --> CFG & AUD & NET & SYS & CLIP & APPS & DIAG & LOGS & SS & SI
    CFG & AUD & NET & SYS & CLIP & APPS & DIAG & LOGS & SS & SI --> CMD & RED & VAL & ERR
    CMD --> HC & WP & NM & SC & JC & CH & WC & GR & SL
    CFG --> FS
    SI --> PROC
```

### Project Structure

```
ii-desktop-mcp/
├── flake.nix                    # Nix flake: package + HM/NixOS module
├── flake.lock
├── pyproject.toml               # Python project metadata (setuptools/hatch)
├── README.md
├── nix/
│   ├── package.nix              # buildPythonApplication derivation
│   └── module.nix               # Home-manager / systemd user service module
├── src/
│   └── ii_desktop_mcp/
│       ├── __init__.py
│       ├── server.py            # FastMCP server instantiation + entrypoint
│       ├── core/
│       │   ├── __init__.py
│       │   ├── subprocess.py    # Async subprocess runner with timeout
│       │   ├── redaction.py     # Secret redaction logic
│       │   ├── validation.py    # Path validation, schema helpers
│       │   └── errors.py        # Error response builders
│       └── tools/
│           ├── __init__.py      # Tool registration orchestrator
│           ├── config.py        # config_read, config_set
│           ├── audio.py         # audio_status, audio_set_volume
│           ├── network.py       # network_status, network_wifi_list
│           ├── systemd_svc.py   # systemd_status, systemd_logs
│           ├── clipboard.py     # clipboard_list, clipboard_copy
│           ├── apps.py          # apps_search, apps_launch
│           ├── diagnostics.py   # diagnostic_bundle
│           ├── shell_logs.py    # shell_logs
│           ├── screenshot.py    # screenshot
│           └── system_info.py   # system_info
└── tests/
    ├── conftest.py              # Shared fixtures, hypothesis profiles
    ├── test_redaction.py        # Property tests for redaction
    ├── test_config.py           # Property tests for config round-trip
    ├── test_validation.py       # Property tests for path/input validation
    ├── test_parsing.py          # Property tests for command output parsing
    └── test_tools/              # Integration tests per tool module
        ├── test_config_tool.py
        ├── test_audio_tool.py
        └── ...
```

### Communication Flow

1. Client connects via stdio (stdin/stdout JSON-RPC)
2. FastMCP handles MCP handshake, tool discovery, and schema advertisement
3. Client invokes a tool → FastMCP dispatches to the registered Python function
4. Tool function validates inputs → executes async subprocess or file I/O → formats response
5. Response returned as structured JSON via MCP protocol

## Components and Interfaces

### Core Utilities

#### `core/subprocess.py` — Async Command Runner

```python
import asyncio
from typing import Optional

class CommandResult:
    stdout: str
    stderr: str
    returncode: int

async def run_command(
    args: list[str],
    timeout: float = 5.0,
    env: Optional[dict[str, str]] = None,
) -> CommandResult:
    """Execute a command asynchronously with timeout.
    
    Raises:
        CommandNotFoundError: if the binary is not in PATH
        CommandTimeoutError: if execution exceeds timeout
    """
    ...
```

#### `core/redaction.py` — Secret Redaction

```python
import re
from typing import Any

REDACTED = "[REDACTED]"

# Patterns that trigger redaction
SENSITIVE_KEY_PATTERNS: list[re.Pattern] = [
    re.compile(r"key", re.IGNORECASE),
    re.compile(r"secret", re.IGNORECASE),
    re.compile(r"password", re.IGNORECASE),
    re.compile(r"token", re.IGNORECASE),
]

# Exact paths always redacted
SENSITIVE_PATHS: set[str] = {
    "ai.systemPrompt",
}

# Namespace prefixes where all values are redacted
SENSITIVE_NAMESPACES: list[str] = [
    "sidebar.booru.zerochan",
]

def redact_config(config: dict[str, Any], path_prefix: str = "") -> dict[str, Any]:
    """Deep-copy config with sensitive values replaced by REDACTED."""
    ...

def is_sensitive_key(key: str, full_path: str) -> bool:
    """Determine if a key/path should be redacted."""
    ...
```

#### `core/validation.py` — Input Validation

```python
from pathlib import Path

ALLOWED_WRITE_PATHS: list[Path] = [
    Path("~/.config/quickshell/ii/user/config.json").expanduser(),
    Path("~/Pictures/Screenshots").expanduser(),
]

def validate_write_path(path: str) -> Path:
    """Validate and resolve a write path, rejecting traversal and disallowed destinations.
    
    Raises:
        ValidationError: if path contains '..' or resolves outside allowed directories
    """
    ...

def validate_namespace(namespace: str) -> list[str]:
    """Parse and validate a dot-separated namespace string.
    
    Raises:
        ValidationError: if namespace exceeds 256 chars or contains invalid characters
    """
    ...

def validate_config_key(key: str) -> list[str]:
    """Parse and validate a config key (max depth 4).
    
    Raises:
        ValidationError: if key has more than 4 segments or targets policies namespace
    """
    ...
```

#### `core/errors.py` — Error Response Formatting

```python
from typing import Any, Optional

class ToolError(Exception):
    """Structured error raised by tool implementations."""
    def __init__(self, code: str, message: str, details: Optional[dict[str, Any]] = None):
        self.code = code
        self.message = message
        self.details = details

def error_response(code: str, message: str, details: Optional[dict[str, Any]] = None) -> dict:
    """Build a consistent error response dict."""
    return {
        "error": {
            "code": code,
            "message": message,
            **({"details": details} if details else {}),
        }
    }

# Standard error codes
NOT_FOUND = "not_found"
UNAVAILABLE = "unavailable"
VALIDATION_ERROR = "validation_error"
TIMEOUT = "timeout"
INTERNAL_ERROR = "internal_error"
```

### Tool Modules

#### `tools/config.py` — Config Read/Write

```python
from mcp.server.fastmcp import FastMCP

def register(mcp: FastMCP) -> None:
    """Register config_read and config_set tools."""

    @mcp.tool()
    async def config_read(namespace: str = "") -> dict:
        """Read Quickshell configuration. Optionally filter by namespace (dot-separated path)."""
        ...

    @mcp.tool()
    async def config_set(key: str, value: str | int | float | bool) -> dict:
        """Set a scalar configuration value. Key is a dot-separated path (max 4 segments)."""
        ...
```

#### `tools/audio.py` — Audio Control

```python
def register(mcp: FastMCP) -> None:
    @mcp.tool()
    async def audio_status() -> dict:
        """Query PipeWire/WirePlumber audio state: sinks, sources, volumes, mute status."""
        ...

    @mcp.tool()
    async def audio_set_volume(
        target: str,
        volume: int | str | None = None,
        mute: bool | str | None = None,
    ) -> dict:
        """Set volume (0-150 or +/-N%) and/or mute state for an audio target."""
        ...
```

#### `tools/network.py` — Network State

```python
def register(mcp: FastMCP) -> None:
    @mcp.tool()
    async def network_status() -> dict:
        """Query NetworkManager connectivity, active connections, and WiFi info."""
        ...

    @mcp.tool()
    async def network_wifi_list() -> dict:
        """List visible WiFi access points with SSID, signal, security, connected status."""
        ...
```

#### `tools/systemd_svc.py` — Systemd Management

```python
def register(mcp: FastMCP) -> None:
    @mcp.tool()
    async def systemd_status(unit: str = "", scope: str = "user") -> dict:
        """Query systemd unit status. Without unit: summary of failed/running. With unit: detailed status."""
        ...

    @mcp.tool()
    async def systemd_logs(unit: str, lines: int = 50, scope: str = "user", priority: int | None = None) -> dict:
        """Read recent journal entries for a systemd unit."""
        ...
```

#### `tools/clipboard.py` — Clipboard History

```python
def register(mcp: FastMCP) -> None:
    @mcp.tool()
    async def clipboard_list(search: str = "", limit: int = 20) -> dict:
        """List or search clipboard history entries."""
        ...

    @mcp.tool()
    async def clipboard_copy(index: int) -> dict:
        """Copy a clipboard history entry back to the active clipboard."""
        ...
```

#### `tools/apps.py` — Application Discovery & Launch

```python
def register(mcp: FastMCP) -> None:
    @mcp.tool()
    async def apps_search(query: str, limit: int = 10) -> dict:
        """Search installed .desktop applications by name, keywords, or description."""
        ...

    @mcp.tool()
    async def apps_launch(id: str) -> dict:
        """Launch an application by its desktop entry ID (e.g., 'org.kde.dolphin')."""
        ...
```

#### `tools/diagnostics.py` — Diagnostic Bundle

```python
def register(mcp: FastMCP) -> None:
    @mcp.tool()
    async def diagnostic_bundle() -> dict:
        """Collect comprehensive desktop diagnostic snapshot (Desktop Doctor).
        
        Concurrently gathers: Hyprland state, failed systemd units, PipeWire status,
        NetworkManager connectivity, shell config (redacted), GPU info, memory, disk,
        and recent Quickshell logs. Completes within 10 seconds.
        """
        ...
```

#### `tools/shell_logs.py` — Quickshell Logs

```python
def register(mcp: FastMCP) -> None:
    @mcp.tool()
    async def shell_logs(lines: int = 50, level: str = "all") -> dict:
        """Read recent Quickshell journal entries, optionally filtered by level (all/warning/error)."""
        ...
```

#### `tools/screenshot.py` — Screenshot Capture

```python
def register(mcp: FastMCP) -> None:
    @mcp.tool()
    async def screenshot(mode: str, output: str = "", path: str = "") -> dict:
        """Capture a screenshot. Mode: 'monitor', 'window', or 'region'."""
        ...
```

#### `tools/system_info.py` — System Information

```python
def register(mcp: FastMCP) -> None:
    @mcp.tool()
    async def system_info() -> dict:
        """Query system hardware and resource information: CPU, GPU, memory, disk, kernel."""
        ...
```

### Server Entrypoint (`server.py`)

```python
from mcp.server.fastmcp import FastMCP
from ii_desktop_mcp.tools import config, audio, network, systemd_svc, clipboard, apps, diagnostics, shell_logs, screenshot, system_info

mcp = FastMCP("ii-desktop-mcp")

# Register all tool modules
for module in [config, audio, network, systemd_svc, clipboard, apps, diagnostics, shell_logs, screenshot, system_info]:
    module.register(mcp)

def main():
    mcp.run(transport="stdio")

if __name__ == "__main__":
    main()
```

## Data Models

### Config Schema (derived from Config.qml)

The Shell_Config at `~/.config/quickshell/ii/user/config.json` is a nested JSON object. Top-level namespaces:

```json
{
  "policies": { "ai": 1, "weeb": 1 },
  "ai": { "systemPrompt": "...", "tool": "functions", "extraModels": [...] },
  "appearance": { "extraBackgroundTint": true, "fakeScreenRounding": 2, ... },
  "audio": { "protection": { "enable": true, "maxAllowedIncrease": 10, "maxAllowed": 90 } },
  "apps": { "bluetooth": "...", "network": "...", "terminal": "..." },
  "background": { "fixedClockPosition": false, "wallpaperPath": "", ... },
  "bar": { "bottom": false, "cornerStyle": 0, "workspaces": { "shown": 10, ... }, ... },
  "battery": { "low": 20, "critical": 5, ... },
  "dock": { "enable": false, "pinnedApps": [...], ... },
  "language": { "translator": { "engine": "auto", ... } },
  "light": { "night": { "automatic": true, "from": "19:00", "to": "06:30", ... } },
  "networking": { "userAgent": "..." },
  "notifications": { "timeout": 7000, ... },
  "osd": { "timeout": 1000 },
  "osk": { "layout": "qwerty_full", ... },
  "overview": { "enable": true, "scale": 0.18, "rows": 2, "columns": 5 },
  "resources": { "updateInterval": 3000 },
  "search": { "nonAppResultDelay": 30, "engineBaseUrl": "...", ... },
  "sidebar": { "keepRightSidebarLoaded": true, "booru": { "zerochan": { "username": "..." } }, ... },
  "time": { "format": "hh:mm", "dateFormat": "ddd, dd/MM" },
  "windows": { "showTitlebar": true, "centerTitle": true },
  "hacks": { "arbitraryRaceConditionDelay": 20 },
  "screenshotTool": { "showContentRegions": true }
}
```

### Config Schema Type Map

A static registry mapping config key paths to their expected types, used for `config_set` validation:

```python
from enum import Enum
from typing import Any

class ConfigType(Enum):
    BOOL = "boolean"
    INT = "integer"
    REAL = "real"
    STRING = "string"

# Derived from Config.qml JsonObject properties
CONFIG_SCHEMA: dict[str, ConfigType] = {
    "appearance.extraBackgroundTint": ConfigType.BOOL,
    "appearance.fakeScreenRounding": ConfigType.INT,
    "appearance.transparency": ConfigType.BOOL,
    "appearance.wallpaperTheming.enableAppsAndShell": ConfigType.BOOL,
    "appearance.wallpaperTheming.enableQtApps": ConfigType.BOOL,
    "appearance.wallpaperTheming.enableTerminal": ConfigType.BOOL,
    "appearance.palette.type": ConfigType.STRING,
    "audio.protection.enable": ConfigType.BOOL,
    "audio.protection.maxAllowedIncrease": ConfigType.REAL,
    "audio.protection.maxAllowed": ConfigType.REAL,
    "apps.bluetooth": ConfigType.STRING,
    "apps.network": ConfigType.STRING,
    "apps.networkEthernet": ConfigType.STRING,
    "apps.taskManager": ConfigType.STRING,
    "apps.terminal": ConfigType.STRING,
    "bar.bottom": ConfigType.BOOL,
    "bar.cornerStyle": ConfigType.INT,
    "bar.borderless": ConfigType.BOOL,
    "bar.topLeftIcon": ConfigType.STRING,
    "bar.showBackground": ConfigType.BOOL,
    "bar.verbose": ConfigType.BOOL,
    "bar.workspaces.monochromeIcons": ConfigType.BOOL,
    "bar.workspaces.shown": ConfigType.INT,
    "bar.workspaces.showAppIcons": ConfigType.BOOL,
    "bar.workspaces.alwaysShowNumbers": ConfigType.BOOL,
    "bar.workspaces.showNumberDelay": ConfigType.INT,
    "bar.weather.enable": ConfigType.BOOL,
    "bar.weather.enableGPS": ConfigType.BOOL,
    "bar.weather.city": ConfigType.STRING,
    "bar.weather.useUSCS": ConfigType.BOOL,
    "bar.weather.fetchInterval": ConfigType.INT,
    "bar.utilButtons.showScreenSnip": ConfigType.BOOL,
    "bar.utilButtons.showColorPicker": ConfigType.BOOL,
    "bar.utilButtons.showMicToggle": ConfigType.BOOL,
    "bar.utilButtons.showKeyboardToggle": ConfigType.BOOL,
    "bar.utilButtons.showDarkModeToggle": ConfigType.BOOL,
    "bar.utilButtons.showPerformanceProfileToggle": ConfigType.BOOL,
    "bar.tray.monochromeIcons": ConfigType.BOOL,
    "bar.resources.alwaysShowSwap": ConfigType.BOOL,
    "bar.resources.alwaysShowCpu": ConfigType.BOOL,
    "battery.low": ConfigType.INT,
    "battery.critical": ConfigType.INT,
    "battery.automaticSuspend": ConfigType.BOOL,
    "battery.suspend": ConfigType.INT,
    "dock.enable": ConfigType.BOOL,
    "dock.monochromeIcons": ConfigType.BOOL,
    "dock.height": ConfigType.REAL,
    "dock.hoverRegionHeight": ConfigType.REAL,
    "dock.pinnedOnStartup": ConfigType.BOOL,
    "dock.hoverToReveal": ConfigType.BOOL,
    "light.night.automatic": ConfigType.BOOL,
    "light.night.from": ConfigType.STRING,
    "light.night.to": ConfigType.STRING,
    "light.night.colorTemperature": ConfigType.INT,
    "networking.userAgent": ConfigType.STRING,
    "notifications.timeout": ConfigType.INT,
    "notifications.forceMonitor.enable": ConfigType.BOOL,
    "notifications.forceMonitor.name": ConfigType.STRING,
    "osd.timeout": ConfigType.INT,
    "osk.layout": ConfigType.STRING,
    "osk.pinnedOnStartup": ConfigType.BOOL,
    "overview.enable": ConfigType.BOOL,
    "overview.scale": ConfigType.REAL,
    "overview.rows": ConfigType.REAL,
    "overview.columns": ConfigType.REAL,
    "resources.updateInterval": ConfigType.INT,
    "search.nonAppResultDelay": ConfigType.INT,
    "search.engineBaseUrl": ConfigType.STRING,
    "search.sloppy": ConfigType.BOOL,
    "search.prefix.action": ConfigType.STRING,
    "search.prefix.ai": ConfigType.STRING,
    "search.prefix.clipboard": ConfigType.STRING,
    "search.prefix.emojis": ConfigType.STRING,
    "search.aiDebounceMs": ConfigType.INT,
    "sidebar.keepRightSidebarLoaded": ConfigType.BOOL,
    "sidebar.translator.delay": ConfigType.INT,
    "sidebar.booru.allowNsfw": ConfigType.BOOL,
    "sidebar.booru.defaultProvider": ConfigType.STRING,
    "sidebar.booru.limit": ConfigType.INT,
    "time.format": ConfigType.STRING,
    "time.dateFormat": ConfigType.STRING,
    "windows.showTitlebar": ConfigType.BOOL,
    "windows.centerTitle": ConfigType.BOOL,
    "hacks.arbitraryRaceConditionDelay": ConfigType.INT,
    "screenshotTool.showContentRegions": ConfigType.BOOL,
    # policies.* excluded — read-only
}
```

### Error Response Model

All errors follow a consistent structure:

```json
{
  "error": {
    "code": "not_found | unavailable | validation_error | timeout | internal_error",
    "message": "Human-readable description",
    "details": { }
  }
}
```

### Tool Response Models

#### Audio Status Response
```json
{
  "default_sink": { "name": "...", "volume": 75, "muted": false },
  "default_source": { "name": "...", "volume": 100, "muted": false },
  "sinks": [{ "id": 1, "name": "...", "description": "...", "active": true }],
  "sources": [{ "id": 2, "name": "...", "description": "...", "active": true }]
}
```

#### Network Status Response
```json
{
  "connectivity": "full",
  "connections": [
    { "type": "wifi", "device": "wlan0", "name": "MyNetwork", "ssid": "MyNetwork", "signal": 82 },
    { "type": "ethernet", "device": "enp5s0", "name": "Wired" }
  ]
}
```

#### Diagnostic Bundle Response
```json
{
  "hyprland": { "version": "...", "monitors": 2, "windows": 12, "active_workspace": 3 },
  "systemd_failed": [{ "unit": "...", "status": "failed" }],
  "pipewire": { "status": "active" },
  "network": { "connectivity": "full" },
  "config": { "...redacted config..." },
  "gpu": { "name": "...", "driver": "..." },
  "memory": { "total": 0, "used": 0, "available": 0, "swap_total": 0, "swap_used": 0 },
  "disk": { "root": { "total": 0, "used": 0, "available": 0 }, "home": { "total": 0, "used": 0, "available": 0 } },
  "quickshell_logs": ["...last 30 lines..."]
}
```

### Nix Packaging

#### `flake.nix`

```nix
{
  description = "ii-desktop-mcp - Desktop intelligence MCP server for Quickshell/Hyprland";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.python312Packages.buildPythonApplication {
            pname = "ii-desktop-mcp";
            version = "0.1.0";
            src = ./.;
            format = "pyproject";
            
            propagatedBuildInputs = with pkgs.python312Packages; [
              mcp  # includes FastMCP
            ];
            
            # Runtime PATH for external commands
            makeWrapperArgs = [
              "--prefix" "PATH" ":" (pkgs.lib.makeBinPath [
                pkgs.hyprland
                pkgs.wireplumber
                pkgs.pulseaudio  # pactl
                pkgs.networkmanager
                pkgs.systemd
                pkgs.cliphist
                pkgs.wl-clipboard
                pkgs.grim
                pkgs.slurp
                pkgs.pciutils  # lspci
              ])
            ];
          };
        }
      );

      homeManagerModules.default = import ./nix/module.nix self;
    };
}
```

#### Systemd User Service (`nix/module.nix`)

```nix
self: { config, lib, pkgs, ... }:
let
  cfg = config.services.ii-desktop-mcp;
in {
  options.services.ii-desktop-mcp = {
    enable = lib.mkEnableOption "ii-desktop-mcp MCP server";
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.ii-desktop-mcp = {
      Unit = {
        Description = "ii-desktop-mcp - Desktop Intelligence MCP Server";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${self.packages.${pkgs.system}.default}/bin/ii-desktop-mcp";
        Restart = "on-failure";
        RestartSec = 5;
        StandardInput = "socket";
        StandardOutput = "socket";
        StandardError = "journal";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
```



## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Config namespace extraction returns correct subtree

*For any* valid nested JSON config object and *for any* valid dot-separated namespace path that exists within it, calling the namespace extraction function with that path SHALL return the exact subtree rooted at that path, equivalent to traversing the object key-by-key along the path segments.

**Validates: Requirements 1.3**

### Property 2: Redaction completeness and structure preservation

*For any* nested JSON config object, the redaction function SHALL:
- Replace the value of every key matching "key", "secret", "password", or "token" (case-insensitive) with "[REDACTED]"
- Replace the value at the exact path "ai.systemPrompt" with "[REDACTED]"
- Replace all values under the "sidebar.booru.zerochan" namespace with "[REDACTED]"
- Preserve all non-sensitive keys and their values unchanged
- Preserve the overall structure (nesting, key names, array positions) of the object

**Validates: Requirements 1.6, 18.2**

### Property 3: Config write/read round-trip

*For any* valid config key in the schema and *for any* value of the correct type for that key, writing the value via `config_set` and then reading it back via `config_read` with the appropriate namespace SHALL return the written value, and the response from `config_set` SHALL contain the key, the previous value, and the new value.

**Validates: Requirements 2.2, 2.7, 2.8**

### Property 4: Config key validation rejects invalid keys

*For any* string that either (a) has more than 4 dot-separated segments, (b) does not exist in the CONFIG_SCHEMA registry, or (c) starts with the "policies." prefix, the `config_set` operation SHALL reject it with an appropriate error code without modifying the config file.

**Validates: Requirements 2.1, 2.3, 2.4, 2.6**

### Property 5: Write path validation restricts to allowed directories

*For any* file path string, the write path validator SHALL accept it only if the fully resolved path (after expanding `~` and resolving symlinks and `..` sequences) falls within either `~/.config/quickshell/ii/user/config.json` or `~/Pictures/Screenshots/`. All other paths, including those using path traversal (`..`) to escape allowed directories, SHALL be rejected with a "validation_error".

**Validates: Requirements 18.6, 18.7, 18.8**

### Property 6: Integer parameter clamping

*For any* integer parameter with a defined maximum (lines capped at 500 for systemd_logs, limit capped at 100 for clipboard_list, limit capped at 50 for apps_search, lines capped at 200 for shell_logs), providing a value above the maximum SHALL result in the effective value being clamped to the maximum without error.

**Validates: Requirements 8.3, 9.4, 11.5, 14.3**

### Property 7: Volume clamping with notice

*For any* integer volume value greater than 150, the `audio_set_volume` tool SHALL clamp the effective volume to 150 and include a notice in the response indicating the value was clamped.

**Validates: Requirements 4.5**

### Property 8: Command output parsing produces valid structured output

*For any* well-formed command output string matching the expected format of wpctl, nmcli, or /proc filesystem entries, the corresponding parser function SHALL produce a valid JSON object containing all required fields with correct types, without raising exceptions.

**Validates: Requirements 3.1, 5.1, 6.1, 16.1**

### Property 9: Clipboard preview truncation

*For any* clipboard entry text, the preview returned by `clipboard_list` SHALL be at most 200 characters long and SHALL be a prefix of the original entry text.

**Validates: Requirements 9.2**

### Property 10: App search excludes hidden entries

*For any* set of desktop entries and *for any* search query, entries with `NoDisplay=true` or `Hidden=true` SHALL never appear in the search results, regardless of how well they match the query.

**Validates: Requirements 11.4**

### Property 11: App search is case-insensitive

*For any* search query string, the set of matching desktop entries SHALL be identical regardless of the case of the query characters (e.g., searching "Firefox", "firefox", and "FIREFOX" return the same results).

**Validates: Requirements 11.3**

### Property 12: Log level filtering correctness

*For any* set of log entries with mixed severity levels, filtering with level "error" SHALL return only entries containing error indicators, filtering with level "warning" SHALL return entries containing warning or error indicators, and filtering with level "all" SHALL return all entries.

**Validates: Requirements 14.2, 14.4, 14.5**

### Property 13: Diagnostic bundle resilience to component failures

*For any* subset of diagnostic components that fail during collection, the diagnostic bundle response SHALL include all non-failed components with their valid data, and each failed component SHALL appear with a null data value and a string error field describing the failure.

**Validates: Requirements 13.4**

### Property 14: Error response structure invariant

*For any* error returned by any tool, the error response SHALL contain a "code" field whose value is one of exactly five strings ("not_found", "unavailable", "validation_error", "timeout", "internal_error") and a "message" field containing a non-empty human-readable string.

**Validates: Requirements 19.1, 19.2**

### Property 15: Missing command error identifies the command

*For any* external command dependency (wpctl, pactl, nmcli, systemctl, journalctl, cliphist, grim, slurp) that is not found in PATH, the error response SHALL have code "unavailable" and the message SHALL contain the name of the missing command.

**Validates: Requirements 19.3**

### Property 16: Unexpected command output does not crash the server

*For any* arbitrary string output from an external subprocess (including empty, binary, or malformed text), the parsing layer SHALL not raise an unhandled exception; instead it SHALL return an error response with code "internal_error" and the raw output included in the details.

**Validates: Requirements 19.4**

### Property 17: No sensitive data leakage in any tool response

*For any* tool response across all tools, the response SHALL NOT contain WiFi PSK values, API key values, authentication tokens, or any value that was marked for redaction in the config. Specifically, no string value matching a known secret pattern from the config SHALL appear verbatim in any tool output.

**Validates: Requirements 6.3, 18.3**

### Property 18: System info excludes hardware identifiers

*For any* system information response, the output SHALL NOT contain MAC addresses (colon or dash-separated hex octets), serial numbers, or other hardware fingerprinting identifiers.

**Validates: Requirements 16.4**

## Error Handling

### Strategy

All errors are handled through a layered approach:

1. **Input Validation Layer** (before execution): FastMCP's type system handles basic type checking. Custom validators handle domain constraints (namespace length, key depth, path safety, value ranges).

2. **Execution Layer** (during subprocess/IO): The async command runner catches `FileNotFoundError` (command not in PATH), `asyncio.TimeoutError` (command exceeds timeout), and `subprocess.CalledProcessError` (non-zero exit).

3. **Parsing Layer** (after execution): Output parsers use try/except to catch malformed output and return `internal_error` with raw output for debugging.

4. **Response Layer** (tool function): Each tool function catches `ToolError` exceptions from lower layers and formats them into the standard error response structure.

### Error Code Mapping

| Situation | Code | Example |
|-----------|------|---------|
| Resource doesn't exist | `not_found` | Config namespace, systemd unit, desktop entry, clipboard index |
| Subsystem offline | `unavailable` | PipeWire down, NetworkManager stopped, command not in PATH |
| Bad input parameters | `validation_error` | Invalid path, wrong type, policy write attempt, traversal |
| Operation took too long | `timeout` | SIGTERM during tool, diagnostic component exceeds budget |
| Unexpected failure | `internal_error` | Malformed JSON config, unparseable command output |

### Subprocess Error Handling

```python
async def run_command(args: list[str], timeout: float = 5.0) -> CommandResult:
    try:
        proc = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except FileNotFoundError:
        raise ToolError(UNAVAILABLE, f"Command not found: {args[0]}")
    except asyncio.TimeoutError:
        proc.kill()
        raise ToolError(TIMEOUT, f"Command timed out after {timeout}s: {' '.join(args)}")
    
    if proc.returncode != 0:
        raise ToolError(INTERNAL_ERROR, f"Command failed with exit code {proc.returncode}", 
                       details={"command": args, "stderr": stderr.decode()})
    
    return CommandResult(stdout=stdout.decode(), stderr=stderr.decode(), returncode=proc.returncode)
```

### Graceful Shutdown

On SIGTERM or stdin EOF:
1. Set a shutdown flag
2. Allow in-flight tool invocations up to 5 seconds
3. If not complete, abort with timeout error response
4. Exit with code 0

```python
import signal
import asyncio

shutdown_event = asyncio.Event()

def handle_sigterm(signum, frame):
    shutdown_event.set()

signal.signal(signal.SIGTERM, handle_sigterm)
```

## Testing Strategy

### Testing Framework

- **Unit/Integration tests**: `pytest` with `pytest-asyncio`
- **Property-based tests**: `hypothesis` (Python's standard PBT library)
- **Mocking**: `unittest.mock` with `AsyncMock` for subprocess calls
- **Coverage**: `pytest-cov` with minimum 80% line coverage target

### Property-Based Testing Configuration

Each property test runs minimum **100 iterations** (Hypothesis default is 100, explicitly configured via settings).

```python
from hypothesis import given, settings, strategies as st

@settings(max_examples=100)
@given(...)
def test_property_N_description(self, ...):
    # Feature: ii-desktop-mcp, Property N: <property text>
    ...
```

### Test Organization

| Test File | Tests | Type |
|-----------|-------|------|
| `test_redaction.py` | Properties 2, 17 | Property |
| `test_config.py` | Properties 1, 3, 4 | Property |
| `test_validation.py` | Properties 5, 6, 7 | Property |
| `test_parsing.py` | Properties 8, 16 | Property |
| `test_clipboard.py` | Property 9 | Property |
| `test_apps.py` | Properties 10, 11 | Property |
| `test_shell_logs.py` | Property 12 | Property |
| `test_diagnostics.py` | Property 13 | Property |
| `test_errors.py` | Properties 14, 15 | Property |
| `test_system_info.py` | Property 18 | Property |
| `test_tools/` | Integration tests for each tool module | Integration |

### Dual Testing Approach

- **Property tests** verify universal invariants (redaction completeness, round-trip, clamping, filtering, structural guarantees) across randomly generated inputs
- **Unit tests** verify specific examples, edge cases, and error conditions (malformed JSON, missing files, specific error messages)
- **Integration tests** verify correct subprocess command construction and response parsing against mocked external commands

### Key Hypothesis Strategies

```python
# Generate nested config-like JSON objects
config_strategy = st.recursive(
    st.one_of(st.booleans(), st.integers(), st.floats(allow_nan=False), st.text()),
    lambda children: st.dictionaries(st.text(min_size=1, max_size=20), children),
    max_leaves=50,
)

# Generate valid dot-separated namespace paths
namespace_strategy = st.lists(
    st.from_regex(r"[a-zA-Z][a-zA-Z0-9]*", fullmatch=True),
    min_size=1, max_size=4
).map(".".join)

# Generate file paths with potential traversal
path_strategy = st.from_regex(r"[a-zA-Z0-9_./-]{1,200}", fullmatch=True)
```

### CI Integration

Tests run in Nix build via:
```nix
checkPhase = ''
  pytest tests/ -x --timeout=30
'';
```
