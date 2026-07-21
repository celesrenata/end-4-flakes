# Implementation Plan: ii-desktop-mcp

## Overview

Build a Python MCP server providing structured desktop intelligence tools for the Quickshell-based Hyprland environment. The server extends hyprmcp with tools for configuration, audio, networking, systemd, clipboard, applications, diagnostics, shell logs, screenshots, and system information. Implementation follows a bottom-up approach: project scaffolding → core utilities → tool modules (in dependency order) → diagnostic bundle (composes other tools) → Nix packaging → property-based tests → integration tests.

## Tasks

- [x] 1. Project scaffolding and core structure
  - [x] 1.1 Initialize repository with pyproject.toml and directory structure
    - Restructure the existing hyprmcp repo at `/home/celes/sources/celesrenata/hyprmcp` into the new package layout
    - Create `pyproject.toml` with project metadata, dependencies (`mcp[cli]`), dev dependencies (`pytest`, `pytest-asyncio`, `hypothesis`, `pytest-cov`), and `[project.scripts]` entry point `ii-desktop-mcp = "ii_desktop_mcp.server:main"`
    - Create directory tree: `src/ii_desktop_mcp/`, `src/ii_desktop_mcp/core/`, `src/ii_desktop_mcp/tools/`, `tests/`, `tests/test_tools/`, `nix/`
    - Create `src/ii_desktop_mcp/__init__.py`, `src/ii_desktop_mcp/core/__init__.py`, `src/ii_desktop_mcp/tools/__init__.py`
    - Migrate existing hyprctl tools from `hyprmcp/server.py` into `src/ii_desktop_mcp/tools/hyprland.py` preserving all original functionality
    - Create `tests/__init__.py`, `tests/test_tools/__init__.py`
    - Update `README.md` with new project description
    - _Requirements: 17.7_

  - [x] 1.2 Create server entrypoint and tool registration orchestrator
    - Create `src/ii_desktop_mcp/server.py` with FastMCP server instantiation (`mcp = FastMCP("ii-desktop-mcp")`), import all tool modules, call `module.register(mcp)` for each, define `main()` calling `mcp.run(transport="stdio")`
    - Create `src/ii_desktop_mcp/tools/__init__.py` as the tool registration orchestrator (empty initially, modules register themselves)
    - _Requirements: 17.1, 17.2_

  - [x] 1.3 Create test configuration and shared fixtures
    - Create `tests/conftest.py` with shared pytest fixtures: mock config file (tmp_path), sample config JSON, Hypothesis profiles (ci profile with max_examples=100)
    - Create `pytest.ini` or `pyproject.toml` pytest section with asyncio_mode = "auto" and timeout = 30
    - _Requirements: All (testing infrastructure)_

- [x] 2. Core utilities implementation
  - [x] 2.1 Implement async subprocess runner (`core/subprocess.py`)
    - Create `src/ii_desktop_mcp/core/subprocess.py` with `CommandResult` dataclass (stdout, stderr, returncode), `run_command(args, timeout, env)` async function
    - Handle `FileNotFoundError` → raise `ToolError(UNAVAILABLE, ...)` naming the missing command
    - Handle `asyncio.TimeoutError` → kill process, raise `ToolError(TIMEOUT, ...)`
    - Handle non-zero exit → raise `ToolError(INTERNAL_ERROR, ...)` with stderr in details
    - _Requirements: 19.3, 19.4_

  - [x] 2.2 Implement error response module (`core/errors.py`)
    - Create `src/ii_desktop_mcp/core/errors.py` with `ToolError` exception class (code, message, details), `error_response()` builder function
    - Define standard error code constants: `NOT_FOUND`, `UNAVAILABLE`, `VALIDATION_ERROR`, `TIMEOUT`, `INTERNAL_ERROR`
    - _Requirements: 19.1, 19.2_

  - [x] 2.3 Implement redaction logic (`core/redaction.py`)
    - Create `src/ii_desktop_mcp/core/redaction.py` with `REDACTED = "[REDACTED]"`, `SENSITIVE_KEY_PATTERNS` (key, secret, password, token — case-insensitive regexes), `SENSITIVE_PATHS` set (ai.systemPrompt), `SENSITIVE_NAMESPACES` list (sidebar.booru.zerochan)
    - Implement `redact_config(config, path_prefix)` that deep-copies and replaces sensitive values
    - Implement `is_sensitive_key(key, full_path)` helper
    - _Requirements: 1.6, 18.2, 18.3_

  - [x] 2.4 Implement input validation (`core/validation.py`)
    - Create `src/ii_desktop_mcp/core/validation.py` with `ALLOWED_WRITE_PATHS` (config.json, ~/Pictures/Screenshots/)
    - Implement `validate_write_path(path)` — reject traversal, resolve symlinks, check against allowlist
    - Implement `validate_namespace(namespace)` — max 256 chars, valid characters
    - Implement `validate_config_key(key)` — max 4 segments, reject policies.* prefix, check against CONFIG_SCHEMA
    - _Requirements: 18.4, 18.5, 18.6, 18.7, 18.8_

  - [x] 2.5 Implement config schema type map
    - Add `CONFIG_SCHEMA` dict and `ConfigType` enum to `core/validation.py` (or a dedicated `core/schema.py`)
    - Map all config key paths to their expected types as defined in the design document
    - _Requirements: 2.1, 2.4, 2.5_

