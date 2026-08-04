pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions as CF
import qs.modules.common
import qs
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "./ai/"

/**
 * Ai.qml — Singleton service managing the LLM chat system.
 *
 * Supports Google Gemini, OpenAI, and Mistral API formats with streaming responses.
 * Provides function calling (tool use) via built-in tools and MCP server integration.
 *
 * ## Architecture Overview
 *
 * ### Session Lifecycle
 *
 * Sessions are the top-level unit of conversation state. Each session has a name,
 * a JSON message file, and metadata in the sessions index.
 *
 * - newSession(name)      — validates name, saves current session, clears messages,
 *                           creates index entry with timestamps, persists index
 * - switchSession(name)   — saves current session, emits sessionSwitchStarted,
 *                           calls loadSession, updates activeSessionName + Persistent
 *                           state, emits sessionSwitchCompleted
 * - saveCurrentSession()  — serializes messages via chatToJson() → writes to
 *                           {aiChats}/{activeSessionName}.json, updates lastModified
 * - loadSession(name)     — reads {aiChats}/{name}.json via sessionReader FileView,
 *                           parses JSON array, recreates AiMessageData objects into
 *                           messageByID map, assigns messageIDs, increments messageVersion
 * - deleteSession(name)   — switches away if active, removes .json file via Process,
 *                           removes entry from sessionsIndex, persists index
 * - renameSession(old,new)— validates, updates index entry, moves file on disk,
 *                           updates activeSessionName if renaming the current session
 * - archiveSession(name)  — sets archived=true in index (hides from active list)
 * - purgeSession(name)    — writes empty array to session file, preserves index entry
 *
 * On startup (Component.onCompleted): loads sessionsIndex, ensures "Free Dictation"
 * session exists, attempts to load the persisted active session (with fallback to
 * most-recently-modified session, or creates a new default session).
 *
 * ### Message Flow
 *
 * 1. User input arrives via sendUserMessage(text) or sendUserMessageWithAttachments(text)
 * 2. A "user" role AiMessageData is created and added to messageByID/messageIDs
 * 3. requester.makeRequest() is called:
 *    a. Builds endpoint URL via currentApiStrategy.buildEndpoint(model)
 *    b. Filters out interface-role messages, builds request payload via
 *       currentApiStrategy.buildRequestData(model, messages, systemPrompt, temperature, tools, tuning)
 *    c. Writes JSON payload to /tmp/ii-ai-request-payload.json (avoids ARG_MAX)
 *    d. Creates an "assistant" role AiMessageData (thinking=true, done=false)
 *    e. Fires curl --no-buffer via Process, streaming response lines
 * 4. Each response line is parsed by currentApiStrategy.parseResponseLine(data, message)
 *    - Content tokens are appended to message.rawContent / message.content
 *    - Function calls are dispatched to handleFunctionCall()
 *    - Token usage is recorded in tokenCount QtObject
 * 5. On completion (finished signal or process exit): markDone() sets message.done=true,
 *    fires postResponseHook if set, calls saveCurrentSession()
 *
 * ### Context Management
 *
 * - estimateTokens(text)     — approximates token count as ceil(text.length / 4)
 * - contextTokens (readonly) — sum of estimated tokens across systemPrompt + all messages
 * - contextLimit (readonly)  — from current model's context_length (default 128000)
 * - contextUsageRatio        — contextTokens / contextLimit (0.0 to 1.0+)
 * - contextFull              — true when contextUsageRatio >= 1.0 (blocks sending)
 * - Auto-compact threshold   — onContextUsageRatioChanged fires at 0.85 crossing,
 *                              sets autoCompactShown=true to show UI notification
 * - compactChat(focus)       — sends entire conversation to model with a summarization
 *                              prompt, replaces all messages with a single system-role
 *                              summary on success
 * - largerContextModels      — lists models with context_length > current, used by
 *                              AI_Doctor suggestions when context is full
 *
 * ### Message Versioning
 *
 * The `messageVersion` property (int, starts at 0) is incremented inside loadSession()
 * after messages are populated. UI components (e.g., the message ListView delegate)
 * bind to messageVersion to force a complete view refresh on session switch, ensuring
 * stale delegates from the previous session are discarded and new delegates are created
 * from the fresh messageIDs/messageByID state.
 *
 * ### Persistence Model
 *
 * - Sessions index: {XDG_STATE_HOME}/user/ai/chats/sessions-index.json
 *   Format: { "sessions": [{ name, createdAt, lastModified, archived, group, subject, protected? }] }
 *   Loaded/saved via sessionsIndexFile FileView. Rebuilt from filesystem scan if missing/corrupt.
 *
 * - Per-session messages: {XDG_STATE_HOME}/user/ai/chats/{sessionName}.json
 *   Format: JSON array of message objects with fields:
 *   { role, rawContent, model, thinking, done, annotations, annotationSources,
 *     functionName, functionCall, functionResponse, visibleToUser, attachments? }
 *   Read/written via chatSaveFile and sessionReader FileViews.
 *
 * - Attachments: {XDG_STATE_HOME}/user/ai/chats/attachments/{timestamp}-{safeName}
 *   Images are base64-encoded at request time (not stored in chat JSON).
 *
 * - Auto-save triggers: messageIDs change (when not switching), markDone() after
 *   API response completes, session switch (saves outgoing session before loading new one)
 *
 * ### Command System
 *
 * Commands are defined in AiChat.qml's `allCommands` array and dispatched by
 * handleInput() when input starts with the commandPrefix ("/"). Each command
 * object has { name, description, execute(args) }. Key commands:
 *
 * - /model [name]    — switch active LLM model (fuzzy match with suggestions)
 * - /save [name]     — save current chat to a named JSON file
 * - /load [name]     — load a previously saved chat by name
 * - /new [name]      — create a new session (auto-names "Chat N" if no name given)
 * - /switch [name]   — switch to an existing session by name
 * - /delete [name]   — delete a session (file + index entry)
 * - /list            — list all sessions with timestamps
 * - /test            — render a markdown test message (tables, code, LaTeX)
 * - /clear           — clear all messages from the current view
 * - /key [key|get]   — set or display the API key for the current model
 * - /tool [name]     — set the active tool mode (functions/search/none)
 * - /prompt [path]   — load a system prompt from file, or display current
 * - /temp [value]    — set global temperature (0-2)
 * - /tune [...]      — per-model tuning (temp, reasoning, websearch, context, verbosity)
 * - /compact [focus] — summarize conversation to free context space
 * - /summarize [focus] — summarize into a new session (original unchanged)
 *
 * Limitations:
 * - Function calling (tool use) only works fully with Gemini API format;
 *   OpenAI and Mistral have partial support
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    property Component aiModelComponent: AiModel {}
    property Component geminiApiStrategy: GeminiApiStrategy {}
    property Component openaiApiStrategy: OpenAiApiStrategy {}
    property Component mistralApiStrategy: MistralApiStrategy {}
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"

    property string systemPrompt: {
        let prompt = Config.options?.ai?.systemPrompt ?? "";
        for (let key in root.promptSubstitutions) {
            // prompt = prompt.replaceAll(key, root.promptSubstitutions[key]);
            // QML/JS doesn't support replaceAll, so use split/join
            prompt = prompt.split(key).join(root.promptSubstitutions[key]);
        }
        return prompt;
    }
    // property var messages: []
    property var messageIDs: []
    property var messageByID: ({})
    onMessageIDsChanged: {
        if (root.messageIDs.length > 0 && !root.switching) {
            root.saveCurrentSession();
        }
    }
    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelHasApiKey: {
        const model = models[currentModelId];
        if (!model || !model.requires_key) return true;
        if (!apiKeysLoaded) return false;
        const key = apiKeys[model.key_id];
        return (key?.length > 0);
    }
    property var postResponseHook
    property real temperature: Persistent.states?.ai?.temperature ?? 0.5
    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }

    // Per-model tuning settings
    // Returns settings object for the current model, falling back to defaults
    readonly property var currentModelSettings: {
        const settings = Persistent.states?.ai?.modelSettings ?? {};
        return settings[root.currentModelId] ?? {};
    }

    // Get effective temperature for current model (per-model overrides global)
    readonly property real effectiveTemperature: {
        const ms = root.currentModelSettings;
        if (ms.temperature !== undefined && ms.temperature !== null) return ms.temperature;
        return root.temperature;
    }

    // Get model tuning values for current model
    readonly property string currentReasoningEffort: root.currentModelSettings.reasoningEffort ?? ""
    readonly property bool currentWebSearch: root.currentModelSettings.webSearch ?? false
    readonly property string currentSearchContextSize: root.currentModelSettings.searchContextSize ?? "medium"
    readonly property string currentVerbosity: root.currentModelSettings.verbosity ?? ""

    /**
     * Set a tuning parameter for a specific model.
     * @param modelId - the model ID (e.g., "gpt-4.1")
     * @param key - setting key: "temperature", "reasoningEffort", "webSearch", "searchContextSize", "verbosity"
     * @param value - the value to set
     */
    function setModelSetting(modelId, key, value) {
        let allSettings = JSON.parse(JSON.stringify(Persistent.states?.ai?.modelSettings ?? {}));
        if (!allSettings[modelId]) {
            allSettings[modelId] = {};
        }
        allSettings[modelId][key] = value;
        Persistent.states.ai.modelSettings = allSettings;
    }

    /**
     * Get a tuning parameter for a specific model.
     */
    function getModelSetting(modelId, key) {
        const settings = Persistent.states?.ai?.modelSettings ?? {};
        return settings[modelId]?.[key];
    }

    /**
     * Get all tuning settings for the current model (for passing to API strategy).
     */
    function getModelTuning() {
        return {
            "temperature": root.effectiveTemperature,
            "reasoningEffort": root.currentReasoningEffort,
            "webSearch": root.currentWebSearch,
            "searchContextSize": root.currentSearchContextSize,
            "verbosity": root.currentVerbosity,
        };
    }

    // Context window tracking
    function estimateTokens(text) {
        return Math.ceil((text || "").length / 4);
    }

    readonly property int contextTokens: {
        let total = estimateTokens(root.systemPrompt);
        for (const id of root.messageIDs) {
            const msg = root.messageByID[id];
            if (msg) total += estimateTokens(msg.rawContent);
        }
        return total;
    }

    readonly property int contextLimit: models[currentModelId]?.context_length ?? 128000

    readonly property real contextUsageRatio: contextLimit > 0 ? contextTokens / contextLimit : 0

    readonly property bool contextFull: contextUsageRatio >= 1.0

    readonly property string contextMeterText: {
        var percentage = Math.round(root.contextUsageRatio * 100);
        var limit = root.contextLimit;
        var limitStr;
        if (limit >= 1000000) {
            limitStr = (Math.round(limit / 10000) / 100).toFixed(2) + "M";
        } else if (limit >= 1000) {
            limitStr = String(Math.round(limit / 1000)) + "k";
        } else {
            limitStr = String(limit);
        }
        return percentage + "% of " + limitStr;
    }

    // Rename validation error (for inline display in session drawer)
    property string lastRenameError: ""

    // Auto-compact notification state (reset per session)
    property bool autoCompactShown: false
    property bool autoCompactDismissed: false
    property real previousContextUsageRatio: 0

    onContextUsageRatioChanged: {
        // Detect threshold crossing from below (0.85)
        if (root.previousContextUsageRatio < 0.85 && root.contextUsageRatio >= 0.85) {
            if (!root.autoCompactDismissed) {
                root.autoCompactShown = true;
            }
        }
        // After compaction drops below 0.85, reset dismissed so it can re-trigger
        if (root.previousContextUsageRatio >= 0.85 && root.contextUsageRatio < 0.85) {
            root.autoCompactDismissed = false;
            root.autoCompactShown = false;
        }
        root.previousContextUsageRatio = root.contextUsageRatio;
    }

    function dismissAutoCompact() {
        root.autoCompactShown = false;
        root.autoCompactDismissed = true;
    }

    // AI_Doctor: models with larger context windows than the current model
    readonly property var largerContextModels: {
        const currentLimit = root.contextLimit;
        return root.modelList.filter(id => {
            const model = root.models[id];
            return model && model.context_length > currentLimit;
        });
    }

    // Session management
    property string activeSessionName: Persistent.states?.ai?.activeSession ?? "Chat 1"
    property var sessionsIndex: ({})

    // Session switch signals and state
    signal sessionSwitchStarted()
    signal sessionSwitchCompleted()
    property bool switching: false
    property int messageVersion: 0  // Incremented on session switch to force view refresh

    // Compact state
    property bool compacting: false
    property string compactPromptTemplate: "Summarize the following conversation concisely, preserving key context, decisions, and any code or technical details."

    /**
     * Returns the smallest positive integer N such that "Chat {N}" is not
     * already used as a session name in the sessions index.
     */
    function getNextDefaultName() {
        const sessions = root.sessionsIndex.sessions || [];
        const existingNames = sessions.map(s => s.name);
        let n = 1;
        while (existingNames.indexOf(`Chat ${n}`) !== -1) {
            n++;
        }
        return `Chat ${n}`;
    }

    /**
     * Creates a new chat session with the given name.
     * Validates name (non-empty after trim, no / or \ characters).
     * Saves current session, creates empty message list, updates active session.
     * @param name - the session name (optional; if empty, uses getNextDefaultName())
     */
    function newSession(name) {
        // Use default name if none provided
        if (!name || name.trim().length === 0) {
            name = getNextDefaultName();
        } else {
            name = name.trim();
        }

        // Validate: no path separator characters
        if (name.indexOf("/") !== -1 || name.indexOf("\\") !== -1) {
            root.addMessage(
                Translation.tr("Invalid session name: must not contain '/' or '\\' characters"),
                root.interfaceRole
            );
            return;
        }

        // Save the current session before switching
        root.saveCurrentSession();

        // Clear messages for the new session
        root.clearMessages();

        // Reset auto-compact notification state for new session
        root.autoCompactShown = false;
        root.autoCompactDismissed = false;
        root.previousContextUsageRatio = 0;

        // Update active session name
        root.activeSessionName = name;

        // Update Persistent state
        Persistent.states.ai.activeSession = name;

        // Add entry to sessions index
        const sessions = root.sessionsIndex.sessions || [];
        sessions.push({
            "name": name,
            "createdAt": Math.floor(Date.now() / 1000),
            "lastModified": Math.floor(Date.now() / 1000),
            "archived": false,
            "group": "",
            "subject": "",
        });
        root.sessionsIndex = { "sessions": sessions };

        // Persist the updated index
        root.saveSessionsIndex();

        root.addMessage(
            Translation.tr("Created new session: %1").arg(name),
            root.interfaceRole
        );
    }

    function idForMessage(message) {
        // Generate a unique ID using timestamp and random value
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    function safeModelName(modelName) {
        return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-")
    }

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    property list<var> savedChats: []

    property var promptSubstitutions: {
        "{DISTRO}": SystemInfo.distroName,
        "{DATETIME}": `${DateTime.time}, ${DateTime.collapsedCalendarFormat}`,
        "{WINDOWCLASS}": ToplevelManager.activeToplevel?.appId ?? "Unknown",
        "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})` 
    }

    // Gemini: https://ai.google.dev/gemini-api/docs/function-calling
    // OpenAI: https://platform.openai.com/docs/guides/function-calling
    property string currentTool: Config?.options.ai.tool ?? "search"
    property bool yoloMode: false  // Auto-execute commands without approval
    property int _emptyCommandRetries: 0
    property int _emptyResponseRetries: 0
    property var tools: {
        "gemini": {
            "functions": [{"functionDeclarations": [
                {
                    "name": "switch_to_search_mode",
                    "description": "Search the web",
                },
                {
                    "name": "get_shell_config",
                    "description": "Get the desktop shell config file contents",
                },
                {
                    "name": "set_shell_config",
                    "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "key": {
                                "type": "string",
                                "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                            },
                            "value": {
                                "type": "string",
                                "description": "The value to set, e.g. `true`"
                            }
                        },
                        "required": ["key", "value"]
                    }
                },
                {
                    "name": "run_shell_command",
                    "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "command": {
                                "type": "string",
                                "description": "The bash command to run",
                            },
                        },
                        "required": ["command"]
                    }
                },
                {
                    "name": "hypr_config_read",
                    "description": "Read Quickshell or Hyprland configuration via HyprMCP. Returns current config state.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "namespace": {
                                "type": "string",
                                "description": "Dot-separated config namespace to read (e.g. 'bar.workspaces'). Empty string returns all config."
                            }
                        }
                    }
                },
                {
                    "name": "hypr_config_set",
                    "description": "Set a Quickshell config value via HyprMCP with read-back verification. Use hypr_config_read first to see available keys.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "key": {
                                "type": "string",
                                "description": "The dot-separated config key to set (e.g. 'bar.borderless')"
                            },
                            "value": {
                                "type": "string",
                                "description": "The value to set"
                            }
                        },
                        "required": ["key", "value"]
                    }
                },
                {
                    "name": "hypr_set_keyword",
                    "description": "Set a Hyprland runtime keyword via HyprMCP with read-back verification. Used for Hyprland dynamic configuration.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "keyword": {
                                "type": "string",
                                "description": "The Hyprland keyword to set (e.g. 'general:gaps_in')"
                            },
                            "value": {
                                "type": "string",
                                "description": "The value to set"
                            }
                        },
                        "required": ["keyword", "value"]
                    }
                },
            ]}],
            "search": [{
                "google_search": {}
            }],
            "none": []
        },
        "openai": {
            "functions": [
                {
                    "name": "switch_to_search_mode",
                    "description": "Search the web",
                },
                {
                    "name": "get_shell_config",
                    "description": "Get the desktop shell config file contents",
                },
                {
                    "name": "set_shell_config",
                    "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "key": {
                                "type": "string",
                                "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                            },
                            "value": {
                                "type": "string",
                                "description": "The value to set, e.g. `true`"
                            }
                        },
                        "required": ["key", "value"]
                    }
                },
                {
                    "name": "run_shell_command",
                    "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "command": {
                                "type": "string",
                                "description": "The bash command to run",
                            },
                        },
                        "required": ["command"]
                    }
                },
                {
                    "name": "hypr_config_read",
                    "description": "Read Quickshell or Hyprland configuration via HyprMCP. Returns current config state.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "namespace": { "type": "string", "description": "Dot-separated config namespace to read. Empty for all." }
                        }
                    }
                },
                {
                    "name": "hypr_config_set",
                    "description": "Set a Quickshell config value via HyprMCP with read-back verification.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "key": { "type": "string", "description": "Config key to set" },
                            "value": { "type": "string", "description": "Value to set" }
                        },
                        "required": ["key", "value"]
                    }
                },
                {
                    "name": "hypr_set_keyword",
                    "description": "Set a Hyprland runtime keyword via HyprMCP with read-back verification.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "keyword": { "type": "string", "description": "Hyprland keyword" },
                            "value": { "type": "string", "description": "Value to set" }
                        },
                        "required": ["keyword", "value"]
                    }
                },
            ],
            "search": [],
            "none": [],
        },
        "mistral": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": {}
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "hypr_config_read",
                        "description": "Read Quickshell or Hyprland configuration via HyprMCP.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "namespace": { "type": "string", "description": "Config namespace to read" }
                            }
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "hypr_config_set",
                        "description": "Set a Quickshell config value via HyprMCP with verification.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": { "type": "string", "description": "Config key" },
                                "value": { "type": "string", "description": "Value to set" }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "hypr_set_keyword",
                        "description": "Set a Hyprland runtime keyword via HyprMCP with verification.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "keyword": { "type": "string", "description": "Hyprland keyword" },
                                "value": { "type": "string", "description": "Value to set" }
                            },
                            "required": ["keyword", "value"]
                        }
                    }
                },
            ],
            "search": [],
            "none": [],
        }
    }
    property list<var> availableTools: Object.keys(root.tools[models[currentModelId]?.api_format])
    property var toolDescriptions: {
        "functions": Translation.tr("Commands, edit configs, search.\nTakes an extra turn to switch to search mode if that's needed"),
        "search": Translation.tr("Gives the model search capabilities (immediately)"),
        "none": Translation.tr("Disable tools")
    }

    /**
     * Rebuilds the tools property by merging MCP tool declarations into
     * the static built-in tool declarations for each provider format.
     * Called when McpClient.toolsChanged() fires.
     */
    function _rebuildTools() {
        const mcpGemini = McpClient.getToolDeclarations("gemini");
        const mcpOpenai = McpClient.getToolDeclarations("openai");
        const mcpMistral = McpClient.getToolDeclarations("mistral");

        // Gemini: merge MCP functionDeclarations into the existing functionDeclarations array
        const builtinGeminiFuncDecls = [
            { "name": "switch_to_search_mode", "description": "Search the web" },
            { "name": "get_shell_config", "description": "Get the desktop shell config file contents" },
            { "name": "set_shell_config", "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
              "parameters": { "type": "object", "properties": { "key": { "type": "string", "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting." }, "value": { "type": "string", "description": "The value to set, e.g. `true`" } }, "required": ["key", "value"] } },
            { "name": "run_shell_command", "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
              "parameters": { "type": "object", "properties": { "command": { "type": "string", "description": "The bash command to run" } }, "required": ["command"] } },
            { "name": "hypr_config_read", "description": "Read Quickshell or Hyprland configuration via HyprMCP. Returns current config state.",
              "parameters": { "type": "object", "properties": { "namespace": { "type": "string", "description": "Dot-separated config namespace to read (e.g. 'bar.workspaces'). Empty string returns all config." } } } },
            { "name": "hypr_config_set", "description": "Set a Quickshell config value via HyprMCP with read-back verification. Use hypr_config_read first to see available keys.",
              "parameters": { "type": "object", "properties": { "key": { "type": "string", "description": "The dot-separated config key to set (e.g. 'bar.borderless')" }, "value": { "type": "string", "description": "The value to set" } }, "required": ["key", "value"] } },
            { "name": "hypr_set_keyword", "description": "Set a Hyprland runtime keyword via HyprMCP with read-back verification. Used for Hyprland dynamic configuration.",
              "parameters": { "type": "object", "properties": { "keyword": { "type": "string", "description": "The Hyprland keyword to set (e.g. 'general:gaps_in')" }, "value": { "type": "string", "description": "The value to set" } }, "required": ["keyword", "value"] } },
        ];

        // Merge MCP tools into Gemini functionDeclarations
        let mergedGeminiDecls = builtinGeminiFuncDecls.slice();
        if (mcpGemini.length > 0 && mcpGemini[0].functionDeclarations) {
            mergedGeminiDecls = mergedGeminiDecls.concat(mcpGemini[0].functionDeclarations);
        }

        // Built-in OpenAI declarations
        const builtinOpenaiDecls = [
            { "name": "switch_to_search_mode", "description": "Search the web" },
            { "name": "get_shell_config", "description": "Get the desktop shell config file contents" },
            { "name": "set_shell_config", "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
              "parameters": { "type": "object", "properties": { "key": { "type": "string", "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting." }, "value": { "type": "string", "description": "The value to set, e.g. `true`" } }, "required": ["key", "value"] } },
            { "name": "run_shell_command", "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
              "parameters": { "type": "object", "properties": { "command": { "type": "string", "description": "The bash command to run" } }, "required": ["command"] } },
            { "name": "hypr_config_read", "description": "Read Quickshell or Hyprland configuration via HyprMCP. Returns current config state.",
              "parameters": { "type": "object", "properties": { "namespace": { "type": "string", "description": "Dot-separated config namespace to read. Empty for all." } } } },
            { "name": "hypr_config_set", "description": "Set a Quickshell config value via HyprMCP with read-back verification.",
              "parameters": { "type": "object", "properties": { "key": { "type": "string", "description": "Config key to set" }, "value": { "type": "string", "description": "Value to set" } }, "required": ["key", "value"] } },
            { "name": "hypr_set_keyword", "description": "Set a Hyprland runtime keyword via HyprMCP with read-back verification.",
              "parameters": { "type": "object", "properties": { "keyword": { "type": "string", "description": "Hyprland keyword" }, "value": { "type": "string", "description": "Value to set" } }, "required": ["keyword", "value"] } },
        ];

        // Built-in Mistral declarations
        const builtinMistralDecls = [
            { "type": "function", "function": { "name": "get_shell_config", "description": "Get the desktop shell config file contents", "parameters": {} } },
            { "type": "function", "function": { "name": "set_shell_config", "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.", "parameters": { "type": "object", "properties": { "key": { "type": "string", "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting." }, "value": { "type": "string", "description": "The value to set, e.g. `true`" } }, "required": ["key", "value"] } } },
            { "type": "function", "function": { "name": "run_shell_command", "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.", "parameters": { "type": "object", "properties": { "command": { "type": "string", "description": "The bash command to run" } }, "required": ["command"] } } },
            { "type": "function", "function": { "name": "hypr_config_read", "description": "Read Quickshell or Hyprland configuration via HyprMCP.", "parameters": { "type": "object", "properties": { "namespace": { "type": "string", "description": "Config namespace to read" } } } } },
            { "type": "function", "function": { "name": "hypr_config_set", "description": "Set a Quickshell config value via HyprMCP with verification.", "parameters": { "type": "object", "properties": { "key": { "type": "string", "description": "Config key" }, "value": { "type": "string", "description": "Value to set" } }, "required": ["key", "value"] } } },
            { "type": "function", "function": { "name": "hypr_set_keyword", "description": "Set a Hyprland runtime keyword via HyprMCP with verification.", "parameters": { "type": "object", "properties": { "keyword": { "type": "string", "description": "Hyprland keyword" }, "value": { "type": "string", "description": "Value to set" } }, "required": ["keyword", "value"] } } },
        ];

        root.tools = {
            "gemini": {
                "functions": [{"functionDeclarations": mergedGeminiDecls}],
                "search": [{"google_search": {}}],
                "none": []
            },
            "openai": {
                "functions": builtinOpenaiDecls.concat(mcpOpenai),
                "search": [],
                "none": []
            },
            "mistral": {
                "functions": builtinMistralDecls.concat(mcpMistral),
                "search": [],
                "none": []
            }
        };
    }

    // Model properties:
    // - name: Name of the model
    // - icon: Icon name of the model
    // - description: Description of the model
    // - endpoint: Endpoint of the model
    // - model: Model name of the model
    // - requires_key: Whether the model requires an API key
    // - key_id: The identifier of the API key. Use the same identifier for models that can be accessed with the same key.
    // - key_get_link: Link to get an API key
    // - key_get_description: Description of pricing and how to get an API key
    // - api_format: The API format of the model. Can be "openai" or "gemini". Default is "openai".
    // - extraParams: Extra parameters to be passed to the model. This is a JSON object.
    property var models: {
        "gemini-2.0-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 2.0 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nFast, can perform searches for up-to-date information"),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:streamGenerateContent",
            "model": "gemini-2.0-flash",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
            "context_length": 1048576,
        }),
        "gemini-2.5-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 2.5 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nNewer model that's slower than its predecessor but should deliver higher quality answers"),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent",
            "model": "gemini-2.5-flash",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
            "context_length": 1048576,
        }),
        "gemini-2.5-flash-pro": aiModelComponent.createObject(this, {
            "name": "Gemini 2.5 Pro",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nGoogle's state-of-the-art multipurpose model that excels at coding and complex reasoning tasks."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:streamGenerateContent",
            "model": "gemini-2.5-pro",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
            "context_length": 1048576,
        }),
        "gemini-2.5-flash-lite": aiModelComponent.createObject(this, {
            "name": "Gemini 2.5 Flash-Lite",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nA Gemini 2.5 Flash model optimized for cost-efficiency and high throughput."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:streamGenerateContent",
            "model": "gemini-2.5-flash-lite",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
            "context_length": 1048576,
        }),
        "mistral-medium-3": aiModelComponent.createObject(this, {
            "name": "Mistral Medium 3",
            "icon": "mistral-symbolic",
            "description": Translation.tr("Online | %1's model | Delivers fast, responsive and well-formatted answers. Disadvantages: not very eager to do stuff; might make up unknown function calls").arg("Mistral"),
            "homepage": "https://mistral.ai/news/mistral-medium-3",
            "endpoint": "https://api.mistral.ai/v1/chat/completions",
            "model": "mistral-medium-2505",
            "requires_key": true,
            "key_id": "mistral",
            "key_get_link": "https://console.mistral.ai/api-keys",
            "key_get_description": Translation.tr("**Instructions**: Log into Mistral account, go to Keys on the sidebar, click Create new key"),
            "api_format": "mistral",
            "context_length": 131072,
        }),
        "openrouter-deepseek-r1": aiModelComponent.createObject(this, {
            "name": "DeepSeek R1",
            "icon": "deepseek-symbolic",
            "description": Translation.tr("Online via %1 | %2's model").arg("OpenRouter").arg("DeepSeek"),
            "homepage": "https://openrouter.ai/deepseek/deepseek-r1:free",
            "endpoint": "https://openrouter.ai/api/v1/chat/completions",
            "model": "deepseek/deepseek-r1:free",
            "requires_key": true,
            "key_id": "openrouter",
            "key_get_link": "https://openrouter.ai/settings/keys",
            "key_get_description": Translation.tr("**Pricing**: free. Data use policy varies depending on your OpenRouter account settings.\n\n**Instructions**: Log into OpenRouter account, go to Keys on the topright menu, click Create API Key"),
            "context_length": 65536,
        }),
    }
    property var modelList: Object.keys(root.models)
    property var currentModelId: Persistent.states?.ai?.model || modelList[0]
    readonly property string currentModelName: root.models[root.currentModelId]?.name ?? "No model"

    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(this),
        "gemini": geminiApiStrategy.createObject(this),
        "mistral": mistralApiStrategy.createObject(this),
    }
    property ApiStrategy currentApiStrategy: apiStrategies[models[currentModelId]?.api_format || "openai"]

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            (Config?.options.ai?.extraModels ?? []).forEach(model => {
                const safeModelName = root.safeModelName(model["model"]);
                root.addModel(safeModelName, model)
            });
        }
    }

    // Bridge ModelDiscoveryService discovered models into Ai's model registry
    Connections {
        target: ModelDiscoveryService
        function onDiscoveredModelsChanged() {
            const discovered = ModelDiscoveryService.discoveredModels;
            const providers = Object.keys(discovered);
            for (let i = 0; i < providers.length; i++) {
                const providerModels = discovered[providers[i]];
                for (let j = 0; j < providerModels.length; j++) {
                    const m = providerModels[j];
                    const safeId = root.safeModelName(m.model);
                    if (!root.models[safeId]) {
                        root.addModel(safeId, m);
                    }
                }
            }
            // Refresh modelList to include newly discovered models
            root.modelList = Object.keys(root.models);

            // If the persisted model is now available, switch to it
            const persistedModel = Persistent.states?.ai?.model;
            if (persistedModel && root.models[persistedModel] && root.currentModelId !== persistedModel) {
                root.setModel(persistedModel, false, false);
            }
        }
    }

    // Rebuild tool declarations when MCP tool registry changes
    Connections {
        target: McpClient
        function onToolsChanged() {
            root._rebuildTools();
        }
    }

    Component.onCompleted: {
        setModel(currentModelId, false, false); // Do necessary setup for model
        McpClient.initialize();
        // Restore session state on startup
        root.loadSessionsIndex();
        root.ensureFreeDictationSession();
        const persistedSession = Persistent.states?.ai?.activeSession;
        if (persistedSession && persistedSession.length > 0) {
            try {
                const persistedPath = Directories.aiChats + "/" + persistedSession + ".json";
                sessionReader.path = persistedPath;
                sessionReader.reload();
                const content = sessionReader.text();
                // Sync chatSaveFile so saves target the correct file
                chatSaveFile.chatName = persistedSession;
                if (content && content.trim().length > 0) {
                    const saveData = JSON.parse(content);
                    root.clearMessages();
                    const newMessageByID = ({});
                    for (let i = 0; i < saveData.length; i++) {
                        const message = saveData[i];
                        newMessageByID[i] = root.aiMessageComponent.createObject(root, {
                            "role": message.role,
                            "rawContent": message.rawContent,
                            "content": message.rawContent,
                            "model": message.model ?? "",
                            "thinking": message.thinking ?? false,
                            "done": message.done ?? true,
                            "annotations": message.annotations ?? [],
                            "annotationSources": message.annotationSources ?? [],
                            "functionName": message.functionName ?? "",
                            "functionCall": message.functionCall ?? null,
                            "functionResponse": message.functionResponse ?? "",
                            "visibleToUser": message.visibleToUser ?? true,
                        });
                    }
                    // Assign messageByID first, then messageIDs, so that when
                    // contextTokens and the message list view re-evaluate on
                    // messageIDsChanged, all message objects are already present.
                    root.messageByID = newMessageByID;
                    root.messageIDs = saveData.map((_, i) => i);
                    root.activeSessionName = persistedSession;
                } else {
                    // File empty or unreadable, create new default session
                    root.newSession();
                }
            } catch (e) {
                console.log("[AI] Startup: Could not load persisted session, trying fallback:", e);
                // Fallback: try the most recently modified session
                const sessions = root.sessionsIndex.sessions || [];
                if (sessions.length > 0) {
                    var sorted = [];
                    for (var si = 0; si < sessions.length; si++) {
                        sorted.push(sessions[si]);
                    }
                    sorted.sort((a, b) => (b.lastModified || 0) - (a.lastModified || 0));
                    var loaded = false;
                    for (var fi = 0; fi < sorted.length; fi++) {
                        try {
                            const fallbackPath = Directories.aiChats + "/" + sorted[fi].name + ".json";
                            sessionReader.path = fallbackPath;
                            sessionReader.reload();
                            const fallbackContent = sessionReader.text();
                            chatSaveFile.chatName = sorted[fi].name;
                            if (fallbackContent && fallbackContent.trim().length > 0) {
                                const fallbackData = JSON.parse(fallbackContent);
                                if (!Array.isArray(fallbackData)) continue;
                                root.clearMessages();
                                const fallbackMessageByID = ({});
                                for (var fj = 0; fj < fallbackData.length; fj++) {
                                    var fMsg = fallbackData[fj];
                                    fallbackMessageByID[fj] = root.aiMessageComponent.createObject(root, {
                                        "role": fMsg.role,
                                        "rawContent": fMsg.rawContent,
                                        "content": fMsg.rawContent,
                                        "model": fMsg.model ?? "",
                                        "thinking": fMsg.thinking ?? false,
                                        "done": fMsg.done ?? true,
                                        "annotations": fMsg.annotations ?? [],
                                        "annotationSources": fMsg.annotationSources ?? [],
                                        "functionName": fMsg.functionName ?? "",
                                        "functionCall": fMsg.functionCall ?? null,
                                        "functionResponse": fMsg.functionResponse ?? "",
                                        "visibleToUser": fMsg.visibleToUser ?? true,
                                    });
                                }
                                root.messageByID = fallbackMessageByID;
                                root.messageIDs = fallbackData.map((_, k) => k);
                                root.activeSessionName = sorted[fi].name;
                                Persistent.states.ai.activeSession = sorted[fi].name;
                                loaded = true;
                                break;
                            }
                        } catch (inner) {
                            continue; // Try next session
                        }
                    }
                    if (!loaded) {
                        root.newSession();
                    }
                } else {
                    // No sessions exist — create default
                    root.newSession();
                }
            }
        } else {
            // No persisted session, create a new default
            root.newSession();
        }
        // Initial tool declarations build (includes any early MCP tools)
        root._rebuildTools();
    }

    function guessModelLogo(model) {
        if (model.includes("llama")) return "ollama-symbolic";
        if (model.includes("gemma")) return "google-gemini-symbolic";
        if (model.includes("deepseek")) return "deepseek-symbolic";
        if (/^phi\d*:/i.test(model)) return "microsoft-symbolic";
        return "ollama-symbolic";
    }

    function guessModelName(model) {
        const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
        let words = replaced.split(' ');
        words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`)
        words = words.map((word) => {
            return (word.charAt(0).toUpperCase() + word.slice(1))
        });
        if (words[words.length - 1] === "Latest") words.pop();
        else words[words.length - 1] = `(${words[words.length - 1]})`; // Surround the last word with square brackets
        const result = words.join(' ');
        return result;
    }

    function addModel(modelName, data) {
        root.models[modelName] = aiModelComponent.createObject(this, data);
    }

    Process {
        id: getOllamaModels
        running: true
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-installed-ollama-models.sh`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    const dataJson = JSON.parse(data);
                    const modelNames = dataJson.map(entry => typeof entry === "string" ? entry : entry.name);
                    root.modelList = [...root.modelList, ...modelNames];
                    dataJson.forEach(entry => {
                        const model = typeof entry === "string" ? entry : entry.name;
                        const contextLength = (typeof entry === "object" && entry.context_length) ? entry.context_length : 0;
                        const safeModelName = root.safeModelName(model);
                        const modelData = {
                            "name": guessModelName(model),
                            "icon": guessModelLogo(model),
                            "description": Translation.tr("Local Ollama model | %1").arg(model),
                            "homepage": `https://ollama.com/library/${model}`,
                            "endpoint": "http://localhost:11434/v1/chat/completions",
                            "model": model,
                            "requires_key": false,
                        };
                        if (contextLength > 0) {
                            modelData.context_length = contextLength;
                        }
                        root.addModel(safeModelName, modelData);
                    });

                    root.modelList = Object.keys(root.models);

                } catch (e) {
                    console.log("Could not fetch Ollama models:", e);
                }
            }
        }
    }

    Process {
        id: getDefaultPrompts
        running: true
        command: ["ls", "-1", Directories.defaultAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.defaultPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.defaultAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getUserPrompts
        running: true
        command: ["ls", "-1", Directories.userAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.userPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.userAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getSavedChats
        running: true
        command: ["ls", "-1", Directories.aiChats]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.savedChats = text.split("\n")
                    .filter(fileName => fileName.endsWith(".json"))
                    .map(fileName => `${Directories.aiChats}/${fileName}`)
            }
        }
    }

    FileView {
        id: promptLoader
        watchChanges: false;
        onLoadedChanged: {
            if (!promptLoader.loaded) return;
            Config.options.ai.systemPrompt = promptLoader.text();
            root.addMessage(Translation.tr("Loaded the following system prompt\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
        }
    }

    function printPrompt() {
        root.addMessage(Translation.tr("The current system prompt is\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
    }

    function loadPrompt(filePath) {
        promptLoader.path = "" // Unload
        promptLoader.path = filePath; // Load
        promptLoader.reload();
    }

    function addMessage(message, role) {
        if (message.length === 0) return;
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": role,
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
        });
        const id = idForMessage(aiMessage);
        root.messageByID[id] = aiMessage;
        root.messageIDs = [...root.messageIDs, id];
    }

    function removeMessage(indexOrId) {
        // Accept either a numeric index or a message ID string
        var idx;
        if (typeof indexOrId === "string") {
            idx = root.messageIDs.indexOf(indexOrId);
        } else {
            idx = indexOrId;
        }
        if (idx < 0 || idx >= messageIDs.length) return;
        const id = root.messageIDs[idx];
        root.messageIDs.splice(idx, 1);
        root.messageIDs = [...root.messageIDs];
        delete root.messageByID[id];
    }

    /**
     * Retry from a specific assistant message — removes it and re-sends the request.
     */
    function retryFromMessage(messageId) {
        const idx = root.messageIDs.indexOf(messageId);
        if (idx < 0) return;
        // Remove this message and any subsequent messages (tool results, etc.)
        const toRemove = root.messageIDs.slice(idx);
        for (const id of toRemove) {
            delete root.messageByID[id];
        }
        root.messageIDs = root.messageIDs.slice(0, idx);
        // Re-send the request
        root._emptyResponseRetries = 0;
        root._emptyCommandRetries = 0;
        requester.makeRequest();
    }

    function addApiKeyAdvice(model) {
        root.addMessage(
            Translation.tr('To set an API key, pass it with the %4 command\n\nTo view the key, pass "get" with the command<br/>\n\n### For %1:\n\n**Link**: %2\n\n%3')
                .arg(model.name).arg(model.key_get_link).arg(model.key_get_description ?? Translation.tr("<i>No further instruction provided</i>")).arg("/key"), 
            Ai.interfaceRole
        );
    }

    function getModel() {
        return models[currentModelId];
    }

    function setModel(modelId, feedback = true, setPersistentState = true) {
        if (!modelId) modelId = ""
        // Case-insensitive lookup: find the actual key in modelList
        const matchedId = modelList.find(m => m.toLowerCase() === modelId.toLowerCase()) || "";
        if (matchedId) {
            const model = models[matchedId]
            // Fetch API keys if needed
            if (model?.requires_key) KeyringStorage.fetchKeyringData();
            // See if policy prevents online models
            if (Config.options.policies.ai === 2 && !model.endpoint.includes("localhost")) {
                root.addMessage(
                    Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                    root.interfaceRole
                );
                return;
            }
            root.currentModelId = matchedId;
            if (setPersistentState) Persistent.states.ai.model = matchedId;
            if (feedback) root.addMessage(Translation.tr("Model set to %1").arg(model.name), root.interfaceRole);
            if (model.requires_key) {
                // If key not there show advice
                if (root.apiKeysLoaded && (!root.apiKeys[model.key_id] || root.apiKeys[model.key_id].length === 0)) {
                    root.addApiKeyAdvice(model)
                }
            }
        } else {
            // Show top fuzzy matches (max 5)
            if (feedback) {
                const fuzzyResults = CF.Fuzzy.go(modelId, modelList.map(m => ({ name: CF.Fuzzy.prepare(m), obj: m })), { key: "name", limit: 5 });
                let msg = Translation.tr("Model not found: `%1`").arg(modelId);
                if (fuzzyResults.length > 0) {
                    msg += "\n\n" + Translation.tr("Did you mean:") + "\n" + fuzzyResults.map(r => "- `" + r.target + "`").join("\n");
                }
                msg += "\n\n" + Translation.tr("Use `/model` to see suggestions, or check the Providers tab.");
                root.addMessage(msg, Ai.interfaceRole);
            }
        }
    }

    /**
     * Switches to a model suggested by AI_Doctor (e.g. one with a larger context window).
     * Calls setModel which updates Persistent state, triggering QML bindings to
     * recalculate contextLimit → contextUsageRatio → contextFull, unblocking message sending.
     * @param modelId - the model ID to switch to
     */
    function switchToModel(modelId) {
        const model = models[modelId];
        if (!model) {
            root.addMessage(Translation.tr("Cannot switch: model '%1' not found").arg(modelId), root.interfaceRole);
            return;
        }
        root.setModel(modelId, true, true);
    }

    function setTool(tool) {
        if (!root.tools[models[currentModelId]?.api_format] || !(tool in root.tools[models[currentModelId]?.api_format])) {
            root.addMessage(Translation.tr("Invalid tool. Supported tools:\n- %1").arg(root.availableTools.join("\n- ")), root.interfaceRole);
            return false;
        }
        Config.options.ai.tool = tool;
        return true;
    }
    
    function getTemperature() {
        return root.temperature;
    }

    function setTemperature(value) {
        if (value == NaN || value < 0 || value > 2) {
            root.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole);
            return;
        }
        Persistent.states.ai.temperature = value;
        root.temperature = value;
        root.addMessage(Translation.tr("Temperature set to %1").arg(value), Ai.interfaceRole);
    }

    function setApiKey(key) {
        const model = models[currentModelId];
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
            return;
        }
        if (!key || key.length === 0) {
            const model = models[currentModelId];
            root.addApiKeyAdvice(model)
            return;
        }
        KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim());
        root.addMessage(Translation.tr("API key set for %1").arg(model.name), Ai.interfaceRole);
    }

    function printApiKey() {
        const model = models[currentModelId];
        if (model.requires_key) {
            const key = root.apiKeys[model.key_id];
            if (key) {
                root.addMessage(Translation.tr("API key:\n\n```txt\n%1\n```").arg(key), Ai.interfaceRole);
            } else {
                root.addMessage(Translation.tr("No API key set for %1").arg(model.name), Ai.interfaceRole);
            }
        } else {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
        }
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), Ai.interfaceRole);
    }

    function clearMessages() {
        root.messageIDs = [];
        root.messageByID = ({});
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
    }

    // Temp file for request payloads — avoids shell ARG_MAX with large base64 images
    FileView {
        id: requestPayloadFile
        path: "/tmp/ii-ai-request-payload.json"
        preload: false
        blockWrites: true
    }

    Process {
        id: requester
        property list<string> baseCommand: ["bash", "-c"]
        property AiMessageData message
        property string messageId: ""
        property ApiStrategy currentStrategy

        function markDone() {
            requester.message.done = true;
            if (root.postResponseHook) {
                root.postResponseHook();
                root.postResponseHook = null; // Reset hook after use
            }
            root.saveCurrentSession();
            root.saveChat("lastSession")
        }

        function makeRequest() {
            const model = models[currentModelId];
            requester.currentStrategy = root.currentApiStrategy;
            requester.currentStrategy.reset(); // Reset strategy state

            /* Put API key in environment variable */
            if (model.requires_key) requester.environment[`${root.apiKeyEnvVarName}`] = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : ""

            /* Build endpoint, request data */
            const endpoint = root.currentApiStrategy.buildEndpoint(model);
            const messageArray = root.messageIDs.map(id => root.messageByID[id]);
            const filteredMessageArray = messageArray.filter(message => message.role !== Ai.interfaceRole);
            const tuning = root.getModelTuning();
            // Append fresh timestamp to system prompt so the model always has accurate current time
            const now = new Date();
            const freshDatetime = Qt.locale().toString(now, "hh:mm:ss, dddd dd MMMM yyyy");
            let liveSystemPrompt = root.systemPrompt + `\n\n[Current local time at moment of request: ${freshDatetime}]`;

            // Append tool usage instructions when function calling is active
            let activeTools = root.tools[model.api_format]?.[root.currentTool] ?? [];

            // If tool calls have been failing, temporarily suppress tools to force a text response
            if (root._emptyCommandRetries < 0) {
                activeTools = [];
                root._emptyCommandRetries = 0;
            }

            if (activeTools.length > 0) {
                liveSystemPrompt += `\n\n## Tool Usage\n- You have access to tools. Use them proactively to answer questions — don't guess when you can look it up.\n- You may call multiple tools in sequence to gather comprehensive information before responding. After receiving a tool result, you can call another tool if more info is needed.\n- Prefer gathering real data over speculating. If the user asks about their system, network, or environment, run commands to get actual information.\n- When a single command isn't sufficient, make additional tool calls until you have enough data to give a complete answer.`;
            }

            const data = root.currentApiStrategy.buildRequestData(model, filteredMessageArray, liveSystemPrompt, tuning.temperature, activeTools, tuning);
            // console.log("[Ai] Request data: ", JSON.stringify(data, null, 2));

            let requestHeaders = {
                "Content-Type": "application/json",
            }
            
            /* Create local message object */
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
            });
            const id = idForMessage(requester.message);
            requester.messageId = id;
            root.messageByID[id] = requester.message;
            root.messageIDs = [...root.messageIDs, id];

            /* Build header string for curl */
            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            // console.log("Request headers: ", JSON.stringify(requestHeaders));
            // console.log("Header string: ", headerString);

            /* Get authorization header from strategy */
            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);

            /* Write JSON payload to temp file via FileView to avoid ARG_MAX limits.
             * Large base64 image payloads can exceed the 2MB shell argument limit. */
            const payloadJson = JSON.stringify(data);
            requestPayloadFile.setText(payloadJson);
            const payloadPath = requestPayloadFile.path;

            /* Build curl command that reads POST body from file (-d @file) */
            const requestCommandString = `curl --no-buffer "${endpoint}"`
                + ` ${headerString}`
                + (authHeader ? ` ${authHeader}` : "")
                + ` -d @'${payloadPath}'`
            
            /* Send the request */
            requester.command = baseCommand.concat([requestCommandString]);
            requester.running = true
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (requester.message.thinking) requester.message.thinking = false;
                // console.log("[Ai] Raw response line: ", data);

                // Handle response line
                try {
                    const result = requester.currentStrategy.parseResponseLine(data, requester.message);
                    // console.log("[Ai] Parsed response result: ", JSON.stringify(result, null, 2));
                    
                    if (result.functionCall) {
                        requester.message.functionCall = result.functionCall;
                        root.handleFunctionCall(result.functionCall.name, result.functionCall.args, requester.message);
                    }
                    if (result.tokenUsage) {
                        root.tokenCount.input = result.tokenUsage.input;
                        root.tokenCount.output = result.tokenUsage.output;
                        root.tokenCount.total = result.tokenUsage.total;
                    }
                    if (result.finished) {
                        requester.markDone();
                    }
                    
                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    requester.message.rawContent += data;
                    requester.message.content += data;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            const result = requester.currentStrategy.onRequestFinished(requester.message);
            
            // Check if the message ended up empty or errored
            const msgContent = (requester.message.rawContent || "").trim();
            // Strip think blocks to check if there's any visible content
            const visibleContent = msgContent.replace(/<think>[\s\S]*?<\/think>/g, "")
                                             .replace(/<think>[\s\S]*$/, "")  // unclosed think block
                                             .trim();
            const isEmpty = msgContent.length === 0 || visibleContent.length === 0;
            const isError = msgContent.includes('"error"') && !msgContent.includes("</think>");

            if (!isEmpty && !isError) {
                root._emptyResponseRetries = 0;
            }

            if (isEmpty || isError) {
                // Remove the broken/empty assistant message BEFORE saving
                const msgId = requester.messageId;
                const idx = root.messageIDs.indexOf(msgId);
                if (idx !== -1) {
                    root.messageIDs.splice(idx, 1);
                    root.messageIDs = [...root.messageIDs];
                    delete root.messageByID[msgId];
                }

                // Auto-retry once if model returned only thinking (likely a failed tool call attempt)
                root._emptyResponseRetries = (root._emptyResponseRetries || 0) + 1;
                if (root._emptyResponseRetries <= 2 && !isError && msgContent.length > 0) {
                    requester.makeRequest();
                    return;
                }
                root._emptyResponseRetries = 0;

                // Show a useful error
                if (msgContent.length === 0) {
                    root.addMessage(Translation.tr("No response from model. Check API key or network connection."), root.interfaceRole);
                } else if (isError) {
                    const errorText = msgContent.replace(/[\n\r]+/g, " ").substring(0, 300);
                    root.addMessage(Translation.tr("API error: %1").arg(errorText), root.interfaceRole);
                } else {
                    root.addMessage(Translation.tr("Model returned only internal reasoning with no visible response. Try again."), root.interfaceRole);
                }
                // Handle API key advice
                if (msgContent.includes("API key not valid")) {
                    root.addApiKeyAdvice(models[requester.message.model]);
                }
            } else {
                // Valid response — mark done and save
                if (result.finished) {
                    requester.markDone();
                } else if (!requester.message.done) {
                    requester.markDone();
                }
                // Handle API key advice even for non-empty responses
                if (msgContent.includes("API key not valid")) {
                    root.addApiKeyAdvice(models[requester.message.model]);
                }
            }
        }
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        if (root.switching) return;
        if (root.contextFull) {
            root.addMessage(
                Translation.tr("Context window is full. Please compact the conversation or switch to a model with a larger context window."),
                root.interfaceRole
            );
            return;
        }
        root.addMessage(message, "user");
        requester.makeRequest();
    }

    function createFunctionOutputMessage(name, output, includeOutputInChat = true) {
        return aiMessageComponent.createObject(root, {
            "role": "user",
            "content": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "rawContent": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "functionName": name,
            "functionResponse": output,
            "thinking": false,
            "done": true,
            // "visibleToUser": false,
        });
    }

    function addFunctionOutputMessage(name, output) {
        const aiMessage = createFunctionOutputMessage(name, output);
        const id = idForMessage(aiMessage);
        root.messageByID[id] = aiMessage;
        root.messageIDs = [...root.messageIDs, id];
    }

    function rejectCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"
        addFunctionOutputMessage(message.functionName, Translation.tr("Command rejected by user"))
    }

    function approveCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"

        const responseMessage = createFunctionOutputMessage(message.functionName, "", false);
        const id = idForMessage(responseMessage);
        root.messageByID[id] = responseMessage;
        root.messageIDs = [...root.messageIDs, id];

        commandExecutionProc.message = responseMessage;
        commandExecutionProc.baseMessageContent = responseMessage.content;
        commandExecutionProc.shellCommand = message.functionCall.args.command;
        commandExecutionProc.running = true; // Start the command execution
    }

    Process {
        id: commandExecutionProc
        property string shellCommand: ""
        property AiMessageData message
        property string baseMessageContent: ""
        command: ["bash", "-c", shellCommand]
        stdout: SplitParser {
            onRead: (output) => {
                commandExecutionProc.message.functionResponse += output + "\n\n";
                const updatedContent = commandExecutionProc.baseMessageContent + `\n\n<think>\n<tt>${commandExecutionProc.message.functionResponse}</tt>\n</think>`;
                commandExecutionProc.message.rawContent = updatedContent;
                commandExecutionProc.message.content = updatedContent;
            }
        }
        onExited: (exitCode, exitStatus) => {
            commandExecutionProc.message.functionResponse += `[[ Command exited with code ${exitCode} (${exitStatus}) ]]\n`;
            requester.makeRequest(); // Continue
        }
    }


    function handleFunctionCall(name, args: var, message: AiMessageData) {
        if (name === "switch_to_search_mode") {
            const modelId = root.currentModelId;
            root.currentTool = "search"
            root.postResponseHook = () => { root.currentTool = "functions" }
            addFunctionOutputMessage(name, Translation.tr("Switched to search mode. Continue with the user's request."))
            requester.makeRequest();
        } else if (name === "get_shell_config") {
            const configJson = CF.ObjectUtils.toPlainObject(Config.options)
            addFunctionOutputMessage(name, JSON.stringify(configJson));
            requester.makeRequest();
        } else if (name === "set_shell_config") {
            if (!args.key || !args.value) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `key` and `value`."));
                return;
            }
            const key = args.key;
            const value = args.value;
            Config.setNestedValue(key, value);
        } else if (name === "run_shell_command") {
            if (!args.command || args.command.trim().length === 0) {
                root._emptyCommandRetries = (root._emptyCommandRetries || 0) + 1;
                if (root._emptyCommandRetries > 2) {
                    addFunctionOutputMessage(name, Translation.tr("Tool calling failed repeatedly (empty command). Stop calling tools and respond to the user with what you have gathered so far."));
                    root._emptyCommandRetries = -1; // Signal to suppress tools on next request
                    requester.makeRequest();
                    return;
                }
                addFunctionOutputMessage(name, Translation.tr("Error: your tool call had empty arguments. Provide the command as: {\"command\": \"your_bash_command_here\"}"));
                requester.makeRequest();
                return;
            }
            root._emptyCommandRetries = 0;
            const contentToAppend = `\n\n**Command execution request**\n\n\`\`\`command\n${args.command}\n\`\`\``;
            message.rawContent += contentToAppend;
            message.content += contentToAppend;
            message.functionName = name;
            message.functionCall = { name: name, args: args };
            if (root.yoloMode) {
                message.functionPending = true;
                root.approveCommand(message);
            } else {
                message.functionPending = true;
            }
        } else if (name === "hypr_config_read") {
            // Route through McpClient (ii-desktop MCP path with HTTP/stdio hybrid)
            root.executeMcpTool("mcp_ii_desktop_config_read", { namespace: args.namespace || "" }, "hypr_config_read");
        } else if (name === "hypr_config_set") {
            if (!args.key || !args.value) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `key` and `value`."));
                return;
            }
            root.executeMcpTool("mcp_ii_desktop_config_set", { key: args.key, value: args.value }, "hypr_config_set");
        } else if (name === "hypr_set_keyword") {
            if (!args.keyword || !args.value) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `keyword` and `value`."));
                return;
            }
            root.executeMcpTool("mcp_ii_desktop_set_keyword", { keyword: args.keyword, value: args.value }, "hypr_set_keyword");
        }
        else if (McpClient.toolRegistry[name]) {
            handleMcpToolCall(name, args, message);
        }
        else {
            root.addMessage(Translation.tr("Unknown function call: %1").arg(name), "assistant");
        }
    }

    /**
     * Handles an MCP tool call — checks auto-approve, otherwise prompts user.
     */
    function handleMcpToolCall(name, args, message) {
        if (McpClient.isToolAutoApproved(name)) {
            executeMcpTool(name, args);
        } else {
            // Require user approval — set pending state on the message
            message.functionPending = true;
            message.pendingMcpTool = name;
            message.pendingMcpArgs = args;
        }
    }

    /**
     * Dispatches an MCP tool call to McpClient and handles the response.
     * @param name — the MCP tool name to call (prefixed, e.g., "mcp_ii_desktop_config_read")
     * @param args — the arguments to pass to the tool
     * @param outputName — optional name to use in the function output message (defaults to name)
     */
    function executeMcpTool(name, args, outputName) {
        const displayName = outputName || name;
        const promise = McpClient.callTool(name, args);
        promise.then(result => {
            root.addFunctionOutputMessage(displayName, result);
            requester.makeRequest();
        });
        promise.catch(err => {
            root.addFunctionOutputMessage(displayName, Translation.tr("MCP tool error: %1").arg(String(err)));
            requester.makeRequest();
        });
    }

    /**
     * Approves a pending MCP tool call (called from UI).
     */
    function approveMcpTool(message) {
        message.functionPending = false;
        executeMcpTool(message.pendingMcpTool, message.pendingMcpArgs);
    }

    /**
     * Rejects a pending MCP tool call (called from UI).
     * Delivers a rejection notice as the function response so the LLM
     * knows the tool was not executed and can continue the conversation.
     */
    function rejectMcpTool(message) {
        const toolName = message.pendingMcpTool;
        message.functionPending = false;
        root.addFunctionOutputMessage(toolName,
            Translation.tr("Tool execution rejected by user"));
        requester.makeRequest();
    }

    function chatToJson() {
        return root.messageIDs.map(id => {
            const message = root.messageByID[id]
            if (!message) return null
            var obj = {
                "role": message.role,
                "rawContent": message.rawContent,
                "model": message.model,
                "thinking": false,
                "done": true,
                "annotations": message.annotations,
                "annotationSources": message.annotationSources,
                "functionName": message.functionName,
                "functionCall": message.functionCall,
                "functionResponse": message.functionResponse,
                "visibleToUser": message.visibleToUser,
            }
            // Only include attachments if non-empty (keep JSON lean)
            // NOTE: We do NOT save base64 images — they are re-encoded from attachment
            // files at request time. This keeps chat files small.
            if (message.attachments && message.attachments.length > 0) {
                obj.attachments = message.attachments
            }
            return obj
        }).filter(m => m !== null)
    }

    FileView {
        id: sessionsIndexFile
        path: `${Directories.aiChats}/sessions-index.json`
        blockLoading: true
    }

    Process {
        id: scanSessionFiles
        running: false
        command: ["ls", "-1", Directories.aiChats]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) {
                    root.sessionsIndex = { "sessions": [] };
                    root.saveSessionsIndex();
                    return;
                }
                const files = text.split("\n")
                    .filter(fileName => fileName.endsWith(".json") && fileName !== "sessions-index.json");
                const now = Math.floor(Date.now() / 1000);
                const sessions = files.map(fileName => {
                    const name = fileName.replace(/\.json$/, "");
                    return {
                        "name": name,
                        "createdAt": now,
                        "lastModified": now,
                        "archived": false,
                        "group": "",
                        "subject": "",
                    };
                });
                root.sessionsIndex = { "sessions": sessions };
                root.saveSessionsIndex();
            }
        }
    }

    function loadSessionsIndex() {
        try {
            sessionsIndexFile.reload();
            const content = sessionsIndexFile.text();
            if (!content || content.trim().length === 0) {
                // File is empty or missing, rebuild
                scanSessionFiles.running = true;
                return;
            }
            const parsed = JSON.parse(content);
            if (parsed && Array.isArray(parsed.sessions)) {
                // Migrate existing entries: add missing fields for backward compatibility
                for (var i = 0; i < parsed.sessions.length; i++) {
                    var s = parsed.sessions[i];
                    if (s.archived === undefined) s.archived = false;
                    if (s.group === undefined) s.group = "";
                    if (s.subject === undefined) s.subject = "";
                    // protected is optional — only set on special sessions like Free Dictation
                }
                root.sessionsIndex = parsed;
            } else {
                // Invalid structure, rebuild
                scanSessionFiles.running = true;
            }
        } catch (e) {
            console.log("[AI] Could not load sessions index, rebuilding:", e);
            scanSessionFiles.running = true;
        }
    }

    function saveSessionsIndex() {
        const content = JSON.stringify(root.sessionsIndex, null, 2);
        sessionsIndexFile.setText(content);
    }

    /**
     * Purges (clears all messages from) a session without removing it from the index.
     * Preserves the session entry with all metadata; only the messages are removed.
     * @param name The session name to purge
     */
    function purgeSession(name) {
        const trimmedName = (name || "").trim();
        if (trimmedName.length === 0) {
            root.addMessage(Translation.tr("Please specify a session name to purge"), root.interfaceRole);
            return;
        }

        // Verify session exists in index
        const sessions = root.sessionsIndex.sessions || [];
        const entry = sessions.find(s => s.name === trimmedName);
        if (!entry) {
            root.addMessage(
                Translation.tr("Session \"%1\" not found in sessions index").arg(trimmedName),
                root.interfaceRole
            );
            return;
        }

        // Write empty array to the session file
        chatSaveFile.chatName = trimmedName;
        chatSaveFile.setText(JSON.stringify([]));

        // Update lastModified timestamp in index
        entry.lastModified = Math.floor(Date.now() / 1000);
        root.sessionsIndex = { "sessions": sessions };
        root.saveSessionsIndex();

        // If purging the active session, clear in-memory messages
        if (trimmedName === root.activeSessionName) {
            root.clearMessages();
        }

        root.addMessage(
            Translation.tr("Purged all messages from session \"%1\"").arg(trimmedName),
            root.interfaceRole
        );
    }

    Process {
        id: deleteSessionFileProc
        running: false
        property string sessionFilePath: ""
        command: ["rm", "-f", sessionFilePath]
    }

    function deleteSession(name) {
        if (!name || name.trim().length === 0) {
            root.addMessage(Translation.tr("Please specify a session name to delete"), root.interfaceRole);
            return;
        }
        name = name.trim();
        if (name === root.activeSessionName) {
            // Switch to another session before deleting the active one
            const sessions = (root.sessionsIndex.sessions || []).filter(s => s.name !== name && !s.archived);
            if (sessions.length === 0) {
                // No other sessions — create a new one first
                root.newSession("");
            } else {
                root.switchSession(sessions[0].name);
            }
        }
        // Remove session JSON file from filesystem
        deleteSessionFileProc.sessionFilePath = `${Directories.aiChats}/${name}.json`;
        deleteSessionFileProc.running = true;
        // Remove entry from sessionsIndex and save
        const sessions = (root.sessionsIndex.sessions || []).filter(s => s.name !== name);
        root.sessionsIndex = { "sessions": sessions };
        root.saveSessionsIndex();
    }

    Process {
        id: renameSessionFileProc
        running: false
        property string oldPath: ""
        property string newPath: ""
        command: ["mv", "-f", oldPath, newPath]
    }

    /**
     * Renames a session (updates index, moves file, updates active name if needed).
     * Validates: non-empty, no path separators, no duplicates, not "Free Dictation".
     * @param oldName current session name
     * @param newName new session name
     */
    function renameSession(oldName, newName) {
        oldName = (oldName || "").trim();
        newName = (newName || "").trim();
        root.lastRenameError = "";

        // Validate: both names must be non-empty
        if (!oldName || !newName) {
            root.lastRenameError = Translation.tr("Session name cannot be empty");
            root.addMessage(root.lastRenameError, root.interfaceRole);
            return;
        }

        // Same name — no-op
        if (oldName === newName) return;

        // Validate: no path separator characters
        if (newName.indexOf("/") !== -1 || newName.indexOf("\\") !== -1) {
            root.lastRenameError = Translation.tr("Invalid name: must not contain '/' or '\\\\' characters");
            root.addMessage(root.lastRenameError, root.interfaceRole);
            return;
        }

        // Validate: cannot rename TO "Free Dictation" (protected name)
        if (newName === "Free Dictation") {
            root.lastRenameError = Translation.tr("Cannot rename to \"Free Dictation\" — that name is reserved");
            root.addMessage(root.lastRenameError, root.interfaceRole);
            return;
        }

        // Validate: check oldName exists and is not protected
        const sessions = root.sessionsIndex.sessions || [];
        const entry = sessions.find(s => s.name === oldName);
        if (!entry) {
            root.lastRenameError = Translation.tr("Session \"%1\" not found").arg(oldName);
            root.addMessage(root.lastRenameError, root.interfaceRole);
            return;
        }
        if (entry.protected) {
            root.lastRenameError = Translation.tr("Cannot rename the protected session \"%1\"").arg(oldName);
            root.addMessage(root.lastRenameError, root.interfaceRole);
            return;
        }

        // Validate: no duplicate
        const duplicate = sessions.find(s => s.name === newName);
        if (duplicate) {
            root.lastRenameError = Translation.tr("A session named \"%1\" already exists").arg(newName);
            root.addMessage(root.lastRenameError, root.interfaceRole);
            return;
        }

        // Update sessions index
        entry.name = newName;
        entry.lastModified = Math.floor(Date.now() / 1000);
        root.sessionsIndex = { "sessions": sessions };
        root.saveSessionsIndex();

        // Move the file on disk
        renameSessionFileProc.oldPath = `${Directories.aiChats}/${oldName}.json`;
        renameSessionFileProc.newPath = `${Directories.aiChats}/${newName}.json`;
        renameSessionFileProc.running = true;

        // If this was the active session, update active name and persist
        if (oldName === root.activeSessionName) {
            root.activeSessionName = newName;
            Persistent.states.ai.activeSession = newName;
        }

        root.addMessage(
            Translation.tr("Renamed session \"%1\" → \"%2\"").arg(oldName).arg(newName),
            root.interfaceRole
        );
    }

    /**
     * Archives a session (sets archived=true, removes from active list display).
     * @param name The session name to archive
     */
    function archiveSession(name) {
        const trimmedName = (name || "").trim();
        if (trimmedName.length === 0) return;

        const sessions = root.sessionsIndex.sessions || [];
        const entry = sessions.find(s => s.name === trimmedName);
        if (!entry) {
            root.addMessage(Translation.tr("Session \"%1\" not found").arg(trimmedName), root.interfaceRole);
            return;
        }

        entry.archived = true;
        entry.lastModified = Math.floor(Date.now() / 1000);
        root.sessionsIndex = { "sessions": sessions };
        root.saveSessionsIndex();
        root.addMessage(Translation.tr("Archived session \"%1\"").arg(trimmedName), root.interfaceRole);
    }

    /**
     * Unarchives a session (sets archived=false, restores to active list).
     * @param name The session name to unarchive
     */
    function unarchiveSession(name) {
        const trimmedName = (name || "").trim();
        if (trimmedName.length === 0) return;

        const sessions = root.sessionsIndex.sessions || [];
        const entry = sessions.find(s => s.name === trimmedName);
        if (!entry) {
            root.addMessage(Translation.tr("Session \"%1\" not found").arg(trimmedName), root.interfaceRole);
            return;
        }

        entry.archived = false;
        entry.lastModified = Math.floor(Date.now() / 1000);
        root.sessionsIndex = { "sessions": sessions };
        root.saveSessionsIndex();
        root.addMessage(Translation.tr("Unarchived session \"%1\"").arg(trimmedName), root.interfaceRole);
    }

    /**
     * Sets the group label for a session.
     * Validates: 1-64 chars, not whitespace-only.
     * @param name The session name
     * @param group The group label to assign
     */
    function setSessionGroup(name, group) {
        const trimmedName = (name || "").trim();
        if (trimmedName.length === 0) return;

        // Validate group: 1-64 chars, not whitespace-only
        if (!group || group.length === 0 || group.trim().length === 0) {
            root.addMessage(Translation.tr("Group label cannot be empty or whitespace-only"), root.interfaceRole);
            return;
        }
        if (group.length > 64) {
            root.addMessage(Translation.tr("Group label cannot exceed 64 characters"), root.interfaceRole);
            return;
        }

        const sessions = root.sessionsIndex.sessions || [];
        const entry = sessions.find(s => s.name === trimmedName);
        if (!entry) {
            root.addMessage(Translation.tr("Session \"%1\" not found").arg(trimmedName), root.interfaceRole);
            return;
        }

        entry.group = group;
        entry.lastModified = Math.floor(Date.now() / 1000);
        root.sessionsIndex = { "sessions": sessions };
        root.saveSessionsIndex();
    }

    /**
     * Sets the subject for a session.
     * Validates: 1-128 chars, not whitespace-only.
     * @param name The session name
     * @param subject The subject to assign
     */
    function setSessionSubject(name, subject) {
        const trimmedName = (name || "").trim();
        if (trimmedName.length === 0) return;

        // Validate subject: 1-128 chars, not whitespace-only
        if (!subject || subject.length === 0 || subject.trim().length === 0) {
            root.addMessage(Translation.tr("Subject cannot be empty or whitespace-only"), root.interfaceRole);
            return;
        }
        if (subject.length > 128) {
            root.addMessage(Translation.tr("Subject cannot exceed 128 characters"), root.interfaceRole);
            return;
        }

        const sessions = root.sessionsIndex.sessions || [];
        const entry = sessions.find(s => s.name === trimmedName);
        if (!entry) {
            root.addMessage(Translation.tr("Session \"%1\" not found").arg(trimmedName), root.interfaceRole);
            return;
        }

        entry.subject = subject;
        entry.lastModified = Math.floor(Date.now() / 1000);
        root.sessionsIndex = { "sessions": sessions };
        root.saveSessionsIndex();
    }

    FileView {
        id: chatSaveFile
        property string chatName: "chat"
        path: `${Directories.aiChats}/${chatName}.json`
        blockLoading: true
    }

    // Dedicated reader for session loading — path is set imperatively, never bound.
    // blockAllReads ensures text() always returns the NEW file content after a path change,
    // not stale data from the previously loaded file.
    FileView {
        id: sessionReader
        blockAllReads: true
    }

    /**
     * Saves chat to a JSON list of message objects.
     * @param chatName name of the chat
     */
    function saveChat(chatName) {
        chatSaveFile.chatName = chatName.trim()
        const saveContent = JSON.stringify(root.chatToJson())
        chatSaveFile.setText(saveContent)
        getSavedChats.running = true;
    }

    /**
     * Loads chat from a JSON list of message objects.
     * @param chatName name of the chat
     */
    function loadChat(chatName) {
        try {
            chatSaveFile.chatName = chatName.trim()
            chatSaveFile.reload()
            const saveContent = chatSaveFile.text()
            // console.log(saveContent)
            const saveData = JSON.parse(saveContent)
            root.clearMessages()
            // Populate messageByID before assigning messageIDs so that when
            // contextTokens and the message list view re-evaluate on
            // messageIDsChanged, all message objects are already present.
            const newMessageByID = ({});
            for (let i = 0; i < saveData.length; i++) {
                const message = saveData[i];
                newMessageByID[i] = root.aiMessageComponent.createObject(root, {
                    "role": message.role,
                    "rawContent": message.rawContent,
                    "content": message.rawContent,
                    "model": message.model,
                    "thinking": message.thinking,
                    "done": message.done,
                    "annotations": message.annotations,
                    "annotationSources": message.annotationSources,
                    "functionName": message.functionName,
                    "functionCall": message.functionCall,
                    "functionResponse": message.functionResponse,
                    "visibleToUser": message.visibleToUser,
                    "attachments": message.attachments || [],
                    "images": message.images || [],
                });
            }
            root.messageByID = newMessageByID;
            root.messageIDs = saveData.map((_, i) => i);
            // console.log(JSON.stringify(messageIDs))
        } catch (e) {
            console.log("[AI] Could not load chat: ", e);
        } finally {
            getSavedChats.running = true;
        }
    }

    // Compact chat process - sends summarization request
    Process {
        id: compactRequester
        property list<string> baseCommand: ["bash", "-c"]
        property AiMessageData compactMessage
        property ApiStrategy currentStrategy

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                try {
                    compactRequester.currentStrategy.parseResponseLine(data, compactRequester.compactMessage);
                } catch (e) {
                    // Fallback: accumulate raw data
                    compactRequester.compactMessage.rawContent += data;
                    compactRequester.compactMessage.content += data;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            // Let strategy finalize if needed
            compactRequester.currentStrategy.onRequestFinished(compactRequester.compactMessage);

            const summary = compactRequester.compactMessage.rawContent.trim();
            if (exitCode !== 0 || summary.length === 0) {
                // Failure: preserve original messages, show error
                root.addMessage(
                    Translation.tr("Failed to compact conversation. Your messages have been preserved."),
                    root.interfaceRole
                );
                root.compacting = false;
                return;
            }

            // Success: replace entire message list with a single system-role summary
            root.clearMessages();
            const aiMessage = root.aiMessageComponent.createObject(root, {
                "role": "system",
                "content": summary,
                "rawContent": summary,
                "thinking": false,
                "done": true,
            });
            const id = root.idForMessage(aiMessage);
            root.messageIDs = [id];
            root.messageByID[id] = aiMessage;

            // Save session and update state
            root.saveCurrentSession();
            root.compacting = false;
        }
    }

    // Keyword generation process - extracts keywords from conversation
    Process {
        id: keywordRequester
        property list<string> baseCommand: ["bash", "-c"]
        property string sessionName: ""
        property AiMessageData keywordMessage
        property ApiStrategy currentStrategy

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                try {
                    keywordRequester.currentStrategy.parseResponseLine(data, keywordRequester.keywordMessage);
                } catch (e) {
                    keywordRequester.keywordMessage.rawContent += data;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (keywordRequester.currentStrategy) {
                keywordRequester.currentStrategy.onRequestFinished(keywordRequester.keywordMessage);
            }
            var keywords = (keywordRequester.keywordMessage.rawContent || "").trim();
            if (exitCode === 0 && keywords.length > 0 && keywords.length <= 128) {
                root.setSessionSubject(keywordRequester.sessionName, keywords);
                console.log("[AI] Keywords generated for '" + keywordRequester.sessionName + "': " + keywords);
            }
        }
    }

    /**
     * Compacts the current conversation by sending it to the model for summarization.
     * On success, replaces the conversation with a single system-role summary message.
     * On failure, preserves original messages and shows an error.
     * @param focusInstruction Optional instruction to guide what to preserve in the summary
     */
    function compactChat(focusInstruction) {
        if (root.compacting) return; // Already compacting
        if (root.messageIDs.length === 0) {
            root.addMessage(Translation.tr("Nothing to compact — conversation is empty."), root.interfaceRole);
            return;
        }

        root.compacting = true;

        const model = models[currentModelId];
        const strategy = root.currentApiStrategy;
        compactRequester.currentStrategy = strategy;
        strategy.reset();

        // Create a temporary message object to accumulate the response
        compactRequester.compactMessage = root.aiMessageComponent.createObject(root, {
            "role": "assistant",
            "content": "",
            "rawContent": "",
            "thinking": false,
            "done": false,
        });

        // Build the summarization system prompt
        let summarizationPrompt = root.compactPromptTemplate;
        if (focusInstruction && focusInstruction.trim().length > 0) {
            summarizationPrompt += " " + focusInstruction.trim();
        }

        // Build conversation content as a single user message
        const conversationText = root.messageIDs.map(id => {
            const msg = root.messageByID[id];
            if (!msg) return "";
            return `[${msg.role}]: ${msg.rawContent}`;
        }).filter(line => line.length > 0).join("\n\n");

        // Create a synthetic message array with the conversation as a single user message
        const syntheticMessages = [root.aiMessageComponent.createObject(root, {
            "role": "user",
            "content": conversationText,
            "rawContent": conversationText,
            "thinking": false,
            "done": true,
        })];

        // Build the request using the current API strategy
        const endpoint = strategy.buildEndpoint(model);
        const data = strategy.buildRequestData(model, syntheticMessages, summarizationPrompt, root.temperature, []);

        // Set up API key environment variable
        if (model.requires_key) {
            compactRequester.environment[`${root.apiKeyEnvVarName}`] = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : "";
        }

        // Build request headers
        let requestHeaders = { "Content-Type": "application/json" };
        let headerString = Object.entries(requestHeaders)
            .filter(([k, v]) => v && v.length > 0)
            .map(([k, v]) => `-H '${k}: ${v}'`)
            .join(' ');

        const authHeader = strategy.buildAuthorizationHeader(root.apiKeyEnvVarName);

        const requestCommandString = `curl --no-buffer "${endpoint}"`
            + ` ${headerString}`
            + (authHeader ? ` ${authHeader}` : "")
            + ` -d '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`;

        compactRequester.command = compactRequester.baseCommand.concat([requestCommandString]);
        compactRequester.running = true;
    }

    /**
     * Saves the current session to its JSON file.
     * Updates the lastModified timestamp in the sessions index.
     */
    function saveCurrentSession() {
        root.saveChat(root.activeSessionName);
        if (root.sessionsIndex.sessions) {
            const entry = root.sessionsIndex.sessions.find(s => s.name === root.activeSessionName);
            if (entry) {
                entry.lastModified = Math.floor(Date.now() / 1000);
                root.saveSessionsIndex();
            }
        }
    }

    // Summarize-to-new-chat process
    Process {
        id: summarizeRequester
        property list<string> baseCommand: ["bash", "-c"]
        property AiMessageData summarizeMessage
        property ApiStrategy currentStrategy

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                try {
                    summarizeRequester.currentStrategy.parseResponseLine(data, summarizeRequester.summarizeMessage);
                } catch (e) {
                    summarizeRequester.summarizeMessage.rawContent += data;
                    summarizeRequester.summarizeMessage.content += data;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            summarizeRequester.currentStrategy.onRequestFinished(summarizeRequester.summarizeMessage);
            const response = summarizeRequester.summarizeMessage.rawContent.trim();

            if (exitCode !== 0 || response.length === 0) {
                root.addMessage(
                    Translation.tr("Failed to summarize conversation. Your messages have been preserved."),
                    root.interfaceRole
                );
                return;
            }

            // Parse title and summary from response
            // Expected format: first line is the title (max 50 chars), second line is keywords, rest is summary
            var lines = response.split("\n");
            var title = lines[0].trim();
            if (title.length > 50) title = title.substring(0, 50);
            if (title.length === 0) title = "Summary";
            // Second line is keywords, rest is summary
            var keywords = lines.length > 1 ? lines[1].trim() : "";
            var summary = lines.length > 2 ? lines.slice(2).join("\n").trim() : (lines.length > 1 ? lines[1] : response);
            // If keywords line looks like a keyword list (short, has commas), use it; otherwise treat as summary
            if (keywords.length > 128 || keywords.indexOf(",") === -1) {
                // Not a valid keyword line, treat all after title as summary
                keywords = "";
                summary = lines.length > 1 ? lines.slice(1).join("\n").trim() : response;
            }

            // Save current session (original stays unchanged)
            root.saveCurrentSession();

            // Create new session with model-generated title
            root.clearMessages();
            root.activeSessionName = title;
            Persistent.states.ai.activeSession = title;

            // Add to sessions index
            var sessions = root.sessionsIndex.sessions || [];
            sessions.push({
                "name": title,
                "createdAt": Math.floor(Date.now() / 1000),
                "lastModified": Math.floor(Date.now() / 1000),
                "archived": false,
                "group": "",
                "subject": keywords.length > 0 ? keywords.substring(0, 128) : "",
            });
            root.sessionsIndex = { "sessions": sessions };
            root.saveSessionsIndex();

            // Add summary as system message
            var aiMessage = root.aiMessageComponent.createObject(root, {
                "role": "system",
                "content": summary,
                "rawContent": summary,
                "thinking": false,
                "done": true,
            });
            var id = root.idForMessage(aiMessage);
            root.messageIDs = [id];
            root.messageByID[id] = aiMessage;
            root.saveCurrentSession();

            root.addMessage(
                Translation.tr("Created summary session: \"%1\"").arg(title),
                root.interfaceRole
            );
        }
    }

    /**
     * Creates a new session with a model-generated title and summary from the
     * current conversation. The original session remains unchanged.
     * @param focusInstruction Optional instruction to guide the summary
     */
    function summarizeToNewChat(focusInstruction) {
        if (root.messageIDs.length === 0) {
            root.addMessage(Translation.tr("Nothing to summarize — conversation is empty."), root.interfaceRole);
            return;
        }

        var model = models[currentModelId];
        var strategy = root.currentApiStrategy;
        summarizeRequester.currentStrategy = strategy;
        strategy.reset();

        // Create temporary message for accumulating response
        summarizeRequester.summarizeMessage = root.aiMessageComponent.createObject(root, {
            "role": "assistant",
            "content": "",
            "rawContent": "",
            "thinking": false,
            "done": false,
        });

        // Build summarization prompt asking for title + summary
        var summarizationPrompt = "Generate a title (first line, max 50 characters), then on the second line 3-5 comma-separated keywords, then a concise summary (remaining lines) of the following conversation. The title should describe the topic. Keywords should be single words or short phrases useful for search.";
        if (focusInstruction && focusInstruction.trim().length > 0) {
            summarizationPrompt += " Focus on: " + focusInstruction.trim();
        }

        // Build conversation as single user message
        var conversationText = root.messageIDs.map(function(id) {
            var msg = root.messageByID[id];
            if (!msg) return "";
            return "[" + msg.role + "]: " + msg.rawContent;
        }).filter(function(line) { return line.length > 0; }).join("\n\n");

        var syntheticMessages = [root.aiMessageComponent.createObject(root, {
            "role": "user",
            "content": conversationText,
            "rawContent": conversationText,
            "thinking": false,
            "done": true,
        })];

        var endpoint = strategy.buildEndpoint(model);
        var data = strategy.buildRequestData(model, syntheticMessages, summarizationPrompt, root.temperature, []);

        if (model.requires_key) {
            summarizeRequester.environment[root.apiKeyEnvVarName] = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : "";
        }

        var requestHeaders = { "Content-Type": "application/json" };
        var headerString = Object.entries(requestHeaders)
            .filter(function(entry) { return entry[1] && entry[1].length > 0; })
            .map(function(entry) { return "-H '" + entry[0] + ": " + entry[1] + "'"; })
            .join(' ');

        var authHeader = strategy.buildAuthorizationHeader(root.apiKeyEnvVarName);

        var requestCommandString = 'curl --no-buffer "' + endpoint + '"'
            + ' ' + headerString
            + (authHeader ? ' ' + authHeader : '')
            + " -d '" + CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data)) + "'";

        summarizeRequester.command = summarizeRequester.baseCommand.concat([requestCommandString]);
        summarizeRequester.running = true;
    }

    // --- Free Dictation Session Management ---

    FileView {
        id: freeDictationFile
        path: `${Directories.aiChats}/Free Dictation.json`
        blockLoading: true
    }

    /**
     * Creates the "Free Dictation" session if it doesn't already exist in the
     * sessions index. Called on Component.onCompleted to guarantee the session
     * is always available for the voice assistant pipeline.
     */
    function ensureFreeDictationSession() {
        const sessions = root.sessionsIndex.sessions || [];
        const exists = sessions.some(s => s.name === "Free Dictation");
        if (exists) return;

        // Add entry to sessions index
        const now = Math.floor(Date.now() / 1000);
        sessions.push({
            "name": "Free Dictation",
            "createdAt": now,
            "lastModified": now,
            "archived": false,
            "group": "",
            "subject": "",
            "protected": true,
        });
        root.sessionsIndex = { "sessions": sessions };
        root.saveSessionsIndex();

        // Create empty chat file
        freeDictationFile.setText(JSON.stringify([]));
    }

    /**
     * Appends a message to the "Free Dictation" session without switching the
     * active session. Reads the current file, appends the new message, and
     * writes it back.
     * @param text The message content
     * @param role The message role ("user" or "assistant")
     */
    function appendToFreeDictation(text, role) {
        if (!text || text.trim().length === 0) return;

        let messages = [];
        try {
            freeDictationFile.reload();
            const content = freeDictationFile.text();
            if (content && content.trim().length > 0) {
                messages = JSON.parse(content);
            }
        } catch (e) {
            console.log("[AI] Could not read Free Dictation session, starting fresh:", e);
            messages = [];
        }

        messages.push({
            "role": role,
            "rawContent": text,
            "model": role === "assistant" ? root.currentModelId : "",
            "thinking": false,
            "done": true,
            "annotations": [],
            "annotationSources": [],
            "functionName": "",
            "functionCall": null,
            "functionResponse": "",
            "visibleToUser": true,
        });

        freeDictationFile.setText(JSON.stringify(messages));

        // Update lastModified in sessions index
        if (root.sessionsIndex.sessions) {
            const entry = root.sessionsIndex.sessions.find(s => s.name === "Free Dictation");
            if (entry) {
                entry.lastModified = Math.floor(Date.now() / 1000);
                root.saveSessionsIndex();
            }
        }
    }

    // === Attachment Management ===

    // Pending attachments for the next message (list of {name, path, type, size})
    property var pendingAttachments: []

    /**
     * Stores a file in the attachments directory and returns its metadata.
     * The file is copied (not moved) so the original remains intact.
     * @param sourcePath Absolute path to the source file
     * @param fileName Original file name (for display)
     * @param mimeType MIME type of the file
     * @returns Object {name, path, type, size} where path is relative to aiAttachments dir
     */
    function storeAttachment(sourcePath, fileName, mimeType) {
        const timestamp = Date.now()
        // Sanitize filename: replace spaces and special chars
        const safeName = fileName.replace(/[^a-zA-Z0-9._-]/g, "_")
        const storedName = timestamp + "-" + safeName
        const destPath = Directories.aiAttachments + "/" + storedName

        // Copy file to attachments directory
        Quickshell.execDetached(["cp", "--", sourcePath, destPath])

        return {
            "name": fileName,
            "path": storedName,  // relative to aiAttachments
            "type": mimeType || "application/octet-stream",
            "size": 0,  // size will be determined by the file itself
        }
    }

    /**
     * Stores clipboard image data (from wl-paste) as a resized PNG attachment.
     * Pipes wl-paste through magick to resize (max 1024px) before saving.
     * This keeps base64 payloads well under ARG_MAX for curl commands.
     * @param callback Function called with the attachment metadata when done
     */
    function storeClipboardImage(callback) {
        const timestamp = Date.now()
        const storedName = timestamp + "-clipboard.png"
        const destPath = Directories.aiAttachments + "/" + storedName
        clipboardImageSaver.destPath = destPath
        clipboardImageSaver.storedName = storedName
        clipboardImageSaver.callback = callback
        // Pipe clipboard image through magick to resize (max 1024x1024, preserve aspect ratio)
        // and strip metadata to reduce file size. Output as PNG for lossless quality at reasonable size.
        clipboardImageSaver.command = ["bash", "-c",
            "wl-paste --type image/png | magick png:- -resize '1024x1024>' -strip png:'" + destPath + "'"
        ]
        clipboardImageSaver.running = true
    }

    Process {
        id: clipboardImageSaver
        property string destPath: ""
        property string storedName: ""
        property var callback: null

        onExited: (exitCode, exitStatus) => {
            if (callback) {
                if (exitCode !== 0) {
                    console.log("[Ai] Clipboard image save failed (exit " + exitCode + "), trying fallback without resize");
                    // Fallback: save raw without resize
                    clipboardImageFallback.destPath = destPath;
                    clipboardImageFallback.storedName = storedName;
                    clipboardImageFallback.callback = callback;
                    clipboardImageFallback.command = ["bash", "-c", "wl-paste --type image/png > '" + destPath + "'"];
                    clipboardImageFallback.running = true;
                    callback = null;
                    return;
                }
                var meta = {
                    "name": "clipboard-image.png",
                    "path": storedName,
                    "type": "image/png",
                    "size": 0,
                }
                callback(meta)
                callback = null
            }
        }
    }

    // Fallback process if magick resize fails (e.g., magick not installed)
    Process {
        id: clipboardImageFallback
        property string destPath: ""
        property string storedName: ""
        property var callback: null

        onExited: (exitCode, exitStatus) => {
            if (callback) {
                var meta = {
                    "name": "clipboard-image.png",
                    "path": storedName,
                    "type": "image/png",
                    "size": 0,
                }
                callback(meta)
                callback = null
            }
        }
    }

    /**
     * Adds an attachment to the pending list (shown in input area before sending).
     */
    function addPendingAttachment(attachment) {
        root.pendingAttachments = [...root.pendingAttachments, attachment]
    }

    /**
     * Removes a pending attachment by index.
     */
    function removePendingAttachment(index) {
        var arr = [...root.pendingAttachments]
        arr.splice(index, 1)
        root.pendingAttachments = arr
    }

    /**
     * Clears all pending attachments.
     */
    function clearPendingAttachments() {
        root.pendingAttachments = []
    }

    /**
     * Sends a user message with any pending attachments.
     * For image attachments: base64-encodes them and includes in the message's images array.
     * For text/document attachments: reads content and appends to message text.
     * Attachments are stored on the message object, then cleared from pending.
     */
    function sendUserMessageWithAttachments(message) {
        if (message.length === 0 && root.pendingAttachments.length === 0) return;
        if (root.switching) return;
        if (root.contextFull) {
            root.addMessage(
                Translation.tr("Context window is full. Please compact the conversation or switch to a model with a larger context window."),
                root.interfaceRole
            );
            return;
        }

        // Separate images from non-image attachments
        var imageAttachments = [];
        var textAttachments = [];
        for (var i = 0; i < root.pendingAttachments.length; i++) {
            var att = root.pendingAttachments[i];
            if ((att.type || "").startsWith("image/")) {
                imageAttachments.push(att);
            } else {
                textAttachments.push(att);
            }
        }

        // Store pending attachments for the async encode process
        attachmentEncoder.userMessage = message;
        attachmentEncoder.allAttachments = [...root.pendingAttachments];
        attachmentEncoder.imageAttachments = imageAttachments;
        attachmentEncoder.textAttachments = textAttachments;
        attachmentEncoder.encodedImages = [];
        attachmentEncoder.textContents = [];
        attachmentEncoder.currentIndex = 0;
        root.clearPendingAttachments();

        // Start encoding pipeline
        attachmentEncoder.processNext();
    }

    // Sequential attachment encoder — processes each attachment one at a time
    // (base64 for images, cat for text files), then sends the message
    QtObject {
        id: attachmentEncoder
        property string userMessage: ""
        property var allAttachments: []
        property var imageAttachments: []
        property var textAttachments: []
        property var encodedImages: []
        property var textContents: []
        property int currentIndex: 0

        // Total items to process: images first, then text files
        property int totalItems: imageAttachments.length + textAttachments.length

        function processNext() {
            if (currentIndex >= totalItems) {
                // All done — send the message
                finishAndSend();
                return;
            }

            if (currentIndex < imageAttachments.length) {
                // Encode an image
                var att = imageAttachments[currentIndex];
                var absPath = Directories.aiAttachments + "/" + att.path;
                encodeProcess.command = ["base64", "-w", "0", absPath];
                encodeProcess.running = true;
            } else {
                // Read a text file
                var textIdx = currentIndex - imageAttachments.length;
                var textAtt = textAttachments[textIdx];
                var textAbsPath = Directories.aiAttachments + "/" + textAtt.path;
                readProcess.fileName = textAtt.name;
                readProcess.command = ["head", "-c", "100000", textAbsPath]; // Cap at 100KB
                readProcess.running = true;
            }
        }

        function finishAndSend() {
            // Build the final message content
            var finalContent = userMessage;

            // Append text file contents
            for (var i = 0; i < textContents.length; i++) {
                var tc = textContents[i];
                if (tc.content.length > 0) {
                    finalContent += "\n\n--- Attached file: " + tc.name + " ---\n" + tc.content;
                }
            }

            var aiMessage = root.aiMessageComponent.createObject(root, {
                "role": "user",
                "content": finalContent,
                "rawContent": finalContent,
                "thinking": false,
                "done": true,
                "attachments": allAttachments,
                "images": encodedImages,
            });
            var id = root.idForMessage(aiMessage);
            root.messageByID[id] = aiMessage;
            root.messageIDs = [...root.messageIDs, id];
            requester.makeRequest();
        }
    }

    // Process for base64-encoding image attachments
    Process {
        id: encodeProcess
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    attachmentEncoder.encodedImages.push(text.trim());
                } else {
                    // Empty output — encoding failed or empty file
                    attachmentEncoder.encodedImages.push("");
                }
                attachmentEncoder.currentIndex++;
                attachmentEncoder.processNext();
            }
        }
    }

    // Process for reading text file contents
    Process {
        id: readProcess
        property string fileName: ""
        stdout: StdioCollector {
            onStreamFinished: {
                attachmentEncoder.textContents.push({
                    name: readProcess.fileName,
                    content: text
                });
                attachmentEncoder.currentIndex++;
                attachmentEncoder.processNext();
            }
        }
    }

    /**
     * Returns the absolute path for an attachment given its relative stored name.
     */
    function getAttachmentAbsolutePath(relativePath) {
        return Directories.aiAttachments + "/" + relativePath
    }

    /**
     * Opens an attachment with xdg-open for viewing/downloading.
     */
    function openAttachment(relativePath) {
        const absPath = getAttachmentAbsolutePath(relativePath)
        Quickshell.execDetached(["xdg-open", absPath])
    }

    /**
     * Copies an attachment to the user's Downloads folder.
     */
    function downloadAttachment(relativePath, originalName) {
        const absPath = getAttachmentAbsolutePath(relativePath)
        const destPath = CF.FileUtils.trimFileProtocol(Directories.downloads) + "/" + originalName
        Quickshell.execDetached(["cp", "--", absPath, destPath])
    }

    // Search state
    property var searchResults: []
    property int searchIndex: -1
    property var crossSessionResults: []

    // Keyword generation state
    property int _lastKeywordMessageCount: 0
    property int _keywordGenerationThreshold: 5

    /**
     * Returns all sessions sorted by lastModified (newest first).
     * Each entry contains name and lastModified timestamp.
     */
    function listSessions() {
        const sessions = root.sessionsIndex.sessions || [];
        return [...sessions].sort((a, b) => (b.lastModified || 0) - (a.lastModified || 0));
    }

    /**
     * Searches messages in the active session using filters.
     * @param query Object with keyword, dateStart, dateEnd, subject, group fields
     * @returns Array of SearchResult objects {messageIndex, matchStart, matchEnd}
     */
    function searchMessages(query) {
        var results = [];
        var keyword = (query.keyword || "").toLowerCase();
        var dateStart = query.dateStart || null;
        var dateEnd = query.dateEnd || null;

        // Keyword must be at least 2 chars
        if (keyword.length > 0 && keyword.length < 2) {
            root.searchResults = [];
            root.searchIndex = -1;
            return [];
        }

        // No active filter — clear results
        if (keyword.length === 0 && dateStart === null && dateEnd === null) {
            root.searchResults = [];
            root.searchIndex = -1;
            return [];
        }

        console.log("[AI] searchMessages: keyword='" + keyword + "' messageIDs.length=" + root.messageIDs.length)

        for (var i = 0; i < root.messageIDs.length; i++) {
            var id = root.messageIDs[i];
            var msg = root.messageByID[id];
            if (!msg) continue;

            var content = (msg.rawContent || "").toLowerCase();

            // Keyword filter
            if (keyword.length >= 2) {
                var matchStart = content.indexOf(keyword);
                if (matchStart === -1) continue;

                // Date range filter (if timestamps available)
                if (dateStart !== null && msg.timestamp && msg.timestamp < dateStart) continue;
                if (dateEnd !== null && msg.timestamp && msg.timestamp > dateEnd) continue;

                results.push({
                    "messageIndex": i,
                    "matchStart": matchStart,
                    "matchEnd": matchStart + keyword.length,
                });
            } else {
                // No keyword filter — only date range
                if (dateStart !== null && msg.timestamp && msg.timestamp < dateStart) continue;
                if (dateEnd !== null && msg.timestamp && msg.timestamp > dateEnd) continue;
                results.push({
                    "messageIndex": i,
                    "matchStart": 0,
                    "matchEnd": 0,
                });
            }
        }

        root.searchResults = results;
        root.searchIndex = results.length > 0 ? 0 : -1;

        // Cross-session keyword search
        root.crossSessionResults = root.searchSessionsByKeyword(keyword);

        return results;
    }

    /**
     * Navigate to next search result (wraps at end).
     */
    function nextSearchResult() {
        if (root.searchResults.length === 0) return;
        if (root.searchIndex >= root.searchResults.length - 1) {
            root.searchIndex = 0;
        } else {
            root.searchIndex = root.searchIndex + 1;
        }
    }

    /**
     * Navigate to previous search result (wraps at start).
     */
    function prevSearchResult() {
        if (root.searchResults.length === 0) return;
        if (root.searchIndex <= 0) {
            root.searchIndex = root.searchResults.length - 1;
        } else {
            root.searchIndex = root.searchIndex - 1;
        }
    }

    /**
     * Clear search state.
     */
    function clearSearch() {
        root.searchResults = [];
        root.searchIndex = -1;
    }

    /**
     * Switches to the specified session by name.
     * Saves the current session first, then loads the target session.
     * @param name The session name to switch to
     */
    function switchSession(name) {
        const trimmedName = (name || "").trim();
        console.log("[AI] switchSession called:", trimmedName, "| current:", root.activeSessionName);
        if (trimmedName.length === 0) {
            root.addMessage(Translation.tr("Session name cannot be empty"), root.interfaceRole);
            return;
        }

        // Verify session exists in index
        if (!root.sessionsIndex.sessions || !root.sessionsIndex.sessions.find(s => s.name === trimmedName)) {
            const available = (root.sessionsIndex.sessions || []).map(s => s.name).join("\n- ");
            root.addMessage(
                Translation.tr("Session \"%1\" not found.\n\nAvailable sessions:\n- %2").arg(trimmedName).arg(available || Translation.tr("(none)")),
                root.interfaceRole
            );
            return;
        }

        // Don't switch to the already active session
        if (trimmedName === root.activeSessionName) {
            root.addMessage(Translation.tr("Already on session \"%1\"").arg(trimmedName), root.interfaceRole);
            return;
        }

        // Save current session before switching
        root.maybeGenerateKeywords();
        root.saveCurrentSession();

        // Signal switch starting, disable input
        root.switching = true;
        root.sessionSwitchStarted();

        // Load the target session
        root.loadSession(trimmedName);

        // Reset auto-compact notification state for the switched session
        root.autoCompactShown = false;
        root.autoCompactDismissed = false;
        root.previousContextUsageRatio = 0;

        // Update active session name and persist
        root.activeSessionName = trimmedName;
        Persistent.states.ai.activeSession = trimmedName;

        // Signal switch completed, re-enable input
        root.switching = false;
        root.sessionSwitchCompleted();
    }

    /**
     * Loads a session's message history from its JSON file.
     * On failure: preserves current state, displays error, stays on current session.
     * @param name The session name to load
     */
    function loadSession(name) {
        const trimmedName = (name || "").trim();
        console.log("[AI] loadSession called for:", trimmedName);
        try {
            // Use dedicated sessionReader (not chatSaveFile) to avoid binding issues
            const targetPath = Directories.aiChats + "/" + trimmedName + ".json";
            sessionReader.path = targetPath;
            sessionReader.reload();
            const saveContent = sessionReader.text();
            // Keep chatSaveFile in sync so subsequent saves target the correct file
            chatSaveFile.chatName = trimmedName;
            console.log("[AI] loadSession path:", targetPath, "content length:", saveContent ? saveContent.length : 0);
            if (!saveContent || saveContent.trim().length === 0) {
                // Empty file — treat as empty session (not a failure)
                console.log("[AI] loadSession: empty file, clearing messages");
                root.clearMessages();
                return;
            }
            const saveData = JSON.parse(saveContent);
            if (!Array.isArray(saveData)) {
                throw new Error("Session file does not contain a JSON array");
            }
            console.log("[AI] loadSession: parsed", saveData.length, "messages");

            // Only clear messages AFTER successful parse — preserves state on failure
            root.clearMessages();

            // Populate messageByID before assigning messageIDs so that when
            // contextTokens and the message list view re-evaluate on
            // messageIDsChanged, all message objects are already present.
            const newMessageByID = ({});
            for (var i = 0; i < saveData.length; i++) {
                var message = saveData[i];
                newMessageByID[i] = root.aiMessageComponent.createObject(root, {
                    "role": message.role,
                    "rawContent": message.rawContent,
                    "content": message.rawContent,
                    "model": message.model ?? "",
                    "thinking": message.thinking ?? false,
                    "done": message.done ?? true,
                    "annotations": message.annotations ?? [],
                    "annotationSources": message.annotationSources ?? [],
                    "functionName": message.functionName ?? "",
                    "functionCall": message.functionCall ?? null,
                    "functionResponse": message.functionResponse ?? "",
                    "visibleToUser": message.visibleToUser ?? true,
                    "attachments": message.attachments ?? [],
                    "images": message.images ?? [],
                });
            }
            root.messageByID = newMessageByID;
            root.messageIDs = saveData.map((_, i) => i);
            root.messageVersion++;
            console.log("[AI] loadSession DONE: messageIDs.length =", root.messageIDs.length);
        } catch (e) {
            console.log("[AI] Could not load session:", trimmedName, e);
            // Preserve current state — do NOT clear messages on failure
            root.addMessage(
                Translation.tr("Failed to load session \"%1\": %2").arg(trimmedName).arg(String(e)),
                root.interfaceRole
            );
        }
    }

    /**
     * Searches ALL sessions' subjects/names for a keyword match.
     * @param keyword The keyword to search for (min 2 chars)
     * @returns Array of matching session objects
     */
    function searchSessionsByKeyword(keyword) {
        if (!keyword || keyword.length < 2) return [];
        var kw = keyword.toLowerCase();
        var sessions = root.sessionsIndex.sessions || [];
        var results = [];
        for (var i = 0; i < sessions.length; i++) {
            var s = sessions[i];
            var subject = (s.subject || "").toLowerCase();
            var name = (s.name || "").toLowerCase();
            if (subject.indexOf(kw) !== -1 || name.indexOf(kw) !== -1) {
                results.push(s);
            }
        }
        return results;
    }

    /**
     * Called when user is leaving the current session (switching, search open).
     * Generates keywords lazily if enough new messages have been added.
     */
    function maybeGenerateKeywords() {
        var currentCount = root.messageIDs.length;
        var lastCount = root._lastKeywordMessageCount;

        // Skip if: no messages, or not enough growth since last generation
        if (currentCount === 0) return;
        if (lastCount > 0 && currentCount < lastCount * 1.3 && (currentCount - lastCount) < root._keywordGenerationThreshold) return;

        // Check if subject already exists and is recent enough
        var sessions = root.sessionsIndex.sessions || [];
        var entry = null;
        for (var i = 0; i < sessions.length; i++) {
            if (sessions[i].name === root.activeSessionName) {
                entry = sessions[i];
                break;
            }
        }
        if (!entry) return;
        if (entry.subject && entry.subject.length > 0 && lastCount > 0 && currentCount < lastCount * 1.5) return;

        // Generate keywords asynchronously
        root._generateKeywordsForSession(root.activeSessionName);
        root._lastKeywordMessageCount = currentCount;
    }

    /**
     * Builds and fires the keyword extraction request for the given session.
     * @param sessionName The session to generate keywords for
     */
    function _generateKeywordsForSession(sessionName) {
        // Build a brief summary of last 10 messages for keyword extraction
        var messageSample = [];
        var startIdx = Math.max(0, root.messageIDs.length - 10);
        for (var i = startIdx; i < root.messageIDs.length; i++) {
            var msg = root.messageByID[root.messageIDs[i]];
            if (msg && msg.rawContent) {
                messageSample.push(msg.rawContent.substring(0, 200));
            }
        }
        if (messageSample.length === 0) return;

        var sampleText = messageSample.join("\n");

        // Use the existing model to extract keywords
        var model = root.models[root.currentModelId];
        if (!model) return;

        var strategy = root.currentApiStrategy;
        keywordRequester.sessionName = sessionName;
        keywordRequester.currentStrategy = strategy;
        strategy.reset();

        keywordRequester.keywordMessage = root.aiMessageComponent.createObject(root, {
            "role": "assistant", "content": "", "rawContent": "", "thinking": false, "done": false,
        });

        var prompt = "Extract 3-7 comma-separated keywords/topics from this conversation sample. Reply with ONLY the keywords, nothing else:";
        var syntheticMessages = [root.aiMessageComponent.createObject(root, {
            "role": "user", "content": sampleText, "rawContent": sampleText, "thinking": false, "done": true,
        })];

        var endpoint = strategy.buildEndpoint(model);
        var data = strategy.buildRequestData(model, syntheticMessages, prompt, 0.0, []);

        if (model.requires_key) {
            keywordRequester.environment[root.apiKeyEnvVarName] = root.apiKeys ? (root.apiKeys[model.key_id] || "") : "";
        }

        var requestHeaders = {"Content-Type": "application/json"};
        var headerString = "";
        var keys = Object.keys(requestHeaders);
        for (var j = 0; j < keys.length; j++) {
            if (requestHeaders[keys[j]] && requestHeaders[keys[j]].length > 0) {
                headerString += " -H '" + keys[j] + ": " + requestHeaders[keys[j]] + "'";
            }
        }
        var authHeader = strategy.buildAuthorizationHeader(root.apiKeyEnvVarName);

        var cmd = 'curl --no-buffer --max-time 10 "' + endpoint + '"' + headerString
            + (authHeader ? ' ' + authHeader : '')
            + " -d '" + CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data)) + "'";

        keywordRequester.command = ["bash", "-c", cmd];
        keywordRequester.running = true;
    }
}
