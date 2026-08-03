pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

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
                    result._resolve(response);
                });
                toolsPromise.catch(toolsErr => {
                    // Connected but tools/list failed — still mark connected
                    bridge.state = "connected";
                    bridge._resetIdleTimer();
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
        // For HTTP transport, use HTTP path
        if (bridge.transport === "http" && bridge.httpEndpoint && bridge.state === "connected") {
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
    // Internal: shell escaping for HTTP curl commands
    // ──────────────────────────────────────────────

    function _shellEscape(str) {
        // Escape single quotes for shell: replace ' with '\''
        return String(str).split("'").join("'\\''");
    }

    // ──────────────────────────────────────────────
    // Public: Switch transport from HTTP to stdio (fallback)
    // ──────────────────────────────────────────────

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
