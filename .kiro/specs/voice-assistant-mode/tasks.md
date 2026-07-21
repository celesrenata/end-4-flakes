# Implementation Plan: Voice Assistant Mode

## Overview

Transform the existing dictation system into a full voice assistant. When the sidebar is closed, dictated text is classified (command vs dictation), commands execute directly via ActionPalette without opening the overview, concise responses display in a floating indicator, and optionally speak back via TTS. All interactions log to a persistent "Free Dictation" session. A settings panel configures STT/TTS providers.

## Tasks

- [x] 1. Configuration Extensions
  - [x] 1.1 Add voice assistant config keys to Config.qml
    - Add to the `dictation` JsonObject in `ii/modules/common/Config.qml`:
      - `property string ttsProvider: "none"` (none, piper, espeak-ng, openai)
      - `property string ttsVoice: ""` (provider-specific voice ID)
      - `property bool talkback: false` (enable TTS playback)
      - `property string intentMode: "heuristic"` (heuristic, ai)
      - `property string httpEndpoint: ""` (HTTP batch endpoint for STT)
    - Also add to `configs/quickshell/modules/common/Config.qml` (non-ii version) for consistency
    - File: `ii/modules/common/Config.qml`, `modules/common/Config.qml`
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_

- [x] 2. Intent Classifier
  - [x] 2.1 Implement heuristic intent classification in DictationService
    - Add `_classifyIntent(text)` function returning "command" or "dictation"
    - Implement COMMAND_VERBS list (open, close, launch, set, change, toggle, switch, move, kill, run, show, hide, play, pause, stop, mute, unmute, find, search, check, tell, give, list)
    - Implement QUESTION_WORDS list (what, how, when, where, who, which, is, are, can, do, does, will, would, should, could)
    - Logic: imperative verb → command, question word → command, has "?" → command, >20 words without patterns → dictation, else → command (default)
    - File: `ii/services/DictationService.qml`
    - _Requirements: 7.1, 7.2, 7.3, 7.5, 7.7_

  - [x] 2.2 Implement AI-based intent classification (optional mode)
    - When `Config.options.dictation.intentMode === "ai"`, for ambiguous cases (short text, no pattern match), send a lightweight LLM classification request
    - Prompt: "Classify this as 'command' or 'dictation'. Reply with one word only: <text>"
    - Use the current model from Ai.qml, timeout 2s, default to "command" on failure
    - File: `ii/services/DictationService.qml`
    - _Requirements: 7.4_

- [x] 3. Free Dictation Session
  - [x] 3.1 Add session management functions to Ai.qml
    - Add `function ensureFreeDictationSession()` — creates "Free Dictation" session if it doesn't exist, called on Component.onCompleted
    - Add `function appendToFreeDictation(text, role)` — appends a message to the Free Dictation session without switching the active session
    - Use existing session storage (`sessions-index.json`, `chats/Free Dictation.json`)
    - File: `ii/services/Ai.qml`
    - _Requirements: 4.1, 4.2, 4.3, 4.6_

  - [x] 3.2 Prevent deletion of Free Dictation session in UI
    - In `AiChat.qml` session drawer, hide the delete button when `modelData.name === "Free Dictation"`
    - File: `ii/modules/sidebarLeft/AiChat.qml`
    - _Requirements: 4.1_

  - [x] 3.3 Add re-send capability for Free Dictation messages
    - In the session drawer or message context menu, add a "Re-send" action for user messages in the Free Dictation session
    - When activated, call `DictationService._processVoiceAssistant(messageText)`
    - File: `ii/modules/sidebarLeft/AiChat.qml`
    - _Requirements: 4.5_

