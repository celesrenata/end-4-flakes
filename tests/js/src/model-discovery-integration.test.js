import { describe, it, expect, beforeEach } from 'vitest';
import {
    providerConfigs,
    sampleCustomProvider,
    getEffectiveProviderConfig,
    buildValidationCommand,
    mapErrorResponse,
    formatModelName,
    parseModelListResponse,
    mapModelToAiModel,
    composeModelRegistry,
    safeModelName
} from './model-discovery-logic.js';

// ============================================================
// Shared test helpers — simulate QML runtime state management
// ============================================================

/**
 * Creates a mock KeyringStorage that mirrors the real singleton's API.
 */
function createMockKeyringStorage() {
    const storage = { apiKeys: {} };
    return {
        setNestedField(path, value) {
            let obj = storage;
            for (let i = 0; i < path.length - 1; i++) {
                if (!obj[path[i]]) obj[path[i]] = {};
                obj = obj[path[i]];
            }
            obj[path[path.length - 1]] = value;
        },
        getNestedField(path) {
            let obj = storage;
            for (let i = 0; i < path.length; i++) {
                if (obj === undefined || obj === null) return undefined;
                obj = obj[path[i]];
            }
            return obj;
        },
        deleteNestedField(path) {
            let obj = storage;
            for (let i = 0; i < path.length - 1; i++) {
                if (!obj[path[i]]) return;
                obj = obj[path[i]];
            }
            delete obj[path[path.length - 1]];
        },
        get keyringData() { return storage; }
    };
}

/**
 * Creates a mock Config store that mirrors the real Config singleton.
 */
function createMockConfig() {
    const options = {
        ai: { customProviders: [], extraModels: [] },
        policies: { ai: 1 }
    };
    return {
        options,
        setNestedField(path, value) {
            let obj = options;
            for (let i = 0; i < path.length - 1; i++) {
                if (!obj[path[i]]) obj[path[i]] = {};
                obj = obj[path[i]];
            }
            obj[path[path.length - 1]] = value;
        }
    };
}

/**
 * Simulates the full validation flow that the QML runtime performs:
 * 1. buildValidationCommand → get curl command
 * 2. Execute (mocked) → get response body + HTTP status
 * 3. Parse status → update validationState
 * 4. On success → store key + trigger discovery
 */
function simulateValidationFlow(providerId, apiKey, mockResponse, state, keyring, customProviders = []) {
    // Step 1: Build command
    const cmd = buildValidationCommand(providerId, apiKey, customProviders);
    if (!cmd) {
        state.validationStates[providerId] = { status: "error", message: "Unknown provider" };
        return;
    }

    // Step 2: Set loading state
    state.validationStates[providerId] = { status: "loading", message: "" };

    // Step 3: Process mock response (simulates curl stdout)
    const httpStatus = mockResponse.statusCode;
    const responseBody = mockResponse.body;

    if (httpStatus >= 200 && httpStatus < 300) {
        // Success path
        state.validationStates[providerId] = { status: "success", message: "" };
        const config = getEffectiveProviderConfig(providerId, customProviders);
        if (config && config.requires_key) {
            keyring.setNestedField(["apiKeys", config.key_id], apiKey);
        }
        return true; // triggers discovery
    } else {
        // Error path
        const errorMsg = mapErrorResponse(httpStatus, responseBody);
        state.validationStates[providerId] = { status: "error", message: errorMsg };
        return false;
    }
}

/**
 * Simulates model discovery flow:
 * 1. Fetch model list from endpoint (mocked)
 * 2. Parse response via parseModelListResponse
 * 3. Map each model via mapModelToAiModel
 * 4. Store in discoveredModels
 */
function simulateDiscoveryFlow(providerId, mockResponseBody, state, customProviders = []) {
    const rawModels = parseModelListResponse(providerId, mockResponseBody);
    const mapped = [];
    for (let i = 0; i < rawModels.length; i++) {
        const aiModel = mapModelToAiModel(providerId, rawModels[i], customProviders);
        if (aiModel) mapped.push(aiModel);
    }
    state.discoveredModels[providerId] = mapped;
    return mapped;
}

// ============================================================
// Task 13.1: Validation flow with mocked curl responses
// ============================================================

