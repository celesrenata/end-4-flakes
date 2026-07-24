# Implementation Plan: MCP Sidebar Integration

## Overview

This plan integrates the full MCP ecosystem into the Quickshell AI sidebar. It creates a `McpClient` singleton that manages server lifecycles, dynamically discovers tools via `tools/list`, dispatches tool calls over stdio JSON-RPC, converts schemas to per-provider formats, migrates existing HyprMCP tools, adds URL detection with inline fetch, and renders tool results in collapsible blocks. The existing `handleFunctionCall()` chain is preserved — MCP tools are a fallback path after built-in matching fails.

## Tasks

- [x] 1. Create McpServerBridge component and MCP protocol layer
  - [x] 1.1 Create `configs/quickshell/ii/services/mcp/McpServerBridge.qml` implementing per-server stdio JSON-RPC communication
    - Create the `services/mcp/` directory and `McpServerBridge.qml` component
    - Implement `Process` + `SplitParser` for stdout line-by-line reading
    - Implement JSON-RPC 2.0 request serialization (single-line UTF-8 JSON, newline-terminated, ≤1 MB)
    - Implement pending request map with id-based correlation (up to 32 concurrent)
    - Implement per-request timeout (configurable, default 30s) with cleanup
    - Handle malformed stdout lines: discard, log first 200 chars as warning
    - Handle server exit/EOF: reject all pending requests with disconnect error
    - Implement `spawn()` → starts process, sends `initialize` handshake, resolves on response within 10s
    - Implement `shutdown()` → graceful signal, force-kill after 5s fallback
    - Implement idle timer (5 min inactivity → shutdown)
    - Implement `discoverTools()` → send `tools/list`, parse response, populate `discoveredTools`
    - Implement state machine: disconnected → connecting → connected → error
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7_

  - [x] 1.2 Write property tests for JSON-RPC serialization (Properties 6, 7)
    - **Property 6: JSON-RPC request serialization** — For any valid tool call, serialized request is single-line UTF-8 JSON with `\n`, ≤1 MB, contains required fields
    - **Property 7: JSON-RPC serialization round-trip** — Serialize then parse produces semantically equivalent object
    - **Validates: Requirements 4.1, 4.8**

  - [x] 1.3 Write property tests for response correlation and malformed line handling (Properties 8, 9)
    - **Property 8: Response correlation under concurrency** — Up to 32 pending requests, responses in arbitrary order, each resolves correct request
    - **Property 9: Malformed stdout lines discarded** — Invalid JSON or non-JSON-RPC lines don't affect pending requests
    - **Validates: Requirements 4.3, 4.5, 4.4**

- [x] 2. Create McpClient singleton with tool registry and lifecycle management
  - [x] 2.1 Create `configs/quickshell/ii/services/McpClient.qml` singleton
    - Implement config parsing from `~/.kiro/settings/mcp.json` (read, validate, filter disabled entries)
    - Implement `toolRegistry` as plain JS object mapping `toolName → { serverName, originalName, description, inputSchema }`
    - Implement `serverStates` tracking (connected, disconnected, connecting, error, disabled)
    - Implement `autoApproveList` aggregation from all server configs
    - Implement `initialize()` → read config, instantiate `McpServerBridge` per enabled server (lazy, not spawned yet)
    - Implement `callTool(toolName, args)` → lazy-spawn target server if needed, dispatch JSON-RPC `tools/call`, return result
    - Implement tool name prefixing: `mcp_{server}_{tool}` for all MCP tools
    - Implement conflict detection: reject MCP tools matching built-in names, log warning
    - Implement `isToolAutoApproved(toolName)` check
    - Implement `setServerDisabled(name, disabled)` → update config, disconnect/skip server
    - Implement `getServerStatus()` for UI consumption
    - Emit `toolsChanged()` signal when registry updates
    - Handle missing/malformed mcp.json gracefully (operate with built-in tools only, log warning)
    - Handle invalid timeout values (clamp to default 30000ms if outside 1000–300000)
    - Set environment variables from server `env` field before spawning
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 3.1, 3.4, 3.5, 7.4, 10.1, 10.2, 10.3, 10.5, 10.6, 10.7_

  - [x] 2.2 Write property tests for config parsing and timeout clamping (Properties 1, 21, 22)
    - **Property 1: Config parsing filters disabled servers** — Parsing config produces exactly non-disabled entries with fields preserved
    - **Property 21: Timeout value clamping** — Values 1000–300000 used as-is, others default to 30000
    - **Property 22: Environment variable application** — All env key-value pairs present in process environment
    - **Validates: Requirements 1.1, 10.1, 10.3, 10.7, 10.2**

  - [x] 2.3 Write property tests for tool registry (Properties 2, 3, 5, 18)
    - **Property 2: Tool registry population from tools/list** — Valid entries registered, invalid skipped
    - **Property 3: Tool-to-server mapping invariant** — Every tool has non-empty serverName from config
    - **Property 5: Name collision prefixing** — Conflicting names get server prefix, no duplicates in registry
    - **Property 18: Built-in name conflict rejection** — MCP tools matching built-in names are rejected
    - **Validates: Requirements 2.2, 2.7, 2.4, 2.5, 8.7, 7.4**

  - [x] 2.4 Register McpClient singleton in `configs/quickshell/ii/services/qmldir`
    - Add `singleton McpClient 1.0 McpClient.qml` entry
    - _Requirements: 2.3_