- [x] 4. ActionPalette Direct Execution
  - [x] 4.1 Add submitQueryDirect function to ActionPalette
    - Add `function submitQueryDirect(queryText, extraSystemPrompt)` that:
      - Does NOT require `GlobalStates.overviewOpen`
      - Appends `extraSystemPrompt` to the LLM system prompt for this request
      - Processes the query through the same LLM pipeline as `submitQuery`
      - Emits existing `actionPlanReady` signal when plan is received
    - Add `signal responseSummary(string text)` — emitted with the plan summary
    - File: `services/ActionPalette.qml`
    - _Requirements: 1.1, 1.2, 2.1_

  - [x] 4.2 Implement auto-execution of safe actions
    - After `actionPlanReady`, auto-execute actions of type `config.set`, `hyprland.dispatch`, `app.launch` without user confirmation
    - For `shell.exec` actions, emit `approvalRequired` signal and wait
    - After all actions complete, emit `executionComplete` and `responseSummary` with the summary text
    - File: `services/ActionPalette.qml`
    - _Requirements: 1.2, 1.3_

  - [x] 4.3 Add voice assistant system prompt constant
    - Define the concise-response system prompt as a constant in DictationService:
      ```
      "Respond concisely in natural spoken language. For simple lookups, one sentence max. For moderate queries, up to three short sentences. Only give detailed responses when explicitly asked. Use contractions and informal units. No markdown, no tables, no bullet points — plain spoken text."
      ```
    - This gets passed as `extraSystemPrompt` to `submitQueryDirect`
    - File: `ii/services/DictationService.qml`
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [x] 5. Voice Assistant Pipeline
  - [x] 5.1 Implement _processVoiceAssistant function in DictationService
    - Replace the current sidebar-closed routing (IPC to overview) with the voice assistant pipeline:
      1. Call `_classifyIntent(text)` 
      2. Call `Ai.appendToFreeDictation(text, "user")`
      3. If "dictation": show "Captured" in indicator, done
      4. If "command": call `ActionPalette.submitQueryDirect(text, VOICE_PROMPT)`
    - File: `ii/services/DictationService.qml`
    - _Requirements: 12.2, 12.3, 12.4, 7.6_

  - [x] 5.2 Handle ActionPalette response in voice assistant mode
    - Connect to `ActionPalette.responseSummary` signal
    - On response: set `responseText` property, show in Floating Indicator
    - Call `Ai.appendToFreeDictation(summaryText, "assistant")`
    - If talkback enabled: call `TtsService.speak(summaryText)`
    - File: `ii/services/DictationService.qml`
    - _Requirements: 1.4, 1.5, 4.3_

  - [x] 5.3 Handle ActionPalette errors and timeouts
    - Connect to `ActionPalette.executionFailed` signal
    - On error: display error in indicator for 3s, log to Free Dictation
    - Add a 15-second timeout on the LLM request
    - File: `ii/services/DictationService.qml`
    - _Requirements: 1.6_

- [x] 6. TTS Engine
  - [x] 6.1 Create TtsService.qml singleton
    - Create `ii/services/TtsService.qml` as a Singleton
    - Properties: `provider`, `voice`, `playing`, `_apiKey`
    - Process component for TTS execution (`ttsProcess`)
    - Register in `ii/services/qmldir`
    - File: `ii/services/TtsService.qml`, `ii/services/qmldir`
    - _Requirements: 3.1_

  - [x] 6.2 Implement piper TTS backend
    - `speak(text)` for piper: `echo '<text>' | piper --model <voice> --output_raw | pw-play --format=s16 --rate=22050 --channels=1 -`
    - Escape single quotes in text
    - File: `ii/services/TtsService.qml`
    - _Requirements: 3.2, 11.1, 11.2_

  - [x] 6.3 Implement espeak-ng TTS backend
    - `speak(text)` for espeak-ng: `espeak-ng "<text>" --stdout | pw-play -`
    - Escape double quotes in text
    - File: `ii/services/TtsService.qml`
    - _Requirements: 3.3, 11.1, 11.2_

  - [x] 6.4 Implement OpenAI TTS backend
    - `speak(text)` for openai: curl to `https://api.openai.com/v1/audio/speech` with model "tts-1", voice from config, pipe to pw-play
    - Use API key from KeyringStorage (same "openai" key_id as chat)
    - File: `ii/services/TtsService.qml`
    - _Requirements: 3.4, 11.1, 11.3_

  - [x] 6.5 Implement stop and interrupt behavior
    - `stop()`: set `ttsProcess.running = false` (SIGTERM)
    - When dictation activates during TTS playback, call `TtsService.stop()` first
    - Cancel in-progress playback when new speak() is called
    - File: `ii/services/TtsService.qml`, `ii/services/DictationService.qml`
    - _Requirements: 3.6, 11.4_

  - [x] 6.6 Handle TTS errors gracefully
    - On `ttsProcess.onExited` with non-zero exit: log error, don't crash
    - Response text remains visible in Floating Indicator regardless of TTS failure
    - File: `ii/services/TtsService.qml`
    - _Requirements: 3.7, 11.5_