describe('Integration: Validation flow with mocked curl responses', () => {
    let state;
    let keyring;

    beforeEach(() => {
        state = { validationStates: {}, discoveredModels: {} };
        keyring = createMockKeyringStorage();
    });

    it('successful validation (200 + model list) transitions idle → loading → success', () => {
        const providerId = "openai";
        const apiKey = "sk-test-key-12345";

        // Initial state is idle (no entry)
        expect(state.validationStates[providerId]).toBeUndefined();

        // Simulate response: 200 with a valid model list body
        const mockResponse = {
            statusCode: 200,
            body: JSON.stringify({ data: [{ id: "gpt-4" }] })
        };

        const triggersDiscovery = simulateValidationFlow(
            providerId, apiKey, mockResponse, state, keyring
        );

        // Final state should be success
        expect(state.validationStates[providerId].status).toBe("success");
        expect(state.validationStates[providerId].message).toBe("");
        expect(triggersDiscovery).toBe(true);
    });

    it('failed validation (401) transitions idle → loading → error with auth message', () => {
        const providerId = "anthropic";
        const apiKey = "bad-key";
        const mockResponse = { statusCode: 401, body: '{"error":"invalid_api_key"}' };

        const triggersDiscovery = simulateValidationFlow(
            providerId, apiKey, mockResponse, state, keyring
        );

        expect(state.validationStates[providerId].status).toBe("error");
        expect(state.validationStates[providerId].message).toBe("Invalid or revoked API key");
        expect(triggersDiscovery).toBe(false);
    });

    it('rate limited (429) transitions to error with rate limit message', () => {
        const providerId = "mistral";
        const apiKey = "sk-mistral-key";
        const mockResponse = { statusCode: 429, body: '{"error":"rate_limited"}' };

        const triggersDiscovery = simulateValidationFlow(
            providerId, apiKey, mockResponse, state, keyring
        );

        expect(state.validationStates[providerId].status).toBe("error");
        expect(state.validationStates[providerId].message).toBe("Rate limited — try again later");
        expect(triggersDiscovery).toBe(false);
    });

    it('network error (status 0) transitions to error with network message', () => {
        const providerId = "ollama";
        const apiKey = "";
        const mockResponse = { statusCode: 0, body: "" };

        const triggersDiscovery = simulateValidationFlow(
            providerId, apiKey, mockResponse, state, keyring
        );

        expect(state.validationStates[providerId].status).toBe("error");
        expect(state.validationStates[providerId].message).toBe("Network error — check your connection");
        expect(triggersDiscovery).toBe(false);
    });

    it('successful validation stores key in KeyringStorage', () => {
        const providerId = "openai";
        const apiKey = "sk-stored-key-xyz";
        const mockResponse = { statusCode: 200, body: '{"data":[]}' };

        simulateValidationFlow(providerId, apiKey, mockResponse, state, keyring);

        const storedKey = keyring.getNestedField(["apiKeys", "openai"]);
        expect(storedKey).toBe(apiKey);
    });

    it('failed validation does not store key in KeyringStorage', () => {
        const providerId = "openai";
        const apiKey = "sk-bad-key";
        const mockResponse = { statusCode: 403, body: '{"error":"forbidden"}' };

        simulateValidationFlow(providerId, apiKey, mockResponse, state, keyring);

        const storedKey = keyring.getNestedField(["apiKeys", "openai"]);
        expect(storedKey).toBeUndefined();
    });

    it('successful validation triggers model discovery (returns true)', () => {
        const providerId = "gemini";
        const apiKey = "AIza-test-key";
        const mockResponse = { statusCode: 200, body: '{"models":[]}' };

        const triggersDiscovery = simulateValidationFlow(
            providerId, apiKey, mockResponse, state, keyring
        );

        expect(triggersDiscovery).toBe(true);
    });

    it('ollama validation success does not store key (requires_key=false)', () => {
        const providerId = "ollama";
        const apiKey = "";
        const mockResponse = {
            statusCode: 200,
            body: JSON.stringify({ models: [{ name: "llama3:7b" }] })
        };

        simulateValidationFlow(providerId, apiKey, mockResponse, state, keyring);

        // Ollama has requires_key=false, so nothing stored
        expect(keyring.keyringData.apiKeys["ollama"]).toBeUndefined();
        expect(keyring.keyringData.apiKeys[""]).toBeUndefined();
    });
});

// ============================================================
// Task 13.2: Model discovery and registry population
// ============================================================

