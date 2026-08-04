# Implementation Plan: MCP Streamable HTTP with SSE Support

## Overview

Implement full MCP Streamable HTTP transport with Server-Sent Events (SSE) support in the Quickshell McpServerBridge. The implementation adds an SSE event parser module, streaming curl process management, a server push channel, session ID lifecycle, incremental result delivery signals, and configuration compatibility — all while preserving existing stdio and one-shot HTTP paths.

## Tasks

- [x] 1. Create SseEventParser.mjs module
  - [x] 1.1 Implement the SseEventParser.mjs ES module with createParser() factory
    - Create `configs/quickshell/ii/services/mcp/SseEventParser.mjs`
    - Implement `feedLine(line)` — field parsing for `event:`, `data:`, `id:`, `retry:`, comment lines (`:` prefix), unrecognized fields (ignore), and blank-line event emission
    - Implement `end()` — discard incomplete event buffer on stream end
    - Implement `reset()` — clear all accumulated state
    - Enforce 10 MB size limit on accumulated data, returning `{ error: "size_limit_exceeded" }` from feedLine when exceeded
    - Export `createParser` as named export
    - JSON parsing of data field on event emission (pass raw string if invalid JSON)
    - Default event type to `"message"` when no `event:` field is present
    - Strip single leading space from field values after colon
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 1.3, 1.8_

  - [ ]* 1.2 Write property test for SSE field parsing (Property 7)
    - **Property 7: SSE Field Parsing**
    - Test that recognized fields (`event`, `data`, `id`, `retry`) are extracted correctly with single leading space stripped
    - Test that comment lines (`:` prefix) are discarded without affecting buffer
    - Test that unrecognized field names are ignored without error
    - **Validates: Requirements 5.1, 5.4, 5.7**

  - [ ]* 1.3 Write property test for SSE event emission on blank line (Property 8)
    - **Property 8: SSE Event Emission on Blank Line**
    - Test that a sequence of field lines followed by a blank line emits exactly one event with correct type and concatenated data, then resets the buffer
    - **Validates: Requirements 5.2**

  - [ ]* 1.4 Write property test for SSE data JSON handling (Property 9)
    - **Property 9: SSE Data JSON Handling**
    - Test that valid JSON data is parsed to an object; invalid JSON is passed as raw string
    - **Validates: Requirements 5.5, 5.6**

  - [ ]* 1.5 Write property test for SSE parser chunking independence (Property 10)
    - **Property 10: SSE Parser Chunking Independence**
    - Test that feeding lines one-at-a-time produces identical events to feeding them in arbitrary batches (split at line boundaries)
    - **Validates: Requirements 5.9**

  - [ ]* 1.6 Write property test for multi-line data concatenation and JSON-RPC resolution (Property 1)
    - **Property 1: SSE Multi-Line Data Concatenation and JSON-RPC Resolution**
    - Test that N `data:` lines within a single event are concatenated with newline separators and parsed as a single JSON message
    - **Validates: Requirements 1.2, 1.3, 5.3**

- [x] 2. Checkpoint - Verify SseEventParser tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 3. Add session management and streaming properties to McpServerBridge
  - [x] 3.1 Add new properties, signals, and state for SSE transport to McpServerBridge.qml
    - Add properties: `sessionId`, `sseSupported`, `nonSseMarked`, `activeProcessCount`, `requestQueue`, `pushChannelProcess`, `pushChannelActive`, `reconnectAttempts`, `reconnectInterval`, `streamingAccumulator`
    - Add signals: `streamingContent(int requestId, string content)`, `progressNotification(string token, real current, real total)`, `pushChannelDisconnected()`
    - Add constants: `_maxConcurrentProcesses: 2`, `_maxQueueSize: 10`, `_inactivityTimeout: 120000`, `_idleDisconnectTimeout: 60000`, `_pushReconnectMax: 10`, `_pushReconnectCap: 30000`
    - _Requirements: 3.1, 3.5, 4.6, 4.7, 7.1_

  - [x] 3.2 Implement `_buildCurlHeaders()` helper for session ID inclusion
    - Build header array including `Content-Type: application/json`, `Accept: text/event-stream, application/json`, and `Mcp-Session-Id` (when stored)
    - _Requirements: 3.1, 3.2_

  - [x] 3.3 Implement session ID extraction from curl `-i` header output
    - Parse response headers (Phase 1 of header/body state machine) to extract `Content-Type` and `Mcp-Session-Id`
    - Store session ID on first receipt, replace on subsequent responses
    - _Requirements: 3.1, 3.2, 3.5_

  - [ ]* 3.4 Write property test for session ID persistence and inclusion (Property 5)
    - **Property 5: Session ID Persistence and Inclusion**
    - Test that any HTTP response with `Mcp-Session-Id` stores exactly that value, and all subsequent requests include it
    - **Validates: Requirements 3.1, 3.2, 3.5**

