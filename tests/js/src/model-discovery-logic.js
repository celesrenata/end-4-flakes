/**
 * Pure logic functions from ModelDiscoveryService.qml
 * Extracted for property-based testing with fast-check + vitest
 */

// Provider configuration registry (matches QML providerConfigs exactly)
export const providerConfigs = {
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
};

// Sample custom provider for testing
export const sampleCustomProvider = {
    id: "custom-12345",
    name: "My vLLM",
    baseUrl: "http://localhost:5000/v1",
    apiKey: "test-key-123",
    icon: "ai-openai-symbolic"
};

/**
 * Get effective provider config for a provider ID.
 * Checks built-in providerConfigs first, then custom providers.
 */
export function getEffectiveProviderConfig(providerId, customProviders = []) {
    if (providerConfigs[providerId]) {
        return providerConfigs[providerId];
    }
    for (var i = 0; i < customProviders.length; i++) {
        if (customProviders[i].id === providerId) {
            var cp = customProviders[i];
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

/**
 * Build the curl validation command for a provider.
 */
export function buildValidationCommand(providerId, apiKey, customProviders = []) {
    var config = getEffectiveProviderConfig(providerId, customProviders);
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
    return {
        endpoint: endpoint,
        auth: authPart,
        command: ["bash", "-c", 'curl -s -w "\\n%{http_code}" "' + endpoint + '" ' + authPart]
    };
}

/**
 * Map HTTP status and response body to a user-facing error message.
 */
export function mapErrorResponse(httpStatus, responseBody) {
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

/**
 * Format a model ID into a human-friendly display name.
 */
export function formatModelName(modelId) {
    var replaced = modelId.replace(/-/g, " ").replace(/:/g, " ");
    var words = replaced.split(" ");
    var lastWord = words[words.length - 1];
    if (/^\d+b$/i.test(lastWord)) {
        words[words.length - 1] = lastWord.replace(/(\d+)b/i, function(_, num) {
            return num + "B";
        });
        words[words.length - 1] = "(" + words[words.length - 1] + ")";
    }
    for (var i = 0; i < words.length; i++) {
        words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1);
    }
    if (words[words.length - 1] === "Latest") {
        words.pop();
    }
    return words.join(" ");
}

/**
 * Parse a model list response body into raw model data objects.
 */
export function parseModelListResponse(providerId, responseBody) {
    try {
        var json = JSON.parse(responseBody);
        if (providerId === "ollama") {
            return json.models || [];
        } else if (providerId === "gemini") {
            return json.models || [];
        } else {
            return json.data || [];
        }
    } catch (e) {
        return [];
    }
}

/**
 * Map raw model data to AiModel-compatible properties.
 */
export function mapModelToAiModel(providerId, modelData, customProviders = []) {
    var config = getEffectiveProviderConfig(providerId, customProviders);
    if (!config) return null;

    var modelId = "";
    if (providerId === "ollama") {
        modelId = modelData.name || modelData.model || "";
    } else if (providerId === "gemini") {
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

/**
 * Compose a model registry from discovered models and extra models.
 * This mirrors the logic in Ai.qml's computed models property.
 */
export function composeModelRegistry(discoveredModels, extraModels = []) {
    var result = {};
    var providers = Object.keys(discoveredModels);
    for (var i = 0; i < providers.length; i++) {
        var providerModels = discoveredModels[providers[i]];
        for (var j = 0; j < providerModels.length; j++) {
            var m = providerModels[j];
            var safeId = safeModelName(m.model);
            result[safeId] = m;
        }
    }
    for (var k = 0; k < extraModels.length; k++) {
        var safeExtra = safeModelName(extraModels[k].model || extraModels[k].name || "");
        result[safeExtra] = extraModels[k];
    }
    return result;
}

/**
 * Sanitize a model name for use as an object key.
 */
export function safeModelName(modelName) {
    return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-");
}