- [x] 3. Checkpoint - Ensure MCP protocol and registry logic works
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Integrate McpClient into Ai.qml and implement provider-specific declarations
  - [x] 4.1 Modify `configs/quickshell/ii/services/Ai.qml` to integrate McpClient
    - Call `McpClient.initialize()` on component completion
    - Modify `tools` property to dynamically merge MCP tool declarations via `McpClient.getToolDeclarations(format)`
    - Connect to `McpClient.toolsChanged()` signal to rebuild declarations
    - Modify `handleFunctionCall()`: after built-in if/else chain, add MCP fallback via `McpClient.callTool()`
    - Add unknown function handling: display message, don't crash or leave pending state
    - Add `handleMcpToolCall()` function with auto-approve check and pending state
    - Add user approval UI flow: set `functionPending`, show tool name + args, handle approve/reject
    - On reject: deliver rejection notice as function response to LLM, continue conversation
    - Respect tool mode: "none" → no declarations, "search" → omit function tools, "functions" → include all
    - _Requirements: 2.3, 3.1, 3.2, 3.3, 3.5, 3.6, 3.7, 3.8, 7.1, 7.2, 7.3, 7.5, 7.6, 9.4_

  - [x] 4.2 Implement `getToolDeclarations(format)` in McpClient for Gemini, OpenAI, and Mistral formats
    - Gemini: `[{ "functionDeclarations": [...] }]` structure merged with built-in declarations
    - OpenAI: flat array of `{ name, description, parameters }` objects
    - Mistral: array of `{ type: "function", function: { name, description, parameters } }` objects
    - Preserve all property names, types, descriptions, and required arrays from MCP schemas
    - Handle empty registry gracefully (return empty array or omit tools field)
    - _Requirements: 9.1, 9.2, 9.3, 9.5, 9.6_

  - [x] 4.3 Write property tests for provider-specific declarations and dispatch priority (Properties 4, 17, 19, 20)
    - **Property 4: Function declarations include all registered tools** — Every registry tool + every built-in tool included, no omissions or duplicates
    - **Property 17: Dispatch priority** — Built-in match → built-in handler; registry match → MCP; neither → error
    - **Property 19: Schema conversion to provider formats** — Correct structure per provider
    - **Property 20: Schema property preservation** — All names, types, descriptions, required arrays preserved
    - **Validates: Requirements 2.3, 7.1, 7.2, 7.3, 9.1, 9.2, 9.3, 9.5**

  - [x] 4.4 Write property test for auto-approve decision (Property 10)
    - **Property 10: Auto-approve decision** — Tool in autoApprove list → execute without confirmation; not in list → require approval
    - **Validates: Requirements 3.5, 3.6**

- [x] 5. Migrate ii-desktop HyprMCP tools to unified MCP Client
  - [x] 5.1 Implement ii-desktop hybrid transport in McpClient (HTTP first, stdio fallback)
    - Try HTTP POST to `http://localhost:7580/mcp` with JSON-RPC format first (5s connection timeout)
    - On HTTP failure: fall back to spawning ii-desktop as stdio process via MCP_Config command
    - Complete MCP initialization handshake before dispatching tool calls
    - Map server-side tool names to prefixed LLM-facing names (`mcp_ii_desktop_*`)
    - Include all tools from ii-desktop `tools/list` in function declarations (audio_status, network_status, clipboard_list, apps_search, apps_launch, screenshot, system_info, diagnostic_bundle, config_read, config_set, set_keyword)
    - Implement write operation read-back verification for `config_set` and `set_keyword`
    - Remove old hardcoded `curl` dispatch for hypr_config_read, hypr_config_set, hypr_set_keyword (replace with MCP path)
    - Ensure config_read, config_set, set_keyword produce identical responses through new path
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7_

  - [x] 5.2 Write property test for write operation read-back verification (Property 23)
    - **Property 23: Write operation read-back verification** — Successful write → config_read for affected namespace → compare returned vs written value
    - **Validates: Requirements 8.6**

