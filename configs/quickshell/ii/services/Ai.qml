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
 * Basic service to handle LLM chats. Supports Google's and OpenAI's API formats.
 * Supports Gemini and OpenAI models.
 * Limitations:
 * - For now functions only work with Gemini API format
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
        if (root.messageIDs.length > 0) {
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
            limitStr = String(limit / 1000000) + "M";
        } else if (limit >= 1000) {
            limitStr = String(limit / 1000) + "k";
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

    Component.onCompleted: {
        setModel(currentModelId, false, false); // Do necessary setup for model
        // Restore session state on startup
        root.loadSessionsIndex();
        root.ensureFreeDictationSession();
        const persistedSession = Persistent.states?.ai?.activeSession;
        if (persistedSession && persistedSession.length > 0) {
            try {
                chatSaveFile.chatName = persistedSession;
                chatSaveFile.reload();
                const content = chatSaveFile.text();
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
                            chatSaveFile.chatName = sorted[fi].name;
                            chatSaveFile.reload();
                            const fallbackContent = chatSaveFile.text();
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
                    root.modelList = [...root.modelList, ...dataJson];
                    dataJson.forEach(model => {
                        const safeModelName = root.safeModelName(model);
                        root.addModel(safeModelName, {
                            "name": guessModelName(model),
                            "icon": guessModelLogo(model),
                            "description": Translation.tr("Local Ollama model | %1").arg(model),
                            "homepage": `https://ollama.com/library/${model}`,
                            "endpoint": "http://localhost:11434/v1/chat/completions",
                            "model": model,
                            "requires_key": false,
                        })
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
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function removeMessage(index) {
        if (index < 0 || index >= messageIDs.length) return;
        const id = root.messageIDs[index];
        root.messageIDs.splice(index, 1);
        root.messageIDs = [...root.messageIDs];
        delete root.messageByID[id];
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
        modelId = modelId.toLowerCase()
        if (modelList.indexOf(modelId) !== -1) {
            const model = models[modelId]
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
            root.currentModelId = modelId;
            if (setPersistentState) Persistent.states.ai.model = modelId;
            if (feedback) root.addMessage(Translation.tr("Model set to %1").arg(model.name), root.interfaceRole);
            if (model.requires_key) {
                // If key not there show advice
                if (root.apiKeysLoaded && (!root.apiKeys[model.key_id] || root.apiKeys[model.key_id].length === 0)) {
                    root.addApiKeyAdvice(model)
                }
            }
        } else {
            if (feedback) root.addMessage(Translation.tr("Invalid model. Supported: \n```\n") + modelList.join("\n```\n```\n"), Ai.interfaceRole) + "\n```"
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

    Process {
        id: requester
        property list<string> baseCommand: ["bash", "-c"]
        property AiMessageData message
        property ApiStrategy currentStrategy

        function markDone() {
            requester.message.done = true;
            if (root.postResponseHook) {
                root.postResponseHook();
                root.postResponseHook = null; // Reset hook after use
            }
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
            const data = root.currentApiStrategy.buildRequestData(model, filteredMessageArray, root.systemPrompt, root.temperature, root.tools[model.api_format][root.currentTool]);
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
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = requester.message;

            /* Build header string for curl */ 
            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            // console.log("Request headers: ", JSON.stringify(requestHeaders));
            // console.log("Header string: ", headerString);

            /* Get authorization header from strategy */
            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
            
            /* Create command string */
            const requestCommandString = `curl --no-buffer "${endpoint}"`
                + ` ${headerString}`
                + (authHeader ? ` ${authHeader}` : "")
                + ` -d '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
            
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
            
            if (result.finished) {
                requester.markDone();
            } else if (!requester.message.done) {
                requester.markDone();
            }

            // Handle error responses
            if (requester.message.content.includes("API key not valid")) {
                root.addApiKeyAdvice(models[requester.message.model]);
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
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
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
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = responseMessage;

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

    Process {
        id: hyprMcpProc
        running: false
        property string pendingTool: ""
        property var pendingArgs: ({})
        property string responseBuffer: ""

        stdout: SplitParser {
            onRead: data => {
                hyprMcpProc.responseBuffer += data;
            }
        }

        onExited: (exitCode, exitStatus) => {
            const response = hyprMcpProc.responseBuffer.trim();
            hyprMcpProc.responseBuffer = "";

            if (exitCode !== 0 || response.length === 0) {
                root.addFunctionOutputMessage(hyprMcpProc.pendingTool,
                    Translation.tr("HyprMCP error: service unreachable or returned empty response (exit code: %1)").arg(exitCode));
                requester.makeRequest();
                return;
            }

            try {
                const parsed = JSON.parse(response);
                const content = parsed.result?.content?.[0]?.text || JSON.stringify(parsed);

                if (hyprMcpProc.pendingTool === "hypr_config_read") {
                    // Return config state to model
                    root.addFunctionOutputMessage("hypr_config_read", content);
                    requester.makeRequest();
                } else {
                    // For write operations: trigger read-back verification
                    const key = hyprMcpProc.pendingArgs.key || hyprMcpProc.pendingArgs.keyword || "";
                    const value = String(hyprMcpProc.pendingArgs.value || "");
                    const namespace = key.split(".").slice(0, -1).join(".") || key;

                    hyprMcpVerifyProc.originalTool = hyprMcpProc.pendingTool;
                    hyprMcpVerifyProc.expectedValue = value;
                    hyprMcpVerifyProc.verifyKey = key;
                    hyprMcpVerifyProc.responseBuffer = "";
                    hyprMcpVerifyProc.command = ["bash", "-c",
                        `curl -s -X POST http://localhost:7580/mcp -H 'Content-Type: application/json' -d '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify({
                            method: "tools/call",
                            params: { name: "config_read", arguments: { namespace: namespace } }
                        }))}'`
                    ];
                    hyprMcpVerifyProc.running = true;
                }
            } catch (e) {
                root.addFunctionOutputMessage(hyprMcpProc.pendingTool,
                    Translation.tr("HyprMCP error: could not parse response: %1").arg(String(e)));
                requester.makeRequest();
            }
        }
    }

    Process {
        id: hyprMcpVerifyProc
        running: false
        property string expectedValue: ""
        property string verifyKey: ""
        property string originalTool: ""
        property string responseBuffer: ""

        stdout: SplitParser {
            onRead: data => {
                hyprMcpVerifyProc.responseBuffer += data;
            }
        }

        onExited: (exitCode, exitStatus) => {
            const response = hyprMcpVerifyProc.responseBuffer.trim();
            hyprMcpVerifyProc.responseBuffer = "";

            if (exitCode !== 0 || response.length === 0) {
                // Read-back failed — report error but don't claim success
                root.addFunctionOutputMessage(hyprMcpVerifyProc.originalTool,
                    Translation.tr("Write appeared to succeed but verification read-back failed (exit code: %1). Cannot confirm change was applied.").arg(exitCode));
                requester.makeRequest();
                return;
            }

            try {
                const parsed = JSON.parse(response);
                const content = parsed.result?.content?.[0]?.text || JSON.stringify(parsed);

                // Check if the expected value appears in the read-back
                const actualStr = String(content);
                const expectedStr = String(hyprMcpVerifyProc.expectedValue);

                if (actualStr.indexOf(expectedStr) !== -1) {
                    // Match — report verified success
                    root.addFunctionOutputMessage(hyprMcpVerifyProc.originalTool,
                        Translation.tr("Verified: %1 = %2").arg(hyprMcpVerifyProc.verifyKey).arg(expectedStr));
                } else {
                    // Mismatch — report both expected and actual to model and user
                    root.addFunctionOutputMessage(hyprMcpVerifyProc.originalTool,
                        "Verification failed: expected " + expectedStr + ", got " + actualStr);
                    root.addMessage(
                        Translation.tr("⚠️ Config verification mismatch for \"%1\": expected \"%2\", actual value: %3")
                            .arg(hyprMcpVerifyProc.verifyKey).arg(expectedStr).arg(actualStr),
                        root.interfaceRole
                    );
                }
            } catch (e) {
                root.addFunctionOutputMessage(hyprMcpVerifyProc.originalTool,
                    Translation.tr("Verification read-back parse error: %1").arg(String(e)));
            }

            requester.makeRequest();
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
            if (!args.command || args.command.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `command`."));
                return;
            }
            const contentToAppend = `\n\n**Command execution request**\n\n\`\`\`command\n${args.command}\n\`\`\``;
            message.rawContent += contentToAppend;
            message.content += contentToAppend;
            message.functionPending = true; // Use thinking to indicate the command is waiting for approval
        } else if (name === "hypr_config_read") {
            const namespace = args.namespace || "";
            hyprMcpProc.pendingTool = "hypr_config_read";
            hyprMcpProc.pendingArgs = { namespace: namespace };
            hyprMcpProc.command = ["bash", "-c",
                `curl -s -X POST http://localhost:7580/mcp -H 'Content-Type: application/json' -d '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify({
                    method: "tools/call",
                    params: { name: "config_read", arguments: { namespace: namespace } }
                }))}'`
            ];
            hyprMcpProc.running = true;
        } else if (name === "hypr_config_set") {
            if (!args.key || !args.value) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `key` and `value`."));
                return;
            }
            hyprMcpProc.pendingTool = "hypr_config_set";
            hyprMcpProc.pendingArgs = { key: args.key, value: args.value };
            hyprMcpProc.command = ["bash", "-c",
                `curl -s -X POST http://localhost:7580/mcp -H 'Content-Type: application/json' -d '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify({
                    method: "tools/call",
                    params: { name: "config_set", arguments: { key: args.key, value: args.value } }
                }))}'`
            ];
            hyprMcpProc.running = true;
        } else if (name === "hypr_set_keyword") {
            if (!args.keyword || !args.value) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `keyword` and `value`."));
                return;
            }
            hyprMcpProc.pendingTool = "hypr_set_keyword";
            hyprMcpProc.pendingArgs = { keyword: args.keyword, value: args.value };
            hyprMcpProc.command = ["bash", "-c",
                `curl -s -X POST http://localhost:7580/mcp -H 'Content-Type: application/json' -d '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify({
                    method: "tools/call",
                    params: { name: "set_keyword", arguments: { keyword: args.keyword, value: args.value } }
                }))}'`
            ];
            hyprMcpProc.running = true;
        }
        else root.addMessage(Translation.tr("Unknown function call: %1").arg(name), "assistant");
    }

    function chatToJson() {
        return root.messageIDs.map(id => {
            const message = root.messageByID[id]
            if (!message) return null
            return ({
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
            })
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
            root.addMessage(Translation.tr("Cannot delete the active session \"%1\". Switch to another session first.").arg(name), root.interfaceRole);
            return;
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
            // Expected format: first line is the title (max 50 chars), rest is summary
            var lines = response.split("\n");
            var title = lines[0].trim();
            if (title.length > 50) title = title.substring(0, 50);
            if (title.length === 0) title = "Summary";
            var summary = lines.length > 1 ? lines.slice(1).join("\n").trim() : response;

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
                "subject": "",
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
        var summarizationPrompt = "Generate a title (first line, max 50 characters) and a concise summary (remaining lines) of the following conversation. The title should describe the topic.";
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

    // Search state
    property var searchResults: []
    property int searchIndex: -1

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
        try {
            chatSaveFile.chatName = trimmedName;
            chatSaveFile.reload();
            const saveContent = chatSaveFile.text();
            if (!saveContent || saveContent.trim().length === 0) {
                // Empty file — treat as empty session (not a failure)
                root.clearMessages();
                return;
            }
            const saveData = JSON.parse(saveContent);
            if (!Array.isArray(saveData)) {
                throw new Error("Session file does not contain a JSON array");
            }

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
                });
            }
            root.messageByID = newMessageByID;
            root.messageIDs = saveData.map((_, i) => i);
        } catch (e) {
            console.log("[AI] Could not load session:", trimmedName, e);
            // Preserve current state — do NOT clear messages on failure
            root.addMessage(
                Translation.tr("Failed to load session \"%1\": %2").arg(trimmedName).arg(String(e)),
                root.interfaceRole
            );
        }
    }
}