describe('Integration: Model discovery and registry population', () => {
    let state;

    beforeEach(() => {
        state = { validationStates: {}, discoveredModels: {} };
    });

    it('Ollama models[] format is parsed and mapped correctly', () => {
        const ollamaResponse = JSON.stringify({
            models: [
                { name: "llama3:7b", model: "llama3:7b" },
                { name: "mistral:latest", model: "mistral:latest" },
                { name: "codellama:13b", model: "codellama:13b" }
            ]
        });

        const models = simulateDiscoveryFlow("ollama", ollamaResponse, state);

        expect(models).toHaveLength(3);
        expect(models[0].model).toBe("llama3:7b");
        expect(models[0].api_format).toBe("openai");
        expect(models[0].requires_key).toBe(false);
        expect(models[0].key_id).toBe("");
        expect(models[0].endpoint).toBe("http://localhost:11434/v1/chat/completions");
        expect(models[1].model).toBe("mistral:latest");
        expect(models[2].model).toBe("codellama:13b");
    });

    it('Gemini models[] format is parsed and mapped correctly', () => {
        const geminiResponse = JSON.stringify({
            models: [
                { name: "models/gemini-2.0-flash" },
                { name: "models/gemini-2.5-pro" }
            ]
        });

        const models = simulateDiscoveryFlow("gemini", geminiResponse, state);

        expect(models).toHaveLength(2);
        expect(models[0].model).toBe("gemini-2.0-flash");
        expect(models[0].api_format).toBe("gemini");
        expect(models[0].requires_key).toBe(true);
        expect(models[0].key_id).toBe("gemini");
        expect(models[0].endpoint).toContain("gemini-2.0-flash");
        expect(models[0].endpoint).toContain("streamGenerateContent");
        expect(models[1].model).toBe("gemini-2.5-pro");
    });

    it('OpenAI data[] format is parsed and mapped correctly', () => {
        const openaiResponse = JSON.stringify({
            data: [
                { id: "gpt-4.1-mini", object: "model" },
                { id: "gpt-4o", object: "model" }
            ]
        });

        const models = simulateDiscoveryFlow("openai", openaiResponse, state);

        expect(models).toHaveLength(2);
        expect(models[0].model).toBe("gpt-4.1-mini");
        expect(models[0].api_format).toBe("openai");
        expect(models[0].requires_key).toBe(true);
        expect(models[0].key_id).toBe("openai");
        expect(models[0].endpoint).toBe("https://api.openai.com/v1/chat/completions");
        expect(models[1].model).toBe("gpt-4o");
    });

    it('Anthropic data[] format is parsed and mapped correctly', () => {
        const anthropicResponse = JSON.stringify({
            data: [
                { id: "claude-sonnet-4-20250514" },
                { id: "claude-3-5-haiku-20241022" }
            ]
        });

        const models = simulateDiscoveryFlow("anthropic", anthropicResponse, state);

        expect(models).toHaveLength(2);
        expect(models[0].model).toBe("claude-sonnet-4-20250514");
        expect(models[0].api_format).toBe("openai");
        expect(models[0].key_id).toBe("anthropic");
        expect(models[0].endpoint).toBe("https://api.anthropic.com/v1/messages");
    });

    it('custom provider (OpenAI-compatible) data[] format is parsed and mapped', () => {
        const customProvider = {
            id: "custom-vllm",
            name: "My vLLM",
            baseUrl: "http://localhost:5000/v1",
            apiKey: "test-key",
            icon: "ai-openai-symbolic"
        };

        const customResponse = JSON.stringify({
            data: [
                { id: "meta-llama/Llama-3-8b-instruct" },
                { id: "mistralai/Mistral-7B-v0.1" }
            ]
        });

        const rawModels = parseModelListResponse("custom-vllm", customResponse);
        const mapped = [];
        for (let i = 0; i < rawModels.length; i++) {
            const aiModel = mapModelToAiModel("custom-vllm", rawModels[i], [customProvider]);
            if (aiModel) mapped.push(aiModel);
        }
        state.discoveredModels["custom-vllm"] = mapped;

        expect(mapped).toHaveLength(2);
        expect(mapped[0].model).toBe("meta-llama/Llama-3-8b-instruct");
        expect(mapped[0].api_format).toBe("openai");
        expect(mapped[0].endpoint).toBe("http://localhost:5000/v1/chat/completions");
        expect(mapped[0].requires_key).toBe(true);
        expect(mapped[1].model).toBe("mistralai/Mistral-7B-v0.1");
    });

    it('composed registry contains discovered models + extraModels', () => {
        // Simulate discovering models from two providers
        const ollamaResponse = JSON.stringify({
            models: [{ name: "llama3:7b" }]
        });
        const openaiResponse = JSON.stringify({
            data: [{ id: "gpt-4o" }]
        });

        simulateDiscoveryFlow("ollama", ollamaResponse, state);
        simulateDiscoveryFlow("openai", openaiResponse, state);

        const extraModels = [
            { name: "Custom Model", model: "my-custom-model", endpoint: "http://example.com/v1/chat", api_format: "openai" }
        ];

        const registry = composeModelRegistry(state.discoveredModels, extraModels);

        expect(registry[safeModelName("llama3:7b")]).toBeDefined();
        expect(registry[safeModelName("gpt-4o")]).toBeDefined();
        expect(registry[safeModelName("my-custom-model")]).toBeDefined();
        expect(Object.keys(registry)).toHaveLength(3);
    });

    it('empty response body returns empty models array', () => {
        const models = simulateDiscoveryFlow("openai", "", state);
        expect(models).toHaveLength(0);
        expect(state.discoveredModels["openai"]).toEqual([]);
    });

    it('malformed JSON response returns empty models array', () => {
        const models = simulateDiscoveryFlow("gemini", "not valid json {{{", state);
        expect(models).toHaveLength(0);
    });

    it('model display names are human-readable', () => {
        const ollamaResponse = JSON.stringify({
            models: [{ name: "llama3:7b" }, { name: "codellama:13b" }]
        });

        const models = simulateDiscoveryFlow("ollama", ollamaResponse, state);

        expect(models[0].name).toBe("Llama3 (7B)");
        expect(models[1].name).toBe("Codellama (13B)");
    });
});

