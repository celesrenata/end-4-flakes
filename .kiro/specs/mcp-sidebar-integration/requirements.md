# Requirements Document

## Introduction

This feature integrates Model Context Protocol (MCP) servers into the existing AI sidebar chat in the Quickshell desktop environment. Currently, the sidebar only exposes 3 hardcoded HyprMCP tools (config_read, config_set, set_keyword) via HTTP. This feature enables the full set of MCP tools — including web fetching, GitHub operations, persistent memory, desktop control, and more — to be available to the sidebar AI. It also adds intelligent URL handling so pasted links can be fetched and summarized inline rather than only opened externally.

## Glossary

- **MCP_Client**: The QML-side component that manages communication with MCP servers, handling tool discovery, lifecycle, and request/response dispatch
- **MCP_Server**: An external stdio-based process that exposes tools via the JSON-RPC-based Model Context Protocol (e.g., fetch, github, memory, ii-desktop)
- **MCP_Bridge**: A persistent child process or proxy daemon that translates between the QML layer and stdio-based MCP servers using JSON-RPC over stdin/stdout
- **Tool_Registry**: The runtime registry of all discovered MCP tools, their schemas, and server associations — used to build LLM function declarations dynamically
- **MCP_Config**: The JSON configuration file (~/.kiro/settings/mcp.json) that declares available MCP servers, their commands, arguments, environment variables, and auto-approve lists
- **Tool_Call**: A single invocation of an MCP tool, consisting of a tool name, arguments, and the resulting response
- **URL_Detector**: The component that identifies URLs in user input and offers contextual actions (fetch with AI vs open in browser)
- **Sidebar_AI**: The existing AI chat service (Ai.qml) that handles LLM interactions, function calling, and message rendering

## Requirements

### Requirement 1: MCP Server Lifecycle Management

**User Story:** As a sidebar AI user, I want MCP servers to be started and stopped automatically, so that tools are available when needed without manual process management.

#### Acceptance Criteria

1. WHEN the Sidebar_AI initializes, THE MCP_Client SHALL read the MCP_Config file and register all declared servers, excluding entries whose disabled field is set to true
2. WHEN a Tool_Call targets a server that is not running, THE MCP_Client SHALL spawn the MCP_Server process using the command, args, and env from MCP_Config
3. WHILE an MCP_Server is running and has received no Tool_Call for 5 minutes, THE MCP_Client SHALL send a graceful shutdown signal to the MCP_Server
4. IF a graceful shutdown does not result in process exit within 5 seconds, THEN THE MCP_Client SHALL forcibly terminate the process
5. IF an MCP_Server process exits unexpectedly, THEN THE MCP_Client SHALL mark that server as unavailable, log the exit code, and allow re-spawn on the next Tool_Call targeting that server
6. WHEN an MCP_Server is spawned, THE MCP_Client SHALL complete the MCP initialization handshake (initialize request/response) within 10 seconds
7. IF the MCP initialization handshake times out, THEN THE MCP_Client SHALL terminate the process and report the failure to the Sidebar_AI as a function response

### Requirement 2: Dynamic Tool Discovery

**User Story:** As a sidebar AI user, I want the AI to automatically know what MCP tools are available, so that it can use them without hardcoded tool definitions.

#### Acceptance Criteria

1. WHEN an MCP_Server completes initialization, THE MCP_Client SHALL send a tools/list request and await a response within 10 seconds
2. WHEN tools/list returns a response containing one or more tools, THE Tool_Registry SHALL store each tool's name, description, and input schema
3. WHEN the Tool_Registry is updated, THE Sidebar_AI SHALL rebuild its function declarations to include all registered MCP tools alongside built-in tools
4. THE Tool_Registry SHALL map each tool name to its originating MCP_Server to enable correct dispatch
5. IF two MCP_Servers expose tools with identical names, THEN THE Tool_Registry SHALL prefix the tool name with the server identifier (e.g., "github_search_repositories")
6. IF the tools/list request fails, times out, or returns an empty tool list, THEN THE MCP_Client SHALL log a warning and mark the server as having no available tools without affecting other registered servers
7. IF a tool entry in the tools/list response is missing a name or contains an unparseable input schema, THEN THE Tool_Registry SHALL skip that tool, log a warning, and continue registering the remaining tools

