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
    property Component bedrockApiStrategy: BedrockApiStrategy {}
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
            ],
            "search": [],
            "none": [],
        }
    }
    property list<var> availableTools: Object.keys(root.tools[models[currentModelId]?.api_format] || root.tools["openai"])
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
        var result = {};
        // Add all discovered models from ModelDiscoveryService
        var providers = Object.keys(ModelDiscoveryService.discoveredModels);
        for (var i = 0; i < providers.length; i++) {
            var providerModels = ModelDiscoveryService.discoveredModels[providers[i]];
            for (var j = 0; j < providerModels.length; j++) {
                var m = providerModels[j];
                var safeId = root.safeModelName(m.model);
                result[safeId] = aiModelComponent.createObject(root, m);
            }
        }
        // Add extraModels from config
        var extras = Config.options?.ai?.extraModels ?? [];
        for (var k = 0; k < extras.length; k++) {
            var safeExtra = root.safeModelName(extras[k].model || extras[k].name || "");
            result[safeExtra] = aiModelComponent.createObject(root, extras[k]);
        }
        return result;
    }
    property var modelList: Object.keys(root.models)
    property var currentModelId: Persistent.states?.ai?.model || modelList[0]

    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(this),
        "gemini": geminiApiStrategy.createObject(this),
        "mistral": mistralApiStrategy.createObject(this),
        "bedrock": bedrockApiStrategy.createObject(this),
    }
    property ApiStrategy currentApiStrategy: apiStrategies[models[currentModelId]?.api_format || "openai"]

    Component.onCompleted: {
        setModel(currentModelId, false, false); // Do necessary setup for model
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

    function isVisionCapable(modelId) {
        var model = root.models[modelId];
        if (!model) return false;
        var name = (model.model || "").toLowerCase();
        if (name.startsWith("gpt-4o")) return true;
        if (name.startsWith("gpt-4-turbo")) return true;
        if (name.startsWith("gpt-4.1")) return true;
        if (name.startsWith("gemini-")) return true;
        if (name.startsWith("claude-3-")) return true;
        if (name.startsWith("claude-4-")) return true;
        if (name.startsWith("llava")) return true;
        if (name.startsWith("pixtral")) return true;
        if (name.indexOf("vision") !== -1) return true;
        return false;
    }

    property string bestVisionModel: {
        for (var i = 0; i < root.modelList.length; i++) {
            var id = root.modelList[i];
            if (!root.isVisionCapable(id)) continue;
            var model = root.models[id];
            if (!model.requires_key || (root.apiKeys[model.key_id] && root.apiKeys[model.key_id].length > 0)) {
                return id;
            }
        }
        return "";
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
        return models[currentModelId] || { name: "No model", icon: "auto_awesome", api_format: "openai" };
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

    Process {
        id: bedrockRequester
        property AiMessageData message
        property string stderrOutput: ""

        function markDone() {
            bedrockRequester.message.done = true;
            if (root.postResponseHook) {
                root.postResponseHook();
                root.postResponseHook = null;
            }
            root.saveChat("lastSession")
        }

        stderr: StdioCollector {
            onStreamFinished: {
                bedrockRequester.stderrOutput = text;
            }
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (bedrockRequester.message.thinking) bedrockRequester.message.thinking = false;
                try {
                    var result = root.apiStrategies["bedrock"].parseResponseLine(data, bedrockRequester.message);
                    if (result.tokenUsage) {
                        root.tokenCount.input = result.tokenUsage.input || 0;
                        root.tokenCount.output = result.tokenUsage.output || 0;
                        root.tokenCount.total = result.tokenUsage.total || 0;
                    }
                    if (result.finished) {
                        bedrockRequester.markDone();
                    }
                } catch (e) {
                    console.log("[AI] Bedrock: Could not parse response: ", e);
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                bedrockRequester.message.content += "\n\n[Error: " + (bedrockRequester.stderrOutput || "Process exited with code " + exitCode) + "]";
                bedrockRequester.message.rawContent = bedrockRequester.message.content;
            }
            if (!bedrockRequester.message.done) {
                bedrockRequester.markDone();
            }
            bedrockRequester.stderrOutput = "";
        }
    }

    function makeBedrockRequest() {
        var model = models[currentModelId];
        var strategy = root.apiStrategies["bedrock"];

        var messageArray = root.messageIDs.map(function(id) { return root.messageByID[id]; });
        var filteredMessageArray = messageArray.filter(function(message) { return message.role !== Ai.interfaceRole; });
        var data = strategy.buildRequestData(model, filteredMessageArray, root.systemPrompt, root.temperature, []);

        // Create message object
        bedrockRequester.message = root.aiMessageComponent.createObject(root, {
            "role": "assistant",
            "model": currentModelId,
            "content": "",
            "rawContent": "",
            "thinking": true,
            "done": false,
        });
        var id = idForMessage(bedrockRequester.message);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = bedrockRequester.message;

        // Build aws CLI command
        var messagesJson = JSON.stringify(data.messages);
        var systemJson = JSON.stringify(data.system);
        var cmdArgs = "aws bedrock-runtime converse-stream"
            + " --model-id " + model.model
            + " --messages '" + CF.StringUtils.shellSingleQuoteEscape(messagesJson) + "'"
            + " --region " + AwsCredentialReader.region
            + " --profile " + AwsCredentialReader.profile
            + " --output json";
        if (data.system && data.system.length > 0) {
            cmdArgs += " --system '" + CF.StringUtils.shellSingleQuoteEscape(systemJson) + "'";
        }

        bedrockRequester.command = ["bash", "-c", cmdArgs];
        bedrockRequester.running = true;
    }

    function cancelRequest() {
        if (bedrockRequester.running) {
            bedrockRequester.running = false;
        }
        if (requester.running) {
            requester.running = false;
        }
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        root.addMessage(message, "user");
        var model = models[currentModelId];
        if (model && model.api_format === "bedrock") {
            root.makeBedrockRequest();
        } else {
            requester.makeRequest();
        }
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
        }
        else root.addMessage(Translation.tr("Unknown function call: %1").arg(name), "assistant");
    }

    // --- Vision request (standalone, does not affect chat history) ---

    Process {
        id: visionRequester
        property list<string> baseCommand: ["bash", "-c"]
        property var onChunk
        property var onDone
        property var onError
        property ApiStrategy currentStrategy
        property bool finished: false

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (visionRequester.finished) return;
                try {
                    var result = visionRequester.currentStrategy.parseVisionLine
                        ? visionRequester.currentStrategy.parseVisionLine(data)
                        : visionRequester.parseResponseLine(data);
                    if (result.text && result.text.length > 0) {
                        if (visionRequester.onChunk) visionRequester.onChunk(result.text);
                    }
                    if (result.finished) {
                        visionRequester.finished = true;
                        if (visionRequester.onDone) visionRequester.onDone();
                    }
                } catch (e) {
                    // Fallback: try to extract text from raw line
                    var text = visionRequester.parseResponseLine(data);
                    if (text.text && text.text.length > 0) {
                        if (visionRequester.onChunk) visionRequester.onChunk(text.text);
                    }
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (!visionRequester.finished && text.length > 0) {
                    if (visionRequester.onError) visionRequester.onError(text);
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (!visionRequester.finished) {
                visionRequester.finished = true;
                if (exitCode !== 0) {
                    if (visionRequester.onError) visionRequester.onError("Vision request failed with exit code " + exitCode);
                } else {
                    if (visionRequester.onDone) visionRequester.onDone();
                }
            }
        }

        function parseResponseLine(line) {
            // Generic parser for OpenAI/Gemini/Mistral streaming formats
            var cleanData = line.trim();
            if (cleanData.startsWith("data:")) {
                cleanData = cleanData.slice(5).trim();
            }
            if (!cleanData || cleanData.startsWith(":")) return {};
            if (cleanData === "[DONE]") return { finished: true };

            try {
                var dataJson = JSON.parse(cleanData);
                // OpenAI/Mistral format
                var content = dataJson.choices
                    ? (dataJson.choices[0]?.delta?.content || "")
                    : "";
                // Gemini format
                if (!content && dataJson.candidates) {
                    var parts = dataJson.candidates[0]?.content?.parts;
                    if (parts && parts.length > 0) content = parts[0].text || "";
                }
                if (dataJson.done) return { text: content, finished: true };
                return { text: content };
            } catch (e) {
                return {};
            }
        }
    }

    Process {
        id: visionBedrockRequester
        property var onChunk
        property var onDone
        property var onError
        property bool finished: false

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (visionBedrockRequester.finished) return;
                try {
                    var event = JSON.parse(data);
                    if (event.contentBlockDelta !== undefined) {
                        var delta = event.contentBlockDelta.delta || {};
                        var text = delta.text || "";
                        if (text && visionBedrockRequester.onChunk) {
                            visionBedrockRequester.onChunk(text);
                        }
                    }
                    if (event.messageStop !== undefined) {
                        visionBedrockRequester.finished = true;
                        if (visionBedrockRequester.onDone) visionBedrockRequester.onDone();
                    }
                } catch (e) {
                    // ignore unparseable lines
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (!visionBedrockRequester.finished && text.length > 0) {
                    if (visionBedrockRequester.onError) visionBedrockRequester.onError(text);
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (!visionBedrockRequester.finished) {
                visionBedrockRequester.finished = true;
                if (exitCode !== 0) {
                    if (visionBedrockRequester.onError) visionBedrockRequester.onError("Bedrock vision request failed with exit code " + exitCode);
                } else {
                    if (visionBedrockRequester.onDone) visionBedrockRequester.onDone();
                }
            }
        }
    }

    /**
     * Sends a standalone vision request without affecting chat history.
     * @param text The user prompt/question about the image
     * @param images Array of base64-encoded PNG strings
     * @param onChunk Callback receiving each streamed text fragment: onChunk(text)
     * @param onDone Callback when the response is complete: onDone()
     * @param onError Callback on failure: onError(errorMessage)
     * @param modelId Optional model ID override (defaults to currentModelId)
     */
    function sendVisionMessage(text, images, onChunk, onDone, onError, modelId) {
        var targetModelId = modelId || root.currentModelId;
        var model = root.models[targetModelId];
        if (!model) {
            if (onError) onError("Model not found: " + targetModelId);
            return;
        }

        var apiFormat = model.api_format || "openai";
        var strategy = root.apiStrategies[apiFormat];
        if (!strategy) {
            if (onError) onError("No API strategy for format: " + apiFormat);
            return;
        }

        var visionSystemPrompt = "You are a helpful vision assistant analyzing images.";

        // Build a fake message object with images for the strategy
        var visionMessage = root.aiMessageComponent.createObject(root, {
            "role": "user",
            "content": text,
            "rawContent": text,
            "images": images,
            "thinking": false,
            "done": true,
        });

        if (apiFormat === "bedrock") {
            // Use AWS CLI converse-stream
            var data = strategy.buildRequestData(model, [visionMessage], visionSystemPrompt, root.temperature, []);
            var messagesJson = JSON.stringify(data.messages);
            var systemJson = JSON.stringify(data.system);

            var cmdArgs = "aws bedrock-runtime converse-stream"
                + " --model-id " + model.model
                + " --messages '" + CF.StringUtils.shellSingleQuoteEscape(messagesJson) + "'"
                + " --region " + AwsCredentialReader.region
                + " --profile " + AwsCredentialReader.profile
                + " --output json";
            if (data.system && data.system.length > 0) {
                cmdArgs += " --system '" + CF.StringUtils.shellSingleQuoteEscape(systemJson) + "'";
            }

            visionBedrockRequester.onChunk = onChunk;
            visionBedrockRequester.onDone = onDone;
            visionBedrockRequester.onError = onError;
            visionBedrockRequester.finished = false;
            visionBedrockRequester.command = ["bash", "-c", cmdArgs];
            visionBedrockRequester.running = true;
        } else {
            // Use curl for OpenAI/Gemini/Mistral formats
            strategy.reset();
            var endpoint = strategy.buildEndpoint(model);
            var requestData = strategy.buildRequestData(model, [visionMessage], visionSystemPrompt, root.temperature, []);

            var requestHeaders = { "Content-Type": "application/json" };
            var headerString = Object.entries(requestHeaders)
                .filter(function(entry) { return entry[1] && entry[1].length > 0; })
                .map(function(entry) { return "-H '" + entry[0] + ": " + entry[1] + "'"; })
                .join(' ');

            var authHeader = strategy.buildAuthorizationHeader(root.apiKeyEnvVarName);

            // Set API key in environment
            if (model.requires_key) {
                visionRequester.environment = {};
                visionRequester.environment[root.apiKeyEnvVarName] = root.apiKeys ? (root.apiKeys[model.key_id] || "") : "";
            }

            var requestCommandString = 'curl --no-buffer "' + endpoint + '"'
                + ' ' + headerString
                + (authHeader ? ' ' + authHeader : "")
                + " -d '" + CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(requestData)) + "'";

            visionRequester.onChunk = onChunk;
            visionRequester.onDone = onDone;
            visionRequester.onError = onError;
            visionRequester.currentStrategy = strategy;
            visionRequester.finished = false;
            visionRequester.command = visionRequester.baseCommand.concat([requestCommandString]);
            visionRequester.running = true;
        }

        // Clean up the temporary message object (not added to chat history)
        visionMessage.destroy();
    }

    function chatToJson() {
        return root.messageIDs.map(id => {
            const message = root.messageByID[id]
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
        })
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
            root.messageIDs = saveData.map((_, i) => {
                return i
            })
            // console.log(JSON.stringify(messageIDs))
            for (let i = 0; i < saveData.length; i++) {
                const message = saveData[i];
                root.messageByID[i] = root.aiMessageComponent.createObject(root, {
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
        } catch (e) {
            console.log("[AI] Could not load chat: ", e);
        } finally {
            getSavedChats.running = true;
        }
    }
}