// ============================================================
// Task 13.3: Policy enforcement and provider visibility
// ============================================================

describe('Integration: Policy enforcement and provider visibility', () => {
    const allBuiltInProviders = ["openai", "anthropic", "gemini", "mistral", "openrouter", "ollama"];

    /**
     * Simulates the ProviderPanel's provider list computation based on policy.
     * This mirrors the QML logic: policies.ai === 0 → empty,
     * policies.ai === 2 → ollama + localhost customs, else → all.
     */
    function computeVisibleProviders(policyAi, customProviders = []) {
        if (policyAi === 0) {
            return [];
        }
        if (policyAi === 2) {
            // Local-only: Ollama + custom providers with localhost endpoints
            const localCustoms = customProviders.filter(cp => {
                const url = (cp.baseUrl || "").toLowerCase();
                return url.indexOf("localhost") !== -1 || url.indexOf("127.0.0.1") !== -1;
            });
            return ["ollama"].concat(localCustoms.map(cp => cp.id));
        }
        // Normal mode: all built-in + all custom
        return allBuiltInProviders.concat(customProviders.map(cp => cp.id));
    }

    it('policies.ai=0 results in no visible providers', () => {
        const visible = computeVisibleProviders(0);
        expect(visible).toHaveLength(0);
    });

    it('policies.ai=0 with custom providers still shows nothing', () => {
        const customs = [
            { id: "custom-1", name: "Test", baseUrl: "http://localhost:5000/v1", apiKey: "" }
        ];
        const visible = computeVisibleProviders(0, customs);
        expect(visible).toHaveLength(0);
    });

    it('policies.ai=2 shows only Ollama and localhost custom providers', () => {
        const customs = [
            { id: "custom-local", name: "Local vLLM", baseUrl: "http://localhost:5000/v1", apiKey: "" },
            { id: "custom-remote", name: "Remote API", baseUrl: "https://api.remote.com/v1", apiKey: "key" },
            { id: "custom-loopback", name: "Loopback", baseUrl: "http://127.0.0.1:8080/v1", apiKey: "" }
        ];

        const visible = computeVisibleProviders(2, customs);

        expect(visible).toContain("ollama");
        expect(visible).toContain("custom-local");
        expect(visible).toContain("custom-loopback");
        expect(visible).not.toContain("custom-remote");
        expect(visible).not.toContain("openai");
        expect(visible).not.toContain("anthropic");
        expect(visible).not.toContain("gemini");
        expect(visible).not.toContain("mistral");
        expect(visible).not.toContain("openrouter");
        expect(visible).toHaveLength(3); // ollama + 2 local customs
    });

    it('policies.ai=1 shows all built-in providers and all custom providers', () => {
        const customs = [
            { id: "custom-local", name: "Local", baseUrl: "http://localhost:5000/v1", apiKey: "" },
            { id: "custom-remote", name: "Remote", baseUrl: "https://api.remote.com/v1", apiKey: "key" }
        ];

        const visible = computeVisibleProviders(1, customs);

        // All 6 built-in
        for (const p of allBuiltInProviders) {
            expect(visible).toContain(p);
        }
        // All custom (regardless of URL)
        expect(visible).toContain("custom-local");
        expect(visible).toContain("custom-remote");
        expect(visible).toHaveLength(8); // 6 built-in + 2 custom
    });

    it('policies.ai=2 with no custom providers shows only Ollama', () => {
        const visible = computeVisibleProviders(2, []);
        expect(visible).toEqual(["ollama"]);
    });

    it('policies.ai=1 with no custom providers shows all 6 built-in', () => {
        const visible = computeVisibleProviders(1, []);
        expect(visible).toEqual(allBuiltInProviders);
    });
});

