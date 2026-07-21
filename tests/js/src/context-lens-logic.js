/**
 * Context Lens — pure logic functions extracted for property-based testing.
 * Ports of QML functions used in configs/quickshell/contextlens.qml and services/Ai.qml.
 */

/**
 * Checks if a model ID matches known vision-capable patterns.
 * Port of the QML isVisionCapable function.
 */
export function isVisionCapable(modelName) {
    const name = (modelName || "").toLowerCase();
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

/**
 * Builds OpenAI-format multimodal content for a message with images.
 * Returns the content field value (array if images, string if not).
 */
export function buildOpenAiContent(text, images) {
    if (images && images.length > 0) {
        const parts = [{ type: "text", text: text }];
        for (let i = 0; i < images.length; i++) {
            parts.push({
                type: "image_url",
                image_url: { url: "data:image/png;base64," + images[i] }
            });
        }
        return parts;
    }
    return text;
}

/**
 * Builds Gemini-format parts array for a message with images.
 */
export function buildGeminiParts(text, images) {
    const parts = [{ text: text }];
    if (images && images.length > 0) {
        for (let i = 0; i < images.length; i++) {
            parts.push({ inlineData: { mimeType: "image/png", data: images[i] } });
        }
    }
    return parts;
}

/**
 * Transforms region coordinates by monitor scale factor.
 * Returns { x, y, width, height } in pixel coordinates.
 */
export function transformCropCoordinates(regionX, regionY, regionWidth, regionHeight, scale) {
    return {
        x: Math.round(regionX * scale),
        y: Math.round(regionY * scale),
        width: Math.round(regionWidth * scale),
        height: Math.round(regionHeight * scale),
    };
}

/**
 * Returns the system prompt for a given action ID.
 */
export function getPromptForAction(actionId, translateTargetLang, customPrompt) {
    switch (actionId) {
    case "explain":
        return "Describe what you see in this screenshot in detail. Explain any UI elements, text, or content visible.";
    case "extract_text":
        return "Extract ALL text visible in this image. Return only the extracted text, preserving layout where possible.";
    case "translate":
        return "Translate all text visible in this image to " + (translateTargetLang || "English") + ". Show original and translation.";
    case "summarize":
        return "Summarize the content shown in this screenshot in 2-3 sentences.";
    case "explain_error":
        return "This screenshot shows an error or problem. Identify the error, explain the likely cause, and suggest a fix.";
    case "generate_command":
        return "Based on what's shown in this screenshot, generate the shell command(s) that would accomplish or fix what's shown. Return only the command(s).";
    case "ask_question":
        return customPrompt || "";
    case "identify_ui":
        return "Identify the application, UI framework, font, icon theme, and color scheme visible in this screenshot.";
    default:
        return "Describe what you see in this image.";
    }
}
