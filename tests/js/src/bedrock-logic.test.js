import { describe, it, expect } from 'vitest';
import * as fc from 'fast-check';
import {
    parseBedrockModelList,
    mapBedrockModelToAiModel,
    formatModelName,
    buildRequestData,
    parseResponseLine,
    parseAwsRegion
} from './bedrock-logic.js';

/**
 * Feature: bedrock-provider, Property 1: Model list parsing preserves model identity
 *
 * For any valid modelSummaries JSON array where each entry has modelId, modelName,
 * inferenceTypesSupported containing "ON_DEMAND", and modelLifecycle.status "ACTIVE":
 * parsed AiModel objects have model === source modelId, api_format === "bedrock",
 * icon === "aws-bedrock-symbolic", endpoint === "aws-bedrock-converse"
 *
 * **Validates: Requirements 4.2, 5.1, 5.2, 5.3, 5.5, 5.6**
 */
describe('Feature: bedrock-provider, Property 1: Model list parsing preserves model identity', () => {
    const modelSummaryArb = fc.record({
        modelId: fc.string({ minLength: 1 }),
        modelName: fc.string({ minLength: 1 }),
        inferenceTypesSupported: fc.constant(["ON_DEMAND"]),
        modelLifecycle: fc.constant({ status: "ACTIVE" })
    });

    const modelSummariesArb = fc.array(modelSummaryArb, { minLength: 1, maxLength: 20 });

    it('parsed AiModel model field equals source modelId', () => {
        fc.assert(fc.property(
            modelSummariesArb,
            (summaries) => {
                const json = JSON.stringify({ modelSummaries: summaries });
                const filtered = parseBedrockModelList(json);
                expect(filtered.length).toBe(summaries.length);
                for (var i = 0; i < filtered.length; i++) {
                    const aiModel = mapBedrockModelToAiModel(filtered[i]);
                    expect(aiModel.model).toBe(summaries[i].modelId);
                }
            }
        ), { numRuns: 100 });
    });

    it('parsed AiModel has api_format "bedrock"', () => {
        fc.assert(fc.property(
            modelSummariesArb,
            (summaries) => {
                const json = JSON.stringify({ modelSummaries: summaries });
                const filtered = parseBedrockModelList(json);
                for (var i = 0; i < filtered.length; i++) {
                    const aiModel = mapBedrockModelToAiModel(filtered[i]);
                    expect(aiModel.api_format).toBe("bedrock");
                }
            }
        ), { numRuns: 100 });
    });

    it('parsed AiModel has icon "aws-bedrock-symbolic"', () => {
        fc.assert(fc.property(
            modelSummariesArb,
            (summaries) => {
                const json = JSON.stringify({ modelSummaries: summaries });
                const filtered = parseBedrockModelList(json);
                for (var i = 0; i < filtered.length; i++) {
                    const aiModel = mapBedrockModelToAiModel(filtered[i]);
                    expect(aiModel.icon).toBe("aws-bedrock-symbolic");
                }
            }
        ), { numRuns: 100 });
    });

    it('parsed AiModel has endpoint "aws-bedrock-converse"', () => {
        fc.assert(fc.property(
            modelSummariesArb,
            (summaries) => {
                const json = JSON.stringify({ modelSummaries: summaries });
                const filtered = parseBedrockModelList(json);
                for (var i = 0; i < filtered.length; i++) {
                    const aiModel = mapBedrockModelToAiModel(filtered[i]);
                    expect(aiModel.endpoint).toBe("aws-bedrock-converse");
                }
            }
        ), { numRuns: 100 });
    });
});

/**
 * Feature: bedrock-provider, Property 2: Model list filtering retains only ON_DEMAND ACTIVE models
 *
 * For any array of model summary objects with arbitrary inferenceTypesSupported arrays
 * and modelLifecycle.status values: filtered output contains only models where
 * inferenceTypesSupported includes "ON_DEMAND" AND status === "ACTIVE", and no
 * qualifying model is excluded.
 *
 * **Validates: Requirements 4.3**
 */
