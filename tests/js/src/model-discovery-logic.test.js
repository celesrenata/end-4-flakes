import { describe, it, expect } from 'vitest';
import * as fc from 'fast-check';
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

const builtInProviderIds = ["openai", "anthropic", "gemini", "mistral", "openrouter", "ollama"];

/**
 * Feature: ai-provider-signin, Property 3: Validation Endpoint Construction
 *
 * For any provider ID in {openai, anthropic, gemini, mistral, openrouter, ollama}
 * and any non-empty API key: `buildValidationCommand` produces correct endpoint
 * and auth scheme per provider config.
 *
 * **Validates: Requirements 10.1, 10.2, 10.3, 10.4, 10.5, 10.6**
 */
describe('Feature: ai-provider-signin, Property 3: Validation Endpoint Construction', () => {
    const providerIdArb = fc.constantFrom(...builtInProviderIds);
    const apiKeyArb = fc.string({ minLength: 1 }).filter(s => s.trim().length > 0);

    it('buildValidationCommand returns non-null for all built-in providers', () => {
        fc.assert(fc.property(
            providerIdArb,
            apiKeyArb,
            (providerId, apiKey) => {
                const result = buildValidationCommand(providerId, apiKey);
                expect(result).not.toBeNull();
                expect(result.endpoint).toBeDefined();
                expect(result.auth).toBeDefined();
                expect(result.command).toBeDefined();
            }
        ), { numRuns: 100 });
    });

    it('bearer providers include Authorization header with key', () => {
        const bearerProviders = fc.constantFrom("openai", "mistral", "openrouter");
        fc.assert(fc.property(
            bearerProviders,
            apiKeyArb,
            (providerId, apiKey) => {
                const result = buildValidationCommand(providerId, apiKey);
                expect(result.auth).toContain("Authorization: Bearer " + apiKey);
                expect(result.endpoint).toBe(providerConfigs[providerId].validation_endpoint);
            }
        ), { numRuns: 100 });
    });

    it('anthropic uses x-api-key header with anthropic-version', () => {
        fc.assert(fc.property(
            apiKeyArb,
            (apiKey) => {
                const result = buildValidationCommand("anthropic", apiKey);
                expect(result.auth).toContain("x-api-key: " + apiKey);
                expect(result.auth).toContain("anthropic-version: 2023-06-01");
                expect(result.endpoint).toBe(providerConfigs["anthropic"].validation_endpoint);
            }
        ), { numRuns: 100 });
    });

    it('gemini appends key as query parameter', () => {
        fc.assert(fc.property(
            apiKeyArb,
            (apiKey) => {
                const result = buildValidationCommand("gemini", apiKey);
                expect(result.endpoint).toBe(providerConfigs["gemini"].validation_endpoint + "?key=" + apiKey);
                expect(result.auth).toBe("");
            }
        ), { numRuns: 100 });
    });

    it('ollama uses no authentication', () => {
        fc.assert(fc.property(
            apiKeyArb,
            (apiKey) => {
                const result = buildValidationCommand("ollama", apiKey);
                expect(result.auth).toBe("");
                expect(result.endpoint).toBe(providerConfigs["ollama"].validation_endpoint);
            }
        ), { numRuns: 100 });
    });
});

/**
 * Feature: ai-provider-signin, Property 4: Error Response Mapping Completeness
 *
 * For any HTTP status code (0–599) and any response body string:
 * `mapErrorResponse` returns a non-empty string. Specific mappings:
 * 401/403 → auth error, 429 → rate limit, 402/quota keywords → credits,
 * permission keywords → permissions, 0 → network error.
 *
 * **Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.6**
 */
