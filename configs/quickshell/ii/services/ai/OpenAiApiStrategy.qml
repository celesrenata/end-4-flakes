import QtQuick

ApiStrategy {
    property bool isReasoning: false
    
    function buildEndpoint(model: AiModel): string {
        // console.log("[AI] Endpoint: " + model.endpoint);
        return model.endpoint;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, tuning: var) {
        let baseData = {
            "model": model.model,
            "messages": [
                {role: "system", content: systemPrompt},
                ...messages.map(message => {
                    // Build multimodal content if message has images
                    var hasImages = message.images && message.images.length > 0;
                    return {
                        "role": message.role,
                        "content": hasImages
                            ? [
                                { type: "text", text: message.rawContent },
                                ...message.images.map(img => ({
                                    type: "image_url",
                                    image_url: { url: "data:image/png;base64," + img }
                                }))
                            ]
                            : message.rawContent,
                    }
                }),
            ],
            "stream": true,
            "temperature": temperature,
        };

        // Apply per-model tuning: reasoning_effort
        if (tuning && tuning.reasoningEffort && tuning.reasoningEffort.length > 0) {
            baseData["reasoning_effort"] = tuning.reasoningEffort;
        }

        // Apply per-model tuning: verbosity
        if (tuning && tuning.verbosity && tuning.verbosity.length > 0) {
            baseData["verbosity"] = tuning.verbosity;
        }

        // Apply per-model tuning: web_search_options
        if (tuning && tuning.webSearch) {
            baseData["web_search_options"] = {
                "search_context_size": tuning.searchContextSize || "medium",
            };
        }

        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `-H "Authorization: Bearer \$\{${apiKeyEnvVarName}\}"`;
    }

    function parseResponseLine(line, message) {
        // Remove 'data: ' prefix if present and trim whitespace
        let cleanData = line.trim();
        if (cleanData.startsWith("data:")) {
            cleanData = cleanData.slice(5).trim();
        }
        
        // Handle special cases
        if (!cleanData || cleanData.startsWith(":")) return {};
        if (cleanData === "[DONE]") {
            return { finished: true };
        }
        
        // Real stuff
        try {
            const dataJson = JSON.parse(cleanData);
            let newContent = "";
            
            const responseContent = dataJson.choices[0]?.delta?.content || dataJson.message?.content;
            const responseReasoning = dataJson.choices[0]?.delta?.reasoning || dataJson.choices[0]?.delta?.reasoning_content;

            if (responseContent && responseContent.length > 0) {
                if (isReasoning) {
                    isReasoning = false;
                    const endBlock = "\n\n</think>\n\n";
                    message.content += endBlock;
                    message.rawContent += endBlock;
                }
                newContent = responseContent;
            } else if (responseReasoning && responseReasoning.length > 0) {
                if (!isReasoning) {
                    isReasoning = true;
                    const startBlock = "\n\n<think>\n\n";
                    message.rawContent += startBlock;
                    message.content += startBlock;
                }
                newContent = responseReasoning;
            }

            message.content += newContent;
            message.rawContent += newContent;

            // Usage metadata
            if (dataJson.usage) {
                return {
                    tokenUsage: {
                        input: dataJson.usage.prompt_tokens ?? -1,
                        output: dataJson.usage.completion_tokens ?? -1,
                        total: dataJson.usage.total_tokens ?? -1
                    }
                };
            }

            if (dataJson.done) {
                return { finished: true };
            }
            
        } catch (e) {
            console.log("[AI] OpenAI: Could not parse line: ", e);
            message.rawContent += line;
            message.content += line;
        }
        
        return {};
    }
    
    function onRequestFinished(message) {
        // OpenAI format doesn't need special finish handling
        return {};
    }
    
    function reset() {
        isReasoning = false;
    }

}