- [x] 7. Floating Response Indicator
  - [x] 7.1 Extend DictationIndicator with VoiceResponse state
    - Add new visual state: show response text with max 500px width, word wrap
    - Bind to `DictationService.responseText` — visible when non-empty and state is Idle (response received)
    - Add auto-dismiss Timer (4s) that clears responseText
    - While `TtsService.playing`, keep indicator visible (pause auto-dismiss)
    - File: `ii/modules/dictation/DictationIndicator.qml`
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.6_

  - [x] 7.2 Add click-to-copy behavior
    - On click: copy responseText to clipboard via `wl-copy`, dismiss indicator
    - File: `ii/modules/dictation/DictationIndicator.qml`
    - _Requirements: 8.5_

  - [x] 7.3 Add shell.exec approval UI
    - When `DictationService.awaitingApproval` is true, show command text with [Approve] and [Reject] buttons
    - On Approve: call `ActionPalette.approveCommand(actionIndex)`
    - On Reject: call `ActionPalette.rejectCommand()`
    - Indicator stays visible until user responds
    - File: `ii/modules/dictation/DictationIndicator.qml`
    - _Requirements: 8.7, 1.3_

  - [x] 7.4 Add TTS playback animation
    - While `TtsService.playing`, show a speaker/volume wave animation icon next to response text
    - File: `ii/modules/dictation/DictationIndicator.qml`
    - _Requirements: 3.5_

- [x] 8. Provider Settings UI
  - [x] 8.1 Create VoiceAssistantConfig.qml settings component
    - New file with ContentSection titled "Voice Assistant"
    - STT provider dropdown: openai, faster-whisper, whisper-cpp, custom
    - STT endpoint text input (pre-populated from config)
    - STT model text input
    - TTS provider dropdown: none, piper, espeak-ng, openai
    - TTS voice text input
    - Talkback toggle
    - Intent mode selector: heuristic, ai
    - File: `ii/modules/settings/VoiceAssistantConfig.qml`
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8_

  - [x] 8.2 Register VoiceAssistantConfig in settings app
    - Add to the `pages` array in `ii/settings.qml` with name "Voice" and icon "record_voice_over"
    - File: `ii/settings.qml`
    - _Requirements: 6.1_

  - [x] 8.3 Add endpoint health check indicator
    - When STT endpoint changes, perform a connectivity check (curl HEAD to base URL)
    - Display green/red dot next to endpoint field indicating reachability
    - File: `ii/modules/settings/VoiceAssistantConfig.qml`
    - _Requirements: 5.4_

  - [x] 8.4 Add default endpoint placeholder text
    - When STT provider selection changes, update the endpoint field placeholder:
      - openai: "https://api.openai.com"
      - faster-whisper: "http://localhost:8080"
      - whisper-cpp: "http://localhost:8080"
      - custom: "http://your-server:port"
    - File: `ii/modules/settings/VoiceAssistantConfig.qml`
    - _Requirements: 6.9_

