# Design: Context Lens

## Architecture

Context Lens is implemented as a standalone Quickshell application (`contextlens.qml`) launched via keybind, similar to `screenshot.qml`. It reuses the screenshot tool's region selection infrastructure and extends the AI service with multimodal (vision) message support.

```
┌──────────────────────────────────────────────────────────────┐
│  contextlens.qml (standalone ShellRoot)                       │
│  ┌──────────────────┐  ┌──────────────────┐                  │
│  │ Region Selector  │→ │ Action Wheel     │                  │
│  │ (from screenshot)│  │ (radial buttons) │                  │
│  └──────────────────┘  └────────┬─────────┘                  │
│                                  │ user picks action          │
│                        ┌─────────▼──────────┐                 │
│                        │ VisionRequest       │                 │
│                        │ • crop image        │                 │
│                        │ • base64 encode     │                 │
│                        │ • build prompt      │                 │
│                        │ • call AI service   │                 │
│                        └─────────┬──────────┘                 │
│                                  │                             │
│                        ┌─────────▼──────────┐                 │
│                        │ ResultOverlay       │                 │
│                        │ • streaming text    │                 │
│                        │ • action buttons    │                 │
│                        │ • auto-dismiss      │                 │
│                        └────────────────────┘                 │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  services/Ai.qml (modified — shared singleton)                │
│  • AiMessageData.images: list<string>                         │
│  • OpenAiApiStrategy — multimodal content array               │
│  • GeminiApiStrategy — inlineData parts                       │
│  • BedrockApiStrategy — image content blocks                  │
│  • sendVisionMessage(text, images) new function               │
└──────────────────────────────────────────────────────────────┘
```

## Component Design

### ContextLens.qml (standalone app)

Launched by `quickshell -p contextlens.qml`. Full-screen overlay per monitor (same pattern as screenshot.qml).

**States:**
1. `Selecting` — frozen screen, region hover/drag active
2. `ActionWheel` — region selected, showing action buttons
3. `Loading` — action picked, waiting for AI response
4. `Result` — showing streamed response
5. `Error` — showing error with retry

**Key differences from screenshot.qml:**
- After selection: shows action wheel instead of immediately copying to clipboard
- Result display: floating overlay near selection instead of just piping to clipboard
- Requires AI service access (imports Ai singleton)

### ActionWheel.qml (component)

A radial or grid layout of action buttons that appears next to the selected region.

**Properties:**
- `regionX, regionY, regionWidth, regionHeight` — where to position relative to
- `actions: list<var>` — array of `{id, icon, label, prompt}`

**Built-in action prompts:**
| Action | System Prompt |
|--------|--------------|
| Explain | "Describe what you see in this screenshot in detail. Explain any UI elements, text, or content visible." |
| Extract text | "Extract ALL text visible in this image. Return only the extracted text, preserving layout where possible." |
| Translate | "Translate all text visible in this image to {targetLang}. Show original and translation." |
| Summarize | "Summarize the content shown in this screenshot in 2-3 sentences." |
| Explain error | "This screenshot shows an error or problem. Identify the error, explain the likely cause, and suggest a fix." |
| Generate command | "Based on what's shown in this screenshot, generate the shell command(s) that would accomplish or fix what's shown. Return only the command(s)." |
| Ask a question | (user-provided prompt) |
| Identify UI | "Identify the application, UI framework, font, icon theme, and color scheme visible in this screenshot." |

### VisionRequest (internal logic)

1. Crop the screenshot to the selected region using ImageMagick (`magick input.png -crop WxH+X+Y output.png`)
2. Read the cropped file and base64 encode it
3. Determine the vision model (prefer `contextLens.preferredVisionModel`, fall back to first authenticated vision-capable model)
4. Build the message with image attachment
5. Send via a dedicated Process (curl) — similar to ActionPalette's LLM request pattern but with vision payload

### ResultOverlay.qml (component)

A floating panel that appears near the selected region showing the AI response.

**Properties:**
- `text: string` — streamed result text
- `loading: bool` — show spinner
- `error: string` — error message
- `actions: list<var>` — contextual action buttons

**Layout:**
- Material You rounded rectangle, semi-transparent background
- Max width: 500px, max height: 400px (scrollable)
- Position: below the selected region if space, above otherwise, horizontally centered on the region

### Vision Model Detection

Models that support vision (hardcoded allowlist until capability metadata is implemented):
- `gpt-4o`, `gpt-4o-mini`, `gpt-4-turbo`, `gpt-4.1`, `gpt-4.1-mini`
- `gemini-*` (all Gemini models support vision)
- `claude-3-*`, `claude-4-*` (Anthropic vision models)
- `llava-*`, `llava:*` (Ollama local vision models)
- `pixtral-*` (Mistral vision)
- Any model with "vision" in its ID

The detection function: `isVisionCapable(modelId)` checks the allowlist patterns.

## Data Flow

```
Keybind (Super+Shift+A)
  → launch contextlens.qml
  → grim captures screen (frozen)
  → user selects region (drag or click)
  → action wheel appears
  → user clicks action
  → magick crops region → /tmp/contextlens-crop.png
  → base64 encode crop
  → curl POST to vision model endpoint
  → stream response to ResultOverlay
  → user copies/dismisses/routes to chat
  → contextlens.qml exits
```

## IPC Integration

The main quickshell shell (`ii/shell.qml`) handles the `quickshell:regionSearch` global signal by launching the context lens app:

```qml
GlobalShortcut {
    name: "regionSearch"
    onPressed: Quickshell.execDetached(["quickshell", "-p", Quickshell.shellPath("contextlens.qml")])
}
```

For "Send to chat" routing, the context lens process sends an IPC message to the main shell:
```
quickshell -c ii ipc call aiChat sendImageMessage <base64> <resultText>
```

## Testing Strategy

**Property tests (fast-check + vitest):**
1. Image base64 encoding round-trip
2. Vision model detection covers all known patterns
3. Action prompt construction produces valid multimodal payloads
4. Region crop coordinates are correctly transformed per monitor scale
5. Result text truncation for overlay display

**Integration tests:**
1. Full flow with mocked curl (select region → action → mocked response → display)
2. Policy enforcement blocks online models in local-only mode
3. Error handling: timeout, network failure, no vision model configured
4. Multi-monitor coordinate transformation