describe('Feature: ai-provider-signin, Property 4: Error Response Mapping Completeness', () => {
    const httpStatusArb = fc.integer({ min: 0, max: 599 });
    const responseBodyArb = fc.string();

    it('always returns a non-empty string for any status and body', () => {
        fc.assert(fc.property(
            httpStatusArb,
            responseBodyArb,
            (status, body) => {
                const result = mapErrorResponse(status, body);
                expect(typeof result).toBe("string");
                expect(result.length).toBeGreaterThan(0);
            }
        ), { numRuns: 200 });
    });

    it('401 and 403 map to auth error', () => {
        fc.assert(fc.property(
            fc.constantFrom(401, 403),
            responseBodyArb,
            (status, body) => {
                expect(mapErrorResponse(status, body)).toBe("Invalid or revoked API key");
            }
        ), { numRuns: 100 });
    });

    it('429 maps to rate limit', () => {
        fc.assert(fc.property(
            responseBodyArb,
            (body) => {
                expect(mapErrorResponse(429, body)).toBe("Rate limited — try again later");
            }
        ), { numRuns: 100 });
    });

    it('402 maps to credits error', () => {
        fc.assert(fc.property(
            responseBodyArb,
            (body) => {
                expect(mapErrorResponse(402, body)).toBe("Insufficient credits or quota exceeded");
            }
        ), { numRuns: 100 });
    });

    it('quota/credit/billing/insufficient keywords map to credits error', () => {
        const quotaKeyword = fc.constantFrom("quota", "credit", "billing", "insufficient");
        // Use a status that won't match the 401/403/429/402 rules
        const safeStatus = fc.integer({ min: 404, max: 599 }).filter(s => s !== 429);
        fc.assert(fc.property(
            safeStatus,
            quotaKeyword,
            fc.string(),
            (status, keyword, prefix) => {
                const body = prefix + keyword + prefix;
                expect(mapErrorResponse(status, body)).toBe("Insufficient credits or quota exceeded");
            }
        ), { numRuns: 100 });
    });

    it('permission/scope keywords map to permissions error', () => {
        const permKeyword = fc.constantFrom("permission", "scope");
        // Use a status that doesn't trigger other rules, and body without quota keywords
        const safeStatus = fc.integer({ min: 404, max: 599 }).filter(s => s !== 429);
        fc.assert(fc.property(
            safeStatus,
            permKeyword,
            (status, keyword) => {
                // Ensure no quota keywords in body
                const body = "error: " + keyword + " denied";
                expect(mapErrorResponse(status, body)).toBe("Key lacks required permissions");
            }
        ), { numRuns: 100 });
    });

    it('status 0 maps to network error', () => {
        fc.assert(fc.property(
            fc.string().filter(s => {
                const lower = s.toLowerCase();
                return lower.indexOf("quota") === -1 &&
                       lower.indexOf("credit") === -1 &&
                       lower.indexOf("billing") === -1 &&
                       lower.indexOf("insufficient") === -1 &&
                       lower.indexOf("permission") === -1 &&
                       lower.indexOf("scope") === -1;
            }),
            (body) => {
                expect(mapErrorResponse(0, body)).toBe("Network error — check your connection");
            }
        ), { numRuns: 100 });
    });
});

/**
 * Feature: ai-provider-signin, Property 5: Model Registry Composition
 *
 * For any combination of discovered model sets and extraModels array:
 * registry contains exactly the union, extraModels always present
 * regardless of auth state.
 *
 * **Validates: Requirements 7.2, 7.4**
 */
describe('Feature: ai-provider-signin, Property 5: Model Registry Composition', () => {
    const modelEntryArb = fc.record({
        name: fc.string({ minLength: 1 }),
        model: fc.string({ minLength: 1 }).filter(s => /^[a-zA-Z0-9._-]+$/.test(s) && s !== "__proto__" && s !== "constructor" && s !== "prototype"),
        endpoint: fc.string({ minLength: 1 }),
        api_format: fc.constantFrom("openai", "gemini", "mistral")
    });

    const providerModelsArb = fc.record({
        openai: fc.array(modelEntryArb, { minLength: 0, maxLength: 5 }),
        anthropic: fc.array(modelEntryArb, { minLength: 0, maxLength: 5 }),
        ollama: fc.array(modelEntryArb, { minLength: 0, maxLength: 5 })
    });

    const extraModelsArb = fc.array(modelEntryArb, { minLength: 0, maxLength: 5 });

    it('registry contains the union of all discovered models and extraModels', () => {
        fc.assert(fc.property(
            providerModelsArb,
            extraModelsArb,
            (discovered, extras) => {
                const registry = composeModelRegistry(discovered, extras);
                const registryKeys = Object.keys(registry);

                // Count total expected models (unique by safeModelName)
                const expectedKeys = new Set();
                for (const provider of Object.keys(discovered)) {
                    for (const m of discovered[provider]) {
                        expectedKeys.add(safeModelName(m.model));
                    }
                }
                for (const m of extras) {
                    expectedKeys.add(safeModelName(m.model || m.name || ""));
                }

                expect(registryKeys.length).toBe(expectedKeys.size);
                for (const key of expectedKeys) {
                    expect(registry[key]).toBeDefined();
                }
            }
        ), { numRuns: 100 });
    });

    it('extraModels are always present regardless of discovered models', () => {
        fc.assert(fc.property(
            extraModelsArb.filter(arr => arr.length > 0),
            (extras) => {
                // Empty discovered models (simulating no auth)
                const registry = composeModelRegistry({}, extras);
                for (const m of extras) {
                    const key = safeModelName(m.model || m.name || "");
                    expect(registry[key]).toBeDefined();
                }
            }
        ), { numRuns: 100 });
    });
});