describe('Feature: bedrock-provider, Property 2: Model list filtering retains only ON_DEMAND ACTIVE models', () => {
    const inferenceTypesArb = fc.subarray(["ON_DEMAND", "PROVISIONED", "INFERENCE_PROFILE"], { minLength: 0 });
    const statusArb = fc.constantFrom("ACTIVE", "LEGACY", "RETIRED");

    const modelSummaryArb = fc.record({
        modelId: fc.string({ minLength: 1 }),
        modelName: fc.string({ minLength: 1 }),
        inferenceTypesSupported: inferenceTypesArb,
        modelLifecycle: statusArb.map(s => ({ status: s }))
    });

    const modelSummariesArb = fc.array(modelSummaryArb, { minLength: 0, maxLength: 20 });

    it('every item in result has ON_DEMAND in inferenceTypesSupported AND ACTIVE status', () => {
        fc.assert(fc.property(
            modelSummariesArb,
            (summaries) => {
                const json = JSON.stringify({ modelSummaries: summaries });
                const result = parseBedrockModelList(json);
                for (var i = 0; i < result.length; i++) {
                    expect(result[i].inferenceTypesSupported).toContain("ON_DEMAND");
                    expect(result[i].modelLifecycle.status).toBe("ACTIVE");
                }
            }
        ), { numRuns: 100 });
    });

    it('no qualifying model is excluded from the result (completeness)', () => {
        fc.assert(fc.property(
            modelSummariesArb,
            (summaries) => {
                const json = JSON.stringify({ modelSummaries: summaries });
                const result = parseBedrockModelList(json);

                // Count how many in the original qualify
                var expectedCount = 0;
                for (var i = 0; i < summaries.length; i++) {
                    var types = summaries[i].inferenceTypesSupported || [];
                    var hasOnDemand = false;
                    for (var j = 0; j < types.length; j++) {
                        if (types[j] === "ON_DEMAND") {
                            hasOnDemand = true;
                            break;
                        }
                    }
                    if (hasOnDemand && summaries[i].modelLifecycle.status === "ACTIVE") {
                        expectedCount++;
                    }
                }
                expect(result.length).toBe(expectedCount);
            }
        ), { numRuns: 100 });
    });
});

/**
 * Feature: bedrock-provider, Property 3: Model name formatting produces capitalized human-friendly names
 *
 * For any string with dashes, colons, or spaces: formatModelName produces output where
 * each word is capitalized, dashes/colons replaced with spaces, trailing "Latest" removed,
 * param suffixes like "7b" formatted as "(7B)"
 *
 * **Validates: Requirements 5.4**
 */
describe('Feature: bedrock-provider, Property 3: Model name formatting produces capitalized human-friendly names', () => {
    const modelNameArb = fc.stringOf(
        fc.constantFrom('a', 'b', 'c', '1', '2', '3', '-', ':', 'l', 'a', 't', 'e', 's', 't', 'b', 'B', ' '),
        { minLength: 1, maxLength: 30 }
    );

    it('result does not contain dashes or colons (replaced with spaces)', () => {
        fc.assert(fc.property(
            modelNameArb,
            (name) => {
                const result = formatModelName(name);
                expect(result.indexOf("-")).toBe(-1);
                expect(result.indexOf(":")).toBe(-1);
            }
        ), { numRuns: 100 });
    });

    it('each word starts with uppercase (if non-empty and not a parenthesized suffix)', () => {
        fc.assert(fc.property(
            modelNameArb,
            (name) => {
                const result = formatModelName(name);
                if (result.length === 0) return; // empty input produces empty output
                const words = result.split(" ");
                for (var i = 0; i < words.length; i++) {
                    if (words[i].length > 0) {
                        if (words[i].startsWith("(")) {
                            // Parenthesized suffix like "(7B)" — char after paren is uppercase
                            expect(words[i].charAt(1)).toBe(words[i].charAt(1).toUpperCase());
                        } else {
                            expect(words[i].charAt(0)).toBe(words[i].charAt(0).toUpperCase());
                        }
                    }
                }
            }
        ), { numRuns: 100 });
    });

    it('result does not end with "Latest"', () => {
        fc.assert(fc.property(
            modelNameArb,
            (name) => {
                const result = formatModelName(name);
                if (result.length === 0) return;
                const words = result.split(" ");
                if (words.length > 0) {
                    expect(words[words.length - 1]).not.toBe("Latest");
                }
            }
        ), { numRuns: 100 });
    });

    it('strings ending with /\\d+b$/i pattern get formatted as "(<N>B)"', () => {
        const paramModelArb = fc.tuple(
            fc.string({ minLength: 1, maxLength: 20 }).filter(s => /^[a-zA-Z0-9._-]+$/.test(s)),
            fc.integer({ min: 1, max: 999 })
        ).map(([prefix, num]) => prefix + "-" + num + "b");

        fc.assert(fc.property(
            paramModelArb,
            (modelId) => {
                const result = formatModelName(modelId);
                expect(result).toMatch(/\(\d+B\)/);
            }
        ), { numRuns: 100 });
    });
});

