# Requirements Document

## Introduction

Add full MCP Streamable HTTP transport with Server-Sent Events (SSE) support to the Quickshell McpServerBridge. Currently, HTTP-based MCP servers are contacted via one-shot curl POST requests that wait for the complete response before parsing. This feature upgrades the HTTP transport to maintain persistent SSE connections, enabling streaming tool responses, server-initiated notifications, and session management. The same `~/.kiro/settings/mcp.json` configuration must work for both the Quickshell sidebar and VS Code (Kiro IDE) without modification.

## Glossary

- **McpServerBridge**: The per-server QML component in Quickshell that manages communication with a single MCP server via stdio or HTTP transport.
- **McpClient**: The singleton QML component that manages all MCP server lifecycles, tool registry, and dispatches tool calls to the appropriate McpServerBridge.
- **SSE_Connection**: A persistent HTTP connection using the `text/event-stream` content type that allows the server to push events to the client over a long-lived response.
- **Streamable_HTTP_Transport**: The MCP transport protocol (spec 2024-11-05) where the client sends JSON-RPC via HTTP POST and receives responses as either plain JSON or an SSE stream, with optional server-push via a GET endpoint.
- **Session_Id**: An opaque identifier sent by the server in the `Mcp-Session-Id` response header, used by the client to correlate subsequent requests with an established session.
- **SSE_Event**: A single event in an SSE stream, consisting of optional `event:` and `data:` fields separated by newlines, terminated by a blank line.
- **Streaming_Curl_Process**: A curl process launched with `--no-buffer` that writes output incrementally as data arrives rather than buffering until completion.
- **Tool_Call_Response**: The JSON-RPC result returned by an MCP server in response to a `tools/call` request, potentially delivered incrementally via SSE events.
- **Server_Push_Channel**: A persistent GET request to the server's SSE endpoint that receives server-initiated notifications (tool list changes, progress updates) outside of request-response cycles.
- **mcp_json_Config**: The shared configuration file at `~/.kiro/settings/mcp.json` that defines MCP server endpoints and is consumed by both Quickshell and VS Code.

## Requirements

### Requirement 1: Persistent SSE Connection for Tool Call Responses

**User Story:** As a Quickshell sidebar user, I want tool call responses to stream incrementally via SSE, so that I can see partial results as they arrive during long-running tool calls.

#### Acceptance Criteria

1. WHEN the McpServerBridge sends an HTTP POST for a `tools/call` request and the server responds with `Content-Type: text/event-stream`, THE McpServerBridge SHALL process each SSE event as it is written to curl's stdout, delivering parsed event data to the pending request handler within 100 milliseconds of receipt.
2. WHEN a `data:` line containing a complete JSON-RPC response (a well-formed JSON object with `jsonrpc`, `id`, and either `result` or `error` fields) is received in the SSE stream, THE McpServerBridge SHALL resolve the pending request with the parsed result.
3. WHEN multiple `data:` lines are received within the same SSE event (delimited by a blank line per the SSE specification), THE McpServerBridge SHALL concatenate the `data:` field values separated by a newline character and parse the combined value as a single JSON message, up to a maximum concatenated size of 10 MB.
4. WHEN the server responds with `Content-Type: application/json` instead of `text/event-stream`, THE McpServerBridge SHALL fall back to the existing one-shot response parsing behavior.
5. IF the SSE stream terminates unexpectedly before delivering a complete JSON-RPC response, THEN THE McpServerBridge SHALL reject the pending request with an error indicating whether the cause was a connection drop or an inactivity timeout, and include the elapsed time since the last received data.
6. THE Streaming_Curl_Process SHALL use `--no-buffer` (or equivalent) to ensure curl does not buffer SSE data before writing to stdout.
7. IF no data is received on the SSE stream for 120 seconds, THEN THE McpServerBridge SHALL terminate the curl process and reject the pending request with an inactivity timeout error.
8. IF the concatenated SSE event data exceeds 10 MB before a blank-line delimiter is received, THEN THE McpServerBridge SHALL terminate the curl process and reject the pending request with an error indicating the message size limit was exceeded.

### Requirement 2: Server-Initiated Notification Channel

**User Story:** As a Quickshell sidebar user, I want to receive server-initiated notifications (like tool list changes and progress updates), so that the sidebar reflects server state changes without polling.

#### Acceptance Criteria

