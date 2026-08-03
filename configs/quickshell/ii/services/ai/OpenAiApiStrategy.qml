import QtQuick

ApiStrategy {
    property bool isReasoning: false
    // Accumulator for streaming tool_calls (arguments arrive in chunks)
    property var _pendingToolCall: null
    
    function buildEndpoint(model: AiModel): string {
        // console.log("[AI] Endpoint: " + model.endpoint);
        return model.endpoint;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, tuning: var) {
        let baseData = {
            "model": model.model,
            "messages": [
                {role: "system", content: systemPrompt},
                ...messages.map((message, idx) => {
                    // Assistant message that made a function call — include tool_calls
                    if (message.role === "assistant" && message.functionCall) {
                        const msg = { role: "assistant", content: message.rawContent || "" };
                        msg.tool_calls = [{
                            id: "call_" + idx,
                            type: "function",
                            "function": {
                                name: message.functionCall.name,
                                arguments: JSON.stringify(message.functionCall.args || {})
                            }
                        }];
                        return msg;
                    }

                    // Tool result message — use role: "tool"
                    if (message.functionResponse && message.functionName) {
                        return {
                            role: "tool",
                            tool_call_id: "call_" + (idx - 1),
                            content: message.functionResponse
                        };
                    }

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

        // Add function tools to request (OpenAI chat completions format)
        if (tools && tools.length > 0) {
            baseData["tools"] = tools.map(t => ({
                "type": "function",
                "function": {
                    "name": t.name,
                    "description": t.description || "",
                    "parameters": t.parameters || { "type": "object", "properties": {} }
                }
            }));
        }

        // Web search: When enabled, override model to gpt-5-search-api which has
        // built-in web search on Chat Completions. The model always searches before responding.
        // Note: gpt-5-search-api doesn't support temperature, tools, or other tuning params.
        if (tuning && tuning.webSearch) {
            baseData["model"] = "gpt-5-search-api";
            delete baseData["temperature"];
            delete baseData["tools"];
            delete baseData["reasoning_effort"];
            delete baseData["verbosity"];
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
            // If we have a pending tool call that wasn't flushed by finish_reason
            if (_pendingToolCall) {
                let args = {};
                try {
                    args = JSON.parse(_pendingToolCall.arguments);
                } catch (e) {
                    console.warn("[AI] OpenAI: Could not parse tool_call arguments on DONE: " + e);
                }
                const result = { functionCall: { name: _pendingToolCall.name, args: args }, finished: true };
                _pendingToolCall = null;
                return result;
            }
            return { finished: true };
        }
        
        // Real stuff
        try {
            const dataJson = JSON.parse(cleanData);
            let newContent = "";
            
            const responseContent = dataJson.choices[0]?.delta?.content || dataJson.message?.content;
            const responseReasoning = dataJson.choices[0]?.delta?.reasoning || dataJson.choices[0]?.delta?.reasoning_content;
            const responseToolCalls = dataJson.choices[0]?.delta?.tool_calls || dataJson.message?.tool_calls;

            // Handle streaming tool_calls
            if (responseToolCalls && responseToolCalls.length > 0) {
                const tc = responseToolCalls[0];
                if (tc.function) {
                    // Start or accumulate tool call
                    if (!_pendingToolCall) {
                        _pendingToolCall = { name: "", arguments: "" };
                    }
                    if (tc.function.name && tc.function.name.length > 0) {
                        _pendingToolCall.name = tc.function.name;
                    }
                    if (tc.function.arguments !== undefined && tc.function.arguments !== null) {
                        _pendingToolCall.arguments += tc.function.arguments;
                    }
                }
                // Close reasoning block if open
                if (isReasoning) {
                    isReasoning = false;
                    const endBlock = "\n\n</think>\n\n";
                    message.content += endBlock;
                    message.rawContent += endBlock;
                }
                // Don't return yet — wait for finish_reason or [DONE] or done:true
            }

            // Check if this is a finish with a tool call
            const finishReason = dataJson.choices[0]?.finish_reason;
            if ((finishReason === "tool_calls" || finishReason === "function_call" || (finishReason === "stop" && _pendingToolCall))) {
                if (_pendingToolCall && _pendingToolCall.name) {
                    let args = {};
                    try {
                        if (_pendingToolCall.arguments.trim().length > 0) {
                            args = JSON.parse(_pendingToolCall.arguments);
                        }
                    } catch (e) {
                        console.warn("[AI] OpenAI: Could not parse tool_call arguments: " + e + " raw: " + _pendingToolCall.arguments.substring(0, 200));
                        args = { _parseError: true, _raw: _pendingToolCall.arguments };
                    }
                    const result = { functionCall: { name: _pendingToolCall.name, args: args } };
                    _pendingToolCall = null;
                    return result;
                }
            }

            // Also handle non-streaming tool_calls (complete in one message)
            if (dataJson.message?.tool_calls && dataJson.message.tool_calls.length > 0) {
                const tc = dataJson.message.tool_calls[0];
                if (tc.function) {
                    let args = {};
                    try {
                        args = JSON.parse(tc.function.arguments || "{}");
                    } catch (e) {
                        console.warn("[AI] OpenAI: Could not parse tool_call arguments: " + e);
                    }
                    return { functionCall: { name: tc.function.name, args: args } };
                }
            }

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
                // Flush any pending tool call before marking finished
                if (_pendingToolCall) {
                    let args = {};
                    try {
                        args = JSON.parse(_pendingToolCall.arguments);
                    } catch (e) {
                        console.warn("[AI] OpenAI: Could not parse tool_call arguments on done: " + e);
                    }
                    const result = { functionCall: { name: _pendingToolCall.name, args: args }, finished: true };
                    _pendingToolCall = null;
                    return result;
                }
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
        _pendingToolCall = null;
    }

}