### Requirement 3: MCP Tool Execution

**User Story:** As a sidebar AI user, I want the AI to call MCP tools and receive their results, so that it can perform actions like fetching web pages, searching GitHub, or controlling my desktop.

#### Acceptance Criteria

1. WHEN the LLM issues a function call matching a tool in the Tool_Registry, THE MCP_Client SHALL send a tools/call JSON-RPC request to the appropriate MCP_Server via stdin, including the tool name and arguments as specified in the LLM function call
2. WHEN the MCP_Server writes a tools/call response with isError false to stdout, THE MCP_Client SHALL parse the result content and deliver it to the Sidebar_AI as a function response message
3. WHILE a Tool_Call is in progress, THE Sidebar_AI SHALL display the tool name and a loading animation on the assistant message until the response is received or the timeout elapses
4. IF a Tool_Call does not receive a response within the server's configured timeout (defaulting to 30 seconds), THEN THE MCP_Client SHALL cancel the pending request and return a timeout error indicating the tool name and elapsed duration to the Sidebar_AI
5. WHEN a tool in the MCP_Config auto-approve list is called, THE MCP_Client SHALL execute it without user confirmation
6. WHEN a tool NOT in the auto-approve list is called, THE Sidebar_AI SHALL display the tool name and arguments and request user approval before execution
7. IF the user rejects a pending tool approval, THEN THE Sidebar_AI SHALL skip the Tool_Call, deliver a rejection notice as the function response to the LLM, and continue the conversation without executing the tool
8. IF the MCP_Server writes a tools/call response with isError true, THEN THE MCP_Client SHALL deliver the error content to the Sidebar_AI as a function response message indicating tool failure

### Requirement 4: Stdio JSON-RPC Communication

**User Story:** As a developer, I want reliable stdio communication with MCP servers, so that tool calls and responses are correctly serialized and deserialized.

#### Acceptance Criteria

1. THE MCP_Bridge SHALL write JSON-RPC 2.0 requests as UTF-8 encoded single-line JSON (no embedded newlines) terminated by a single newline character (\n) to the MCP_Server stdin, with each request not exceeding 1 MB in size
2. THE MCP_Bridge SHALL read MCP_Server stdout line-by-line using the QML SplitParser and parse each complete line as either a JSON-RPC response (containing an id field) or a notification (no id field)
3. THE MCP_Bridge SHALL correlate responses to pending requests by matching the JSON-RPC id field and SHALL resolve the corresponding pending request within one event-loop cycle of receiving the matching response line
4. IF the MCP_Server writes a line to stdout that is not valid JSON or does not conform to JSON-RPC 2.0 structure, THEN THE MCP_Bridge SHALL discard the line without delivering it to any pending request handler and SHALL emit a warning to stderr identifying the first 200 characters of the malformed content
5. THE MCP_Bridge SHALL support up to 32 concurrent pending requests to the same MCP_Server by writing each request immediately to stdin and matching responses by id as they arrive, preserving request-response pairing regardless of response order
6. IF a pending request does not receive a matching response within 30 seconds, THEN THE MCP_Bridge SHALL consider the request timed out, remove it from the pending queue, and deliver a timeout error to the caller
7. IF the MCP_Server process exits or the stdout stream reaches EOF while requests are still pending, THEN THE MCP_Bridge SHALL reject all pending requests with an error indicating the server disconnected
8. FOR ALL valid JSON-RPC requests written to stdin, parsing the serialized output then re-serializing SHALL produce a semantically equivalent JSON structure (round-trip property)

### Requirement 5: URL Detection and Fetch Integration

**User Story:** As a sidebar AI user, I want to paste URLs into the chat and have the AI fetch and summarize them, so that I can get information without leaving the sidebar.

#### Acceptance Criteria