- [x] 3. Checkpoint — Core utilities
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Config tool module
  - [x] 4.1 Implement config_read tool (`tools/config.py`)
    - Create `src/ii_desktop_mcp/tools/config.py` with `register(mcp)` function
    - Implement `config_read(namespace="")` — read Shell_Config JSON, apply namespace extraction, redact sensitive values, return subtree
    - Handle missing file → error "unavailable", malformed JSON → error "internal_error", missing namespace → error "not_found"
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8_

  - [x] 4.2 Implement config_set tool (`tools/config.py`)
    - Implement `config_set(key, value)` — validate key (max 4 segments, exists in schema, not policies.*), validate value type, read current file, update value, write atomically, return {key, previous, new}
    - Handle unrecognized key → error, type mismatch → error with expected type, policies.* → error "read-only"
    - Handle missing/corrupt config file → error without creating/overwriting
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9_

  - [x] 4.3 Write property tests for config namespace extraction
    - **Property 1: Config namespace extraction returns correct subtree**
    - **Validates: Requirements 1.3**

  - [x] 4.4 Write property tests for config round-trip
    - **Property 3: Config write/read round-trip**
    - **Validates: Requirements 2.2, 2.7, 2.8**

  - [x] 4.5 Write property tests for config key validation
    - **Property 4: Config key validation rejects invalid keys**
    - **Validates: Requirements 2.1, 2.3, 2.4, 2.6**

- [x] 5. Redaction and validation property tests
  - [x] 5.1 Write property tests for redaction completeness
    - **Property 2: Redaction completeness and structure preservation**
    - **Validates: Requirements 1.6, 18.2**

  - [x] 5.2 Write property tests for path validation
    - **Property 5: Write path validation restricts to allowed directories**
    - **Validates: Requirements 18.6, 18.7, 18.8**

  - [x] 5.3 Write property tests for integer parameter clamping
    - **Property 6: Integer parameter clamping**
    - **Validates: Requirements 8.3, 9.4, 11.5, 14.3**

  - [x] 5.4 Write property tests for volume clamping
    - **Property 7: Volume clamping with notice**
    - **Validates: Requirements 4.5**

- [x] 6. Audio tool module
  - [x] 6.1 Implement audio_status tool (`tools/audio.py`)
    - Create `src/ii_desktop_mcp/tools/audio.py` with `register(mcp)` function
    - Implement `audio_status()` — run wpctl/pactl, parse output into structured JSON (default sink/source, volumes, mute states, all sinks/sources)
    - Handle missing PipeWire/WirePlumber → error "unavailable"
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [x] 6.2 Implement audio_set_volume tool (`tools/audio.py`)
    - Implement `audio_set_volume(target, volume, mute)` — validate target, clamp volume >150 to 150 with notice, execute wpctl commands, return resulting state
    - Handle invalid target → error "not_found"
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 7. Network tool module
  - [x] 7.1 Implement network_status tool (`tools/network.py`)
    - Create `src/ii_desktop_mcp/tools/network.py` with `register(mcp)` function
    - Implement `network_status()` — run nmcli commands, parse connectivity state, active connections (type, device, name, SSID, signal for wifi)
    - Handle missing NetworkManager → error "unavailable"
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x] 7.2 Implement network_wifi_list tool (`tools/network.py`)
    - Implement `network_wifi_list()` — run `nmcli -t -f ...` to list APs, parse into structured array (SSID, signal %, security, connected status)
    - Never expose WiFi passwords/PSK values
    - Handle no WiFi device → error "not_found"
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