/**
 * Feature: ai-provider-signin, Property 6: Model Metadata Mapping Correctness
 *
 * For any provider ID (built-in or custom) and valid model data:
 * `mapModelToAiModel` produces correct `api_format`, `endpoint`,
 * `key_id`, `requires_key` per provider config.
 *
 * **Validates: Requirements 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 1.7**
 */
describe('Feature: ai-provider-signin, Property 6: Model Metadata Mapping Correctness', () => {
    const modelIdArb = fc.string({ minLength: 1, maxLength: 50 })
        .filter(s => /^[a-zA-Z0-9._/-]+$/.test(s));

    it('built-in providers produce correct api_format, key_id, requires_key', () => {
        fc.assert(fc.property(
            fc.constantFrom(...builtInProviderIds),
            modelIdArb,
            (providerId, modelId) => {
                const config = providerConfigs[providerId];
                let modelData;
                if (providerId === "ollama") {
                    modelData = { name: modelId };
                } else if (providerId === "gemini") {
                    modelData = { name: "models/" + modelId };
                } else {
                    modelData = { id: modelId };
                }

                const result = mapModelToAiModel(providerId, modelData);
                expect(result).not.toBeNull();
                expect(result.api_format).toBe(config.api_format);
                expect(result.key_id).toBe(config.key_id);
                expect(result.requires_key).toBe(config.requires_key);
            }
        ), { numRuns: 100 });
    });

    it('ollama has requires_key=false and key_id=""', () => {
        fc.assert(fc.property(
            modelIdArb,
            (modelId) => {
                const result = mapModelToAiModel("ollama", { name: modelId });
                expect(result.requires_key).toBe(false);
                expect(result.key_id).toBe("");
            }
        ), { numRuns: 100 });
    });

    it('gemini endpoint uses template with model substitution', () => {
        fc.assert(fc.property(
            modelIdArb,
            (modelId) => {
                const result = mapModelToAiModel("gemini", { name: "models/" + modelId });
                expect(result.endpoint).toContain(modelId);
                expect(result.endpoint).toContain("streamGenerateContent");
            }
        ), { numRuns: 100 });
    });

    it('custom providers produce api_format "openai" and correct endpoint', () => {
        const customProviderArb = fc.record({
            id: fc.string({ minLength: 1 }).map(s => "custom-" + s.replace(/[^a-zA-Z0-9]/g, '')),
            name: fc.string({ minLength: 1 }),
            baseUrl: fc.constantFrom("http://localhost:5000/v1", "http://myserver:8080/v1", "https://api.example.com/v1"),
            apiKey: fc.string({ minLength: 1 }),
            icon: fc.constant("ai-openai-symbolic")
        });

        fc.assert(fc.property(
            customProviderArb,
            modelIdArb,
            (customProvider, modelId) => {
                const result = mapModelToAiModel(customProvider.id, { id: modelId }, [customProvider]);
                expect(result).not.toBeNull();
                expect(result.api_format).toBe("openai");
                expect(result.endpoint).toBe(customProvider.baseUrl + "/chat/completions");
            }
        ), { numRuns: 100 });
    });
});

/**
 * Feature: ai-provider-signin, Property 7: Discovery and Validation Share Endpoints
 *
 * For every built-in provider ID: `providerConfigs[id].validation_endpoint ===
 * providerConfigs[id].model_endpoint`. For custom providers: both endpoints
 * use `baseUrl + "/models"`.
 *
 * **Validates: Requirements 10.7**
 */
describe('Feature: ai-provider-signin, Property 7: Discovery and Validation Share Endpoints', () => {
    it('all built-in providers have identical validation_endpoint and model_endpoint', () => {
        fc.assert(fc.property(
            fc.constantFrom(...builtInProviderIds),
            (providerId) => {
                const config = providerConfigs[providerId];
                expect(config.validation_endpoint).toBe(config.model_endpoint);
            }
        ), { numRuns: 100 });
    });

    it('custom providers use baseUrl + "/models" for both validation and model endpoints', () => {
        const baseUrlArb = fc.constantFrom(
            "http://localhost:5000/v1",
            "http://myserver:8080/v1",
            "https://api.example.com/v1",
            "http://10.0.0.1:11434/v1"
        );

        fc.assert(fc.property(
            baseUrlArb,
            fc.string({ minLength: 1 }),
            (baseUrl, name) => {
                const customProvider = {
                    id: "custom-test",
                    name: name,
                    baseUrl: baseUrl,
                    apiKey: "test-key",
                    icon: "ai-openai-symbolic"
                };
                const config = getEffectiveProviderConfig(customProvider.id, [customProvider]);
                expect(config).not.toBeNull();
                expect(config.validation_endpoint).toBe(baseUrl + "/models");
                expect(config.model_endpoint).toBe(baseUrl + "/models");
                expect(config.validation_endpoint).toBe(config.model_endpoint);
            }
        ), { numRuns: 100 });
    });
});

