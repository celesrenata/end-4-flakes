# Design Document: Voice Assistant Mode

## Overview

Extends the existing DictationService singleton to include a voice assistant pipeline that activates when the sidebar is closed. The pipeline: STT → Intent Classification → Action Execution (or Dictation Capture) → Concise Response → TTS Talkback → Floating Indicator display. All voice interactions are logged to a persistent "Free Dictation" session. A settings UI section configures STT/TTS providers.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ DictationService.qml (extended)                                      │
│                                                                       │
│  transcription complete                                               │
│         │                                                             │
│         ▼                                                             │
│  ┌─── sidebar open? ───┐                                             │
│  │ YES                  │ NO                                          │
│  ▼                      ▼                                             │
│  Input field       IntentClassifier                                   │
│  (existing)         │          │                                      │
│                "command"    "dictation"                                │
│                     │          │                                       │
│                     ▼          ▼                                       │
│              ActionPalette   Free Dictation                            │
│              .submitQuery()  Session (append)                          │
│                     │          │                                       │
│                     ▼          ▼                                       │
│              Execute plan   Floating Indicator                         │
│                     │       "Captured"                                 │
│                     ▼                                                  │
│              Concise response                                         │
│                     │                                                  │
│                     ├─── talkback? ──► TTS Engine ──► pw-play          │
│                     │                                                  │
│                     ▼                                                  │
│              Floating Response Indicator                               │
│              + log to Free Dictation Session                           │
└─────────────────────────────────────────────────────────────────────┘
```

## Component Design

### 1. Intent Classifier (within DictationService.qml)

**Type:** Pure JavaScript function  
**Location:** `DictationService._classifyIntent(text) → "command" | "dictation"`  
**Requirements:** 7.1–7.7

```
function _classifyIntent(text):
    words = text.trim().split(/\s+/)
    firstWord = words[0].toLowerCase()
    
    // Imperative verbs → command
    if firstWord in COMMAND_VERBS: return "command"
    
    // Question starters → command
    if firstWord in QUESTION_WORDS: return "command"
    
    // Contains question mark → command
    if text.includes("?"): return "command"
    
    // Long text without command patterns → dictation
    if words.length > 20: return "dictation"
    
    // Ambiguous short text → default to command
    return "command"
```

Constants:
- `COMMAND_VERBS`: open, close, launch, set, change, toggle, switch, move, kill, run, show, hide, play, pause, stop, mute, unmute, find, search, check, tell, give, list
- `QUESTION_WORDS`: what, how, when, where, who, which, is, are, can, do, does, will, would, should, could

When `intentMode === "ai"`, the classifier sends a lightweight LLM call with a classification prompt for ambiguous cases only.

### 2. Voice Assistant Pipeline (within DictationService.qml)

**Type:** New function `_processVoiceAssistant(text)`  
**Location:** DictationService.qml  
**Requirements:** 1.1–1.6, 2.1–2.5, 12.2–12.4

Flow:
1. Classify intent via `_classifyIntent(text)`
2. Log to Free Dictation session: `Ai.addMessageToSession("Free Dictation", text, "user")`
3. If "dictation": show brief "Captured" indicator, emit signal, done
4. If "command": inject voice-assistant system prompt into ActionPalette, call `ActionPalette.submitQueryDirect(text, voiceAssistantSystemPrompt)`
5. Listen for `ActionPalette.actionPlanReady` signal
6. Auto-execute safe actions (config.set, hyprland.dispatch, app.launch)
7. Prompt for shell.exec approval via Floating Response Indicator
8. On completion: get summary text, show in indicator, log to session, trigger TTS if enabled

**Voice assistant system prompt** (appended to the action palette's LLM request):
```
Respond concisely in natural spoken language. For simple lookups, one sentence max.
For moderate queries, up to three short sentences. Only give detailed responses
when explicitly asked for detail. Use contractions and informal units (gigs, megs).
No markdown formatting, no tables, no bullet points — plain spoken text only.
```

### 3. TTS Engine (new singleton: TtsService.qml)

**Type:** Singleton service  
**Location:** `configs/quickshell/ii/services/TtsService.qml`  
**Requirements:** 3.1–3.7, 11.1–11.5

Properties:
- `property string provider: Config.options.dictation.ttsProvider` ("none", "piper", "espeak-ng", "openai")
- `property string voice: Config.options.dictation.ttsVoice`
- `property bool playing: ttsProcess.running`

Key function: `speak(text)`:
```
function speak(text):
    if provider === "none": return
    if playing: stop()
    
    switch provider:
        "piper":
            command = ["sh", "-c", 
                `echo '${escaped}' | piper --model ${voice} --output_raw | pw-play --format=s16 --rate=22050 --channels=1 -`]
        "espeak-ng":
            command = ["sh", "-c",
                `espeak-ng "${escaped}" --stdout | pw-play -`]
        "openai":
            command = ["sh", "-c",
                `curl -s https://api.openai.com/v1/audio/speech -H "Authorization: Bearer ${apiKey}" -H "Content-Type: application/json" -d '{"model":"tts-1","input":"${escaped}","voice":"${voice || 'nova'}"}' | pw-play -`]
    
    ttsProcess.command = command
    ttsProcess.running = true