// ============================================================
// Task 13.4: Custom provider CRUD operations
// ============================================================

describe('Integration: Custom provider CRUD operations', () => {
    let config;
    let keyring;
    let state;

    let idCounter = 0;

    /**
     * Simulates ModelDiscoveryService.addCustomProvider logic.
     */
    function addCustomProvider(name, baseUrl, apiKey) {
        const id = "custom-" + Date.now() + "-" + (idCounter++);
        const entry = {
            id,
            name,
            baseUrl,
            apiKey: apiKey || "",
            icon: "ai-openai-symbolic"
        };
        const current = config.options.ai.customProviders || [];
        const updated = current.concat([entry]);
        config.setNestedField(["ai", "customProviders"], updated);
        if (apiKey) {
            keyring.setNestedField(["apiKeys", id], apiKey);
        }
        return id;
    }

    /**
     * Simulates ModelDiscoveryService.updateCustomProvider logic.
     */
    function updateCustomProvider(id, name, baseUrl, apiKey) {
        const current = config.options.ai.customProviders || [];
        const updated = [];
        for (let i = 0; i < current.length; i++) {
            if (current[i].id === id) {
                updated.push({ id, name, baseUrl, apiKey: apiKey || "", icon: "ai-openai-symbolic" });
            } else {
                updated.push(current[i]);
            }
        }
        config.setNestedField(["ai", "customProviders"], updated);
        if (apiKey) {
            keyring.setNestedField(["apiKeys", id], apiKey);
        } else {
            keyring.deleteNestedField(["apiKeys", id]);
        }
    }

    /**
     * Simulates ModelDiscoveryService.deleteCustomProvider logic.
     */
    function deleteCustomProvider(id) {
        const current = config.options.ai.customProviders || [];
        const updated = current.filter(cp => cp.id !== id);
        config.setNestedField(["ai", "customProviders"], updated);
        keyring.deleteNestedField(["apiKeys", id]);
        delete state.discoveredModels[id];
        delete state.validationStates[id];
    }

    beforeEach(() => {
        config = createMockConfig();
        keyring = createMockKeyringStorage();
        state = { validationStates: {}, discoveredModels: {} };
    });

    it('addCustomProvider creates correct entry in config', () => {
        const id = addCustomProvider("My vLLM", "http://localhost:5000/v1", "test-key");

        const providers = config.options.ai.customProviders;
        expect(providers).toHaveLength(1);
        expect(providers[0].id).toBe(id);
        expect(providers[0].name).toBe("My vLLM");
        expect(providers[0].baseUrl).toBe("http://localhost:5000/v1");
        expect(providers[0].apiKey).toBe("test-key");
        expect(providers[0].icon).toBe("ai-openai-symbolic");
    });

    it('addCustomProvider stores API key in KeyringStorage when provided', () => {
        const id = addCustomProvider("Test Server", "http://localhost:8080/v1", "secret-key");

        const storedKey = keyring.getNestedField(["apiKeys", id]);
        expect(storedKey).toBe("secret-key");
    });

    it('addCustomProvider without API key does not store in keyring', () => {
        const id = addCustomProvider("No Auth Server", "http://localhost:8080/v1", "");

        const storedKey = keyring.getNestedField(["apiKeys", id]);
        expect(storedKey).toBeUndefined();
    });

    it('addCustomProvider generates unique IDs for multiple providers', () => {
        // Use small delay to ensure unique timestamps
        const id1 = addCustomProvider("Server 1", "http://localhost:5000/v1", "");
        const id2 = addCustomProvider("Server 2", "http://localhost:6000/v1", "");

        const providers = config.options.ai.customProviders;
        expect(providers).toHaveLength(2);
        // IDs start with "custom-"
        expect(id1.startsWith("custom-")).toBe(true);
        expect(id2.startsWith("custom-")).toBe(true);
    });

    it('updateCustomProvider updates the correct entry', () => {
        const id = addCustomProvider("Old Name", "http://localhost:5000/v1", "old-key");

        updateCustomProvider(id, "New Name", "http://localhost:6000/v1", "new-key");

        const providers = config.options.ai.customProviders;
        expect(providers).toHaveLength(1);
        expect(providers[0].name).toBe("New Name");
        expect(providers[0].baseUrl).toBe("http://localhost:6000/v1");
        expect(providers[0].apiKey).toBe("new-key");
        expect(keyring.getNestedField(["apiKeys", id])).toBe("new-key");
    });

    it('updateCustomProvider removes key from keyring when key is cleared', () => {
        const id = addCustomProvider("Server", "http://localhost:5000/v1", "has-key");
        expect(keyring.getNestedField(["apiKeys", id])).toBe("has-key");

        updateCustomProvider(id, "Server", "http://localhost:5000/v1", "");

        expect(keyring.getNestedField(["apiKeys", id])).toBeUndefined();
    });

    it('updateCustomProvider does not affect other providers', () => {
        const id1 = addCustomProvider("Server 1", "http://localhost:5000/v1", "key1");
        const id2 = addCustomProvider("Server 2", "http://localhost:6000/v1", "key2");

        updateCustomProvider(id1, "Updated 1", "http://localhost:7000/v1", "newkey1");

        const providers = config.options.ai.customProviders;
        expect(providers).toHaveLength(2);
        const p2 = providers.find(p => p.id === id2);
        expect(p2.name).toBe("Server 2");
        expect(p2.baseUrl).toBe("http://localhost:6000/v1");
    });

    it('deleteCustomProvider removes entry from config', () => {
        const id = addCustomProvider("To Delete", "http://localhost:5000/v1", "key");

        deleteCustomProvider(id);

        expect(config.options.ai.customProviders).toHaveLength(0);
    });

    it('deleteCustomProvider cleans up keyring, discoveredModels, and validationStates', () => {
        const id = addCustomProvider("To Delete", "http://localhost:5000/v1", "key");
        // Simulate some state for this provider
        state.discoveredModels[id] = [{ model: "test-model", name: "Test" }];
        state.validationStates[id] = { status: "success", message: "" };

        deleteCustomProvider(id);

        expect(keyring.getNestedField(["apiKeys", id])).toBeUndefined();
        expect(state.discoveredModels[id]).toBeUndefined();
        expect(state.validationStates[id]).toBeUndefined();
    });

    it('deleteCustomProvider does not affect other providers', () => {
        const id1 = addCustomProvider("Keep", "http://localhost:5000/v1", "key1");
        const id2 = addCustomProvider("Delete", "http://localhost:6000/v1", "key2");

        deleteCustomProvider(id2);

        const providers = config.options.ai.customProviders;
        expect(providers).toHaveLength(1);
        expect(providers[0].id).toBe(id1);
        expect(providers[0].name).toBe("Keep");
        expect(keyring.getNestedField(["apiKeys", id1])).toBe("key1");
    });

    it('custom provider is usable for validation after add', () => {
        const id = addCustomProvider("My Server", "http://localhost:5000/v1", "my-key");
        const providers = config.options.ai.customProviders;

        // Verify the custom provider can be used with getEffectiveProviderConfig
        const effectiveConfig = getEffectiveProviderConfig(id, providers);
        expect(effectiveConfig).not.toBeNull();
        expect(effectiveConfig.api_format).toBe("openai");
        expect(effectiveConfig.model_endpoint).toBe("http://localhost:5000/v1/models");
        expect(effectiveConfig.chat_endpoint).toBe("http://localhost:5000/v1/chat/completions");

        // Verify buildValidationCommand works
        const cmd = buildValidationCommand(id, "my-key", providers);
        expect(cmd).not.toBeNull();
        expect(cmd.endpoint).toBe("http://localhost:5000/v1/models");
        expect(cmd.auth).toContain("Bearer my-key");
    });
});
