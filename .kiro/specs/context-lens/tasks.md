# Implementation Plan: Context Lens

## Overview

Implements an AI-powered visual analysis tool triggered via keybind. Reuses the screenshot tool's region selection, adds an action wheel for intent selection, extends the AI service with vision/multimodal support, and displays streaming results in a floating overlay. Implementation proceeds: vision API support → context lens app skeleton → action wheel → vision request pipeline → result overlay → chat integration → policy enforcement → tests.

## Tasks

- [x] 1. Vision API support in Ai service
  - [x] 1.1 Add images property to AiMessageData
    - Add `property list<string> images: []` to `services/ai/AiMessageData.qml`
    - Images are base64-encoded PNG strings (no data: prefix, just raw base64)
    - _Requirements: 3.1_

  - [x] 1.2 Extend OpenAiApiStrategy for multimodal messages
    - In `buildRequestData`: when a message has `images.length > 0`, use content array format instead of plain string
    - Format: `content: [{type:"text", text:msg.rawContent}, ...images.map(img => ({type:"image_url", image_url:{url:"data:image/png;base64," + img}}))]`
    - Messages without images continue to use plain string content
    - File: `services/ai/OpenAiApiStrategy.qml`
    - _Requirements: 3.2_

  - [x] 1.3 Extend GeminiApiStrategy for multimodal messages
    - In `buildRequestData`: when a message has `images.length > 0`, add `inlineData` parts
    - Format: `parts: [{text:msg.rawContent}, ...images.map(img => ({inlineData:{mimeType:"image/png", data:img}}))]`
    - File: `services/ai/GeminiApiStrategy.qml`
    - _Requirements: 3.3_

  - [x] 1.4 Extend BedrockApiStrategy for multimodal messages
    - In `buildRequestData`: when a message has images, use image content blocks
    - Format: `content: [{text:msg.rawContent}, ...images.map(img => ({image:{format:"png", source:{bytes:img}}}))]`
    - File: `services/ai/BedrockApiStrategy.qml`
    - _Requirements: 3.4_

  - [x] 1.5 Add sendVisionMessage function to Ai.qml
    - New function `sendVisionMessage(text, images, onChunk, onDone, onError)` — fires a one-shot vision request without affecting chat history
    - Creates a temporary Process with curl, builds request via current model's API strategy
    - Streams response chunks via `onChunk(text)`, calls `onDone()` on completion, `onError(msg)` on failure
    - Does not modify `root.messages` — this is a standalone request
    - File: `services/Ai.qml`
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [x] 1.6 Implement isVisionCapable model detection
    - Add function `isVisionCapable(modelId)` to `Ai.qml`
    - Checks against known patterns: gpt-4o*, gpt-4-turbo, gpt-4.1*, gemini-*, claude-3-*, claude-4-*, llava*, pixtral*, *vision*
    - Returns bool
    - Add `property string bestVisionModel` computed property that returns the first authenticated vision-capable model ID, or empty string
    - File: `services/Ai.qml`
    - _Requirements: 3.5, 3.6_

- [x] 2. Checkpoint — Vision API verified
  - Verify multimodal request payloads are correctly structured for each provider format. Ask the user if questions arise.

- [x] 3. Context Lens application skeleton
  - [x] 3.1 Create contextlens.qml standalone ShellRoot
    - Create `configs/quickshell/contextlens.qml` as a standalone quickshell app
    - Same structure as `screenshot.qml`: ShellRoot → Variants per screen → PanelWindow overlay
    - Import shared modules (Appearance, Config, Ai, MaterialThemeLoader, HyprlandData)
    - Define state enum: Selecting, ActionWheel, Loading, Result, Error
    - Freeze screen via `grim -o` capture (same as screenshot.qml)
    - File: `configs/quickshell/contextlens.qml`
    - _Requirements: 1.1, 1.2, 1.3, 10.2_

  - [x] 3.2 Implement region selection (reuse screenshot.qml patterns)
    - Copy/adapt the region detection and selection logic from screenshot.qml:
      - Window regions from HyprlandData
      - Drag-to-select custom rectangle
      - `TargetRegion` component for visual feedback
      - `updateTargetedRegion(x, y)` hit-testing
    - On selection complete (mouseRelease or click): transition to ActionWheel state
    - Store `selectedRegionX/Y/Width/Height` for cropping
    - _Requirements: 1.2, 1.3, 9.2_

  - [x] 3.3 Wire keybind to launch contextlens.qml
    - Add GlobalShortcut handler for `regionSearch` in `ii/shell.qml` (or verify existing handler launches this)
    - Alternatively: update the keybind fallback in `keybinds.conf.template` to launch `quickshell -p contextlens.qml`
    - _Requirements: 1.1_