1. WHEN the user submits a message containing one or more URLs, THE URL_Detector SHALL identify each URL and present a per-URL inline action chip offering "Fetch with AI" or "Open in browser", displayed adjacent to the detected URL within the message area
2. WHEN the user selects "Fetch with AI", THE Sidebar_AI SHALL invoke the fetch MCP_Server's fetch tool with the selected URL and a timeout of 30 seconds
3. WHEN the fetch tool returns page content, THE Sidebar_AI SHALL truncate the content to a maximum of 8000 characters, include it in the conversation context, and instruct the LLM to summarize the page content
4. WHEN the user selects "Open in browser", THE Sidebar_AI SHALL open the URL externally using Qt.openUrlExternally as the current behavior
5. IF the URL_Detector identifies a URL but the fetch MCP_Server is not present in the MCP configuration, THEN THE Sidebar_AI SHALL skip the "Fetch with AI" option and open the URL externally
6. THE URL_Detector SHALL recognize URLs matching the pattern https://, http://, and www. prefixes within the submitted message text, up to a maximum URL length of 2048 characters
7. IF the fetch MCP_Server returns an error or does not respond within 30 seconds, THEN THE Sidebar_AI SHALL display an error message indicating the fetch failed and offer the user the option to open the URL in the browser instead

### Requirement 6: Tool Result Presentation

**User Story:** As a sidebar AI user, I want MCP tool results to be clearly presented in the chat, so that I can distinguish tool outputs from regular AI responses.

#### Acceptance Criteria

1. WHEN an MCP tool returns a text result, THE Sidebar_AI SHALL render it within a collapsible block that displays the header "Tool: [tool_name]" and defaults to the expanded state, where [tool_name] is the name string returned by the MCP server
2. WHEN an MCP tool returns a result where the content is valid JSON, THE Sidebar_AI SHALL render the content inside a syntax-highlighted code block with language set to "json"
3. WHEN an MCP tool returns an error, THE Sidebar_AI SHALL display the error within a collapsible block using the Material Design 3 error color role for the header background, distinguishing it from successful tool results which use the secondary-container color role
4. WHILE a Tool_Call is pending, THE Sidebar_AI SHALL display the tool name and a loading animation in the message area; IF a Tool_Call remains pending for more than 30 seconds, THEN THE Sidebar_AI SHALL display a timeout indicator alongside the loading animation
5. WHEN multiple Tool_Calls occur in sequence within one assistant turn, THE Sidebar_AI SHALL display each tool invocation as a separate collapsible block, rendered in invocation order within the same message, up to a maximum of 20 tool blocks per message
6. WHEN a tool result text exceeds 500 lines, THE Sidebar_AI SHALL truncate the displayed output to 500 lines and display an indication that the output was truncated along with the total line count

### Requirement 7: Integration with Existing Function Calling

**User Story:** As a developer, I want MCP tools to coexist with existing built-in tools (shell commands, config read/write), so that no current functionality is broken.

#### Acceptance Criteria

1. THE Sidebar_AI SHALL preserve all existing built-in tools (switch_to_search_mode, get_shell_config, set_shell_config, run_shell_command, hypr_config_read, hypr_config_set, hypr_set_keyword) such that each remains callable and included in the functionDeclarations sent to the LLM API when tool mode is set to "functions"
2. WHEN the LLM issues a function call, THE Sidebar_AI SHALL match the function name against the built-in tool list first; IF no built-in tool matches, THEN THE Sidebar_AI SHALL look up the function name in the Tool_Registry for MCP tools
3. IF a function call name matches neither a built-in tool nor a registered MCP tool, THEN THE Sidebar_AI SHALL display a message indicating the function is unknown and SHALL NOT crash or leave the conversation in a pending state
4. THE Tool_Registry SHALL reject registration of any MCP tool whose name is an exact case-sensitive string match with a built-in tool name, and SHALL log a warning indicating the conflict
5. WHEN the tool mode is set to "none", THE Sidebar_AI SHALL send no tool declarations to the LLM API and SHALL ignore any function call responses for both built-in and MCP tools
6. WHEN the tool mode is set to "search", THE Sidebar_AI SHALL omit function-calling tool declarations (both built-in and MCP) from the LLM API request and SHALL send only search-mode tool declarations where supported by the provider

### Requirement 8: HyprMCP Migration to MCP Client

**User Story:** As a developer, I want the existing HyprMCP tools to be served through the unified MCP_Client, so that the codebase has a single tool dispatch path.

#### Acceptance Criteria