```

Key function: `stop()`:
```
function stop():
    ttsProcess.running = false  // sends SIGTERM
```

### 4. Floating Response Indicator (extend DictationIndicator.qml)

**Type:** Extension of existing DictationIndicator PanelWindow  
**Location:** `configs/quickshell/ii/modules/dictation/DictationIndicator.qml`  
**Requirements:** 8.1–8.7

New states to handle:
- `VoiceResponse` — show response text + optional TTS icon
- `Approval` — show command + approve/reject buttons

New properties on DictationService:
- `property string responseText: ""`
- `property bool awaitingApproval: false`
- `property string approvalCommand: ""`

The indicator expands to 500px max width when showing response text. Auto-dismiss timer (4s) starts when TTS finishes or immediately if talkback is off.

### 5. Free Dictation Session (within Ai.qml)

**Type:** Extension of existing session management  
**Location:** `configs/quickshell/ii/services/Ai.qml`  
**Requirements:** 4.1–4.6

New functions on Ai singleton:
- `ensureFreeDictationSession()` — create "Free Dictation" if it doesn't exist
- `appendToFreeDictation(text, role)` — add message without switching active session

The session uses the existing `sessions-index.json` / `chats/<name>.json` storage. On Quickshell start, `ensureFreeDictationSession()` is called. The session cannot be deleted (UI skips it in delete button rendering).

### 6. ActionPalette Extension

**Type:** New function on existing ActionPalette singleton  
**Location:** `configs/quickshell/services/ActionPalette.qml`  
**Requirements:** 1.1–1.6, 2.1–2.5

New function: `submitQueryDirect(queryText, extraSystemPrompt)`:
- Same as `submitQuery` but:
  - Does NOT require overview to be open
  - Appends `extraSystemPrompt` to the LLM system prompt
  - Emits `actionPlanReady` signal when plan is received
  - Returns the plan summary text via a new signal `responseSummary(text)`

### 7. Provider Settings Panel (new QML component)

**Type:** ContentSection within StyleConfig.qml or a new VoiceAssistantConfig.qml  
**Location:** `configs/quickshell/ii/modules/settings/VoiceAssistantConfig.qml`  
**Requirements:** 6.1–6.9

Adds a "Voice Assistant" tab/section to the settings app with:
- STT provider dropdown
- STT endpoint text field
- STT model text field  
- TTS provider dropdown
- TTS voice text field
- Talkback toggle
- Intent mode selector (heuristic / ai)

### 8. Config.qml Extensions

**Requirements:** 9.1–9.6

New keys added to `dictation` JsonObject:
```qml
property string ttsProvider: "none"      // none, piper, espeak-ng, openai
property string ttsVoice: ""             // Provider-specific voice ID
property bool talkback: false            // Enable TTS playback
property string intentMode: "heuristic"  // heuristic, ai
property string httpEndpoint: ""         // HTTP batch endpoint for STT
```

## Data Flow

### Voice Command (sidebar closed, intent = "command"):
1. Audio → STT → text
2. `_classifyIntent(text)` → "command"
3. `Ai.appendToFreeDictation(text, "user")`
4. `ActionPalette.submitQueryDirect(text, voicePrompt)` 
5. Wait for `actionPlanReady` / `responseSummary`
6. Auto-execute safe actions
7. Show summary in Floating Response Indicator
8. `Ai.appendToFreeDictation(summary, "assistant")`
9. If talkback: `TtsService.speak(summary)`

### Pure Dictation (sidebar closed, intent = "dictation"):
1. Audio → STT → text
2. `_classifyIntent(text)` → "dictation"
3. `Ai.appendToFreeDictation(text, "user")`
4. Show "Captured to Free Dictation" in Floating Response Indicator (2s)
5. No TTS, no action execution

### Sidebar Open (unchanged):
1. Audio → STT → text
2. Append to input field (existing behavior)
3. No intent classification, no voice assistant pipeline

## File Changes

| File | Change |
|------|--------|
| `ii/services/DictationService.qml` | Add `_classifyIntent`, `_processVoiceAssistant`, response properties, TTS integration |
| `ii/services/TtsService.qml` | **New** — TTS singleton |
| `ii/services/qmldir` | Add TtsService registration |
| `ii/services/Ai.qml` | Add `ensureFreeDictationSession`, `appendToFreeDictation` |
| `ii/modules/dictation/DictationIndicator.qml` | Extend with VoiceResponse and Approval states |
| `ii/modules/common/Config.qml` | Add ttsProvider, ttsVoice, talkback, intentMode, httpEndpoint |
| `ii/modules/settings/VoiceAssistantConfig.qml` | **New** — Settings panel section |
| `ii/settings.qml` | Add VoiceAssistant page to pages array |
| `services/ActionPalette.qml` | Add `submitQueryDirect`, `responseSummary` signal |

## Testing Strategy

- **Intent classifier**: Property-based tests with Hypothesis — for any text, returns exactly "command" or "dictation"
- **TTS pipeline**: Integration test with mock pw-play verifying audio format and cleanup
- **Free Dictation session**: Unit test verifying session creation, append, persistence
- **ActionPalette direct mode**: Integration test verifying execution without overview open
- **Config persistence**: Verify all new keys read/write correctly