1. WHEN the McpServerBridge establishes a session with an HTTP-based MCP server, THE McpServerBridge SHALL open a Server_Push_Channel by issuing a GET request to the server's SSE endpoint.
2. WHILE the Server_Push_Channel is open, THE McpServerBridge SHALL parse incoming SSE_Events that contain valid JSON-RPC notifications and dispatch them to the appropriate handler within 200 milliseconds of receipt.
3. IF a received SSE_Event cannot be parsed as a valid JSON-RPC message, THEN THE McpServerBridge SHALL discard the event, log a warning, and continue listening on the Server_Push_Channel without interruption.
4. WHEN a `notifications/tools/list_changed` notification is received on the Server_Push_Channel, THE McpServerBridge SHALL re-discover tools by sending a `tools/list` request.
5. WHEN a `notifications/progress` notification is received on the Server_Push_Channel, THE McpServerBridge SHALL emit a signal containing the progress token, current value, and total value where total is set to -1 if the server omits it.
6. IF the Server_Push_Channel connection drops, THEN THE McpServerBridge SHALL attempt to reconnect with exponential backoff starting at 1 second, doubling each interval, capping at 30 seconds, for a maximum of 10 attempts before transitioning to the disconnected state and emitting a connection-failure signal.
7. WHEN the McpServerBridge shuts down or enters the disconnected state, THE McpServerBridge SHALL close the Server_Push_Channel curl process.

### Requirement 3: Session Management

**User Story:** As a Quickshell sidebar user, I want the MCP client to maintain session state with HTTP servers, so that servers can associate multiple requests with the same client session.

#### Acceptance Criteria

1. WHEN the server includes an `Mcp-Session-Id` header in any HTTP response, THE McpServerBridge SHALL store the Session_Id and include it as an `Mcp-Session-Id` request header in all subsequent HTTP requests to that server.
2. WHILE the McpServerBridge has a stored Session_Id for a server, WHEN the McpServerBridge sends an HTTP request to that server, THE McpServerBridge SHALL include the stored Session_Id in the `Mcp-Session-Id` request header.
3. IF a server responds with HTTP 404 to a request that includes a Session_Id, THEN THE McpServerBridge SHALL clear the stored Session_Id, re-initialize the session by performing the full handshake, and retry the original request at most 1 time; if the retry also receives HTTP 404, THE McpServerBridge SHALL report the server as unreachable and cease further requests to that server until the next explicit user-initiated connection attempt.
4. WHEN the McpServerBridge shuts down a server connection, THE McpServerBridge SHALL send an HTTP DELETE request to the server endpoint with the stored Session_Id header to signal session termination; IF the DELETE request does not receive a response within 5 seconds or receives an error response, THEN THE McpServerBridge SHALL discard the stored Session_Id and proceed with shutdown without blocking.
5. THE McpServerBridge SHALL store at most one Session_Id per server instance.

### Requirement 4: Streaming Curl Process Management

**User Story:** As a Quickshell sidebar user, I want the SSE curl processes to be managed reliably, so that connections do not leak resources or hang indefinitely.

#### Acceptance Criteria

1. THE McpServerBridge SHALL use a single long-lived Streaming_Curl_Process per Server_Push_Channel rather than spawning a new process for each notification.
2. WHEN a tool call HTTP POST produces an SSE response, THE McpServerBridge SHALL use a Streaming_Curl_Process that reads stdout line-by-line and emits parsed events incrementally.
3. WHEN the per-request timeout of 30 seconds expires and the Streaming_Curl_Process has not received a complete JSON-RPC response, THE McpServerBridge SHALL send SIGTERM to the curl process and reject the pending request with a timeout error indication. IF the curl process does not exit within 5 seconds of receiving SIGTERM, THEN THE McpServerBridge SHALL send SIGKILL to force termination.
4. WHEN the idle timeout of 60 seconds fires and no requests are pending, THE McpServerBridge SHALL terminate the Server_Push_Channel curl process and transition to disconnected state.
5. IF a Streaming_Curl_Process exits with a non-zero exit code, THEN THE McpServerBridge SHALL log the error including the exit code and transition the affected channel to an error state.
6. THE McpServerBridge SHALL limit the total number of concurrent curl processes per server to 2 (one for requests, one for the push channel).
7. IF a new request arrives while the per-server curl process limit of 2 is already reached, THEN THE McpServerBridge SHALL queue the request and process it when a process slot becomes available or reject it with a capacity error indication if the queue exceeds 10 pending requests.

### Requirement 5: SSE Event Parser

**User Story:** As a developer, I want a robust SSE event parser, so that all valid SSE streams from MCP servers are correctly interpreted.

#### Acceptance Criteria

1. THE SSE_Event parser SHALL parse `event:`, `data:`, `id:`, and `retry:` fields as defined by the W3C Server-Sent Events specification, storing each field's value after stripping a single leading space character following the colon if present.
2. WHEN a blank line (empty line or line containing only a newline) is received, THE SSE_Event parser SHALL emit the accumulated event with its `event` type (defaulting to `message` if no `event:` field was provided) and `data` payload, then reset the event buffer.
3. WHEN multiple consecutive `data:` lines are received before a blank line, THE SSE_Event parser SHALL concatenate them with newline separators into a single `data` field.
4. WHEN a line starts with `:` (colon), THE SSE_Event parser SHALL treat the line as a comment and discard it without affecting the current event.
5. WHEN the `data` field of an emitted event contains valid JSON, THE SSE_Event parser SHALL parse the JSON and pass the resulting object to the event handler.
6. IF the `data` field of an emitted event is not valid JSON, THEN THE SSE_Event parser SHALL pass the raw string to the event handler.
7. WHEN a line contains an unrecognized field name (not `event`, `data`, `id`, or `retry`), THE SSE_Event parser SHALL ignore the line without affecting the current event or producing an error.
8. IF the stream ends before a blank line is received and the event buffer contains accumulated data, THEN THE SSE_Event parser SHALL discard the incomplete event without emitting it to the event handler.
9. THE SSE_Event parser SHALL preserve round-trip fidelity such that for any valid SSE stream, the sequence of emitted events (each with its event type and data payload) is identical whether the stream is delivered one line at a time or in arbitrary chunks split at line boundaries.

