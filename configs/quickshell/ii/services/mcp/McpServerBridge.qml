pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import "SseEventParser.mjs" as SseParser

/**
 * McpServerBridge — per-server stdio JSON-RPC 2.0 communication bridge.
 *
 * Manages a single MCP server process lifecycle:
 * - Spawns the process with initialize handshake
 * - Sends JSON-RPC requests and correlates responses by id
 * - Handles idle timeout, graceful shutdown, and force-kill
 * - Discovers tools via tools/list
 *
 * State machine: disconnected → connecting → connected → error
 */
Item {
    id: bridge

    // Server configuration
    property string serverName: ""
    property string serverCommand: ""
    property list<string> serverArgs: []
    property var serverEnv: ({})
    property int timeout: 30000           // Per-request timeout (ms), default 30s
    property string transport: "stdio"    // "stdio" or "http"
    property string httpEndpoint: ""      // For HTTP transport
    property bool disabled: false          // When true, no network activity is initiated

    // State
    property string state: "disconnected" // disconnected, connecting, connected, error
    property var pendingRequests: ({})    // id → { resolve, reject, timer }
    property int nextRequestId: 1
    property var discoveredTools: []
    property string lastError: ""

    // Idle management
    property int idleTimeoutMs: 300000    // 5 minutes default
    property var lastActivityTimestamp: 0

    // Constants
    readonly property int _maxConcurrent: 32
    readonly property int _maxRequestSize: 1048576  // 1 MB
    readonly property int _initTimeout: 10000       // 10s handshake timeout
    readonly property int _shutdownGrace: 5000      // 5s graceful shutdown
    readonly property int _malformedLogMax: 200     // Max chars to log for malformed lines

    // Internal pending count
    property int _pendingCount: 0

    // Internal: state change tracking for recovery logic
    property string _previousState: "disconnected"
    onStateChanged: {
        if (bridge.state === "connected" && bridge._previousState === "error") {
            bridge._handleErrorToConnected();
        }
        bridge._previousState = bridge.state;
    }

    // ──────────────────────────────────────────────
    // SSE Transport State
    // ──────────────────────────────────────────────

    // Session management
    property string sessionId: ""              // Stored Mcp-Session-Id
    property bool sseSupported: false          // Whether server supports SSE
    property bool nonSseMarked: false          // Marked non-SSE after 400/405

    // Streaming process management
    property int activeProcessCount: 0         // Current active curl processes
    property var requestQueue: []              // Pending requests when at capacity
    property var pushChannelProcess: null      // Reference to push channel Process
    property bool pushChannelActive: false     // Whether push channel is running

    // Reconnection state
    property int reconnectAttempts: 0          // Push channel reconnect counter
    property int reconnectInterval: 1000       // Current backoff interval (ms)

    // Streaming accumulator
    property var streamingAccumulator: ({})    // requestId → accumulated data

    // Internal: active streaming request states (keyed by request id)
    property var _streamingStates: ({})

    // Internal: push channel state (header/body state machine + SSE parser)
    property var _pushChannelState: null
    property var _pushIdleTimer: null

    // SSE signals
    signal streamingContent(int requestId, string content)
    signal progressNotification(string token, real current, real total)
    signal pushChannelDisconnected()

    // SSE constants
    readonly property int _maxConcurrentProcesses: 2   // Max curl processes per server
    readonly property int _maxQueueSize: 10            // Max queued requests
    readonly property int _inactivityTimeout: 120000   // 120s no-data timeout
    readonly property int _idleDisconnectTimeout: 60000 // 60s idle → close push channel
    readonly property int _pushReconnectMax: 10        // Max reconnect attempts
    readonly property int _pushReconnectCap: 30000     // Max backoff interval (ms)

    // ──────────────────────────────────────────────
    // Process (stdio transport)
    // ──────────────────────────────────────────────

    Process {
        id: serverProc
        running: false

        stdout: SplitParser {
            onRead: data => {
                bridge._handleStdoutLine(data);
            }
        }

        stderr: SplitParser {
            onRead: data => {
                console.warn(`[MCP:${bridge.serverName}] stderr: ${data}`);
            }
        }

        onExited: (exitCode, exitStatus) => {
            bridge._handleProcessExit(exitCode, exitStatus);
        }
    }

    // ──────────────────────────────────────────────
    // HTTP request Process component (for dynamic HTTP requests)
    // ──────────────────────────────────────────────

    // (HTTP request processes are created dynamically in _sendHttpRequest)

    // ──────────────────────────────────────────────
    // Idle timer
    // ──────────────────────────────────────────────

    Timer {
        id: idleTimer
        interval: bridge.idleTimeoutMs
        repeat: false
        running: false
        onTriggered: {
            if (bridge.state === "connected" && bridge._pendingCount === 0) {
                console.log(`[MCP:${bridge.serverName}] Idle timeout reached, shutting down`);
                bridge.shutdown();
            }
        }
    }

    // ──────────────────────────────────────────────
    // Force-kill timer (used during shutdown)
    // ──────────────────────────────────────────────

    Timer {
        id: forceKillTimer
        interval: bridge._shutdownGrace
        repeat: false
        running: false
        onTriggered: {
            if (serverProc.running) {
                console.warn(`[MCP:${bridge.serverName}] Graceful shutdown timed out, force-killing`);
                serverProc.signal(9); // SIGKILL
            }
        }
    }

    // ──────────────────────────────────────────────
    // Public API
    // ──────────────────────────────────────────────

    /**
     * spawn() — Start process, send initialize handshake, resolve on success.
     * For HTTP transport: probe the endpoint with a tools/list request.
     * Returns an object with { then(cb), catch(cb) } for Promise-like usage.
     */
    function spawn() {
        if (bridge.disabled) {
            return bridge._makeResolved({ disabled: true });
        }

        if (bridge.state === "connecting" || bridge.state === "connected") {
            return bridge._makeResolved({ already: true });
        }

        // HTTP transport: probe endpoint, no process spawn needed
        if (bridge.transport === "http" && bridge.httpEndpoint) {
            return bridge._spawnHttp();
        }

        // Stdio transport: normal process spawn
        return bridge._spawnStdio();
    }

    /**
     * _spawnHttp() — Probe HTTP endpoint and discover tools.
     * Tries tools/list first (works for stateless Streamable HTTP servers).
     * If that fails with an initialization error, performs the full handshake:
     *   initialize → notifications/initialized → tools/list
     */
    function _spawnHttp() {
        if (bridge.disabled) {
            return bridge._makeResolved({ disabled: true });
        }

        bridge.state = "connecting";
        bridge.lastError = "";
        bridge.nextRequestId = 1;

        const result = bridge._makePromise();

        // Try tools/list directly first (stateless servers like memory, searxng)
        const probePromise = bridge._sendHttpRequest("tools/list", {}, 5000);

        probePromise.then(response => {
            if (bridge.state !== "connecting") return;
            bridge.state = "connected";
            bridge._resetIdleTimer();
            bridge._parseToolsResponse(response);
            // Mark SSE support if session was established
            if (bridge.sessionId) {
                bridge.sseSupported = true;
            }
            bridge.nonSseMarked = false;
            // Open push channel for SSE-capable servers
            if (bridge.sseSupported) {
                bridge._openPushChannel();
            }
            result._resolve(response);
        });

        probePromise.catch(err => {
            // If the error mentions "initialization", try the full handshake
            const errStr = String(err).toLowerCase();
            if (errStr.indexOf("initializ") !== -1 || errStr.indexOf("session") !== -1) {
                bridge._spawnHttpWithHandshake(result);
            } else {
                bridge.state = "error";
                bridge.lastError = "HTTP probe failed: " + err;
                result._reject(bridge.lastError);
            }
        });

        return result;
    }

    /**
     * _spawnHttpWithHandshake() — Full MCP handshake over HTTP for SSE-based servers.
     */
    function _spawnHttpWithHandshake(result) {
        const initPromise = bridge._sendHttpRequest("initialize", {
            protocolVersion: "2024-11-05",
            capabilities: {},
            clientInfo: { name: "ii-sidebar", version: "1.0.0" }
        }, bridge._initTimeout);

        initPromise.then(initResponse => {
            // Send initialized notification
            bridge._sendHttpRequest("notifications/initialized", {}, 3000);

            // Small delay to let server process the notification, then list tools
            const delayTimer = Qt.createQmlObject(
                `import QtQuick; Timer { interval: 200; repeat: false; running: true }`,
                bridge, "handshakeDelay"
            );
            delayTimer.triggered.connect(() => {
                delayTimer.destroy();

                const toolsPromise = bridge._sendHttpRequest("tools/list", {}, 5000);
                toolsPromise.then(response => {
                    if (bridge.state !== "connecting") return;
                    bridge.state = "connected";
                    bridge._resetIdleTimer();
                    bridge._parseToolsResponse(response);
                    // Mark SSE support if session was established
                    if (bridge.sessionId) {
                        bridge.sseSupported = true;
                    }
                    bridge.nonSseMarked = false;
                    // Open push channel for SSE-capable servers
                    if (bridge.sseSupported) {
                        bridge._openPushChannel();
                    }
                    result._resolve(response);
                });
                toolsPromise.catch(toolsErr => {
                    // Connected but tools/list failed — still mark connected
                    bridge.state = "connected";
                    bridge._resetIdleTimer();
                    // Mark SSE support if session was established
                    if (bridge.sessionId) {
                        bridge.sseSupported = true;
                    }
                    bridge.nonSseMarked = false;
                    // Open push channel for SSE-capable servers
                    if (bridge.sseSupported) {
                        bridge._openPushChannel();
                    }
                    result._resolve(initResponse);
                });
            });
        });

        initPromise.catch(initErr => {
            bridge.state = "error";
            bridge.lastError = "HTTP handshake failed: " + initErr;
            result._reject(bridge.lastError);
        });
    }

    /**
     * _parseToolsResponse(response) — Parse tools from a tools/list response.
     * Handles both array and object (dict) formats.
     */
    function _parseToolsResponse(response) {
        const rawTools = response?.tools || [];
        const tools = [];

        if (Array.isArray(rawTools)) {
            for (let i = 0; i < rawTools.length; i++) {
                const tool = rawTools[i];
                if (!tool.name || typeof tool.name !== "string") continue;
                let schema = tool.inputSchema || {};
                if (typeof schema === "string") {
                    try { schema = JSON.parse(schema); } catch (e) { continue; }
                }
                tools.push({
                    name: tool.name,
                    description: tool.description || "",
                    inputSchema: schema
                });
            }
        } else if (rawTools && typeof rawTools === "object") {
            const toolNames = Object.keys(rawTools);
            for (let i = 0; i < toolNames.length; i++) {
                const name = toolNames[i];
                const tool = rawTools[name];
                if (!tool || typeof tool !== "object") continue;
                let schema = tool.inputSchema || {};
                if (typeof schema === "string") {
                    try { schema = JSON.parse(schema); } catch (e) { continue; }
                }
                tools.push({
                    name: name,
                    description: tool.description || "",
                    inputSchema: schema
                });
            }
        }

        if (tools.length > 0) {
            bridge.discoveredTools = tools;
        }
    }

    /**
     * _spawnStdio() — Standard stdio process spawn with MCP handshake.
     */
    function _spawnStdio() {
        bridge.state = "connecting";
        bridge.lastError = "";
        bridge.nextRequestId = 1;
        bridge.pendingRequests = {};
        bridge._pendingCount = 0;

        // Build command
        const cmdParts = [bridge.serverCommand, ...bridge.serverArgs];
        serverProc.command = cmdParts;

        // Set environment variables
        if (bridge.serverEnv && Object.keys(bridge.serverEnv).length > 0) {
            for (const key in bridge.serverEnv) {
                serverProc.environment[key] = bridge.serverEnv[key];
            }
        }

        serverProc.running = true;

        // Send initialize handshake with 10s timeout
        const initPromise = bridge.sendRequest("initialize", {
            protocolVersion: "2024-11-05",
            capabilities: {},
            clientInfo: { name: "ii-sidebar", version: "1.0.0" }
        }, bridge._initTimeout);

        const result = bridge._makePromise();

        initPromise.then(response => {
            if (bridge.state === "connecting") {
                bridge.state = "connected";
                bridge._resetIdleTimer();
                // Send initialized notification (no id = notification)
                bridge._writeNotification("notifications/initialized", {});
                result._resolve(response);
            }
        });

        initPromise.catch(err => {
            bridge.state = "error";
            bridge.lastError = err;
            if (serverProc.running) {
                serverProc.running = false;
            }
            result._reject(err);
        });

        return result;
    }

    /**
     * shutdown() — Graceful SIGTERM, force-kill after 5s fallback.
     */
    function shutdown() {
        // Close push channel first (SSE transport)
        if (bridge.pushChannelActive) {
            bridge._closePushChannel();
        }

        // Send session DELETE (fire-and-forget, SSE transport)
        if (bridge.sessionId && bridge.httpEndpoint) {
            bridge._sendSessionDelete();
        }

        // Reset SSE state
        bridge.sseSupported = false;
        bridge.nonSseMarked = false;
        bridge.reconnectAttempts = 0;
        bridge.reconnectInterval = 1000;
        bridge.streamingAccumulator = {};
        bridge._streamingStates = {};
        bridge.activeProcessCount = 0;
        bridge.requestQueue = [];

        // For HTTP-only servers (no stdio process), just transition to disconnected
        if (!serverProc.running) {
            bridge.state = "disconnected";
            return;
        }

        // Reject all pending requests
        bridge._rejectAllPending("Server shutting down");

        // Graceful stop (sends SIGTERM)
        serverProc.running = false;
        forceKillTimer.running = true;

        // Stop idle timer
        idleTimer.running = false;
    }

    /**
     * sendRequest(method, params, customTimeout) — Send JSON-RPC request.
     * Routes to HTTP or stdio transport depending on bridge configuration.
     * Returns a Promise-like object { then(cb), catch(cb) }.
     */
    function sendRequest(method, params, customTimeout) {
        // For HTTP transport with SSE support: use streaming path with retry
        if (bridge.transport === "http" && bridge.httpEndpoint && bridge.state === "connected") {
            if (bridge.sseSupported && !bridge.nonSseMarked) {
                // Check process slot capacity
                if (bridge.activeProcessCount >= bridge._maxConcurrentProcesses) {
                    const result = bridge._makePromise();
                    bridge._enqueueRequest(method, params, customTimeout || bridge.timeout, result);
                    return result;
                }
                // Use streaming path with retry for network errors
                return bridge._sendWithRetry(method, params, customTimeout);
            }
            // Non-SSE server: use existing one-shot curl
            return bridge._sendHttpRequest(method, params, customTimeout);
        }

        // Stdio transport
        return bridge._sendStdioRequest(method, params, customTimeout);
    }

    /**
     * _sendHttpRequest(method, params, customTimeout) — HTTP POST to endpoint.
     * Creates a temporary curl Process for each request.
     * Uses full JSON-RPC 2.0 envelope as required by MCP Streamable HTTP transport.
     */
    function _sendHttpRequest(method, params, customTimeout) {
        const result = bridge._makePromise();
        const timeoutMs = customTimeout || bridge.timeout;
        const timeoutSec = Math.ceil(timeoutMs / 1000);

        const id = bridge.nextRequestId;
        bridge.nextRequestId += 1;

        const requestBody = JSON.stringify({
            jsonrpc: "2.0",
            id: id,
            method: method,
            params: params || {}
        });

        const curlCmd = `curl -s --connect-timeout ${timeoutSec} --max-time ${timeoutSec} -X POST ${bridge.httpEndpoint} -H 'Content-Type: application/json' -d '${bridge._shellEscape(requestBody)}'`;

        // Use a state object to track completion across callbacks
        const state = { completed: false };

        const proc = Qt.createQmlObject(`
            import Quickshell;
            import Quickshell.Io;
            Process {
                property string responseBuffer: ""
                running: false
                stdout: SplitParser {
                    onRead: data => { responseBuffer += data + "\\n"; }
                }
                stderr: SplitParser {
                    onRead: data => {}
                }
            }
        `, bridge, "httpProc");

        proc.command = ["bash", "-c", curlCmd];

        // Set up timeout timer
        const timeoutTimer = Qt.createQmlObject(
            `import QtQuick; Timer {
                interval: ${timeoutMs + 2000}
                repeat: false
                running: true
            }`, bridge, "httpTimeout"
        );

        timeoutTimer.triggered.connect(() => {
            if (!state.completed) {
                state.completed = true;
                proc.running = false;
                proc.destroy();
                timeoutTimer.destroy();
                result._reject(`HTTP request timeout after ${timeoutMs}ms (method: ${method})`);
            }
        });

        proc.exited.connect((exitCode, exitStatus) => {
            if (state.completed) return;
            state.completed = true;
            timeoutTimer.running = false;
            timeoutTimer.destroy();

            let response = proc.responseBuffer.trim();
            proc.destroy();

            if (exitCode !== 0 || response.length === 0) {
                result._reject(`HTTP request failed (exit code: ${exitCode}, method: ${method})`);
                return;
            }

            // Handle SSE format: extract JSON from "data: {...}" lines
            if (response.indexOf("event:") !== -1 || response.indexOf("data:") !== -1) {
                const lines = response.split("\n");
                let jsonPayload = "";
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim();
                    if (line.startsWith("data:")) {
                        jsonPayload += line.substring(5).trim();
                    }
                }
                if (jsonPayload.length > 0) {
                    response = jsonPayload;
                }
            }

            try {
                const parsed = JSON.parse(response);
                if (parsed.error) {
                    result._reject(parsed.error.message || JSON.stringify(parsed.error));
                } else {
                    result._resolve(parsed.result !== undefined ? parsed.result : parsed);
                }
            } catch (e) {
                result._reject(`HTTP response parse error: ${e} (method: ${method}, response: ${response.substring(0, 200)})`);
            }
        });

        proc.running = true;

        // Update activity
        bridge._resetIdleTimer();

        return result;
    }

    // ──────────────────────────────────────────────
    // Internal: Streaming HTTP request (SSE-aware)
    // ──────────────────────────────────────────────

    /**
     * _handleStreamingLineById(requestId, line) — Dispatch a stdout line to the
     * correct streaming request state. Called from dynamically-created Process objects
     * whose SplitParser onRead handlers cannot close over local variables.
     */
    function _handleStreamingLineById(requestId, line) {
        const state = bridge._streamingStates[requestId];
        if (!state || state.completed) return;

        // Reset inactivity timer on any received data
        if (state.inactivityTimer) {
            state.inactivityTimer.restart();
        }

        if (state.context.inHeaders) {
            bridge._parseResponseHeaderLine(line, state.context);
            return;
        }

        // Body phase — route based on Content-Type
        if (state.context.contentType === "text/event-stream") {
            state.sseParser.feedLine(line);
        } else {
            // JSON accumulation mode
            state.jsonBuffer += line + "\n";
        }
    }

    /**
     * _sendStreamingHttpRequest(method, params, customTimeout) — SSE-aware HTTP POST.
     *
     * Creates a persistent Process with SplitParser for streaming curl output.
     * Handles both text/event-stream (SSE) and application/json responses.
     * Emits streamingContent signals for intermediate tool call data.
     * Returns a Promise-like object { then(cb), catch(cb) }.
     */
    function _sendStreamingHttpRequest(method, params, customTimeout) {
        if (bridge.disabled) {
            const result = bridge._makePromise();
            result._reject("Server is disabled");
            return result;
        }

        const result = bridge._makePromise();
        const timeoutMs = customTimeout || bridge.timeout;

        const id = bridge.nextRequestId;
        bridge.nextRequestId += 1;

        const requestBody = JSON.stringify({
            jsonrpc: "2.0",
            id: id,
            method: method,
            params: params || {}
        });

        // Build curl command as array: -N (no-buffer), -i (include headers),
        // --connect-timeout 10, --max-time 0 (no max for streaming)
        const cmd = ["curl", "-N", "-i", "--connect-timeout", "10", "--max-time", "0",
                     "-X", "POST", bridge.httpEndpoint,
                     ...bridge._buildCurlHeaders(),
                     "-d", requestBody];

        // State tracking for this streaming request
        const state = {
            completed: false,
            context: { inHeaders: true, contentType: "", httpStatus: 0 },
            jsonBuffer: "",
            sseParser: SseParser.createParser(),
            accumulatedContent: [],
            isToolCall: (method === "tools/call"),
            proc: null,
            inactivityTimer: null
        };

        // Set up SSE parser event handler
        state.sseParser.onEvent = (event) => {
            if (state.completed) return;

            // Reset inactivity timer on event
            if (state.inactivityTimer) {
                state.inactivityTimer.restart();
            }

            const data = event.data;

            // Check if it's a JSON-RPC response (final answer)
            if (data && typeof data === "object" && data.jsonrpc === "2.0" && data.id !== undefined) {
                state.completed = true;
                bridge.activeProcessCount -= 1;
                bridge._processQueue();

                if (state.inactivityTimer) {
                    state.inactivityTimer.running = false;
                    state.inactivityTimer.destroy();
                    state.inactivityTimer = null;
                }
                if (state.proc) {
                    state.proc.running = false;
                    state.proc.destroy();
                    state.proc = null;
                }

                // Clean up streaming state
                delete bridge._streamingStates[id];
                delete bridge.streamingAccumulator[id];

                if (data.error) {
                    result._reject(data.error.message || JSON.stringify(data.error));
                } else {
                    result._resolve(data.result);
                }
                return;
            }

            // Intermediate streaming content
            const content = typeof data === "string" ? data : JSON.stringify(data);
            state.accumulatedContent.push(content);
            bridge.streamingAccumulator[id] = state.accumulatedContent;

            if (state.isToolCall) {
                bridge.streamingContent(id, content);
            }
        };

        // Store state on bridge for the dynamic process handler to access
        bridge._streamingStates[id] = state;

        // Increment process count
        bridge.activeProcessCount += 1;

        // Create the streaming Process with SplitParser
        const proc = Qt.createQmlObject(`
            import Quickshell;
            import Quickshell.Io;
            Process {
                property int requestId: ${id}
                running: false
                stdout: SplitParser {
                    onRead: data => { bridge._handleStreamingLineById(${id}, data); }
                }
                stderr: SplitParser {
                    onRead: data => {}
                }
            }
        `, bridge, "streamingProc_" + id);

        proc.command = cmd;
        state.proc = proc;

        // Create inactivity timer (120s no-data timeout)
        const inactivityTimer = Qt.createQmlObject(`
            import QtQuick;
            Timer {
                interval: ${bridge._inactivityTimeout}
                repeat: false
                running: true
            }
        `, bridge, "inactivityTimer_" + id);

        state.inactivityTimer = inactivityTimer;

        inactivityTimer.triggered.connect(() => {
            if (state.completed) return;
            state.completed = true;
            bridge.activeProcessCount -= 1;
            bridge._processQueue();

            // Clean up
            delete bridge._streamingStates[id];
            delete bridge.streamingAccumulator[id];

            if (state.proc) {
                state.proc.signal(15); // SIGTERM
                state.proc.destroy();
                state.proc = null;
            }
            inactivityTimer.destroy();
            state.inactivityTimer = null;

            result._reject(`Inactivity timeout (${bridge._inactivityTimeout / 1000}s no data) — method: ${method}`);
        });

        proc.exited.connect((exitCode, exitStatus) => {
            if (state.completed) return;
            state.completed = true;
            bridge.activeProcessCount -= 1;
            bridge._processQueue();

            // Stop inactivity timer
            if (state.inactivityTimer) {
                state.inactivityTimer.running = false;
                state.inactivityTimer.destroy();
                state.inactivityTimer = null;
            }

            // Clean up state
            delete bridge._streamingStates[id];
            delete bridge.streamingAccumulator[id];

            if (exitCode !== 0) {
                if (state.proc) {
                    state.proc.destroy();
                    state.proc = null;
                }
                result._reject(`Streaming HTTP request failed (exit code: ${exitCode}, method: ${method})`);
                return;
            }

            // Exit code 0 — resolve with what we have
            if (state.context.contentType === "text/event-stream") {
                // SSE mode: finalize parser, resolve with accumulated content
                state.sseParser.end();
                const accumulated = state.accumulatedContent.join("\n");
                if (state.proc) {
                    state.proc.destroy();
                    state.proc = null;
                }
                result._resolve(accumulated || null);
            } else {
                // JSON mode: parse accumulated buffer
                if (state.proc) {
                    state.proc.destroy();
                    state.proc = null;
                }
                const response = state.jsonBuffer.trim();
                if (!response) {
                    result._reject(`Empty response from server (method: ${method})`);
                    return;
                }
                try {
                    const parsed = JSON.parse(response);
                    if (parsed.error) {
                        result._reject(parsed.error.message || JSON.stringify(parsed.error));
                    } else {
                        result._resolve(parsed.result !== undefined ? parsed.result : parsed);
                    }
                } catch (e) {
                    result._reject(`Response parse error: ${e} (method: ${method})`);
                }
            }
        });

        // Start the process
        proc.running = true;
        bridge._resetIdleTimer();

        return result;
    }

    /**
     * _sendStdioRequest(method, params, customTimeout) — Stdio JSON-RPC request.
     */
    function _sendStdioRequest(method, params, customTimeout) {
        const result = bridge._makePromise();

        // Check concurrency limit
        if (bridge._pendingCount >= bridge._maxConcurrent) {
            result._reject(`Max concurrent requests (${bridge._maxConcurrent}) reached`);
            return result;
        }

        // Check process is alive
        if (!serverProc.running && bridge.state !== "connecting") {
            result._reject("Server process not running");
            return result;
        }

        const id = bridge.nextRequestId;
        bridge.nextRequestId += 1;

        const request = {
            jsonrpc: "2.0",
            id: id,
            method: method,
            params: params || {}
        };

        // Serialize
        const serialized = JSON.stringify(request);

        // Check size limit (1 MB)
        if (serialized.length > bridge._maxRequestSize) {
            result._reject(`Request exceeds 1 MB size limit (${serialized.length} bytes)`);
            return result;
        }

        // Set up timeout
        const timeoutMs = customTimeout || bridge.timeout;
        const timeoutTimer = Qt.createQmlObject(
            `import QtQuick; Timer {
                interval: ${timeoutMs}
                repeat: false
                running: true
            }`, bridge, "requestTimeout"
        );

        // Store pending request
        const pendingEntry = {
            resolve: result._resolve,
            reject: result._reject,
            timer: timeoutTimer,
            method: method
        };

        bridge.pendingRequests[id] = pendingEntry;
        bridge._pendingCount += 1;

        // Wire timeout
        timeoutTimer.triggered.connect(() => {
            if (bridge.pendingRequests[id]) {
                const entry = bridge.pendingRequests[id];
                delete bridge.pendingRequests[id];
                bridge._pendingCount -= 1;
                entry.timer.destroy();
                entry.reject(`Request timeout after ${timeoutMs}ms (method: ${method}, id: ${id})`);
            }
        });

        // Write to stdin (single-line JSON + newline)
        serverProc.write(serialized + "\n");

        // Update activity
        bridge._resetIdleTimer();

        return result;
    }

    /**
     * discoverTools() — Send tools/list, parse response, populate discoveredTools.
     * Returns a Promise-like object.
     */
    function discoverTools() {
        const result = bridge._makePromise();

        const listPromise = bridge.sendRequest("tools/list", {});

        listPromise.then(response => {
            const tools = [];
            const rawTools = response?.tools || [];

            if (Array.isArray(rawTools)) {
                // Standard MCP format: array of { name, description, inputSchema }
                for (let i = 0; i < rawTools.length; i++) {
                    const tool = rawTools[i];
                    if (!tool.name || typeof tool.name !== "string") {
                        console.warn(`[MCP:${bridge.serverName}] Skipping tool with missing name at index ${i}`);
                        continue;
                    }
                    let schema = tool.inputSchema || {};
                    if (typeof schema === "string") {
                        try { schema = JSON.parse(schema); } catch (e) {
                            console.warn(`[MCP:${bridge.serverName}] Skipping tool "${tool.name}" with unparseable schema`);
                            continue;
                        }
                    }
                    tools.push({
                        name: tool.name,
                        description: tool.description || "",
                        inputSchema: schema
                    });
                }
            } else if (rawTools && typeof rawTools === "object") {
                // Dict format: { toolName: { description, inputSchema } }
                const toolNames = Object.keys(rawTools);
                for (let i = 0; i < toolNames.length; i++) {
                    const name = toolNames[i];
                    const tool = rawTools[name];
                    if (!tool || typeof tool !== "object") {
                        console.warn(`[MCP:${bridge.serverName}] Skipping invalid tool entry "${name}"`);
                        continue;
                    }
                    let schema = tool.inputSchema || {};
                    if (typeof schema === "string") {
                        try { schema = JSON.parse(schema); } catch (e) {
                            console.warn(`[MCP:${bridge.serverName}] Skipping tool "${name}" with unparseable schema`);
                            continue;
                        }
                    }
                    tools.push({
                        name: name,
                        description: tool.description || "",
                        inputSchema: schema
                    });
                }
            }

            bridge.discoveredTools = tools;
            result._resolve(tools);
        });

        listPromise.catch(err => {
            console.warn(`[MCP:${bridge.serverName}] tools/list failed: ${err}`);
            bridge.discoveredTools = [];
            result._reject(err);
        });

        return result;
    }

    // ──────────────────────────────────────────────
    // Internal: stdout line handling
    // ──────────────────────────────────────────────

    function _handleStdoutLine(data) {
        // Try to parse as JSON
        let parsed;
        try {
            parsed = JSON.parse(data);
        } catch (e) {
            // Malformed line — discard and log warning (first 200 chars)
            const preview = data.length > bridge._malformedLogMax
                ? data.substring(0, bridge._malformedLogMax) + "..."
                : data;
            console.warn(`[MCP:${bridge.serverName}] Malformed stdout (discarded): ${preview}`);
            return;
        }

        // Validate JSON-RPC 2.0 structure
        if (parsed.jsonrpc !== "2.0") {
            const preview = data.length > bridge._malformedLogMax
                ? data.substring(0, bridge._malformedLogMax) + "..."
                : data;
            console.warn(`[MCP:${bridge.serverName}] Non-JSON-RPC line (discarded): ${preview}`);
            return;
        }

        // Check if it's a response (has id) or notification (no id)
        if (parsed.id !== undefined && parsed.id !== null) {
            // Response — correlate with pending request
            const id = parsed.id;
            const entry = bridge.pendingRequests[id];

            if (entry) {
                // Remove from pending
                delete bridge.pendingRequests[id];
                bridge._pendingCount -= 1;

                // Cancel timeout
                if (entry.timer) {
                    entry.timer.running = false;
                    entry.timer.destroy();
                }

                // Resolve or reject based on error field
                if (parsed.error) {
                    entry.reject(parsed.error.message || JSON.stringify(parsed.error));
                } else {
                    entry.resolve(parsed.result);
                }
            } else {
                console.warn(`[MCP:${bridge.serverName}] Response for unknown id: ${id}`);
            }
        } else {
            // Notification — log for now (MCP notifications like progress, etc.)
            if (parsed.method) {
                console.log(`[MCP:${bridge.serverName}] Notification: ${parsed.method}`);
            }
        }

        // Update activity timestamp
        bridge._resetIdleTimer();
    }

    // ──────────────────────────────────────────────
    // Internal: process exit handling
    // ──────────────────────────────────────────────

    function _handleProcessExit(exitCode, exitStatus) {
        console.log(`[MCP:${bridge.serverName}] Process exited (code: ${exitCode}, status: ${exitStatus})`);

        forceKillTimer.running = false;
        idleTimer.running = false;

        // Reject all pending requests with disconnect error
        bridge._rejectAllPending(`Server disconnected (exit code: ${exitCode})`);

        // Update state
        if (bridge.state !== "disconnected") {
            bridge.state = bridge.state === "connecting" ? "error" : "disconnected";
            if (exitCode !== 0 && bridge.state !== "disconnected") {
                bridge.lastError = `Process exited with code ${exitCode}`;
            }
        }
    }

    // ──────────────────────────────────────────────
    // Internal: reject all pending requests
    // ──────────────────────────────────────────────

    function _rejectAllPending(reason) {
        const ids = Object.keys(bridge.pendingRequests);
        for (let i = 0; i < ids.length; i++) {
            const id = ids[i];
            const entry = bridge.pendingRequests[id];
            if (entry) {
                if (entry.timer) {
                    entry.timer.running = false;
                    entry.timer.destroy();
                }
                entry.reject(reason);
            }
        }
        bridge.pendingRequests = {};
        bridge._pendingCount = 0;
    }

    // ──────────────────────────────────────────────
    // Internal: write notification (no id, no response expected)
    // ──────────────────────────────────────────────

    function _writeNotification(method, params) {
        const notification = {
            jsonrpc: "2.0",
            method: method,
            params: params || {}
        };
        const serialized = JSON.stringify(notification);
        if (serverProc.running) {
            serverProc.write(serialized + "\n");
        }
    }

    // ──────────────────────────────────────────────
    // Internal: idle timer management
    // ──────────────────────────────────────────────

    function _resetIdleTimer() {
        bridge.lastActivityTimestamp = Date.now();
        idleTimer.running = false;
        if (bridge.state === "connected") {
            idleTimer.running = true;
        }
    }

    // ──────────────────────────────────────────────
    // Internal: build curl headers including session ID
    // ──────────────────────────────────────────────

    /**
     * _buildCurlHeaders() — Build curl -H arguments including session ID.
     * Returns array of ["-H", "Header: value", ...] pairs.
     */
    function _buildCurlHeaders() {
        const headers = [
            "-H", "Content-Type: application/json",
            "-H", "Accept: text/event-stream, application/json"
        ];
        if (bridge.sessionId) {
            headers.push("-H", `Mcp-Session-Id: ${bridge.sessionId}`);
        }
        return headers;
    }

    // ──────────────────────────────────────────────
    // Internal: parse response header line from curl -i output
    // ──────────────────────────────────────────────

    /**
     * _parseResponseHeaderLine(line, context) — Parse a single header line from curl -i output.
     * context: { inHeaders: true, contentType: "", httpStatus: 0 }
     * Returns true if still in header phase, false when blank line signals body start.
     */
    function _parseResponseHeaderLine(line, context) {
        // Blank line signals end of headers
        if (line === "" || line === "\r") {
            context.inHeaders = false;
            return false;
        }

        // HTTP status line (e.g., "HTTP/1.1 200 OK" or "HTTP/2 200")
        if (line.startsWith("HTTP/")) {
            const parts = line.split(" ");
            if (parts.length >= 2) {
                context.httpStatus = parseInt(parts[1], 10) || 0;
            }
            return true;
        }

        // Header line: "Name: Value"
        const colonIdx = line.indexOf(":");
        if (colonIdx === -1) return true;

        const name = line.substring(0, colonIdx).trim().toLowerCase();
        const value = line.substring(colonIdx + 1).trim();

        switch (name) {
            case "content-type":
                context.contentType = value.split(";")[0].trim().toLowerCase();
                break;
            case "mcp-session-id":
                bridge.sessionId = value;
                break;
        }

        return true;
    }

    // ──────────────────────────────────────────────
    // Internal: shell escaping for HTTP curl commands
    // ──────────────────────────────────────────────

    function _shellEscape(str) {
        // Escape single quotes for shell: replace ' with '\''
        return String(str).split("'").join("'\\''");
    }

    // ──────────────────────────────────────────────
    // Internal: Process slot limiting and request queue
    // ──────────────────────────────────────────────

    /**
     * _enqueueRequest(method, params, timeout, promise) — Queue a request when at process capacity.
     * Returns true if queued, false if queue is full (promise will be rejected).
     */
    function _enqueueRequest(method, params, timeout, promise) {
        if (bridge.requestQueue.length >= bridge._maxQueueSize) {
            promise._reject(`Request queue full (${bridge._maxQueueSize} pending) — server: ${bridge.serverName}, method: ${method}`);
            return false;
        }

        let queue = bridge.requestQueue.slice(); // copy for reactivity
        queue.push({
            method: method,
            params: params,
            timeout: timeout,
            promise: promise
        });
        bridge.requestQueue = queue;
        return true;
    }

    /**
     * _processQueue() — Dequeue and send the next request when a process slot frees.
     */
    function _processQueue() {
        if (bridge.requestQueue.length === 0) return;
        if (bridge.activeProcessCount >= bridge._maxConcurrentProcesses) return;

        let queue = bridge.requestQueue.slice();
        const entry = queue.shift();
        bridge.requestQueue = queue;

        // Send the dequeued request through the streaming path
        const innerPromise = bridge._sendStreamingHttpRequest(entry.method, entry.params, entry.timeout);

        innerPromise.then(result => {
            entry.promise._resolve(result);
        });

        innerPromise.catch(err => {
            entry.promise._reject(err);
        });
    }

    // ──────────────────────────────────────────────
    // Internal: Push channel notification handler
    // ──────────────────────────────────────────────

    /**
     * _handlePushChannelEvent(notification) — Handle a server-initiated JSON-RPC notification.
     * Dispatches to the appropriate handler based on method name.
     */
    function _handlePushChannelEvent(notification) {
        const method = notification.method;
        const params = notification.params || {};

        switch (method) {
            case "notifications/tools/list_changed":
                console.log(`[MCP:${bridge.serverName}] Tools list changed, re-discovering`);
                bridge.discoverTools();
                break;

            case "notifications/progress":
                const token = String(params.progressToken || "");
                const current = Number(params.progress) || 0;
                const total = (params.total !== undefined && params.total !== null)
                    ? Number(params.total)
                    : -1;
                bridge.progressNotification(token, current, total);
                break;

            default:
                console.log(`[MCP:${bridge.serverName}] Unhandled push notification: ${method}`);
                break;
        }
    }

    // ──────────────────────────────────────────────
    // Internal: Server Push Channel (GET SSE stream)
    // ──────────────────────────────────────────────

    /**
     * _openPushChannel() — Open persistent GET SSE stream for server-initiated notifications.
     * Uses a long-lived curl process with SplitParser for incremental delivery.
     */
    function _openPushChannel() {
        if (bridge.pushChannelActive) return;
        if (!bridge.httpEndpoint) return;
        if (!bridge.sseSupported) return;
        if (bridge.disabled) return;

        bridge.pushChannelActive = true;
        bridge.reconnectAttempts = 0;
        bridge.reconnectInterval = 1000;

        // Build GET command with SSE accept header and session ID
        const headers = ["-H", "Accept: text/event-stream"];
        if (bridge.sessionId) {
            headers.push("-H", `Mcp-Session-Id: ${bridge.sessionId}`);
        }

        const cmd = ["curl", "-N", "-i", "--connect-timeout", "10", "--max-time", "0",
                     "-X", "GET", bridge.httpEndpoint, ...headers];

        // Push channel state machine
        const state = {
            context: { inHeaders: true, contentType: "", httpStatus: 0 },
            sseParser: SseParser.createParser()
        };

        // Set up SSE parser event handler for push channel events
        state.sseParser.onEvent = (event) => {
            const data = event.data;

            // Validate as JSON-RPC notification (has method, no id)
            if (data && typeof data === "object" && data.jsonrpc === "2.0" && data.method) {
                bridge._handlePushChannelEvent(data);
            } else if (data && typeof data === "object" && data.method) {
                // Relaxed check — still try to handle
                bridge._handlePushChannelEvent(data);
            } else {
                // Not a valid JSON-RPC notification — discard with warning
                console.warn(`[MCP:${bridge.serverName}] Push channel: discarding unparseable event`);
            }
        };

        // Create persistent Process for push channel
        const proc = Qt.createQmlObject(`
            import Quickshell;
            import Quickshell.Io;
            Process {
                running: false
                stdout: SplitParser {
                    onRead: data => { bridge._handlePushChannelLine(data); }
                }
                stderr: SplitParser {
                    onRead: data => {}
                }
            }
        `, bridge, "pushChannelProc");

        proc.command = cmd;
        bridge.pushChannelProcess = proc;

        // Store the state for the line handler to access
        bridge._pushChannelState = state;

        proc.exited.connect((exitCode, exitStatus) => {
            bridge.pushChannelActive = false;
            bridge.pushChannelProcess = null;
            bridge._pushChannelState = null;
            proc.destroy();

            if (bridge.state === "connected") {
                console.warn(`[MCP:${bridge.serverName}] Push channel disconnected (exit: ${exitCode})`);
                bridge._attemptPushChannelReconnect();
            }
        });

        proc.running = true;
        bridge.activeProcessCount += 1;
    }

    /**
     * _handlePushChannelLine(line) — Process a line from the push channel stdout.
     * Routes through header/body state machine then to SseEventParser.
     */
    function _handlePushChannelLine(line) {
        const state = bridge._pushChannelState;
        if (!state) return;

        if (state.context.inHeaders) {
            bridge._parseResponseHeaderLine(line, state.context);
            return;
        }

        // Body phase — feed to SSE parser
        state.sseParser.feedLine(line);
    }

    /**
     * _closePushChannel() — Terminate the push channel process and clean up state.
     */
    function _closePushChannel() {
        if (!bridge.pushChannelActive && !bridge.pushChannelProcess) return;

        bridge.pushChannelActive = false;

        if (bridge.pushChannelProcess) {
            bridge.pushChannelProcess.signal(15); // SIGTERM
            bridge.pushChannelProcess.destroy();
            bridge.pushChannelProcess = null;
            bridge.activeProcessCount -= 1;
        }

        bridge._pushChannelState = null;

        // Stop idle disconnect timer if running
        if (bridge._pushIdleTimer) {
            bridge._pushIdleTimer.running = false;
            bridge._pushIdleTimer.destroy();
            bridge._pushIdleTimer = null;
        }
    }

    /**
     * _resetPushIdleTimer() — Reset the 60s idle timer for the push channel.
     * If no requests are pending for 60s, close the push channel.
     */
    function _resetPushIdleTimer() {
        if (!bridge.pushChannelActive) return;

        if (bridge._pushIdleTimer) {
            bridge._pushIdleTimer.restart();
            return;
        }

        bridge._pushIdleTimer = Qt.createQmlObject(`
            import QtQuick;
            Timer {
                interval: ${bridge._idleDisconnectTimeout}
                repeat: false
                running: true
            }
        `, bridge, "pushIdleTimer");

        bridge._pushIdleTimer.triggered.connect(() => {
            if (bridge._pendingCount === 0 && bridge.pushChannelActive) {
                console.log(`[MCP:${bridge.serverName}] Push channel idle timeout (${bridge._idleDisconnectTimeout / 1000}s), closing`);
                bridge._closePushChannel();
            }
        });
    }

    // ──────────────────────────────────────────────
    // Internal: Push channel reconnection with exponential backoff
    // ──────────────────────────────────────────────

    /**
     * _attemptPushChannelReconnect() — Reconnect push channel with exponential backoff.
     * Formula: min(2^(N-1) * 1000, 30000) ms, max 10 attempts.
     */
    function _attemptPushChannelReconnect() {
        if (bridge.disabled) return;

        bridge.reconnectAttempts += 1;

        if (bridge.reconnectAttempts > bridge._pushReconnectMax) {
            console.warn(`[MCP:${bridge.serverName}] Push channel reconnect failed after ${bridge._pushReconnectMax} attempts`);
            bridge.state = "disconnected";
            bridge.pushChannelDisconnected();
            return;
        }

        // Calculate backoff interval: min(2^(N-1) * 1000, 30000)
        const interval = Math.min(Math.pow(2, bridge.reconnectAttempts - 1) * 1000, bridge._pushReconnectCap);
        bridge.reconnectInterval = interval;

        console.log(`[MCP:${bridge.serverName}] Push channel reconnect attempt ${bridge.reconnectAttempts}/${bridge._pushReconnectMax} in ${interval}ms`);

        // Schedule reconnect
        const reconnectTimer = Qt.createQmlObject(`
            import QtQuick;
            Timer {
                interval: ${interval}
                repeat: false
                running: true
            }
        `, bridge, "pushReconnectTimer");

        reconnectTimer.triggered.connect(() => {
            reconnectTimer.destroy();
            // Only attempt if we're still in connected state and push is not active
            if (bridge.state === "connected" && !bridge.pushChannelActive) {
                bridge._openPushChannel();
            }
        });
    }

    // ──────────────────────────────────────────────
    // Internal: Quick reconnect (Req 8.2 — unexpected disconnect recovery)
    // ──────────────────────────────────────────────

    /**
     * _attemptQuickReconnect() — Quick reconnect: 3 attempts at 5s intervals.
     * Used for unexpected disconnects during active operation (Req 8.2).
     * On failure: transition to error state with warning log.
     */
    function _attemptQuickReconnect() {
        if (bridge.disabled) return;

        const maxAttempts = 3;
        const interval = 5000;
        let attempts = 0;

        function tryReconnect() {
            attempts += 1;

            if (attempts > maxAttempts) {
                console.warn(`[MCP:${bridge.serverName}] Push channel reconnect failed after ${maxAttempts} attempts at 5s intervals`);
                bridge.state = "error";
                bridge.lastError = `Push channel reconnect failed (${maxAttempts} attempts)`;
                bridge.pushChannelDisconnected();
                return;
            }

            console.log(`[MCP:${bridge.serverName}] Quick reconnect attempt ${attempts}/${maxAttempts} in ${interval}ms`);

            const timer = Qt.createQmlObject(`
                import QtQuick;
                Timer {
                    interval: ${interval}
                    repeat: false
                    running: true
                }
            `, bridge, "quickReconnectTimer");

            timer.triggered.connect(() => {
                timer.destroy();

                // Abort if state changed while waiting
                if (bridge.state === "disconnected" || bridge.state === "error") {
                    return;
                }

                // Already reconnected by another path
                if (bridge.pushChannelActive) {
                    return;
                }

                // Attempt to reopen push channel
                bridge._openPushChannel();

                // If push channel failed to activate, schedule next attempt
                if (!bridge.pushChannelActive) {
                    tryReconnect();
                }
            });
        }

        tryReconnect();
    }

    /**
     * switchToStdio() — Switch this bridge from HTTP to stdio transport.
     * Used when HTTP probe fails and we need to fall back to spawning the process.
     */
    function switchToStdio() {
        bridge.transport = "stdio";
        bridge.state = "disconnected";
        bridge.lastError = "";
    }

    // ──────────────────────────────────────────────
    // Internal: Tool call retry logic
    // ──────────────────────────────────────────────

    /**
     * _sendWithRetry(method, params, customTimeout) — Send streaming HTTP request with 1 retry.
     * On network error (connection refused, DNS failure, timeout): wait 2s, retry once.
     * On second failure: reject with the failure reason.
     */
    function _sendWithRetry(method, params, customTimeout) {
        const result = bridge._makePromise();

        const firstAttempt = bridge._sendStreamingHttpRequest(method, params, customTimeout);

        firstAttempt.then(response => {
            result._resolve(response);
        });

        firstAttempt.catch(err => {
            const errStr = String(err).toLowerCase();

            // Check if it's a retriable network error
            const isNetworkError = errStr.indexOf("connection refused") !== -1 ||
                                   errStr.indexOf("dns") !== -1 ||
                                   errStr.indexOf("could not resolve") !== -1 ||
                                   errStr.indexOf("timeout") !== -1 ||
                                   errStr.indexOf("exit code: 6") !== -1 ||   // curl: couldn't resolve host
                                   errStr.indexOf("exit code: 7") !== -1 ||   // curl: connection refused
                                   errStr.indexOf("exit code: 28") !== -1;    // curl: timeout

            if (!isNetworkError) {
                result._reject(err);
                return;
            }

            console.log(`[MCP:${bridge.serverName}] Network error, retrying in 2s: ${err}`);

            // Wait 2s, then retry once
            const retryTimer = Qt.createQmlObject(`
                import QtQuick;
                Timer {
                    interval: 2000
                    repeat: false
                    running: true
                }
            `, bridge, "retryTimer");

            retryTimer.triggered.connect(() => {
                retryTimer.destroy();

                const retryAttempt = bridge._sendStreamingHttpRequest(method, params, customTimeout);

                retryAttempt.then(response => {
                    result._resolve(response);
                });

                retryAttempt.catch(retryErr => {
                    result._reject(`Retry failed: ${retryErr} (original: ${err})`);
                });
            });
        });

        return result;
    }

    // ──────────────────────────────────────────────
    // Internal: Session invalidation and re-handshake on HTTP 404
    // ──────────────────────────────────────────────

    /**
     * _handleSessionInvalidation(method, params, customTimeout) — Handle HTTP 404.
     * Clears session, re-handshakes, then retries the original request once.
     * On double-404: marks server unreachable.
     */
    function _handleSessionInvalidation(method, params, customTimeout) {
        const result = bridge._makePromise();

        console.warn(`[MCP:${bridge.serverName}] Session invalidated (404), re-handshaking`);

        // Clear session
        bridge.sessionId = "";
        bridge.sseSupported = false;

        // Re-handshake
        const initPromise = bridge._sendStreamingHttpRequest("initialize", {
            protocolVersion: "2024-11-05",
            capabilities: {},
            clientInfo: { name: "ii-sidebar", version: "1.0.0" }
        }, bridge._initTimeout);

        initPromise.then(initResponse => {
            // Send initialized notification
            bridge._sendStreamingHttpRequest("notifications/initialized", {}, 3000);

            // Small delay then retry original request
            const delayTimer = Qt.createQmlObject(`
                import QtQuick;
                Timer { interval: 200; repeat: false; running: true }
            `, bridge, "rehandshakeDelay");

            delayTimer.triggered.connect(() => {
                delayTimer.destroy();

                // Retry original request
                const retryPromise = bridge._sendStreamingHttpRequest(method, params, customTimeout);

                retryPromise.then(response => {
                    result._resolve(response);
                });

                retryPromise.catch(retryErr => {
                    const retryErrStr = String(retryErr).toLowerCase();
                    if (retryErrStr.indexOf("404") !== -1) {
                        // Double-404: mark unreachable
                        console.error(`[MCP:${bridge.serverName}] Double 404 — marking server unreachable`);
                        bridge.state = "error";
                        bridge.lastError = "Server unreachable (session invalidation loop)";
                        result._reject(bridge.lastError);
                    } else {
                        result._reject(retryErr);
                    }
                });
            });
        });

        initPromise.catch(initErr => {
            bridge.state = "error";
            bridge.lastError = `Re-handshake failed: ${initErr}`;
            result._reject(bridge.lastError);
        });

        return result;
    }

    // ──────────────────────────────────────────────
    // Internal: Session DELETE on shutdown
    // ──────────────────────────────────────────────

    /**
     * _sendSessionDelete() — Send HTTP DELETE to terminate session on shutdown.
     * 5-second timeout; discards session ID regardless of response.
     */
    function _sendSessionDelete() {
        if (!bridge.sessionId || !bridge.httpEndpoint) {
            bridge.sessionId = "";
            return;
        }

        const sessionIdToDelete = bridge.sessionId;
        bridge.sessionId = ""; // Discard immediately

        // Fire-and-forget DELETE with 5s timeout
        const cmd = ["curl", "-s", "--connect-timeout", "5", "--max-time", "5",
                     "-X", "DELETE", bridge.httpEndpoint,
                     "-H", `Mcp-Session-Id: ${sessionIdToDelete}`];

        const proc = Qt.createQmlObject(`
            import Quickshell;
            import Quickshell.Io;
            Process {
                running: false
                stdout: SplitParser {
                    onRead: data => {}
                }
                stderr: SplitParser {
                    onRead: data => {}
                }
            }
        `, bridge, "sessionDeleteProc");

        proc.command = cmd;

        proc.exited.connect((exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn(`[MCP:${bridge.serverName}] Session DELETE failed (exit: ${exitCode}), proceeding`);
            } else {
                console.log(`[MCP:${bridge.serverName}] Session terminated successfully`);
            }
            proc.destroy();
        });

        proc.running = true;
    }

    // ──────────────────────────────────────────────
    // Internal: HTTP 400/405 fallback to one-shot curl
    // ──────────────────────────────────────────────

    /**
     * _handleNonSseFallback(httpStatus) — Mark server as non-SSE on 400/405.
     * Routes all subsequent requests to existing one-shot curl path.
     */
    function _handleNonSseFallback(httpStatus) {
        if (bridge.nonSseMarked) return; // Already marked

        console.log(`[MCP:${bridge.serverName}] Server responded ${httpStatus}, falling back to one-shot HTTP (non-SSE)`);
        bridge.nonSseMarked = true;
        bridge.sseSupported = false;

        // Close push channel if active (server doesn't support SSE)
        if (bridge.pushChannelActive) {
            bridge._closePushChannel();
        }
    }

    // ──────────────────────────────────────────────
    // Internal: Error-to-connected recovery
    // ──────────────────────────────────────────────

    /**
     * _handleErrorToConnected() — Recovery from error state.
     * Re-establishes push channel and refreshes tool registry.
     */
    function _handleErrorToConnected() {
        console.log(`[MCP:${bridge.serverName}] Recovering from error state`);

        // Reset error state
        bridge.lastError = "";
        bridge.nonSseMarked = false;
        bridge.reconnectAttempts = 0;
        bridge.reconnectInterval = 1000;

        // Re-discover tools
        bridge.discoverTools();

        // Re-open push channel if SSE is supported
        if (bridge.sseSupported && bridge.httpEndpoint) {
            bridge._openPushChannel();
        }
    }

    // ──────────────────────────────────────────────
    // Internal: Process termination with SIGKILL escalation
    // ──────────────────────────────────────────────

    /**
     * _terminateWithEscalation(proc) — Send SIGTERM, then SIGKILL after 5s grace.
     * Used for stuck curl processes that don't respond to SIGTERM.
     */
    function _terminateWithEscalation(proc) {
        if (!proc || !proc.running) return;

        // Send SIGTERM
        proc.signal(15);

        // Set up grace timer for SIGKILL
        const graceTimer = Qt.createQmlObject(`
            import QtQuick;
            Timer {
                interval: ${bridge._shutdownGrace}
                repeat: false
                running: true
            }
        `, bridge, "sigkillGraceTimer");

        graceTimer.triggered.connect(() => {
            graceTimer.destroy();
            if (proc && proc.running) {
                console.warn(`[MCP:${bridge.serverName}] Process did not exit after SIGTERM, sending SIGKILL`);
                proc.signal(9); // SIGKILL
            }
        });

        // Clean up grace timer if process exits before it fires
        proc.exited.connect(() => {
            if (graceTimer) {
                graceTimer.running = false;
                graceTimer.destroy();
            }
        });
    }

    // ──────────────────────────────────────────────
    // Internal: Promise-like pattern
    // QML/JS lacks native Promises, so we use a simple
    // callback-based approach compatible with the engine.
    // ──────────────────────────────────────────────

    function _makePromise() {
        const promise = {
            _resolved: false,
            _rejected: false,
            _result: undefined,
            _error: undefined,
            _thenCb: null,
            _catchCb: null,

            then: function(cb) {
                if (promise._resolved) {
                    cb(promise._result);
                } else {
                    promise._thenCb = cb;
                }
                return promise;
            },

            catch: function(cb) {
                if (promise._rejected) {
                    cb(promise._error);
                } else {
                    promise._catchCb = cb;
                }
                return promise;
            },

            _resolve: function(result) {
                if (promise._resolved || promise._rejected) return;
                promise._resolved = true;
                promise._result = result;
                if (promise._thenCb) {
                    promise._thenCb(result);
                }
            },

            _reject: function(error) {
                if (promise._resolved || promise._rejected) return;
                promise._rejected = true;
                promise._error = error;
                if (promise._catchCb) {
                    promise._catchCb(error);
                }
            }
        };
        return promise;
    }

    function _makeResolved(value) {
        const p = bridge._makePromise();
        p._resolve(value);
        return p;
    }
}