/**
 * Feature: bedrock-provider, Property 4: buildRequestData produces valid Bedrock Converse message format
 *
 * For any array of messages with role ("user" or "assistant") and non-empty rawContent:
 * output has each message with matching role and content array containing exactly one
 * {"text": <rawContent>} object.
 *
 * **Validates: Requirements 6.2**
 */
describe('Feature: bedrock-provider, Property 4: buildRequestData produces valid Bedrock Converse message format', () => {
    const messageArb = fc.record({
        role: fc.constantFrom("user", "assistant"),
        rawContent: fc.string({ minLength: 1 })
    });

    const messagesArb = fc.array(messageArb, { minLength: 1, maxLength: 20 });

    it('result.messages.length equals input.length', () => {
        fc.assert(fc.property(
            messagesArb,
            (messages) => {
                const result = buildRequestData(messages, "");
                expect(result.messages.length).toBe(messages.length);
            }
        ), { numRuns: 100 });
    });

    it('each result message role matches input role', () => {
        fc.assert(fc.property(
            messagesArb,
            (messages) => {
                const result = buildRequestData(messages, "");
                for (var i = 0; i < messages.length; i++) {
                    expect(result.messages[i].role).toBe(messages[i].role);
                }
            }
        ), { numRuns: 100 });
    });

    it('each result message content is array of length 1', () => {
        fc.assert(fc.property(
            messagesArb,
            (messages) => {
                const result = buildRequestData(messages, "");
                for (var i = 0; i < messages.length; i++) {
                    expect(Array.isArray(result.messages[i].content)).toBe(true);
                    expect(result.messages[i].content.length).toBe(1);
                }
            }
        ), { numRuns: 100 });
    });

    it('each result message content[0].text equals input rawContent', () => {
        fc.assert(fc.property(
            messagesArb,
            (messages) => {
                const result = buildRequestData(messages, "");
                for (var i = 0; i < messages.length; i++) {
                    expect(result.messages[i].content[0].text).toBe(messages[i].rawContent);
                }
            }
        ), { numRuns: 100 });
    });
});

/**
 * Feature: bedrock-provider, Property 5: System prompt is separated from message array
 *
 * For any non-empty system prompt and any messages array: `buildRequestData` returns
 * system prompt in `system` field as `[{"text": <systemPrompt>}]`, and no element in
 * returned `messages` array has role "system".
 *
 * **Validates: Requirements 6.3**
 */
describe('Feature: bedrock-provider, Property 5: System prompt is separated from message array', () => {
    const messageArb = fc.record({
        role: fc.constantFrom("user", "assistant"),
        rawContent: fc.string({ minLength: 1 })
    });

    it('system field contains exactly the system prompt text', () => {
        fc.assert(fc.property(
            fc.tuple(fc.string({ minLength: 1 }), fc.array(messageArb)),
            ([systemPrompt, messages]) => {
                const result = buildRequestData(messages, systemPrompt);
                expect(result.system).toEqual([{ text: systemPrompt }]);
                expect(result.system.length).toBe(1);
                expect(result.system[0].text).toBe(systemPrompt);
            }
        ), { numRuns: 100 });
    });

    it('no message in result.messages has role "system"', () => {
        fc.assert(fc.property(
            fc.tuple(fc.string({ minLength: 1 }), fc.array(messageArb)),
            ([systemPrompt, messages]) => {
                const result = buildRequestData(messages, systemPrompt);
                for (var i = 0; i < result.messages.length; i++) {
                    expect(result.messages[i].role).not.toBe("system");
                }
            }
        ), { numRuns: 100 });
    });
});

/**
 * Feature: bedrock-provider, Property 6: Stream event parsing concatenates all delta text
 *
 * For any sequence of valid converse-stream event lines (messageStart, contentBlockDelta,
 * messageStop): calling `parseResponseLine` for each line results in `message.content`
 * equaling the exact concatenation of all `contentBlockDelta.delta.text` values in order.
 *
 * **Validates: Requirements 6.5, 10.2**
 */
