pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Core service for AI provider API key validation, model discovery, and balance fetching.
 * Manages provider configurations and state for the Provider Panel.
 */
Singleton {
    id: root

    // Provider configuration registry (built-in providers)
    readonly property var providerConfigs: ({
        "openai": {
            name: "OpenAI",
            icon: "ai-openai-symbolic",
            key_id: "openai",
            requires_key: true,
            validation_endpoint: "https://api.openai.com/v1/models",
            model_endpoint: "https://api.openai.com/v1/models",
            chat_endpoint: "https://api.openai.com/v1/chat/completions",
            auth_type: "bearer",
            api_format: "openai",
            supports_balance: true,
            balance_endpoint: "https://api.openai.com/v1/organization/usage"
        },
        "anthropic": {
            name: "Anthropic",
            icon: "anthropic-symbolic",
            key_id: "anthropic",
            requires_key: true,
            validation_endpoint: "https://api.anthropic.com/v1/models",
            model_endpoint: "https://api.anthropic.com/v1/models",
            chat_endpoint: "https://api.anthropic.com/v1/messages",
            auth_type: "x-api-key",
            api_format: "openai",
            supports_balance: false
        },
        "gemini": {
            name: "Gemini",
            icon: "google-gemini-symbolic",
            key_id: "gemini",
            requires_key: true,
            validation_endpoint: "https://generativelanguage.googleapis.com/v1beta/models",
            model_endpoint: "https://generativelanguage.googleapis.com/v1beta/models",
            chat_endpoint_template: "https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent",
            auth_type: "query_param",
            api_format: "gemini",
            supports_balance: false
        },
        "mistral": {
            name: "Mistral",
            icon: "mistral-symbolic",
            key_id: "mistral",
            requires_key: true,
            validation_endpoint: "https://api.mistral.ai/v1/models",
            model_endpoint: "https://api.mistral.ai/v1/models",
            chat_endpoint: "https://api.mistral.ai/v1/chat/completions",
            auth_type: "bearer",
            api_format: "mistral",
            supports_balance: false
        },
        "openrouter": {
            name: "OpenRouter",
            icon: "openrouter-symbolic",
            key_id: "openrouter",
            requires_key: true,
            validation_endpoint: "https://openrouter.ai/api/v1/models",
            model_endpoint: "https://openrouter.ai/api/v1/models",
            chat_endpoint: "https://openrouter.ai/api/v1/chat/completions",
            auth_type: "bearer",
            api_format: "openai",
            supports_balance: true,
            balance_endpoint: "https://openrouter.ai/api/v1/auth/key"
        },
        "ollama": {
            name: "Ollama",
            icon: "ollama-symbolic",
            key_id: "",
            requires_key: false,
            validation_endpoint: "http://localhost:11434/api/tags",
            model_endpoint: "http://localhost:11434/api/tags",
            chat_endpoint: "http://localhost:11434/v1/chat/completions",
            auth_type: "none",
            api_format: "openai",
            supports_balance: false
        }
    })

    // Validation state per provider: { status: "idle"|"loading"|"success"|"error", message: "" }
    property var validationStates: ({})
    // Discovered models per provider: { "openai": [...], "gemini": [...] }
    property var discoveredModels: ({})
    // Balance info per provider: { "openai": "...", "openrouter": "..." }
    property var balances: ({})

    // Custom providers from user config
    property var customProviders: Config.options.ai.customProviders || []

    // --- Pure functions (testable) ---

    function getEffectiveProviderConfig(providerId) {
        if (providerConfigs[providerId]) {
            return providerConfigs[providerId];
        }
        // Look up in customProviders array
        var customs = customProviders || [];
        for (var i = 0; i < customs.length; i++) {
            if (customs[i].id === providerId) {
                var cp = customs[i];
                var baseUrl = cp.baseUrl || "";
                return {
                    name: cp.name || providerId,
                    icon: cp.icon || "ai-openai-symbolic",
                    key_id: cp.id,
                    requires_key: (cp.apiKey !== undefined && cp.apiKey !== ""),
                    validation_endpoint: baseUrl + "/models",
                    model_endpoint: baseUrl + "/models",
                    chat_endpoint: baseUrl + "/chat/completions",
                    auth_type: (cp.apiKey !== undefined && cp.apiKey !== "") ? "bearer" : "none",
                    api_format: "openai",
                    supports_balance: false
                };
            }
        }
        return null;
    }

    function buildValidationCommand(providerId, apiKey) {
        var config = getEffectiveProviderConfig(providerId);
        if (!config) return null;
        var endpoint = config.validation_endpoint || config.model_endpoint;
        if (!endpoint) return null;
        var authPart = "";
        if (config.auth_type === "bearer") {
            authPart = '-H "Authorization: Bearer ' + apiKey + '"';
        } else if (config.auth_type === "x-api-key") {
            authPart = '-H "x-api-key: ' + apiKey + '" -H "anthropic-version: 2023-06-01"';
        } else if (config.auth_type === "query_param") {
            endpoint = endpoint + "?key=" + apiKey;
        }
        // auth_type === "none" → no auth needed
        return {
            endpoint: endpoint,
            auth: authPart,
            command: ["bash", "-c", 'curl -s -w "\\n%{http_code}" "' + endpoint + '" ' + authPart]
        };
    }

    function mapErrorResponse(httpStatus, responseBody) {
        if (httpStatus === 401 || httpStatus === 403) {
            return "Invalid or revoked API key";
        }
        if (httpStatus === 429) {
            return "Rate limited — try again later";
        }
        if (httpStatus === 402) {
            return "Insufficient credits or quota exceeded";
        }
        var bodyLower = (responseBody || "").toLowerCase();
        if (bodyLower.indexOf("quota") !== -1 || bodyLower.indexOf("insufficient") !== -1 ||
            bodyLower.indexOf("credit") !== -1 || bodyLower.indexOf("billing") !== -1) {
            return "Insufficient credits or quota exceeded";
        }
        if (bodyLower.indexOf("permission") !== -1 || bodyLower.indexOf("scope") !== -1) {
            return "Key lacks required permissions";
        }
        if (httpStatus === 0) {
            return "Network error — check your connection";
        }
        return "Error " + httpStatus + ": " + (responseBody || "Unknown error");
    }

    function formatModelName(modelId) {
        var replaced = modelId.replace(/-/g, " ").replace(/:/g, " ");
        var words = replaced.split(" ");
        // Format last word if it's a param count like "7b"
        var lastWord = words[words.length - 1];
        if (/^\d+b$/i.test(lastWord)) {
            words[words.length - 1] = lastWord.replace(/(\d+)b/i, function(_, num) {
                return num + "B";
            });
            words[words.length - 1] = "(" + words[words.length - 1] + ")";
        }
        // Capitalize each word using indexed for loop
        for (var i = 0; i < words.length; i++) {
            words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1);
        }
        // Remove "Latest" trailing word
        if (words[words.length - 1] === "Latest") {
            words.pop();
        }
        return words.join(" ");
    }

    function parseModelListResponse(providerId, responseBody) {
        try {
            var json = JSON.parse(responseBody);
            if (providerId === "ollama") {
                return json.models || [];
            } else if (providerId === "gemini") {
                return json.models || [];
            } else {
                // OpenAI, Anthropic, Mistral, OpenRouter, and custom providers use { data: [...] }
                return json.data || [];
            }
        } catch (e) {
            console.error("[ModelDiscovery] Failed to parse response for", providerId, e);
            return [];
        }
    }

    function mapModelToAiModel(providerId, modelData) {
        var config = getEffectiveProviderConfig(providerId);
        if (!config) return null;

        var modelId = "";
        // Extract model ID from provider-specific response format
        if (providerId === "ollama") {
            modelId = modelData.name || modelData.model || "";
        } else if (providerId === "gemini") {
            // Gemini returns "models/gemini-2.5-flash" → extract after "models/"
            var rawName = modelData.name || "";
            if (rawName.indexOf("models/") === 0) {
                modelId = rawName.substring(7);
            } else {
                modelId = rawName;
            }
        } else {
            modelId = modelData.id || modelData.name || "";
        }

        var displayName = formatModelName(modelId);

        // Build endpoint
        var endpoint = config.chat_endpoint || "";
        if (providerId === "gemini" && config.chat_endpoint_template) {
            endpoint = config.chat_endpoint_template.split("{model}").join(modelId);
        }

        return {
            name: displayName,
            icon: config.icon,
            description: config.name + " | " + modelId,
            endpoint: endpoint,
            model: modelId,
            requires_key: config.requires_key,
            key_id: config.key_id,
            api_format: config.api_format
        };
    }

    // --- Imperative side-effect functions ---

    function validateKey(providerId, apiKey) {
        var config = getEffectiveProviderConfig(providerId);
        if (!config) return;
        // Set loading state
        var newStates = Object.assign({}, validationStates);
        newStates[providerId] = { status: "loading", message: "" };
        root.validationStates = newStates;
        // Build and launch
        var cmdObj = buildValidationCommand(providerId, apiKey);
        if (!cmdObj) return;
        validationProcess.targetProviderId = providerId;
        validationProcess.targetApiKey = apiKey;
        validationProcess.command = cmdObj.command;
        validationProcess.running = true;
    }

    function discoverModels(providerId) {
        var config = getEffectiveProviderConfig(providerId);
        if (!config) return;
        var endpoint = config.model_endpoint;
        if (!endpoint) return;
        var apiKey = "";
        if (config.requires_key && config.key_id) {
            apiKey = (KeyringStorage.keyringData && KeyringStorage.keyringData.apiKeys)
                ? (KeyringStorage.keyringData.apiKeys[config.key_id] || "") : "";
        }
        var cmdObj = buildValidationCommand(providerId, apiKey);
        if (!cmdObj) return;
        discoveryProcess.targetProviderId = providerId;
        discoveryProcess.command = cmdObj.command;
        discoveryProcess.running = true;
    }

    function isRefreshing(providerId) {
        return discoveryProcess.running && discoveryProcess.targetProviderId === providerId;
    }

    function fetchBalance(providerId) {
        var config = getEffectiveProviderConfig(providerId);
        if (!config || !config.supports_balance || !config.balance_endpoint) return;
        var apiKey = "";
        if (config.requires_key && config.key_id) {
            apiKey = (KeyringStorage.keyringData && KeyringStorage.keyringData.apiKeys)
                ? (KeyringStorage.keyringData.apiKeys[config.key_id] || "") : "";
        }
        if (!apiKey && config.requires_key) return;
        var authPart = "";
        if (config.auth_type === "bearer") {
            authPart = '-H "Authorization: Bearer ' + apiKey + '"';
        }
        balanceProcess.targetProviderId = providerId;
        balanceProcess.command = ["bash", "-c", 'curl -s -w "\\n%{http_code}" "' + config.balance_endpoint + '" ' + authPart];
        balanceProcess.running = true;
    }

    function addCustomProvider(name, baseUrl, apiKey) {
        var id = "custom-" + Date.now();
        var entry = {
            id: id,
            name: name,
            baseUrl: baseUrl,
            apiKey: apiKey || "",
            icon: "ai-openai-symbolic"
        };
        var current = Config.options.ai.customProviders || [];
        var newArray = [];
        for (var i = 0; i < current.length; i++) {
            newArray.push(current[i]);
        }
        newArray.push(entry);
        Config.setNestedField(["ai", "customProviders"], newArray);
        // Store key in keyring if provided
        if (apiKey && apiKey.length > 0) {
            KeyringStorage.setNestedField(["apiKeys", id], apiKey);
        }
        // Trigger model discovery
        root.discoverModels(id);
        return id;
    }

    function updateCustomProvider(id, name, baseUrl, apiKey) {
        var current = Config.options.ai.customProviders || [];
        var newArray = [];
        for (var i = 0; i < current.length; i++) {
            if (current[i].id === id) {
                newArray.push({
                    id: id,
                    name: name,
                    baseUrl: baseUrl,
                    apiKey: apiKey || "",
                    icon: current[i].icon || "ai-openai-symbolic"
                });
            } else {
                newArray.push(current[i]);
            }
        }
        Config.setNestedField(["ai", "customProviders"], newArray);
        // Update key in keyring
        if (apiKey && apiKey.length > 0) {
            KeyringStorage.setNestedField(["apiKeys", id], apiKey);
        }
        // Re-trigger model discovery
        root.discoverModels(id);
    }

    function deleteCustomProvider(id) {
        var current = Config.options.ai.customProviders || [];
        var newArray = [];
        for (var i = 0; i < current.length; i++) {
            if (current[i].id !== id) {
                newArray.push(current[i]);
            }
        }
        Config.setNestedField(["ai", "customProviders"], newArray);
        // Clean up discoveredModels
        var newDiscovered = Object.assign({}, root.discoveredModels);
        delete newDiscovered[id];
        root.discoveredModels = newDiscovered;
        // Clean up validationStates
        var newStates = Object.assign({}, root.validationStates);
        delete newStates[id];
        root.validationStates = newStates;
        // Clean up balances
        var newBalances = Object.assign({}, root.balances);
        delete newBalances[id];
        root.balances = newBalances;
    }

    // --- Process components for async HTTP requests ---

    Process {
        id: validationProcess
        property string targetProviderId: ""
        property string targetApiKey: ""
        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                // The curl command uses -w "\n%{http_code}" so last line is status code
                var lines = data.split("\n");
                var statusCode = parseInt(lines[lines.length - 1]) || 0;
                var body = lines.slice(0, lines.length - 1).join("\n");

                var config = root.getEffectiveProviderConfig(validationProcess.targetProviderId);
                if (statusCode >= 200 && statusCode < 300) {
                    // Success
                    var newStates = Object.assign({}, root.validationStates);
                    newStates[validationProcess.targetProviderId] = { status: "success", message: "" };
                    root.validationStates = newStates;
                    // Store key
                    if (config && config.key_id) {
                        KeyringStorage.setNestedField(["apiKeys", config.key_id], validationProcess.targetApiKey);
                    }
                    // Trigger model discovery
                    root.discoverModels(validationProcess.targetProviderId);
                    // Fetch balance if supported
                    if (config && config.supports_balance) {
                        root.fetchBalance(validationProcess.targetProviderId);
                    }
                } else {
                    // Error
                    var errorMsg = root.mapErrorResponse(statusCode, body);
                    var newStates2 = Object.assign({}, root.validationStates);
                    newStates2[validationProcess.targetProviderId] = { status: "error", message: errorMsg };
                    root.validationStates = newStates2;
                }
            }
        }
    }

    Process {
        id: discoveryProcess
        property string targetProviderId: ""
        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                var lines = data.split("\n");
                var statusCode = parseInt(lines[lines.length - 1]) || 0;
                var body = lines.slice(0, lines.length - 1).join("\n");

                if (statusCode >= 200 && statusCode < 300) {
                    var rawModels = root.parseModelListResponse(discoveryProcess.targetProviderId, body);
                    var mapped = [];
                    for (var i = 0; i < rawModels.length; i++) {
                        var model = root.mapModelToAiModel(discoveryProcess.targetProviderId, rawModels[i]);
                        if (model) {
                            mapped.push(model);
                        }
                    }
                    var newDiscovered = Object.assign({}, root.discoveredModels);
                    newDiscovered[discoveryProcess.targetProviderId] = mapped;
                    root.discoveredModels = newDiscovered;
                    // Fetch balance on model refresh
                    var config = root.getEffectiveProviderConfig(discoveryProcess.targetProviderId);
                    if (config && config.supports_balance) {
                        root.fetchBalance(discoveryProcess.targetProviderId);
                    }
                } else {
                    var newDiscovered2 = Object.assign({}, root.discoveredModels);
                    newDiscovered2[discoveryProcess.targetProviderId] = [];
                    root.discoveredModels = newDiscovered2;
                }
            }
        }
    }

    Process {
        id: balanceProcess
        property string targetProviderId: ""
        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                var lines = data.split("\n");
                var statusCode = parseInt(lines[lines.length - 1]) || 0;
                var body = lines.slice(0, lines.length - 1).join("\n");

                if (statusCode >= 200 && statusCode < 300) {
                    try {
                        var json = JSON.parse(body);
                        var balanceStr = "";
                        // OpenRouter returns { data: { usage, limit, ... } }
                        if (json.data && json.data.limit !== undefined) {
                            balanceStr = "$" + ((json.data.limit - json.data.usage) / 100).toFixed(2);
                        }
                        // OpenAI returns various formats; try to extract credits
                        else if (json.total_available !== undefined) {
                            balanceStr = "$" + json.total_available.toFixed(2);
                        }
                        else if (json.hard_limit_usd !== undefined) {
                            balanceStr = "$" + json.hard_limit_usd.toFixed(2) + " limit";
                        }
                        else {
                            balanceStr = body.substring(0, 50);
                        }
                        var newBalances = Object.assign({}, root.balances);
                        newBalances[balanceProcess.targetProviderId] = balanceStr;
                        root.balances = newBalances;
                    } catch (e) {
                        console.error("[ModelDiscovery] Failed to parse balance for", balanceProcess.targetProviderId, e);
                    }
                }
            }
        }
    }
}