### Requirement 6: Configuration Compatibility

**User Story:** As a user of both Quickshell and VS Code, I want the mcp.json configuration to work for both clients without modification, so that I maintain a single source of truth for MCP server settings.

#### Acceptance Criteria

1. THE McpClient SHALL read server endpoints from the `url` field in mcp_json_Config entries without requiring any fields beyond `url`, `autoApprove`, `disabled`, and the optional `transport` field for HTTP-transport servers.
2. WHEN the McpClient encounters a server entry containing a `url` field and no explicit `transport` field, THE McpClient SHALL first attempt a Streamable HTTP connection with SSE support, and if no SSE event stream is received within 5 seconds, SHALL fall back to the plain JSON-RPC response path.
3. IF a server does not support SSE and responds with a plain JSON-RPC response to the initial Streamable HTTP request, THEN THE McpClient SHALL process the response using the plain JSON-RPC path and SHALL NOT treat the absence of SSE as an error.
4. WHERE a server entry includes a `"transport": "sse"` field, THE McpClient SHALL use SSE mode exclusively for that server and SHALL NOT attempt the plain-JSON fallback probe.
5. THE mcp_json_Config file SHALL contain no Quickshell-specific required fields, such that VS Code (Kiro IDE) parses and operates on all server entries that use the `url` or `command`/`args` fields, ignoring any unrecognized optional fields (e.g., `transport`) without error.

### Requirement 7: Incremental Result Delivery to UI

**User Story:** As a Quickshell sidebar user, I want to see tool call progress in real time, so that long-running operations provide feedback rather than appearing frozen.

#### Acceptance Criteria

1. WHEN the McpServerBridge receives an SSE `data:` line from an in-progress `tools/call` HTTP response while the request process is still running, THE McpServerBridge SHALL emit a `streamingContent` signal carrying the request ID and the partial text content extracted from that `data:` line.
2. WHILE a tool call is in progress and streamingContent signals are being emitted by the target McpServerBridge, THE McpClient SHALL re-emit a `toolStreamingContent` signal with the prefixed tool-call name and partial text so that any QML Connections block targeting McpClient can observe incremental output.
3. WHEN the McpServerBridge HTTP request process exits with exit code 0 after having emitted one or more `streamingContent` signals, THE McpServerBridge SHALL resolve the request promise with the full accumulated content from all received `data:` lines.
4. IF no intermediate SSE `data:` lines arrive before the HTTP request process exits (server sends a single `data:` event with the complete response), THEN THE McpServerBridge SHALL resolve the request promise directly without emitting any `streamingContent` signals.
5. WHILE the McpServerBridge is receiving SSE `data:` events for a streaming `tools/call` response, THE McpServerBridge SHALL reset the request timeout timer upon each received `data:` line, preventing timeout expiry during active streaming.

### Requirement 8: Error Recovery and Resilience

**User Story:** As a Quickshell sidebar user, I want SSE connections to recover gracefully from network interruptions, so that temporary connectivity issues do not require manual server reconnection.

#### Acceptance Criteria

1. IF an HTTP POST for a tool call fails with a network error (connection refused, timeout exceeding the configured per-request timeout, or DNS failure), THEN THE McpServerBridge SHALL retry the request exactly once after a 2-second delay, and if the retry also fails, reject the pending request promise with an error message indicating the failure reason.
2. IF the SSE event stream (Server_Push_Channel) disconnects unexpectedly, THEN THE McpServerBridge SHALL attempt reconnection up to 3 times with a 5-second interval between attempts, and if all 3 attempts fail, transition to error state and emit a warning log entry that includes the server name and number of failed attempts.
3. WHEN the McpServerBridge transitions from error state to connected state (via a successful reconnection attempt or an explicit `connectServer` call), THE McpServerBridge SHALL re-establish the Server_Push_Channel and invoke `discoverTools()` to refresh the tool registry for that server.
4. IF a server responds with HTTP 400 or HTTP 405 to a POST request, THEN THE McpServerBridge SHALL fall back to the existing one-shot curl behavior for that server, log an informational message identifying the server and the received status code, and mark the server as non-SSE for all subsequent requests until the next explicit `connectServer` call.
5. WHILE a server entry has `disabled` set to `true` in the mcp_json_Config, THE McpServerBridge SHALL not initiate any SSE connection, reconnection attempt, or HTTP probe for that server.