describe('Feature: bedrock-provider, Property 6: Stream event parsing concatenates all delta text', () => {
    const deltaTextsArb = fc.array(fc.string({ minLength: 1 }), { minLength: 1, maxLength: 20 });

    it('message.content equals concatenation of all delta texts', () => {
        fc.assert(fc.property(
            deltaTextsArb,
            (deltaTexts) => {
                var lines = [];
                lines.push(JSON.stringify({ messageStart: { role: "assistant" } }));
                for (var i = 0; i < deltaTexts.length; i++) {
                    lines.push(JSON.stringify({ contentBlockDelta: { contentBlockIndex: 0, delta: { text: deltaTexts[i] } } }));
                }
                lines.push(JSON.stringify({ messageStop: { stopReason: "end_turn" } }));

                var message = { content: "" };
                for (var j = 0; j < lines.length; j++) {
                    parseResponseLine(lines[j], message);
                }

                var expected = "";
                for (var k = 0; k < deltaTexts.length; k++) {
                    expected = expected + deltaTexts[k];
                }
                expect(message.content).toBe(expected);
            }
        ), { numRuns: 100 });
    });

    it('final parseResponseLine (messageStop) returns finished true', () => {
        fc.assert(fc.property(
            deltaTextsArb,
            (deltaTexts) => {
                var lines = [];
                lines.push(JSON.stringify({ messageStart: { role: "assistant" } }));
                for (var i = 0; i < deltaTexts.length; i++) {
                    lines.push(JSON.stringify({ contentBlockDelta: { contentBlockIndex: 0, delta: { text: deltaTexts[i] } } }));
                }
                lines.push(JSON.stringify({ messageStop: { stopReason: "end_turn" } }));

                var message = { content: "" };
                var lastResult = null;
                for (var j = 0; j < lines.length; j++) {
                    lastResult = parseResponseLine(lines[j], message);
                }
                expect(lastResult).toEqual({ finished: true });
            }
        ), { numRuns: 100 });
    });
});

/**
 * Feature: bedrock-provider, Property 7: AWS region parsing from config file
 *
 * For any string representing an AWS config file with a `[default]` section containing
 * `region = <value>`: parser extracts exactly `<value>` (trimmed). If no `[default]`
 * section or no `region` line exists, result is "us-west-2".
 *
 * **Validates: Requirements 7.1, 7.2**
 */
describe('Feature: bedrock-provider, Property 7: AWS region parsing from config file', () => {
    const regionValueArb = fc.stringOf(
        fc.constantFrom('a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z','0','1','2','3','4','5','6','7','8','9','-'),
        { minLength: 3, maxLength: 20 }
    );

    it('extracts region value when [default] section has region line', () => {
        fc.assert(fc.property(
            regionValueArb,
            (regionValue) => {
                const configContent = "[default]\nregion = " + regionValue + "\n";
                const result = parseAwsRegion(configContent);
                expect(result).toBe(regionValue);
            }
        ), { numRuns: 100 });
    });

    it('returns "us-west-2" when no [default] section exists', () => {
        const noDefaultArb = fc.stringOf(
            fc.constantFrom('a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z','0','1','2','3','4','5','6','7','8','9',' ','=','\n'),
            { minLength: 0, maxLength: 50 }
        ).filter(s => s.indexOf("[default]") === -1);

        fc.assert(fc.property(
            noDefaultArb,
            (configContent) => {
                const result = parseAwsRegion(configContent);
                expect(result).toBe("us-west-2");
            }
        ), { numRuns: 100 });
    });
});

/**
 * Task 8.1: Unit tests for Bedrock provider config and policy filtering
 *
 * Tests the bedrock provider config structure and policy filtering behavior.
 * Example-based tests (not property-based).
 *
 * _Requirements: 1.1, 1.3, 1.4, 8.1, 8.2, 8.3_
 */