- [x] 4. Implement streaming HTTP request method
  - [x] 4.1 Implement `_sendStreamingHttpRequest(method, params, customTimeout)` with persistent Process + SplitParser
    - Use `curl -N -i` for streaming POST requests
    - Implement header/body phase detection (blank line separates headers from body)
    - Route body to SseEventParser when `Content-Type: text/event-stream`
    - Fall back to JSON accumulation when `Content-Type: application/json`
    - Reset request timeout timer on each received `data:` line
    - Emit `streamingContent` signal for intermediate data lines during `tools/call`
    - Resolve pending request with accumulated content on process exit (code 0)
    - Handle inactivity timeout (120s with no data → SIGTERM)
    - _Requirements: 1.1, 1.2, 1.4, 1.5, 1.6, 1.7, 4.2, 7.1, 7.3, 7.4, 7.5_

  - [x] 4.2 Implement process slot limiting and request queue
    - Track `activeProcessCount` (max 2 per server)
    - Implement `_enqueueRequest(method, params, timeout, promise)` when at capacity
    - Implement `_processQueue()` to dequeue after a process slot frees
    - Reject with capacity error when queue exceeds 10 entries
    - _Requirements: 4.6, 4.7_

  - [ ]* 4.3 Write property test for process concurrency limiting and request queueing (Property 6)
    - **Property 6: Process Concurrency Limiting and Request Queueing**
    - Test that at most 2 processes are active simultaneously and overflow is queued/rejected correctly
    - **Validates: Requirements 4.6, 4.7**

- [x] 5. Implement server push channel
  - [x] 5.1 Implement `_openPushChannel()` — persistent GET SSE stream
    - Launch `curl -N -i -X GET <endpoint>` with `Accept: text/event-stream` and session ID header
    - Use SplitParser on stdout for line-by-line delivery
    - Feed lines through header/body state machine then SseEventParser
    - Dispatch valid JSON-RPC notifications to handlers
    - Discard unparseable events with warning log, continue listening
    - _Requirements: 2.1, 2.2, 2.3, 4.1_

  - [x] 5.2 Implement push channel notification handlers
    - Handle `notifications/tools/list_changed` → call `discoverTools()`
    - Handle `notifications/progress` → emit `progressNotification` signal with token, current, total (-1 if omitted)
    - _Requirements: 2.4, 2.5_

  - [x] 5.3 Implement `_closePushChannel()` and push channel lifecycle integration
    - Close push channel on shutdown or disconnected state transition
    - Close push channel on idle timeout (60s no pending requests)
    - _Requirements: 2.7, 4.4_

  - [x] 5.4 Implement `_attemptPushChannelReconnect()` with exponential backoff
    - Backoff formula: `min(2^(N-1) * 1000, 30000)` ms
    - Maximum 10 reconnect attempts before transitioning to disconnected state
    - Emit `pushChannelDisconnected()` signal on failure
    - _Requirements: 2.6_

  - [ ]* 5.5 Write property test for exponential backoff calculation (Property 4)
    - **Property 4: Exponential Backoff Calculation**
    - Test that for attempt N (1–10), interval equals `min(2^(N-1) * 1000, 30000)` and after attempt 10 the bridge transitions to disconnected
    - **Validates: Requirements 2.6**

  - [ ]* 5.6 Write property test for push channel notification dispatch (Property 2)
    - **Property 2: Push Channel Notification Dispatch and Resilience**
    - Test that valid JSON-RPC notifications are dispatched and invalid data is discarded without affecting the channel
    - **Validates: Requirements 2.2, 2.3**

  - [ ]* 5.7 Write property test for progress signal emission (Property 3)
    - **Property 3: Progress Signal Emission**
    - Test that progress notifications emit correct signal with token, current, total (or -1 if omitted)
    - **Validates: Requirements 2.5**

- [x] 6. Checkpoint - Verify push channel and streaming tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Implement error recovery and session lifecycle
  - [x] 7.1 Implement tool call retry logic (network error → 2s delay → 1 retry)
    - On connection refused, DNS failure, or timeout: wait 2s, retry once
    - On second failure: reject pending request promise with failure reason
    - _Requirements: 8.1_

  - [x] 7.2 Implement push channel reconnection (3 attempts at 5s intervals on unexpected disconnect)
    - On push channel disconnect: attempt reconnect 3 times at 5s intervals
    - On all attempts failed: transition to error state, log warning with server name and attempt count
    - _Requirements: 8.2_

  - [x] 7.3 Implement session invalidation and re-handshake on HTTP 404
    - Clear stored session ID on 404 response
    - Re-initialize session (full handshake)
    - Retry original request once; on double-404 mark server unreachable
    - _Requirements: 3.3_

  - [x] 7.4 Implement `_sendSessionDelete()` on shutdown
    - Send HTTP DELETE with session ID header on graceful shutdown
    - 5-second timeout; discard session ID and proceed regardless of response
    - _Requirements: 3.4_

  - [x] 7.5 Implement HTTP 400/405 fallback to one-shot curl
    - On 400 or 405 response: mark `nonSseMarked = true`, log informational message
    - Route all subsequent requests to existing one-shot curl path until next `connectServer` call
    - _Requirements: 8.4_

  - [x] 7.6 Implement error-to-connected recovery (re-establish push channel + tool refresh)
    - When transitioning from error → connected: reopen push channel and call `discoverTools()`
    - _Requirements: 8.3_

  - [x] 7.7 Implement SIGTERM → 5s grace → SIGKILL escalation for stuck processes
    - On per-request timeout (30s): send SIGTERM to curl process
    - If process doesn't exit within 5s: send SIGKILL
    - _Requirements: 4.3_

