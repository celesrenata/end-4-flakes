pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions as CF
import Quickshell
import Quickshell.Io
import Qt.labs.platform
import QtQuick
import "./mcp/"

/**
 * McpClient — Unified MCP server lifecycle manager and tool registry.
 *
 * Manages all configured MCP servers from ~/.kiro/settings/mcp.json,
 * handles tool discovery, name prefixing, conflict detection, and
 * dispatches tool calls to the appropriate server bridge.
 *
 * Servers are instantiated on initialize() but only spawned lazily
 * on the first tool call targeting them.
 */
Singleton {
    id: root

    // ──────────────────────────────────────────────
    // Public properties
    // ──────────────────────────────────────────────

    // toolName → { serverName, originalName, description, inputSchema }
    property var toolRegistry: ({})

    // serverName → "disconnected"|"connecting"|"connected"|"error"|"disabled"
    property var serverStates: ({})

    // Flat list of prefixed tool names that don't need user confirmation
    property var autoApproveList: []

    // ──────────────────────────────────────────────
    // Signals
    // ──────────────────────────────────────────────

    signal toolsChanged()
    signal serverStateChanged(string serverName, string state)

    // ──────────────────────────────────────────────
    // Internal state
    // ──────────────────────────────────────────────

    // serverName → McpServerBridge instance
    property var _bridges: ({})

    // serverName → config entry (command, args, env, timeout, autoApprove, disabled)
    property var _serverConfigs: ({})

    // Built-in tool names that MCP tools cannot shadow
    readonly property var _builtinToolNames: [
        "switch_to_search_mode",
        "get_shell_config",
        "set_shell_config",
        "run_shell_command",
        "hypr_config_read",
        "hypr_config_set",
        "hypr_set_keyword"
    ]

    // Config file path
    readonly property string _configPath: {
        const home = StandardPaths.standardLocations(StandardPaths.HomeLocation)[0];
        // StandardPaths returns QUrl objects; convert to string first
        const homeStr = String(home);
        const homePath = homeStr.startsWith("file://") ? homeStr.slice(7) : homeStr;
        return homePath + "/.kiro/settings/mcp.json";
    }

    // Bridge component for dynamic instantiation
    property Component _bridgeComponent: McpServerBridge {}

    // ──────────────────────────────────────────────
    // Config file reader
    // ──────────────────────────────────────────────

    FileView {
        id: configFile
        path: root._configPath
        blockLoading: true

        onLoaded: {
            root._parseConfig(configFile.text());
        }

        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                console.warn("[McpClient] Config file not found: " + root._configPath + " — operating with built-in tools only");
            } else {
                console.warn("[McpClient] Failed to load config: " + error + " — operating with built-in tools only");
            }
            // Operate with empty server list
            root._serverConfigs = {};
            root.serverStates = {};
            root.toolRegistry = {};
            root.autoApproveList = [];
        }
    }

    // ──────────────────────────────────────────────
    // Public API
    // ──────────────────────────────────────────────

    /**
     * initialize() — Read mcp.json, register servers, instantiate bridges.
     * Servers are NOT spawned here — they spawn lazily on first callTool().
     */
    function initialize() {
        configFile.reload();
    }

    /**
     * callTool(toolName, args) — Dispatch a tool call to the appropriate MCP server.
     * Lazy-spawns the target server if not yet running.
     * For ii-desktop: tries HTTP first, falls back to stdio on failure.
     * Returns a Promise-like object with .then(cb) and .catch(cb).
     */
    function callTool(toolName, args) {
        const entry = root.toolRegistry[toolName];

        if (!entry) {
            const p = root._makePromise();
            p._reject("Unknown MCP tool: " + toolName);
            return p;
        }

        const serverName = entry.serverName;
        const bridge = root._bridges[serverName];

        if (!bridge) {
            const p = root._makePromise();
            p._reject("No bridge for server: " + serverName);
            return p;
        }

        // Check if server is disabled
        if (root.serverStates[serverName] === "disabled") {
            const p = root._makePromise();
            p._reject("Server is disabled: " + serverName);
            return p;
        }

        const result = root._makePromise();

        // Lazy-spawn if not connected
        if (bridge.state === "disconnected" || bridge.state === "error") {
            root._updateServerState(serverName, "connecting");

            const spawnPromise = bridge.spawn();

            spawnPromise.then(() => {
                root._updateServerState(serverName, "connected");

                // Discover tools after spawn (first time)
                if (bridge.discoveredTools.length === 0) {
                    const discoverPromise = bridge.discoverTools();
                    discoverPromise.then(tools => {
                        root._registerToolsFromServer(serverName, tools);
                        // Now execute the actual tool call
                        root._dispatchToolCall(bridge, entry.originalName, args, result, serverName);
                    });
                    discoverPromise.catch(err => {
                        console.warn("[McpClient] Tool discovery failed for " + serverName + ": " + err);
                        // Still try to dispatch the tool call
                        root._dispatchToolCall(bridge, entry.originalName, args, result, serverName);
                    });
                } else {
                    root._dispatchToolCall(bridge, entry.originalName, args, result, serverName);
                }
            });

            spawnPromise.catch(err => {
                // If HTTP transport failed, try stdio fallback only if we have a command to run
                const config = root._serverConfigs[serverName];
                const hasCommand = config && config.command && config.command.length > 0;

                if ((bridge.transport === "http" || (bridge.httpEndpoint && bridge.state === "error")) && hasCommand) {
                    console.log("[McpClient] HTTP probe failed for " + serverName + ", falling back to stdio");
                    bridge.switchToStdio();
                    root._updateServerState(serverName, "connecting");

                    const stdioSpawn = bridge.spawn();
                    stdioSpawn.then(() => {
                        root._updateServerState(serverName, "connected");
                        if (bridge.discoveredTools.length === 0) {
                            const discoverPromise = bridge.discoverTools();
                            discoverPromise.then(tools => {
                                root._registerToolsFromServer(serverName, tools);
                                root._dispatchToolCall(bridge, entry.originalName, args, result, serverName);
                            });
                            discoverPromise.catch(discErr => {
                                console.warn("[McpClient] Tool discovery failed for " + serverName + " (stdio): " + discErr);
                                root._dispatchToolCall(bridge, entry.originalName, args, result, serverName);
                            });
                        } else {
                            root._dispatchToolCall(bridge, entry.originalName, args, result, serverName);
                        }
                    });
                    stdioSpawn.catch(stdioErr => {
                        root._updateServerState(serverName, "error");
                        result._reject("Failed to spawn server " + serverName + " (both HTTP and stdio failed): " + stdioErr);
                    });
                } else {
                    root._updateServerState(serverName, "error");
                    result._reject("Failed to connect to server " + serverName + ": " + err);
                }
            });
        } else if (bridge.state === "connecting") {
            // Already connecting — wait a bit and retry
            // Use a timer to poll (simplistic approach)
            const retryTimer = Qt.createQmlObject(
                `import QtQuick; Timer { interval: 500; repeat: false; running: true }`,
                root, "retryTimer"
            );
            retryTimer.triggered.connect(() => {
                retryTimer.destroy();
                if (bridge.state === "connected") {
                    root._dispatchToolCall(bridge, entry.originalName, args, result, serverName);
                } else {
                    result._reject("Server " + serverName + " is still connecting");
                }
            });
        } else {
            // Already connected — dispatch immediately
            root._dispatchToolCall(bridge, entry.originalName, args, result, serverName);
        }

        return result;
    }

    /**
     * isToolAutoApproved(toolName) — Check if a tool is in the auto-approve list.
     */
    function isToolAutoApproved(toolName) {
        return root.autoApproveList.indexOf(toolName) !== -1;
    }

    /**
     * setServerDisabled(name, disabled) — Toggle server enabled/disabled state.
     * Updates config file and disconnects/skips the server.
     */
    function setServerDisabled(name, disabled) {
        if (!root._serverConfigs[name]) {
            console.warn("[McpClient] Unknown server: " + name);
            return;
        }

        // Update in-memory config
        root._serverConfigs[name].disabled = disabled;

        // Update state
        if (disabled) {
            // Shutdown the bridge if running
            const bridge = root._bridges[name];
            if (bridge && (bridge.state === "connected" || bridge.state === "connecting")) {
                bridge.shutdown();
            }
            root._updateServerState(name, "disabled");

            // Remove tools from registry that belong to this server
            root._removeToolsForServer(name);
        } else {
            root._updateServerState(name, "disconnected");
        }

        // Persist to config file
        root._saveConfig();
    }

    /**
     * connectServer(name) — Explicitly spawn/reconnect a server.
     * Re-enables if disabled, then attempts to spawn the bridge.
     */
    function connectServer(name) {
        if (!root._serverConfigs[name]) {
            console.warn("[McpClient] Unknown server: " + name);
            return;
        }

        // Re-enable if disabled
        if (root._serverConfigs[name].disabled) {
            root._serverConfigs[name].disabled = false;
            root._saveConfig();
        }

        const bridge = root._bridges[name];
        if (!bridge) {
            console.warn("[McpClient] No bridge for server: " + name);
            root._updateServerState(name, "error");
            return;
        }

        // If already connected, nothing to do
        if (bridge.state === "connected") {
            return;
        }

        // If currently connecting, let it finish
        if (bridge.state === "connecting") {
            return;
        }

        // Spawn the bridge
        root._updateServerState(name, "connecting");
        const spawnPromise = bridge.spawn();

        spawnPromise.then(() => {
            root._updateServerState(name, "connected");
            if (bridge.discoveredTools.length > 0) {
                root._registerToolsFromServer(name, bridge.discoveredTools);
            } else {
                const discoverPromise = bridge.discoverTools();
                discoverPromise.then(tools => {
                    root._registerToolsFromServer(name, tools);
                });
                discoverPromise.catch(err => {
                    console.warn("[McpClient] Tool discovery failed for " + name + ": " + err);
                });
            }
        });

        spawnPromise.catch(err => {
            // Try stdio fallback if applicable
            const config = root._serverConfigs[name];
            const hasCommand = config && config.command && config.command.length > 0;

            if (bridge.transport === "http" && hasCommand) {
                bridge.switchToStdio();
                root._updateServerState(name, "connecting");
                const stdioSpawn = bridge.spawn();
                stdioSpawn.then(() => {
                    root._updateServerState(name, "connected");
                    const discoverPromise = bridge.discoverTools();
                    discoverPromise.then(tools => { root._registerToolsFromServer(name, tools); });
                });
                stdioSpawn.catch(() => { root._updateServerState(name, "error"); });
            } else {
                root._updateServerState(name, "error");
            }
        });
    }

    /**
     * getToolDeclarations(format) — Convert tool registry to provider-specific declarations.
     *
     * @param format  One of "gemini", "openai", "mistral"
     * @returns       Array of declarations in the target provider's structure.
     *                Returns [] if registry is empty.
     *
     * Gemini:  [{ functionDeclarations: [ { name, description, parameters } ] }]
     * OpenAI:  [ { name, description, parameters } ]
     * Mistral: [ { type: "function", function: { name, description, parameters } } ]
     */
    function getToolDeclarations(format) {
        const toolNames = Object.keys(root.toolRegistry);

        if (toolNames.length === 0) {
            return [];
        }

        const declarations = [];

        for (let i = 0; i < toolNames.length; i++) {
            const name = toolNames[i];
            const entry = root.toolRegistry[name];

            declarations.push({
                name: name,
                description: entry.description || "",
                parameters: entry.inputSchema || { type: "object", properties: {}, required: [] }
            });
        }

        if (format === "gemini") {
            return [{ functionDeclarations: declarations }];
        } else if (format === "openai") {
            return declarations;
        } else if (format === "mistral") {
            const mistralDecls = [];
            for (let i = 0; i < declarations.length; i++) {
                mistralDecls.push({
                    type: "function",
                    "function": {
                        name: declarations[i].name,
                        description: declarations[i].description,
                        parameters: declarations[i].parameters
                    }
                });
            }
            return mistralDecls;
        }

        // Unknown format — return empty
        console.warn("[McpClient] Unknown format for getToolDeclarations: " + format);
        return [];
    }

    /**
     * getServerStatus() — Returns array of server status objects for UI display.
     * Each entry: { name, state, toolCount }
     */
    function getServerStatus() {
        const statuses = [];
        const serverNames = Object.keys(root._serverConfigs);

        for (let i = 0; i < serverNames.length; i++) {
            const name = serverNames[i];
            const state = root.serverStates[name] || "disconnected";

            // Count tools for this server
            let toolCount = 0;
            const toolNames = Object.keys(root.toolRegistry);
            for (let j = 0; j < toolNames.length; j++) {
                if (root.toolRegistry[toolNames[j]].serverName === name) {
                    toolCount++;
                }
            }

            statuses.push({
                name: name,
                state: state,
                toolCount: toolCount
            });
        }

        return statuses;
    }

    // ──────────────────────────────────────────────
    // Internal: Config parsing
    // ──────────────────────────────────────────────

    function _parseConfig(text) {
        let config;
        try {
            config = JSON.parse(text);
        } catch (e) {
            console.warn("[McpClient] Malformed mcp.json: " + e + " — operating with built-in tools only");
            root._serverConfigs = {};
            root.serverStates = {};
            root.toolRegistry = {};
            root.autoApproveList = [];
            return;
        }

        const servers = config.mcpServers || {};
        const serverNames = Object.keys(servers);
        const newConfigs = {};
        const newStates = {};
        const newAutoApprove = [];

        for (let i = 0; i < serverNames.length; i++) {
            const name = serverNames[i];
            const entry = servers[name];

            // Filter disabled servers
            if (entry.disabled === true) {
                newConfigs[name] = entry;
                newStates[name] = "disabled";
                continue;
            }

            // Validate and clamp timeout
            let timeout = 30000;
            if (entry.timeout !== undefined && entry.timeout !== null) {
                const t = Number(entry.timeout);
                if (t >= 1000 && t <= 300000) {
                    timeout = t;
                } else {
                    console.warn(`[McpClient] Server "${name}" has invalid timeout ${entry.timeout}, using default 30000ms`);
                }
            }

            newConfigs[name] = {
                command: entry.command || "",
                args: entry.args || [],
                env: entry.env || {},
                autoApprove: entry.autoApprove || [],
                timeout: timeout,
                disabled: false,
                url: entry.url || ""
            };
            newStates[name] = "disconnected";

            // Aggregate auto-approve list with prefixed names
            const serverPrefix = "mcp_" + name.replace(/-/g, "_") + "_";
            const approveList = entry.autoApprove || [];
            for (let j = 0; j < approveList.length; j++) {
                newAutoApprove.push(serverPrefix + approveList[j]);
            }
        }

        root._serverConfigs = newConfigs;
        root.serverStates = newStates;
        root.autoApproveList = newAutoApprove;

        // Instantiate bridges for enabled servers
        root._instantiateBridges();

        // Pre-register ii-desktop tools so they're available for dispatch
        // before the server is spawned (enables hypr_* aliases to work immediately)
        root._preRegisterIiDesktopTools();

        // Eagerly spawn HTTP bridges to discover tools before the first chat request
        root._eagerSpawnHttpBridges();
    }

    // ──────────────────────────────────────────────
    // Internal: Eagerly spawn HTTP bridges for tool discovery
    // ──────────────────────────────────────────────

    function _eagerSpawnHttpBridges() {
        const serverNames = Object.keys(root._bridges);
        for (let i = 0; i < serverNames.length; i++) {
            const name = serverNames[i];
            const bridge = root._bridges[name];
            const config = root._serverConfigs[name];

            // Only eager-spawn HTTP bridges (URL-based servers)
            if (!bridge || bridge.transport !== "http") continue;
            if (bridge.state !== "disconnected") continue;

            // Spawn in background — don't block initialization
            root._updateServerState(name, "connecting");
            const spawnPromise = bridge.spawn();

            // Capture name in closure
            (function(serverName, serverBridge) {
                spawnPromise.then(() => {
                    root._updateServerState(serverName, "connected");
                    // Tools are already populated from the probe response in _spawnHttp
                    if (serverBridge.discoveredTools.length > 0) {
                        root._registerToolsFromServer(serverName, serverBridge.discoveredTools);
                    }
                });
                spawnPromise.catch(err => {
                    console.warn("[McpClient] Eager spawn failed for " + serverName + ": " + err);
                    root._updateServerState(serverName, "error");
                });
            })(name, bridge);
        }
    }

    // ──────────────────────────────────────────────
    // Internal: Pre-register known ii-desktop tools
    // ──────────────────────────────────────────────

    function _preRegisterIiDesktopTools() {
        if (!root._serverConfigs["ii-desktop"] || root._serverConfigs["ii-desktop"].disabled) {
            return;
        }

        // Known ii-desktop tools (registered so aliases work before first spawn)
        const knownTools = [
            { name: "config_read", description: "Read Quickshell configuration" },
            { name: "config_set", description: "Set a scalar configuration value" },
            { name: "set_keyword", description: "Sets a config keyword dynamically" },
            { name: "audio_status", description: "Query PipeWire/WirePlumber audio state" },
            { name: "audio_set_volume", description: "Set volume and/or mute state for an audio target" },
            { name: "network_status", description: "Query NetworkManager connectivity and connections" },
            { name: "network_wifi_list", description: "List visible WiFi access points" },
            { name: "clipboard_list", description: "List or search clipboard history entries" },
            { name: "clipboard_copy", description: "Copy a clipboard history entry to active clipboard" },
            { name: "apps_search", description: "Search installed .desktop applications" },
            { name: "apps_launch", description: "Launch an application by its desktop entry ID" },
            { name: "screenshot", description: "Capture a screenshot" },
            { name: "system_info", description: "Query system hardware and resource information" },
            { name: "diagnostic_bundle", description: "Collect comprehensive desktop diagnostic snapshot" },
            { name: "get_version", description: "Returns the Hyprland version and build information" },
            { name: "list_monitors", description: "Lists all outputs with their properties" },
            { name: "list_workspaces", description: "Lists all workspaces with their properties" },
            { name: "list_clients", description: "Lists all windows with their properties" },
            { name: "list_devices", description: "Lists all connected input devices" },
            { name: "get_active_window", description: "Returns the active window name" },
            { name: "list_layers", description: "Lists all the layers" },
            { name: "get_splash", description: "Returns the current random splash" },
            { name: "dispatch_command", description: "Calls a dispatcher with an argument" },
            { name: "reload_config", description: "Forces a reload of the config file" },
            { name: "enter_kill_mode", description: "Enters kill mode to terminate an app by clicking on it" },
            { name: "shell_logs", description: "Read recent Quickshell journal entries" },
            { name: "systemd_status", description: "Query systemd unit status" },
            { name: "systemd_logs", description: "Read recent journal entries for a systemd unit" },
        ];

        const serverPrefix = "mcp_ii_desktop_";
        let changed = false;

        for (let i = 0; i < knownTools.length; i++) {
            const tool = knownTools[i];
            const prefixedName = serverPrefix + tool.name;

            // Don't overwrite if already registered (e.g., from a previous spawn)
            if (root.toolRegistry[prefixedName]) continue;

            root.toolRegistry[prefixedName] = {
                serverName: "ii-desktop",
                originalName: tool.name,
                description: tool.description,
                inputSchema: { type: "object", properties: {} }
            };
            changed = true;
        }

        if (changed) {
            root.toolRegistry = root.toolRegistry;
            root.toolsChanged();
        }
    }

    // ──────────────────────────────────────────────
    // Internal: Bridge instantiation
    // ──────────────────────────────────────────────

    function _instantiateBridges() {
        // Destroy existing bridges
        const oldNames = Object.keys(root._bridges);
        for (let i = 0; i < oldNames.length; i++) {
            const oldBridge = root._bridges[oldNames[i]];
            if (oldBridge) {
                oldBridge.shutdown();
                oldBridge.destroy();
            }
        }
        root._bridges = {};

        // Create new bridges for enabled servers
        const serverNames = Object.keys(root._serverConfigs);
        for (let i = 0; i < serverNames.length; i++) {
            const name = serverNames[i];
            const config = root._serverConfigs[name];

            if (config.disabled === true) continue;

            // Determine transport: use HTTP if server has a url field, otherwise stdio
            // ii-desktop special case: always try HTTP on port 7580 first
            let transportMode = "stdio";
            let httpEndpoint = "";

            if (name === "ii-desktop") {
                transportMode = "http";
                httpEndpoint = "http://localhost:7580/mcp";
            } else if (config.url) {
                transportMode = "http";
                httpEndpoint = config.url;
            }

            const bridge = root._bridgeComponent.createObject(root, {
                serverName: name,
                serverCommand: config.command || "",
                serverArgs: config.args || [],
                serverEnv: config.env || {},
                timeout: config.timeout,
                transport: transportMode,
                httpEndpoint: httpEndpoint
            });

            // Connect state change handler
            bridge.stateChanged.connect(() => {
                root._handleBridgeStateChange(name, bridge);
            });

            root._bridges[name] = bridge;
        }
    }

    // ──────────────────────────────────────────────
    // Internal: Bridge state change handler
    // ──────────────────────────────────────────────

    function _handleBridgeStateChange(serverName, bridge) {
        const newState = bridge.state;
        if (root.serverStates[serverName] !== newState) {
            root._updateServerState(serverName, newState);
        }
    }

    // ──────────────────────────────────────────────
    // Internal: Tool registration from discovered tools
    // ──────────────────────────────────────────────

    function _registerToolsFromServer(serverName, tools) {
        const serverPrefix = "mcp_" + serverName.replace(/-/g, "_") + "_";
        let changed = false;

        for (let i = 0; i < tools.length; i++) {
            const tool = tools[i];
            const prefixedName = serverPrefix + tool.name;

            // Check conflict with built-in tools
            if (root._builtinToolNames.indexOf(prefixedName) !== -1) {
                console.warn(`[McpClient] Rejecting MCP tool "${prefixedName}" — conflicts with built-in tool name`);
                continue;
            }

            // Register in the tool registry
            root.toolRegistry[prefixedName] = {
                serverName: serverName,
                originalName: tool.name,
                description: tool.description || "",
                inputSchema: tool.inputSchema || {}
            };
            changed = true;
        }

        if (changed) {
            // Trigger reactive update
            root.toolRegistry = root.toolRegistry;
            root.toolsChanged();
        }
    }

    // ──────────────────────────────────────────────
    // Internal: Remove tools for a specific server
    // ──────────────────────────────────────────────

    function _removeToolsForServer(serverName) {
        const toolNames = Object.keys(root.toolRegistry);
        let changed = false;

        for (let i = 0; i < toolNames.length; i++) {
            if (root.toolRegistry[toolNames[i]].serverName === serverName) {
                delete root.toolRegistry[toolNames[i]];
                changed = true;
            }
        }

        if (changed) {
            root.toolRegistry = root.toolRegistry;
            root.toolsChanged();
        }
    }

    // ──────────────────────────────────────────────
    // Internal: Dispatch tool call to bridge
    // ──────────────────────────────────────────────

    function _dispatchToolCall(bridge, originalToolName, args, resultPromise, serverName) {
        const callPromise = bridge.sendRequest("tools/call", {
            name: originalToolName,
            arguments: args || {}
        });

        callPromise.then(response => {
            // Parse MCP tool response
            const content = response?.content || [];
            let resultText = "";

            for (let i = 0; i < content.length; i++) {
                const part = content[i];
                if (part.type === "text") {
                    resultText += (resultText.length > 0 ? "\n" : "") + part.text;
                } else if (part.type === "image") {
                    resultText += (resultText.length > 0 ? "\n" : "") + "[Image: " + (part.mimeType || "unknown") + "]";
                } else {
                    resultText += (resultText.length > 0 ? "\n" : "") + JSON.stringify(part);
                }
            }

            if (response?.isError === true) {
                resultPromise._reject(resultText || "Tool returned an error");
                return;
            }

            // Write verification for ii-desktop write operations
            if (serverName === "ii-desktop" && (originalToolName === "config_set" || originalToolName === "set_keyword")) {
                root._verifyWriteOperation(bridge, originalToolName, args, resultText, resultPromise);
            } else {
                resultPromise._resolve(resultText || JSON.stringify(response));
            }
        });

        callPromise.catch(err => {
            resultPromise._reject("Tool call failed: " + err);
        });
    }

    // ──────────────────────────────────────────────
    // Internal: Write operation read-back verification (ii-desktop)
    // ──────────────────────────────────────────────

    function _verifyWriteOperation(bridge, toolName, args, writeResult, resultPromise) {
        // Determine the key and expected value
        const key = args.key || args.keyword || "";
        const expectedValue = String(args.value || "");
        const namespace = key.split(".").slice(0, -1).join(".") || key;

        // Perform read-back via config_read
        const readPromise = bridge.sendRequest("tools/call", {
            name: "config_read",
            arguments: { namespace: namespace }
        });

        readPromise.then(readResponse => {
            const readContent = readResponse?.content || [];
            let readText = "";
            for (let i = 0; i < readContent.length; i++) {
                if (readContent[i].type === "text") {
                    readText += readContent[i].text;
                }
            }

            if (readResponse?.isError === true) {
                // Read-back failed — report error but don't claim success
                resultPromise._resolve(
                    "Write appeared to succeed but verification read-back failed. Cannot confirm change was applied.\n" +
                    "Write result: " + writeResult
                );
                return;
            }

            // Check if the expected value appears in the read-back
            const actualStr = String(readText);

            if (actualStr.indexOf(expectedValue) !== -1) {
                // Match — report verified success
                resultPromise._resolve("Verified: " + key + " = " + expectedValue);
            } else {
                // Mismatch — report both expected and actual
                resultPromise._resolve(
                    "Verification failed: expected " + expectedValue + " for key " + key + ", got: " + actualStr
                );
            }
        });

        readPromise.catch(err => {
            // Read-back request failed entirely
            resultPromise._resolve(
                "Write appeared to succeed but verification read-back failed: " + err + ". Cannot confirm change was applied.\n" +
                "Write result: " + writeResult
            );
        });
    }

    // ──────────────────────────────────────────────
    // Internal: Update server state and emit signal
    // ──────────────────────────────────────────────

    function _updateServerState(serverName, state) {
        root.serverStates[serverName] = state;
        root.serverStates = root.serverStates; // Trigger reactive update
        root.serverStateChanged(serverName, state);
    }

    // ──────────────────────────────────────────────
    // Internal: Save config back to file
    // ──────────────────────────────────────────────

    function _saveConfig() {
        const output = { mcpServers: {} };
        const serverNames = Object.keys(root._serverConfigs);

        for (let i = 0; i < serverNames.length; i++) {
            const name = serverNames[i];
            const cfg = root._serverConfigs[name];
            output.mcpServers[name] = {
                command: cfg.command || "",
                args: cfg.args || [],
                env: cfg.env || {},
                autoApprove: cfg.autoApprove || [],
                timeout: cfg.timeout || 30000,
                disabled: cfg.disabled || false
            };
        }

        configFile.setText(JSON.stringify(output, null, 2));
    }

    // ──────────────────────────────────────────────
    // Internal: Promise-like pattern
    // (Same as McpServerBridge for consistency)
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
}