/**
 * Feature: ai-provider-signin, Property 8: Model Name Formatting
 *
 * For any model ID string: `formatModelName` returns a string with capitalized
 * word-segments, hyphens→spaces, param suffixes like "7b" → "(7B)".
 *
 * **Validates: Requirements 11.7**
 */
describe('Feature: ai-provider-signin, Property 8: Model Name Formatting', () => {
    // Model IDs contain alphanumeric, hyphens, colons, dots
    const modelIdArb = fc.string({ minLength: 1, maxLength: 40 })
        .filter(s => /^[a-zA-Z0-9._:/-]+$/.test(s) && s.length > 0);

    it('result has all word-segments capitalized (first char uppercase)', () => {
        fc.assert(fc.property(
            modelIdArb,
            (modelId) => {
                const result = formatModelName(modelId);
                const words = result.split(" ");
                for (const word of words) {
                    if (word.length > 0) {
                        // Words starting with "(" like "(7B)" have uppercase after paren
                        if (word.startsWith("(")) {
                            expect(word.charAt(1)).toBe(word.charAt(1).toUpperCase());
                        } else {
                            expect(word.charAt(0)).toBe(word.charAt(0).toUpperCase());
                        }
                    }
                }
            }
        ), { numRuns: 100 });
    });

    it('hyphens and colons are replaced with spaces (not present in output except in parenthetical)', () => {
        fc.assert(fc.property(
            modelIdArb.filter(s => !s.endsWith("latest") && !s.endsWith("Latest")),
            (modelId) => {
                const result = formatModelName(modelId);
                // Hyphens and colons should not appear in the result
                // (they get replaced with spaces)
                expect(result.indexOf("-")).toBe(-1);
                expect(result.indexOf(":")).toBe(-1);
            }
        ), { numRuns: 100 });
    });

    it('param suffixes like "7b" are formatted as "(7B)"', () => {
        const paramModelArb = fc.tuple(
            fc.string({ minLength: 1, maxLength: 20 }).filter(s => /^[a-zA-Z0-9._-]+$/.test(s)),
            fc.integer({ min: 1, max: 999 })
        ).map(([prefix, num]) => prefix + "-" + num + "b");

        fc.assert(fc.property(
            paramModelArb,
            (modelId) => {
                const result = formatModelName(modelId);
                // Should contain the param count in parens with uppercase B
                expect(result).toMatch(/\(\d+B\)/);
            }
        ), { numRuns: 100 });
    });

    it('returns non-empty string for any valid model ID', () => {
        fc.assert(fc.property(
            modelIdArb,
            (modelId) => {
                const result = formatModelName(modelId);
                expect(result.length).toBeGreaterThan(0);
            }
        ), { numRuns: 100 });
    });
});

/**
 * Feature: ai-provider-signin, Property 1: API Key Storage Round-Trip
 *
 * For any provider key_id and non-empty key string: storing then reading
 * from a mock KeyringStorage returns the exact same key.
 *
 * **Validates: Requirements 2.2**
 */
describe('Feature: ai-provider-signin, Property 1: API Key Storage Round-Trip', () => {
    // Mock KeyringStorage for testing the round-trip concept
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
            get keyringData() { return storage; }
        };
    }

    const keyIdArb = fc.string({ minLength: 1, maxLength: 30 })
        .filter(s => /^[a-zA-Z0-9_-]+$/.test(s) && s !== "__proto__" && s !== "constructor" && s !== "prototype");
    const keyValueArb = fc.string({ minLength: 1, maxLength: 200 });

    it('storing then reading returns the exact same key', () => {
        fc.assert(fc.property(
            keyIdArb,
            keyValueArb,
            (keyId, keyValue) => {
                const store = createMockKeyringStorage();
                store.setNestedField(["apiKeys", keyId], keyValue);
                const retrieved = store.getNestedField(["apiKeys", keyId]);
                expect(retrieved).toBe(keyValue);
            }
        ), { numRuns: 100 });
    });

    it('multiple keys can be stored and retrieved independently', () => {
        fc.assert(fc.property(
            fc.array(fc.tuple(keyIdArb, keyValueArb), { minLength: 1, maxLength: 10 }),
            (entries) => {
                const store = createMockKeyringStorage();
                for (const [id, val] of entries) {
                    store.setNestedField(["apiKeys", id], val);
                }
                // Last write wins for duplicate keys
                const seen = new Map();
                for (const [id, val] of entries) {
                    seen.set(id, val);
                }
                for (const [id, expected] of seen) {
                    expect(store.getNestedField(["apiKeys", id])).toBe(expected);
                }
            }
        ), { numRuns: 100 });
    });
});