- [x] 8. Systemd tool module
  - [x] 8.1 Implement systemd_status tool (`tools/systemd_svc.py`)
    - Create `src/ii_desktop_mcp/tools/systemd_svc.py` with `register(mcp)` function
    - Implement `systemd_status(unit="", scope="user")` — without unit: summary of failed/running counts + failed unit list; with unit: detailed status (active state, sub-state, PID, memory, last 20 journal lines)
    - Handle --user vs system scope, missing unit → error "not_found"
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

  - [x] 8.2 Implement systemd_logs tool (`tools/systemd_svc.py`)
    - Implement `systemd_logs(unit, lines=50, scope="user", priority=None)` — run journalctl with appropriate flags, cap lines at 500, parse output
    - Handle no entries → return empty array with message
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

- [x] 9. Clipboard tool module
  - [x] 9.1 Implement clipboard_list tool (`tools/clipboard.py`)
    - Create `src/ii_desktop_mcp/tools/clipboard.py` with `register(mcp)` function
    - Implement `clipboard_list(search="", limit=20)` — run cliphist list (or cliphist search), parse entries, truncate previews to 200 chars, cap limit at 100
    - Handle missing cliphist → error "unavailable"
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_

  - [x] 9.2 Implement clipboard_copy tool (`tools/clipboard.py`)
    - Implement `clipboard_copy(index)` — pipe entry through `cliphist decode | wl-copy`, return success
    - Handle invalid index → error "not_found"
    - _Requirements: 10.1, 10.2, 10.3_

  - [x] 9.3 Write property test for clipboard preview truncation
    - **Property 9: Clipboard preview truncation**
    - **Validates: Requirements 9.2**

- [x] 10. Apps tool module
  - [x] 10.1 Implement apps_search tool (`tools/apps.py`)
    - Create `src/ii_desktop_mcp/tools/apps.py` with `register(mcp)` function
    - Implement `apps_search(query, limit=10)` — scan XDG data dirs for .desktop files, case-insensitive fuzzy match against Name/GenericName/Comment/Keywords, exclude NoDisplay=true/Hidden=true, cap limit at 50
    - Return: desktop entry ID, display name, generic name, comment, exec, icon, categories
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

  - [x] 10.2 Implement apps_launch tool (`tools/apps.py`)
    - Implement `apps_launch(id)` — locate .desktop file by ID, launch detached (gtk-launch or direct Exec), return success
    - Handle missing entry → error "not_found"
    - _Requirements: 12.1, 12.2, 12.3, 12.4_

  - [x] 10.3 Write property tests for app search filtering
    - **Property 10: App search excludes hidden entries**
    - **Property 11: App search is case-insensitive**
    - **Validates: Requirements 11.3, 11.4**

- [x] 11. Shell logs tool module
  - [x] 11.1 Implement shell_logs tool (`tools/shell_logs.py`)
    - Create `src/ii_desktop_mcp/tools/shell_logs.py` with `register(mcp)` function
    - Implement `shell_logs(lines=50, level="all")` — run journalctl for quickshell unit, cap lines at 200, filter by level (all/warning/error)
    - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5_

  - [x] 11.2 Write property test for log level filtering
    - **Property 12: Log level filtering correctness**
    - **Validates: Requirements 14.2, 14.4, 14.5**