- [x] 9. Policy Enforcement
  - [x] 9.1 Add policy checks to voice assistant pipeline
    - In `_processVoiceAssistant`: check `policies.ai` before processing
    - When `policies.ai === 0`: do nothing (existing gate in `activate()` already handles this)
    - When `policies.ai === 2` and TTS provider is "openai": skip TTS, use local fallback or disable
    - When `policies.ai === 2` and intent mode is "ai": verify LLM endpoint is local
    - File: `ii/services/DictationService.qml`, `ii/services/TtsService.qml`
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

- [x] 10. STT Provider Fallback Chain
  - [x] 10.1 Implement STT endpoint fallback in DictationService
    - When configured endpoint is unreachable (transcription fails):
      1. Try localhost equivalent (same provider, localhost address)
      2. Try OpenAI API (if policy allows)
      3. Show error if all fail
    - Log fallback events to console.warn
    - File: `ii/services/DictationService.qml`
    - _Requirements: 5.5_

- [x] 11. Integration & Wiring
  - [x] 11.1 Wire voice assistant pipeline into existing _handleTranscriptionResult
    - Replace the current `else` branch (sidebar closed → IPC to overview) with `_processVoiceAssistant(text)`
    - Keep sidebar-open branch unchanged (appends to input field)
    - File: `ii/services/DictationService.qml`
    - _Requirements: 12.1, 12.2, 12.5_

  - [x] 11.2 Wire TTS stop on new dictation activation
    - In `activate()`, call `TtsService.stop()` before starting a new session
    - File: `ii/services/DictationService.qml`
    - _Requirements: 3.6_

  - [x] 11.3 Wire ActionPalette approval signal to DictationService
    - Connect `ActionPalette.approvalRequired` → set `awaitingApproval = true`, `approvalCommand = command`
    - Connect `ActionPalette.executionComplete` → clear approval state
    - File: `ii/services/DictationService.qml`
    - _Requirements: 1.3_

- [x] 12. Testing
  - [x] 12.1 Write property tests for intent classifier
    - For any text: result is exactly "command" or "dictation"
    - Imperative verbs always → "command"
    - Question marks always → "command"
    - Text >20 words without patterns → "dictation"
    - File: `tests/test_voice_assistant.py`
    - _Requirements: 7.1, 7.2, 7.3, 7.7_

  - [x] 12.2 Write integration test for TTS pipeline
    - Mock pw-play, verify correct command construction for each provider
    - Verify stop() terminates process
    - Verify error handling on non-zero exit
    - File: `tests/test_voice_assistant.py`
    - _Requirements: 3.1–3.7_

  - [x] 12.3 Write test for Free Dictation session management
    - Verify ensureFreeDictationSession creates session
    - Verify appendToFreeDictation adds messages without switching active session
    - Verify session persists across simulated restarts
    - File: `tests/test_voice_assistant.py`
    - _Requirements: 4.1, 4.2, 4.3, 4.6_

## Notes

- The voice assistant pipeline is additive — existing sidebar-open dictation behavior is completely unchanged
- ActionPalette already has the LLM integration and action execution; we're adding a headless mode that skips the UI
- TTS is entirely optional — default is "none" (off), users opt in via settings
- The intent classifier defaults to "command" for ambiguous input — this errs on the side of action over passivity
- piper needs a voice model file (`.onnx`); the settings UI should note this
- The Free Dictation session uses the same storage format as regular chat sessions

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["2.1", "3.1", "4.1", "6.1"] },
    { "id": 2, "tasks": ["2.2", "3.2", "4.2", "4.3", "6.2", "6.3", "6.4"] },
    { "id": 3, "tasks": ["5.1", "5.2", "5.3", "6.5", "6.6"] },
    { "id": 4, "tasks": ["7.1", "7.2", "7.3", "7.4"] },
    { "id": 5, "tasks": ["8.1", "8.2", "8.3", "8.4"] },
    { "id": 6, "tasks": ["9.1", "10.1", "11.1", "11.2", "11.3"] },
    { "id": 7, "tasks": ["3.3", "12.1", "12.2", "12.3"] }
  ]
}
```