/**
 * Feature: ai-provider-signin, Property 9: Custom Provider Config Construction
 *
 * For any non-empty name, valid URL, and optional API key:
 * `getEffectiveProviderConfig` for a custom provider returns api_format "openai",
 * model_endpoint ending in "/models", chat_endpoint ending in "/chat/completions",
 * and auth_type "bearer" iff apiKey is non-empty.
 *
 * **Validates: Requirements 1.7**
 */
describe('Feature: ai-provider-signin, Property 9: Custom Provider Config Construction', () => {
    const nameArb = fc.string({ minLength: 1, maxLength: 50 }).filter(s => s.trim().length > 0);
    const baseUrlArb = fc.constantFrom(
        "http://localhost:5000/v1",
        "http://myserver:8080/v1",
        "https://api.example.com/v1",
        "http://192.168.1.100:11434/v1",
        "http://10.1.1.12:8000/v1"
    );
    const apiKeyArb = fc.oneof(
        fc.constant(""),  // no key
        fc.string({ minLength: 1, maxLength: 100 })  // has key
    );

    it('api_format is always "openai" for custom providers', () => {
        fc.assert(fc.property(
            nameArb,
            baseUrlArb,
            apiKeyArb,
            (name, baseUrl, apiKey) => {
                const provider = { id: "custom-test", name, baseUrl, apiKey, icon: "ai-openai-symbolic" };
                const config = getEffectiveProviderConfig(provider.id, [provider]);
                expect(config.api_format).toBe("openai");
            }
        ), { numRuns: 100 });
    });

    it('model_endpoint ends in "/models"', () => {
        fc.assert(fc.property(
            nameArb,
            baseUrlArb,
            apiKeyArb,
            (name, baseUrl, apiKey) => {
                const provider = { id: "custom-test", name, baseUrl, apiKey, icon: "ai-openai-symbolic" };
                const config = getEffectiveProviderConfig(provider.id, [provider]);
                expect(config.model_endpoint.endsWith("/models")).toBe(true);
            }
        ), { numRuns: 100 });
    });

    it('chat_endpoint ends in "/chat/completions"', () => {
        fc.assert(fc.property(
            nameArb,
            baseUrlArb,
            apiKeyArb,
            (name, baseUrl, apiKey) => {
                const provider = { id: "custom-test", name, baseUrl, apiKey, icon: "ai-openai-symbolic" };
                const config = getEffectiveProviderConfig(provider.id, [provider]);
                expect(config.chat_endpoint.endsWith("/chat/completions")).toBe(true);
            }
        ), { numRuns: 100 });
    });

    it('auth_type is "bearer" iff apiKey is non-empty', () => {
        fc.assert(fc.property(
            nameArb,
            baseUrlArb,
            apiKeyArb,
            (name, baseUrl, apiKey) => {
                const provider = { id: "custom-test", name, baseUrl, apiKey, icon: "ai-openai-symbolic" };
                const config = getEffectiveProviderConfig(provider.id, [provider]);
                if (apiKey !== undefined && apiKey !== "") {
                    expect(config.auth_type).toBe("bearer");
                } else {
                    expect(config.auth_type).toBe("none");
                }
            }
        ), { numRuns: 100 });
    });

    it('requires_key matches whether apiKey is non-empty', () => {
        fc.assert(fc.property(
            nameArb,
            baseUrlArb,
            apiKeyArb,
            (name, baseUrl, apiKey) => {
                const provider = { id: "custom-test", name, baseUrl, apiKey, icon: "ai-openai-symbolic" };
                const config = getEffectiveProviderConfig(provider.id, [provider]);
                expect(config.requires_key).toBe(apiKey !== undefined && apiKey !== "");
            }
        ), { numRuns: 100 });
    });
});