- [x] 8. Implement McpClient signal forwarding and config parsing updates
  - [x] 8.1 Add `toolStreamingContent` signal to McpClient.qml and forward from bridges
    - Add `signal toolStreamingContent(string toolName, string content)` to McpClient
    - Connect each bridge's `streamingContent` signal to re-emit as `toolStreamingContent` with prefixed tool name
    - _Requirements: 7.2_

  - [x] 8.2 Update McpClient `_parseConfig` to handle `transport` field for SSE mode
    - Parse optional `"transport": "sse"` field from mcp.json server entries
    - When `transport` is `"sse"`: configure bridge for SSE-exclusive mode (no plain-JSON fallback probe)
    - When `url` present without explicit `transport`: attempt Streamable HTTP first, fall back to plain JSON if no SSE within 5s
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

  - [x] 8.3 Implement disabled server guard (skip all SSE/HTTP activity for disabled servers)
    - Ensure no curl process, SSE connection, reconnection attempt, or HTTP probe is initiated for disabled servers
    - _Requirements: 8.5_

  - [ ]* 8.4 Write property test for config parsing accepts minimal fields (Property 11)
    - **Property 11: Config Parsing Accepts Minimal Fields**
    - Test that mcp.json entries with only `url` and optional `autoApprove`/`disabled`/`transport` are parsed successfully
    - **Validates: Requirements 6.1**

  - [ ]* 8.5 Write property test for streaming signal forwarding (Property 12)
    - **Property 12: Streaming Signal Forwarding**
    - Test that bridge `streamingContent` signals are re-emitted as McpClient `toolStreamingContent` with correct prefixed tool name
    - **Validates: Requirements 7.1, 7.2**

  - [ ]* 8.6 Write property test for timeout reset during active streaming (Property 14)
    - **Property 14: Timeout Reset During Active Streaming**
    - Test that each `data:` line receipt resets the timeout timer so timeout only fires after configured interval of inactivity
    - **Validates: Requirements 7.5**

  - [ ]* 8.7 Write property test for disabled server guard (Property 15)
    - **Property 15: Disabled Server Guard**
    - Test that servers with `disabled: true` never have any process or connection initiated
    - **Validates: Requirements 8.5**

- [x] 9. Wire streaming request path into existing spawn and sendRequest flows
  - [x] 9.1 Update `_spawnHttp()` to use streaming handshake and open push channel on success
    - Replace one-shot curl probe with streaming-aware `_sendStreamingHttpRequest` for the initialization flow
    - Open push channel after successful connection when SSE is supported
    - Store session ID from handshake response headers
    - _Requirements: 1.1, 2.1, 3.1_

  - [x] 9.2 Update `sendRequest()` routing to use streaming path for SSE-capable servers
    - Route through `_sendStreamingHttpRequest` when `sseSupported` is true and `nonSseMarked` is false
    - Preserve existing `_sendHttpRequest` as fallback for non-SSE servers
    - Integrate process slot check and request queue before dispatching
    - _Requirements: 1.1, 1.4, 4.6_

  - [x] 9.3 Update `shutdown()` to include session DELETE and push channel cleanup
    - Call `_sendSessionDelete()` before process termination
    - Call `_closePushChannel()` to terminate persistent GET
    - Clear session ID and reset SSE state
    - _Requirements: 2.7, 3.4_

  - [ ]* 9.4 Write property test for accumulated content resolution (Property 13)
    - **Property 13: Accumulated Content Resolution**
    - Test that N data lines during a streaming tools/call response resolve the promise with the full accumulated content on process exit (code 0)
    - **Validates: Requirements 7.3**

- [x] 10. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document using Python hypothesis against the SseEventParser.mjs module (loaded via subprocess or direct JS execution)
- Unit tests validate specific examples and edge cases
- The SseEventParser.mjs is pure JavaScript and highly amenable to PBT via a thin Python wrapper
- QML-level integration (signals, Process lifecycle) will be validated via manual testing with `systemctl --user restart quickshell` after deployment

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "3.1"] },
    { "id": 1, "tasks": ["1.2", "1.3", "1.4", "1.5", "1.6", "3.2", "3.3"] },
    { "id": 2, "tasks": ["3.4", "4.1", "4.2"] },
    { "id": 3, "tasks": ["4.3", "5.1", "5.2", "5.3", "5.4"] },
    { "id": 4, "tasks": ["5.5", "5.6", "5.7", "7.1", "7.2", "7.3", "7.4", "7.5", "7.6", "7.7"] },
    { "id": 5, "tasks": ["8.1", "8.2", "8.3"] },
    { "id": 6, "tasks": ["8.4", "8.5", "8.6", "8.7", "9.1", "9.2", "9.3"] },
    { "id": 7, "tasks": ["9.4"] }
  ]
}
```