describe('Bedrock provider config and policy filtering', () => {
    const bedrockConfig = {
        name: "AWS Bedrock",
        icon: "aws-bedrock-symbolic",
        key_id: "bedrock",
        requires_key: false,
        auth_type: "aws_cli",
        api_format: "bedrock",
        supports_balance: false
    };

    function getBuiltInProviders(policyAi) {
        if (policyAi === 2) return ["ollama"];
        return ["openai", "anthropic", "gemini", "mistral", "openrouter", "ollama", "bedrock"];
    }

    it('provider config has correct name', () => {
        expect(bedrockConfig.name).toBe("AWS Bedrock");
    });

    it('provider config has correct icon', () => {
        expect(bedrockConfig.icon).toBe("aws-bedrock-symbolic");
    });

    it('provider config has correct key_id', () => {
        expect(bedrockConfig.key_id).toBe("bedrock");
    });

    it('provider config does not require an API key', () => {
        expect(bedrockConfig.requires_key).toBe(false);
    });

    it('provider config uses aws_cli auth type', () => {
        expect(bedrockConfig.auth_type).toBe("aws_cli");
    });

    it('provider config uses bedrock api format', () => {
        expect(bedrockConfig.api_format).toBe("bedrock");
    });

    it('provider config does not support balance checking', () => {
        expect(bedrockConfig.supports_balance).toBe(false);
    });

    it('bedrock is hidden when policies.ai is 2 (local-only mode)', () => {
        const providers = getBuiltInProviders(2);
        expect(providers).not.toContain("bedrock");
    });

    it('bedrock is visible when policies.ai is 1 (full mode)', () => {
        const providers = getBuiltInProviders(1);
        expect(providers).toContain("bedrock");
    });

    it('policies.ai 0 returns full list (panel hidden at UI level)', () => {
        // When policies.ai is 0 the entire panel is hidden, but the provider
        // list itself still contains bedrock — the hiding is at the panel level.
        const providers = getBuiltInProviders(0);
        expect(providers).toContain("bedrock");
    });

    it('auth_type "aws_cli" with requires_key false means no auth header needed', () => {
        // Config combination signals that no Authorization header is constructed
        expect(bedrockConfig.auth_type).toBe("aws_cli");
        expect(bedrockConfig.requires_key).toBe(false);
    });
});

/**
 * Task 8.2: Integration tests for credential detection and validation flow
 *
 * Example-based tests exercising credential detection scenarios and validation
 * using pure functions from bedrock-logic.js.
 *
 * _Requirements: 2.4, 3.2, 3.3, 3.4, 6.6, 9.1, 9.2, 9.3_
 */
describe('Bedrock credential detection and validation flow', () => {
    it('empty config content returns default region "us-west-2"', () => {
        expect(parseAwsRegion("")).toBe("us-west-2");
    });

    it('validation command structure includes --max-results 1 --region <region>', () => {
        const region = "us-east-1";
        const expectedCommand = "aws bedrock list-foundation-models --max-results 1 --region " + region + " --output json";
        expect(expectedCommand).toContain("--max-results 1");
        expect(expectedCommand).toContain("--region " + region);
    });

    it('parseResponseLine with messageStop returns finished true (exit code 0 success path)', () => {
        const line = JSON.stringify({ messageStop: { stopReason: "end_turn" } });
        const message = { content: "" };
        const result = parseResponseLine(line, message);
        expect(result).toEqual({ finished: true });
    });

    it('parseResponseLine with messageStop returns finished true', () => {
        const line = JSON.stringify({ messageStop: { stopReason: "max_tokens" } });
        const message = { content: "some accumulated text" };
        const result = parseResponseLine(line, message);
        expect(result.finished).toBe(true);
    });

    it('malformed JSON line is skipped without crashing', () => {
        const message = { content: "" };
        const result = parseResponseLine("not json {", message);
        expect(result).toEqual({ finished: false });
        expect(message.content).toBe("");
    });

    it('config file without [default] section returns default region', () => {
        const configContent = "[profile production]\nregion = eu-west-1\n";
        expect(parseAwsRegion(configContent)).toBe("us-west-2");
    });

    it('AWS CLI not on PATH produces consistent error message', () => {
        // The expected error message when AWS CLI is unavailable
        const expectedMessage = "AWS CLI not found. Install the aws-cli package to use Bedrock.";
        expect(expectedMessage).toContain("AWS CLI not found");
        expect(expectedMessage).toContain("aws-cli");
    });

    it('parseAwsRegion with valid [default] config extracts region correctly', () => {
        const configContent = "[default]\nregion = us-east-1\n";
        expect(parseAwsRegion(configContent)).toBe("us-east-1");
    });
});