- [x] 6. Checkpoint - Ensure ii-desktop migration preserves existing functionality
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Implement URL detection and fetch integration
  - [x] 7.1 Create `configs/quickshell/ii/modules/sidebarLeft/aiChat/UrlActionChip.qml` component
    - Inline chip with two icon buttons: "Fetch with AI" and "Open in browser"
    - "Fetch with AI" invokes `McpClient.callTool("mcp_fetch_fetch", { url })` with 30s timeout
    - "Open" invokes `Qt.openUrlExternally(url)`
    - Only show "Fetch with AI" if fetch server is configured and not disabled
    - Style consistent with existing chip components (Material Design 3)
    - _Requirements: 5.1, 5.2, 5.4, 5.5_

  - [x] 7.2 Modify `configs/quickshell/ii/modules/sidebarLeft/AiChat.qml` to detect URLs and render action chips
    - Implement URL detection regex matching `https://`, `http://`, `www.` prefixes (max 2048 char URLs)
    - When user submits message with URLs, render per-URL `UrlActionChip` adjacent to detected URL
    - On "Fetch with AI": truncate returned content to 8000 characters, include in conversation context, instruct LLM to summarize
    - On fetch error/timeout: display error message, offer "Open in browser" fallback
    - _Requirements: 5.1, 5.2, 5.3, 5.6, 5.7_

  - [x] 7.3 Write property tests for URL detection and content truncation (Properties 12, 13)
    - **Property 12: URL detection** — All conforming URLs identified with positions and text, no matches exceeding 2048 chars
    - **Property 13: Fetch content truncation** — Content >8000 chars truncated to exactly 8000; ≤8000 included in full
    - **Validates: Requirements 5.1, 5.6, 5.3**

- [x] 8. Implement tool result presentation UI
  - [x] 8.1 Create `configs/quickshell/ii/modules/sidebarLeft/aiChat/MessageToolBlock.qml` component
    - Collapsible block with header "Tool: [tool_name]", defaults to expanded
    - Success state: `secondaryContainer` background color role
    - Error state: `error` color role background
    - Body: syntax-highlighted JSON code block if content is valid JSON, plain text otherwise
    - Loading state: spinner + tool name while pending; timeout indicator after 30s
    - Truncation: cap at 500 lines with overflow indicator showing total line count
    - Support up to 20 tool blocks per message (additional calls beyond 20 not rendered)
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_

  - [x] 8.2 Modify `configs/quickshell/ii/modules/sidebarLeft/aiChat/AiMessage.qml` to render tool blocks
    - Add tool block segment type to `splitMarkdownBlocks` or detect tool results in message data
    - Render `MessageToolBlock` for each tool invocation in assistant messages
    - Maintain invocation order, cap at 20 blocks per message
    - _Requirements: 6.1, 6.5_

  - [x] 8.3 Write property tests for tool result presentation (Properties 14, 15, 16)
    - **Property 14: Tool result line truncation** — >500 lines truncated with indicator; ≤500 displayed in full
    - **Property 15: Tool result block ordering and cap** — Blocks in invocation order, max 20 rendered
    - **Property 16: JSON content detection** — Valid JSON → syntax-highlighted code block; invalid → plain text
    - **Validates: Requirements 6.6, 6.5, 6.2**

- [x] 9. Implement MCP server status UI and configuration
  - [x] 9.1 Add MCP server status indicator to sidebar chat header in `configs/quickshell/ii/modules/sidebarLeft/AiChat.qml`
    - Display each MCP server's name and connection status (connected, disconnected, error, disabled)
    - Allow user to toggle server disabled state via the UI
    - On toggle: update `mcp.json` disabled field, disconnect/skip without restarting others
    - _Requirements: 10.4, 10.6_

- [x] 10. Final checkpoint - Full integration verification
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties using Python `hypothesis` (matching existing workspace test infrastructure)
- Unit tests validate specific examples and edge cases
- The implementation language is QML/JavaScript for UI components and Python for property-based tests
- Test file: `tests/test_mcp_integration.py` — contains all PBT for this feature
- All MCP tool names are prefixed with `mcp_{server}_{tool}` to avoid conflicts with built-in tools

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3", "2.1"] },
    { "id": 2, "tasks": ["2.2", "2.3", "2.4"] },
    { "id": 3, "tasks": ["4.1", "4.2"] },
    { "id": 4, "tasks": ["4.3", "4.4", "5.1"] },
    { "id": 5, "tasks": ["5.2", "7.1", "8.1"] },
    { "id": 6, "tasks": ["7.2", "7.3", "8.2"] },
    { "id": 7, "tasks": ["8.3", "9.1"] }
  ]
}
```