- [x] 12. Screenshot tool module
  - [x] 12.1 Implement screenshot tool (`tools/screenshot.py`)
    - Create `src/ii_desktop_mcp/tools/screenshot.py` with `register(mcp)` function
    - Implement `screenshot(mode, output="", path="")` — validate path against allowed write dirs, execute grim (+ slurp for region, + hyprctl for window geometry), generate timestamped filename if no path given
    - Handle missing grim → error "unavailable", invalid path → error "validation_error"
    - _Requirements: 15.1, 15.2, 15.3, 15.4, 15.5_

- [x] 13. System info tool module
  - [x] 13.1 Implement system_info tool (`tools/system_info.py`)
    - Create `src/ii_desktop_mcp/tools/system_info.py` with `register(mcp)` function
    - Implement `system_info()` — read /proc/cpuinfo, /proc/meminfo, /proc/uptime, /sys entries, run uname/lspci/free/df, parse into structured JSON
    - Exclude serial numbers, MAC addresses, hardware identifiers
    - _Requirements: 16.1, 16.2, 16.3, 16.4_

  - [x] 13.2 Write property test for system info privacy
    - **Property 18: System info excludes hardware identifiers**
    - **Validates: Requirements 16.4**

- [x] 14. Checkpoint — All tool modules
  - Ensure all tests pass, ask the user if questions arise.

- [x] 15. Diagnostic bundle (composes other tools)
  - [x] 15.1 Implement diagnostic_bundle tool (`tools/diagnostics.py`)
    - Create `src/ii_desktop_mcp/tools/diagnostics.py` with `register(mcp)` function
    - Implement `diagnostic_bundle()` — concurrently gather all diagnostic components using `asyncio.gather(..., return_exceptions=True)` within a 10-second budget
    - Components: Hyprland state (hyprctl), failed systemd units, PipeWire status, NetworkManager connectivity, redacted config, GPU info (lspci), memory (/proc/meminfo), disk (df), Quickshell logs (last 30 lines)
    - For each failed component: include with null data + error string
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5_

  - [x] 15.2 Write property test for diagnostic bundle resilience
    - **Property 13: Diagnostic bundle resilience to component failures**
    - **Validates: Requirements 13.4**

- [x] 16. Server lifecycle and signal handling
  - [x] 16.1 Implement graceful shutdown in server.py
    - Add SIGTERM handler setting shutdown event, stdin EOF detection
    - Allow in-flight tool invocations up to 5 seconds on shutdown, then abort with timeout error
    - Ensure diagnostic messages go to stderr only, stdout reserved for MCP protocol
    - _Requirements: 17.1, 17.3, 17.4, 17.5, 17.6_

- [x] 17. Error handling property tests
  - [x] 17.1 Write property tests for error response structure
    - **Property 14: Error response structure invariant**
    - **Validates: Requirements 19.1, 19.2**

  - [x] 17.2 Write property test for missing command error identification
    - **Property 15: Missing command error identifies the command**
    - **Validates: Requirements 19.3**

  - [x] 17.3 Write property test for unexpected output resilience
    - **Property 16: Unexpected command output does not crash the server**
    - **Validates: Requirements 19.4**

  - [x] 17.4 Write property test for command output parsing
    - **Property 8: Command output parsing produces valid structured output**
    - **Validates: Requirements 3.1, 5.1, 6.1, 16.1**

  - [x] 17.5 Write property test for no sensitive data leakage
    - **Property 17: No sensitive data leakage in any tool response**
    - **Validates: Requirements 6.3, 18.3**

- [x] 18. Checkpoint — All property tests
  - Ensure all tests pass, ask the user if questions arise.

- [x] 19. Nix packaging
  - [x] 19.1 Create flake.nix with package derivation
    - Create `flake.nix` with nixpkgs input, `buildPythonApplication` derivation using pyproject format, `propagatedBuildInputs` for mcp[cli], `makeWrapperArgs` adding runtime PATH for all external commands (hyprland, wireplumber, pulseaudio, networkmanager, systemd, cliphist, wl-clipboard, grim, slurp, pciutils)
    - Support x86_64-linux and aarch64-linux
    - Include `checkPhase` running pytest
    - _Requirements: 17.7_

  - [x] 19.2 Create home-manager module (`nix/module.nix`)
    - Create `nix/module.nix` defining `services.ii-desktop-mcp.enable` option
    - Configure systemd user service with Type=simple, ExecStart pointing to package binary, Restart=on-failure, RestartSec=5, After/PartOf graphical-session.target
    - Wire stdin/stdout as socket for MCP stdio transport, stderr to journal
    - _Requirements: 17.7_

  - [x] 19.3 Create Nix package derivation (`nix/package.nix`)
    - Factor out the `buildPythonApplication` call into `nix/package.nix` for cleaner separation if needed, or keep inline in flake.nix
    - Ensure the package builds cleanly with `nix build`
    - _Requirements: 17.7_