- [x] 4. Action Wheel UI
  - [x] 4.1 Create ActionWheel.qml component
    - Grid or radial layout of action buttons positioned near the selected region
    - Each button: Material Symbol icon + label text
    - Buttons: Explain, Extract text, Translate, Summarize, Explain error, Generate command, Ask a question, Identify UI
    - Clicking a button emits `actionSelected(actionId)` signal
    - Position logic: prefer below the region, shift above if near screen bottom
    - File: `configs/quickshell/modules/contextlens/ActionWheel.qml` (or inline in contextlens.qml)
    - _Requirements: 2.1, 2.2, 2.3, 2.5, 9.2_

  - [x] 4.2 Implement "Ask a question" text input
    - When "Ask a question" is selected, show a text input field below the action wheel
    - On Enter/submit: use the typed text as the user prompt
    - On Escape: cancel and return to action wheel
    - _Requirements: 2.3_

  - [x] 4.3 Add action configuration support
    - Read enabled actions and order from `Config.options.contextLens.actions`
    - Default: all actions enabled in standard order
    - Hidden actions are not shown in the wheel
    - File: `configs/quickshell/contextlens.qml`
    - _Requirements: 2.4, 7.3_

- [x] 5. Vision Request Pipeline
  - [x] 5.1 Implement image cropping via ImageMagick
    - On action selected: run `magick <screenshot> -crop WxH+X+Y /tmp/contextlens-crop.png`
    - Account for monitor scale factor (multiply coordinates by scale)
    - Verify crop dimensions are >= 10x10 pixels (Requirement 6.2)
    - File: `configs/quickshell/contextlens.qml`
    - _Requirements: 9.1, 6.2_

  - [x] 5.2 Implement base64 encoding of cropped image
    - Run `base64 -w0 /tmp/contextlens-crop.png` via Process
    - Store result in a property for the vision request
    - Clean up temp files on exit
    - _Requirements: 9.1_

  - [x] 5.3 Implement vision request Process
    - Determine vision model: check `Config.options.contextLens.preferredVisionModel`, fall back to `Ai.bestVisionModel`
    - If no vision model available: transition to Error state (Requirement 3.6)
    - Build action-specific system prompt based on selected action ID
    - Build curl command with multimodal payload (using the model's API strategy format)
    - Set 30-second timeout timer
    - Stream response via SplitParser on stdout
    - On completion: transition to Result state
    - On error/timeout: transition to Error state
    - File: `configs/quickshell/contextlens.qml`
    - _Requirements: 3.5, 3.6, 6.1, 6.3, 7.2_

  - [x] 5.4 Implement action-specific system prompts
    - Define prompt templates for each action (explain, extract_text, translate, summarize, explain_error, generate_command, identify_ui)
    - For translate: include `Config.options.contextLens.translateTargetLang` in the prompt
    - For ask_question: use the user's typed text as the prompt
    - File: `configs/quickshell/contextlens.qml`
    - _Requirements: 2.2, 7.5_

- [x] 6. Checkpoint — Vision request works end-to-end
  - Verify region selection → crop → encode → send to AI → receive response. Ask the user if questions arise.

- [x] 7. Result Overlay UI
  - [x] 7.1 Create ResultOverlay.qml component
    - Floating `Rectangle` with Material You styling (colLayer1, rounded corners, shadow)
    - Max width 500px, max height 400px, scrollable content
    - Position: anchored near the selected region (below if space, above otherwise)
    - Shows streaming text (updates as chunks arrive)
    - Loading state: show BusyIndicator + "Analyzing..."
    - Error state: show error message + Retry button
    - _Requirements: 4.1, 4.2, 4.3, 6.1_

  - [x] 7.2 Add result action buttons
    - Bottom bar with: "Copy" (copies text to clipboard), "Send to chat", "Dismiss"
    - For extract_text/generate_command actions: add "Paste" button (types text into focused app via ydotool or wl-copy + paste)
    - "Dismiss" or clicking outside closes the overlay and exits contextlens.qml
    - _Requirements: 4.4, 4.5_

  - [x] 7.3 Implement auto-dismiss timer
    - Start a timer when result is fully loaded (onDone)
    - Duration from `Config.options.contextLens.resultTimeout` (default 30s)
    - Reset timer on any user interaction (scroll, hover)
    - On expire: dismiss overlay and exit
    - _Requirements: 4.6, 7.4_

  - [x] 7.4 Implement click-outside-to-dismiss
    - MouseArea covering the full screen behind the overlay
    - Clicking it dismisses the result and exits contextlens.qml
    - _Requirements: 9.3_

- [x] 8. AI Chat Integration
  - [x] 8.1 Add IPC handler in ii/shell.qml for receiving vision results
    - IpcHandler target "contextLens" with function `sendToChat(imageBase64, resultText, actionLabel)`
    - On receive: open sidebar left, switch to AI chat tab, insert a message with the image + result
    - _Requirements: 5.1, 5.3_

  - [x] 8.2 Add image rendering in AI chat message bubbles
    - When a message has `images.length > 0`, render a thumbnail above the text content
    - Clickable thumbnail opens the full image in a popup or default image viewer
    - File: `modules/sidebarLeft/AiChatMessage.qml` (or equivalent)
    - _Requirements: 5.2_

  - [x] 8.3 Implement "Send to chat" action in ResultOverlay
    - On click: encode the IPC call to the main shell via `quickshell -c ii ipc call contextLens sendToChat <args>`
    - Pass image base64 + result text + action label
    - Then exit contextlens.qml
    - _Requirements: 5.1_

- [x] 9. Policy Enforcement
  - [x] 9.1 Check policies.ai before launching
    - If `policies.ai === 0`: show a brief notification "AI is disabled" and exit immediately
    - If `policies.ai === 2`: filter `bestVisionModel` to only include local models (ollama, localhost endpoints)
    - _Requirements: 8.1, 8.2_

  - [x] 9.2 Ensure no image persistence
    - Delete `/tmp/contextlens-crop.png` after base64 encoding
    - Never write image data to persistent storage (only memory + /tmp during the request)
    - _Requirements: 8.3_

- [x] 10. Configuration keys
  - [x] 10.1 Add contextLens config section to Config.qml
    - Add to `modules/common/Config.qml`:
      ```
      property JsonObject contextLens: JsonObject {
          property string defaultAction: "wheel"
          property string preferredVisionModel: ""
          property var actions: ["explain", "extract_text", "translate", "summarize", "explain_error", "generate_command", "ask_question", "identify_ui"]
          property int resultTimeout: 30
          property string translateTargetLang: "English"
      }
      ```
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

- [x] 11. Checkpoint — Full feature verified
  - End-to-end: keybind → select region → action wheel → AI response → copy/dismiss/send to chat. Ask the user if questions arise.

- [x] 12. Property-based tests
  - [x] 12.1 Write property test: vision model detection patterns
    - For known vision model IDs: `isVisionCapable` returns true
    - For known non-vision model IDs: returns false
    - File: `tests/js/src/context-lens-logic.test.js`
    - _Validates: Requirements 3.5_

  - [x] 12.2 Write property test: multimodal payload construction (OpenAI format)
    - For any text + base64 image: payload has correct structure with content array
    - File: `tests/js/src/context-lens-logic.test.js`
    - _Validates: Requirements 3.2_

  - [x] 12.3 Write property test: multimodal payload construction (Gemini format)
    - For any text + base64 image: payload has inlineData parts
    - File: `tests/js/src/context-lens-logic.test.js`
    - _Validates: Requirements 3.3_

  - [x] 12.4 Write property test: region crop coordinate transformation
    - For any monitor scale and region coordinates: transformed coordinates are correctly scaled
    - File: `tests/js/src/context-lens-logic.test.js`
    - _Validates: Requirements 9.1_

  - [x] 12.5 Write property test: action prompt construction
    - For each action ID: prompt template is non-empty and contains action-relevant keywords
    - File: `tests/js/src/context-lens-logic.test.js`
    - _Validates: Requirements 2.2_

- [x] 13. Integration tests
  - [x] 13.1 Write integration test: full vision request cycle with mocked response
    - Mock curl process to return streamed vision response
    - Verify image is included in payload, response streams to overlay
    - File: `tests/js/src/context-lens-integration.test.js`
    - _Requirements: 3.1, 4.3_

  - [x] 13.2 Write integration test: policy enforcement
    - Verify policies.ai=0 blocks launch
    - Verify policies.ai=2 filters to local-only vision models
    - File: `tests/js/src/context-lens-integration.test.js`
    - _Requirements: 8.1, 8.2_

  - [x] 13.3 Write integration test: error handling
    - Verify timeout shows error with retry
    - Verify no vision model shows setup guidance
    - Verify too-small region shows hint
    - File: `tests/js/src/context-lens-integration.test.js`
    - _Requirements: 6.1, 6.2, 6.3_

- [x] 14. Final checkpoint
  - All tests pass, feature works end-to-end. Ask the user if questions arise.

## Notes

- Context Lens is a standalone quickshell app (like screenshot.qml) — not part of the main shell process
- It communicates with the main shell via IPC for "Send to chat" functionality
- The vision request uses a separate Process/curl call (doesn't reuse Ai.qml's requester to avoid state interference)
- Region selection code is adapted from screenshot.qml, not duplicated — shared via module or direct adaptation
- Image data flows: grim capture → display → user selects → magick crop → base64 → API request → response overlay
- Temp files in /tmp are cleaned up on exit (Component.onDestruction)
- The action wheel position adapts to screen edges (doesn't go off-screen)

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.3", "1.4"] },
    { "id": 1, "tasks": ["1.5", "1.6"] },
    { "id": 2, "tasks": ["3.1", "3.2", "3.3", "10.1"] },
    { "id": 3, "tasks": ["4.1", "4.2", "4.3"] },
    { "id": 4, "tasks": ["5.1", "5.2"] },
    { "id": 5, "tasks": ["5.3", "5.4"] },
    { "id": 6, "tasks": ["7.1", "7.2", "7.3", "7.4"] },
    { "id": 7, "tasks": ["8.1", "8.2", "8.3"] },
    { "id": 8, "tasks": ["9.1", "9.2"] },
    { "id": 9, "tasks": ["12.1", "12.2", "12.3", "12.4", "12.5"] },
    { "id": 10, "tasks": ["13.1", "13.2", "13.3"] }
  ]
}
```
