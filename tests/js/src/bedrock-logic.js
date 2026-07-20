/**
 * Pure logic functions from Bedrock provider integration.
 * Extracted for property-based testing with fast-check + vitest.
 * No QML-specific dependencies — plain JavaScript compatible with Node.js.
 */

/**
 * Format a model name into a human-friendly display name.
 * - Replace dashes and colons with spaces
 * - Capitalize each word
 * - Format last word if it matches /^\d+b$/i → "(7B)" format
 * - Remove trailing "Latest" word
 */
export function formatModelName(rawName) {
    var replaced = rawName.replace(/-/g, " ").replace(/:/g, " ");
    var words = replaced.split(" ");
    // Filter out empty strings from consecutive delimiters
    var filtered = [];
    for (var i = 0; i < words.length; i++) {
        if (words[i] !== "") {
            filtered.push(words[i]);
        }
    }
    words = filtered;
    if (words.length === 0) {
        return "";
    }
    var lastWord = words[words.length - 1];
    if (/^\d+b$/i.test(lastWord)) {
        words[words.length - 1] = lastWord.replace(/(\d+)b/i, function(_, num) {
            return num + "B";
        });
        words[words.length - 1] = "(" + words[words.length - 1] + ")";
    }
    for (var j = 0; j < words.length; j++) {
        words[j] = words[j].charAt(0).toUpperCase() + words[j].slice(1);
    }
    if (words.length > 0 && words[words.length - 1] === "Latest") {
        words.pop();
    }
    return words.join(" ");
}

/**
 * Parse a Bedrock model list JSON string and filter to only include
 * models that are ON_DEMAND and ACTIVE.
 *
 * @param {string} jsonString - JSON string containing { modelSummaries: [...] }
 * @returns {Array} Filtered array of model summary objects
 */
export function parseBedrockModelList(jsonString) {
    try {
        var data = JSON.parse(jsonString);
        var summaries = data.modelSummaries || [];
        var result = [];
        for (var i = 0; i < summaries.length; i++) {
            var model = summaries[i];
            var inferenceTypes = model.inferenceTypesSupported || [];
            var hasOnDemand = false;
            for (var j = 0; j < inferenceTypes.length; j++) {
                if (inferenceTypes[j] === "ON_DEMAND") {
                    hasOnDemand = true;
                    break;
                }
            }
            var lifecycle = model.modelLifecycle || {};
            var isActive = lifecycle.status === "ACTIVE";
            if (hasOnDemand && isActive) {
                result.push(model);
            }
        }
        return result;
    } catch (e) {
        return [];
    }
}

/**
 * Map a single Bedrock model summary object to AiModel-compatible properties.
 *
 * @param {Object} modelData - A model summary from the Bedrock API
 * @returns {Object} AiModel-compatible object
 */
export function mapBedrockModelToAiModel(modelData) {
    var modelId = modelData.modelId || "";
    var modelName = modelData.modelName || modelId;
    return {
        name: formatModelName(modelName),
        icon: "aws-bedrock-symbolic",
        description: "AWS Bedrock | " + modelId,
        endpoint: "aws-bedrock-converse",
        model: modelId,
        requires_key: false,
        key_id: "bedrock",
        api_format: "bedrock"
    };
}

/**
 * Convert messages and system prompt to Bedrock Converse API format.
 *
 * @param {Array} messages - Array of { role: "user"|"assistant", rawContent: string }
 * @param {string} systemPrompt - System prompt text (can be empty/falsy)
 * @returns {Object} { messages: [...], system: [...] }
 */
export function buildRequestData(messages, systemPrompt) {
    var convertedMessages = [];
    for (var i = 0; i < messages.length; i++) {
        var msg = messages[i];
        convertedMessages.push({
            role: msg.role,
            content: [{ text: msg.rawContent }]
        });
    }
    var system = [];
    if (systemPrompt) {
        system = [{ text: systemPrompt }];
    }
    return {
        messages: convertedMessages,
        system: system
    };
}

/**
 * Parse a single JSON event line from converse-stream output.
 * Updates message.content in place for contentBlockDelta events.
 *
 * @param {string} line - A JSON string (one line from converse-stream)
 * @param {Object} message - Mutable message object with `content` property
 * @returns {Object} { finished: boolean, error?: string, tokenUsage?: Object }
 */
export function parseResponseLine(line, message) {
    try {
        var event = JSON.parse(line);
    } catch (e) {
        // Malformed JSON — skip line
        return { finished: false };
    }

    if (event.messageStart !== undefined) {
        return { finished: false };
    }

    if (event.contentBlockDelta !== undefined) {
        var delta = event.contentBlockDelta.delta || {};
        var text = delta.text || "";
        if (text) {
            message.content = (message.content || "") + text;
        }
        return { finished: false };
    }

    if (event.contentBlockStop !== undefined) {
        return { finished: false };
    }

    if (event.messageStop !== undefined) {
        return { finished: true };
    }

    if (event.metadata !== undefined) {
        var result = { finished: false };
        var usage = event.metadata.usage;
        if (usage) {
            result.tokenUsage = {
                inputTokens: usage.inputTokens || 0,
                outputTokens: usage.outputTokens || 0,
                totalTokens: usage.totalTokens || 0
            };
        }
        return result;
    }

    // Unknown event type — treat as non-terminal
    return { finished: false };
}

/**
 * Parse the AWS region from an AWS config file content string.
 * Looks for [default] section, then region = <value> within it.
 *
 * @param {string} configFileContent - Content of ~/.aws/config
 * @returns {string} The region value, or "us-west-2" if not found
 */
export function parseAwsRegion(configFileContent) {
    if (!configFileContent) {
        return "us-west-2";
    }
    var lines = configFileContent.split("\n");
    var inDefaultSection = false;
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        // Check for section headers
        if (line.charAt(0) === "[") {
            if (line === "[default]") {
                inDefaultSection = true;
            } else {
                if (inDefaultSection) {
                    // We've left the [default] section without finding region
                    break;
                }
            }
            continue;
        }
        if (inDefaultSection) {
            // Look for region = <value>
            var eqIndex = line.indexOf("=");
            if (eqIndex !== -1) {
                var key = line.substring(0, eqIndex).trim();
                var value = line.substring(eqIndex + 1).trim();
                if (key === "region") {
                    return value;
                }
            }
        }
    }
    return "us-west-2";
}