- [x] 20. Integration tests
  - [x] 20.1 Write integration tests for config tools
    - Test config_read with mocked file, config_set with tmp_path, round-trip behavior
    - Mock filesystem, verify file writes
    - _Requirements: 1.1–1.8, 2.1–2.9_

  - [x] 20.2 Write integration tests for audio tools
    - Mock wpctl/pactl subprocess calls, verify correct command construction and response parsing
    - _Requirements: 3.1–3.4, 4.1–4.5_

  - [x] 20.3 Write integration tests for network tools
    - Mock nmcli subprocess calls, verify parsing of connectivity and WiFi list output
    - Verify no PSK values in response
    - _Requirements: 5.1–5.4, 6.1–6.4_

  - [x] 20.4 Write integration tests for systemd tools
    - Mock systemctl/journalctl subprocess calls, verify status parsing and log retrieval
    - _Requirements: 7.1–7.5, 8.1–8.4_

  - [x] 20.5 Write integration tests for clipboard tools
    - Mock cliphist/wl-copy subprocess calls, verify list parsing and copy pipeline
    - _Requirements: 9.1–9.5, 10.1–10.3_

  - [x] 20.6 Write integration tests for apps tools
    - Create mock .desktop files in tmp_path, verify search and launch behavior
    - _Requirements: 11.1–11.5, 12.1–12.4_

  - [x] 20.7 Write integration tests for diagnostic bundle
    - Mock all subprocess calls, verify concurrent collection, verify resilience to partial failures
    - _Requirements: 13.1–13.5_

  - [x] 20.8 Write integration tests for screenshot tool
    - Mock grim/slurp/hyprctl, verify correct command construction per mode, verify path validation
    - _Requirements: 15.1–15.5_

- [x] 21. Final checkpoint
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document (18 total)
- Unit/integration tests validate specific examples and edge cases
- The diagnostic bundle (task 15) is intentionally placed after all other tool modules since it composes their functionality
- Nix packaging (task 19) can be developed in parallel with testing tasks since it depends only on the Python source being complete
- The implementation targets the forked hyprmcp repository at `/home/celes/sources/celesrenata/hyprmcp` — this is the upstream fork being extended
- The existing `hyprmcp/server.py` serves as the base; we restructure it into the `src/ii_desktop_mcp/` package layout while preserving existing hyprctl tools
- External commands (wpctl, nmcli, systemctl, etc.) should always be mocked in tests — never call real system binaries
- The end-4-flakes flake.nix should import this MCP server package as a flake input for integration

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3"] },
    { "id": 2, "tasks": ["2.1", "2.2"] },
    { "id": 3, "tasks": ["2.3", "2.4", "2.5"] },
    { "id": 4, "tasks": ["4.1", "5.1", "5.2", "5.3", "5.4"] },
    { "id": 5, "tasks": ["4.2", "6.1", "7.1", "8.1", "9.1", "10.1", "11.1", "12.1", "13.1"] },
    { "id": 6, "tasks": ["4.3", "4.4", "4.5", "6.2", "7.2", "8.2", "9.2", "9.3", "10.2", "10.3", "11.2", "13.2"] },
    { "id": 7, "tasks": ["15.1", "16.1"] },
    { "id": 8, "tasks": ["15.2", "17.1", "17.2", "17.3", "17.4", "17.5"] },
    { "id": 9, "tasks": ["19.1", "19.2", "19.3"] },
    { "id": 10, "tasks": ["20.1", "20.2", "20.3", "20.4", "20.5", "20.6", "20.7", "20.8"] }
  ]
}
```
