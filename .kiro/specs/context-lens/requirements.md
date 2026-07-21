# Requirements: Context Lens

## Overview

Context Lens is an AI-powered visual analysis tool integrated into the Quickshell desktop shell. It allows users to select a region, window, or full screen, then send that image to a vision-capable AI model with a specific action (explain, extract text, translate, summarize, identify error, generate command). Results appear in a floating overlay near the selection or route into the AI sidebar chat.

## Functional Requirements

### 1. Capture and Selection

1.1. The user triggers Context Lens via `Super+Shift+A` (already reserved as `quickshell:regionSearch`).
1.2. The overlay freezes the screen (like the existing screenshot tool) and presents selectable regions.
1.3. Region types: custom drag rectangle, detected window regions, detected image content regions (reusing screenshot.qml patterns).
1.4. After selecting a region, an action wheel appears near the selection showing available actions.
1.5. The user can also trigger Context Lens on the clipboard image (if the clipboard contains an image) via `Super+Shift+V`.

### 2. Action Wheel

2.1. The action wheel displays 6–8 circular action buttons around or adjacent to the selected region.
2.2. Built-in actions: "Explain this", "Extract text", "Translate", "Summarize", "Explain error", "Generate command", "Ask a question", "Identify UI".
2.3. "Ask a question" opens a text input overlay for a freeform prompt about the selected image.
2.4. Actions are configurable — users can hide/reorder them via config.
2.5. Clicking an action sends the cropped image + action-specific system prompt to the AI.

### 3. Vision API Integration

3.1. `AiMessageData` must support an `images` property (list of base64-encoded image strings).
3.2. `OpenAiApiStrategy` must support the multimodal message format: `content: [{type:"text", text:...}, {type:"image_url", image_url:{url:"data:image/png;base64,..."}}]`.
3.3. `GeminiApiStrategy` must support inline image data: `parts: [{text:...}, {inlineData:{mimeType:"image/png", data:"..."}}]`.
3.4. `BedrockApiStrategy` must support Bedrock Converse image format: `content: [{text:...}, {image:{format:"png", source:{bytes:"..."}}}]`.
3.5. The system must detect which models support vision (via capability metadata or a hardcoded allowlist) and auto-select an appropriate model.
3.6. If no vision-capable model is configured/authenticated, show an error directing the user to set one up in the Providers panel.

### 4. Results Display

4.1. Results appear in a floating overlay panel anchored near the selected region.
4.2. The overlay uses the same visual language as the notification popup (Material You colors, rounded corners, layer shell overlay).
4.3. Results stream in real-time as the model generates them (character by character or chunk by chunk).
4.4. The overlay includes action buttons: "Copy" (copies result text), "Send to chat" (opens result in sidebar AI chat), "Dismiss".
4.5. For "Extract text" and "Generate command" actions, a "Paste" button inserts the result into the focused application.
4.6. The overlay auto-dismisses after 30 seconds of inactivity (configurable).
4.7. For "Translate" action, results show original + translated text side by side if space permits.

### 5. AI Chat Integration

5.1. "Send to chat" routes the image + result into the sidebar AI chat as a new message with the image attached.
5.2. The sidebar AI chat must be able to render inline images in message history.
5.3. Users can continue a conversation about the image in the sidebar after routing.

### 6. Error Handling

6.1. If the AI request fails (network error, timeout, invalid model), show the error in the results overlay with a "Retry" button.
6.2. If the selected region is too small (< 10x10 pixels), show a hint to select a larger area.
6.3. Timeout: 30 seconds for the AI response. Show a cancel button during loading.

### 7. Configuration

7.1. Config key `contextLens.defaultAction` — the action to auto-execute on single-click (default: show action wheel).
7.2. Config key `contextLens.preferredVisionModel` — override auto-selection with a specific model ID.
7.3. Config key `contextLens.actions` — array of enabled action IDs and their order.
7.4. Config key `contextLens.resultTimeout` — auto-dismiss timeout in seconds (default: 30).
7.5. Config key `contextLens.translateTargetLang` — target language for translations (default: "English").

### 8. Policy Enforcement

8.1. If `policies.ai === 0`, Context Lens keybind does nothing (AI disabled).
8.2. If `policies.ai === 2`, only local vision models are used (no online API calls with screenshot data).
8.3. Image data is never persisted to disk unless the user explicitly saves or routes to chat with persistence enabled.

### 9. Performance

9.1. Image encoding (crop + base64) must complete in under 500ms.
9.2. The action wheel must appear within 200ms of region selection completing.
9.3. The overlay must not block other desktop interactions — clicking outside dismisses it.

## Non-Functional Requirements

10.1. All QML follows existing project patterns: `pragma ComponentBehavior: Bound`, indexed for loops, no spread operator, Process for subprocess calls.
10.2. The Context Lens overlay reuses the screenshot.qml region selection UI code (not duplicated).
10.3. The feature must work with the existing quickshell binary without additional native dependencies beyond `grim` and `ImageMagick` (already present).
