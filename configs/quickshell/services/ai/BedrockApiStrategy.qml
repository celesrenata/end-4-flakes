import QtQuick

ApiStrategy {
    // Sentinel endpoint — not used for HTTP, signals CLI-based invocation
    function buildEndpoint(model: AiModel): string {
        return "aws-bedrock-converse";
    }

    // Convert messages to Bedrock Converse API format.
    // System prompt goes in top-level "system" array, not in messages.
    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>) {
        var convertedMessages = [];
        for (var i = 0; i < messages.length; i++) {
            var msg = messages[i];
            var contentBlocks = [{ text: msg.rawContent }];
            if (msg.images && msg.images.length > 0) {
                for (var j = 0; j < msg.images.length; j++) {
                    contentBlocks.push({
                        image: {
                            format: "png",
                            source: { bytes: msg.images[j] }
                        }
                    });
                }
            }
            convertedMessages.push({
                role: msg.role,
                content: contentBlocks
            });
        }
        var system = [];
        if (systemPrompt) {
            system = [{ text: systemPrompt }];
        }
        return {
            modelId: model.model,
            messages: convertedMessages,
            system: system,
            temperature: temperature
        };
    }

    // Not used for Bedrock — auth is via AWS_SHARED_CREDENTIALS_FILE env var
    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return "";
    }

    // Parse newline-delimited JSON events from converse-stream stdout.
    // Handles: messageStart, contentBlockDelta, contentBlockStop, messageStop, metadata
    function parseResponseLine(line, message) {
        var event;
        try {
            event = JSON.parse(line);
        } catch (e) {
            return {};
        }

        if (event.messageStart !== undefined) {
            return {};
        }

        if (event.contentBlockDelta !== undefined) {
            var delta = event.contentBlockDelta.delta || {};
            var text = delta.text || "";
            if (text) {
                message.content = (message.content || "") + text;
                message.rawContent = (message.rawContent || "") + text;
            }
            return {};
        }

        if (event.contentBlockStop !== undefined) {
            return {};
        }

        if (event.messageStop !== undefined) {
            return { finished: true };
        }

        if (event.metadata !== undefined) {
            var usage = event.metadata.usage;
            if (usage) {
                return {
                    tokenUsage: {
                        input: usage.inputTokens || 0,
                        output: usage.outputTokens || 0,
                        total: usage.totalTokens || 0
                    }
                };
            }
            return {};
        }

        return {};
    }

    function onRequestFinished(message) {
        return {};
    }

    function reset() {}
}