1. WHEN the ii-desktop MCP_Server is configured in MCP_Config, THE MCP_Client SHALL send a tools/list JSON-RPC request to discover all available ii-desktop tools instead of using the 3 hardcoded declarations (hypr_config_read, hypr_config_set, hypr_set_keyword)
2. THE Sidebar_AI SHALL include all tools returned by the ii-desktop tools/list response (including audio_status, network_status, clipboard_list, apps_search, apps_launch, screenshot, system_info, diagnostic_bundle, config_read, config_set, and set_keyword) in the LLM function declarations
3. WHILE the ii-desktop server uses HTTP transport, THE MCP_Client SHALL communicate with it via HTTP POST to http://localhost:7580/mcp using JSON-RPC format (method: "tools/call", params: {name, arguments}), with a per-request timeout of 30 seconds
4. IF the ii-desktop MCP_Server does not respond to an HTTP connection attempt within 5 seconds, THEN THE MCP_Client SHALL fall back to spawning it as a stdio process using the command from MCP_Config and completing the MCP initialization handshake before dispatching tool calls
5. THE migration SHALL NOT remove existing ii-desktop functionality: config_read, config_set, and set_keyword SHALL produce identical JSON-RPC responses through the MCP_Client as they did through the previous direct curl dispatch
6. WHEN a write tool (config_set or set_keyword) returns a successful response, THE MCP_Client SHALL perform a read-back verification by invoking config_read for the affected namespace and comparing the returned value against the written value before reporting success to the Sidebar_AI
7. WHEN the MCP_Client discovers ii-desktop tools, THE Tool_Registry SHALL map server-side tool names (e.g., "config_read") to LLM-facing names prefixed with the server identifier (e.g., "ii_desktop_config_read") to avoid conflicts with built-in tool names

### Requirement 9: Multi-Provider Tool Support

**User Story:** As a sidebar AI user, I want MCP tools to work across different LLM providers, so that I can use tools regardless of which model I select.

#### Acceptance Criteria

1. WHEN the current model uses Gemini API format, THE Sidebar_AI SHALL include MCP tools as an array containing a functionDeclarations object (e.g., `[{"functionDeclarations": [...]}]`) in the request body's tools field
2. WHEN the current model uses OpenAI API format, THE Sidebar_AI SHALL include MCP tools as a flat array of objects with name, description, and parameters properties in the request body
3. WHEN the current model uses Mistral API format, THE Sidebar_AI SHALL include MCP tools as an array of objects each with type "function" and a nested function object containing name, description, and parameters
4. IF the current model does not support function calling, THEN THE Sidebar_AI SHALL omit the tools field from the request and display a message in the chat indicating that tools are unavailable for the selected model
5. WHEN converting MCP tool schemas to provider-specific declarations, THE Sidebar_AI SHALL map each MCP tool's JSON Schema input definition to the parameter format required by the active provider, preserving all property names, types, descriptions, and required field arrays
6. IF no MCP tools are configured for the active tool slot, THEN THE Sidebar_AI SHALL send an empty tools array (or omit the tools field) and proceed with the request without error

### Requirement 10: Configuration and Server Selection

**User Story:** As a sidebar AI user, I want to control which MCP servers are active, so that I can limit resource usage and control what tools the AI can access.

#### Acceptance Criteria

1. THE MCP_Client SHALL read server definitions from the MCP_Config file path (~/.kiro/settings/mcp.json) and exclude any entry whose disabled field is set to true
2. WHEN an MCP_Server entry in MCP_Config has an env field, THE MCP_Client SHALL set those environment variables before spawning the process
3. WHEN an MCP_Server entry has a timeout field with a value between 1000 and 300000 milliseconds, THE MCP_Client SHALL use that value as the maximum response time instead of the default 30000 milliseconds
4. THE Sidebar_AI SHALL provide a UI element in the settings or chat header to view each MCP server's name and connection status (one of: connected, disconnected, error, or disabled)
5. IF the MCP_Config file is missing, unreadable, or contains malformed JSON, THEN THE MCP_Client SHALL operate with only built-in tools and log a warning indicating the reason for failure
6. WHEN the user toggles an MCP_Server's disabled state via the UI element, THE MCP_Client SHALL update the disabled field in MCP_Config and disconnect or skip that server without restarting other active servers
7. IF a timeout field value is outside the range 1000 to 300000 milliseconds, THEN THE MCP_Client SHALL use the default timeout of 30000 milliseconds and log a warning
