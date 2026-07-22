# Implementation Plan: Streaming Voice Agent

## Overview

Replace the batch voice pipeline with bidirectional streaming voice conversations using a single Python helper (`voice-agent-stream.py`) communicating with QML's `VoiceAgentService` via FIFO (audio) + stdin/stdout (JSON control). Two backends: Nova Sonic (HTTP/2 bidirectional) and OpenAI Realtime (WebSocket). Tool calls route through ActionPalette, session context injected from active chat, with graceful fallback to batch mode on failure.

## Tasks

- [x] 1. Python helper script — protocol layer and backend ABC
  - [x] 1.1 Create `voice-agent-stream.py` with CLI argument parsing, BaseVoiceBackend ABC, and async main loop
    - Create `configs/quickshell/ii/scripts/voice-agent-stream.py`
    - Implement argparse for `--backend`, `--audio-fifo`, `--sample-rate`, `--region`, `--profile`, `--api-key`, `--system-prompt`, `--context`, `--tools`
    - Define `BaseVoiceBackend` ABC with `connect()`, `send_audio()`, `send_tool_result()`, `disconnect()`
    - Implement async main: FIFO audio reader task, stdin JSON reader task, stdout JSON writer
    - Emit READY event on successful backend connection
    - Handle STOP/BARGE_IN input events
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 2.1_

  - [x] 1.2 Implement protocol event serialization/deserialization helpers
    - Create output event constructors for all 9 event types (READY, PARTIAL_TRANSCRIPT, TURN_END, TURN_COMPLETE, AUDIO_RESPONSE, TOOL_CALL, SESSION_END, ERROR, FALLBACK)
    - Create input event parser for TOOL_RESULT, STOP, BARGE_IN
    - Base64 encode/decode helpers for AUDIO_RESPONSE PCM data
    - Validate required fields per event type
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 12.7_

  - [x] 1.3 Write property tests for protocol round-trip integrity
    - **Property 1: Protocol round-trip integrity**
    - Generate random valid events, serialize to JSON line, parse back, verify type and required fields present
    - **Validates: Requirements 12.1, 12.2, 12.5, 12.6, 12.7**

  - [x] 1.4 Write property tests for audio format preservation
    - **Property 2: Audio format preservation**
    - Generate random PCM byte sequences (length multiple of 2), base64 encode, decode, verify length preserved and content identical
    - **Validates: Requirements 12.5, 13.1, 13.2, 13.3**

- [ ] 2. Python helper — Nova Sonic backend
  - [x] 2.1 Implement `NovaSonicBackend` class with Bedrock bidirectional streaming
    - Implement `connect()` using boto3/botocore for `invoke-model-with-bidirectional-stream` on `amazon.nova-sonic-v1:0`
    - Implement `send_audio()` to forward PCM chunks per Nova Sonic input event schema
    - Implement event handler to parse Nova Sonic transcript/audio/tool-use events and emit protocol events
    - Send system prompt event at session start with context
    - Handle tool-use events: emit TOOL_CALL, pause audio forwarding until TOOL_RESULT received
    - Implement `send_tool_result()` to forward result in Nova Sonic format
    - Implement `disconnect()` for graceful stream closure
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 13.1_

  - [-] 2.2 Write unit tests for Nova Sonic backend event mapping
    - Test transcript event → PARTIAL_TRANSCRIPT mapping
    - Test audio response event → AUDIO_RESPONSE mapping
    - Test tool-use event → TOOL_CALL mapping
    - Test system prompt injection
    - _Requirements: 5.4, 5.5, 5.6, 5.7_

- [ ] 3. Python helper — OpenAI Realtime backend
  - [x] 3.1 Implement `OpenAIRealtimeBackend` class with WebSocket connection
    - Implement `connect()` to establish WebSocket to `wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview` with API key auth and `OpenAI-Beta: realtime=v1` header
    - Send `session.update` at connection start with server-side VAD enabled, system prompt, and tools
    - Implement `send_audio()` to send `input_audio_buffer.append` events with base64-encoded PCM
    - Implement event handler to parse `response.audio_transcript.delta`, `response.audio.delta`, `response.function_call_arguments.done` events
    - Implement `send_tool_result()` to send `conversation.item.create` with tool output
    - Implement `disconnect()` for graceful WebSocket close
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8, 13.2_

  - [-] 3.2 Write unit tests for OpenAI Realtime backend event mapping
    - Test `response.audio_transcript.delta` → PARTIAL_TRANSCRIPT
    - Test `response.audio.delta` → AUDIO_RESPONSE
    - Test `response.function_call_arguments.done` → TOOL_CALL
    - Test session.update message formation
    - _Requirements: 6.4, 6.5, 6.6, 6.7, 6.8_

- [ ] 4. Python helper — tool call handling and session context
  - [-] 4.1 Implement tool call pairing logic and session context loading
    - Track pending tool call IDs (enforce single pending call invariant)
    - Pause audio forwarding on TOOL_CALL, resume on TOOL_RESULT
    - Load session context from `--context` JSON file path
    - Format context for system prompt injection per backend
    - Implement graceful shutdown: STOP → finalize stream → SESSION_END
    - _Requirements: 8.3, 8.4, 9.2, 9.3, 12.3, 12.4_

  - [ ] 4.2 Write property tests for tool call / result pairing
    - **Property 3: Tool call / result pairing**
    - Generate random sequences of tool calls with unique IDs, verify pairing invariants (no duplicate IDs, no concurrent pending calls)
    - **Validates: Requirements 8.1, 8.2, 8.3, 8.4, 12.3, 12.4, 12.7**

  - [ ] 4.3 Write property tests for session context serialization round-trip
    - **Property 8: Session context serialization round-trip**
    - Generate random message histories (role + content), serialize to JSON, parse back, verify order and field equality
    - **Validates: Requirements 9.1, 9.2, 9.3**

- [ ] 5. Checkpoint — Helper protocol complete
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. QML — Config and backend selection
  - [x] 6.1 Add `voiceBackend` property to Config.qml and ProviderPanel backend selector
    - Add `property string voiceBackend: "none"` to `configs/quickshell/ii/modules/common/Config.qml` dictation JsonObject
    - Add backend selector (ComboBox or similar) to `configs/quickshell/ii/modules/sidebarLeft/ProviderPanel.qml` with options: "none", "nova-sonic", "openai-realtime"
    - Bind selector to `Config.options.dictation.voiceBackend`
    - _Requirements: 1.1, 1.2_

  - [x] 6.2 Implement credential validation logic in VoiceAgentService
    - Check `AwsCredentialReader.credentialsDetected` when backend is "nova-sonic"
    - Check `KeyringStorage` for non-empty "openai" key when backend is "openai-realtime"
    - Display error in DictationIndicator identifying missing credential on failure
    - Remain in Idle state on credential failure
    - _Requirements: 1.3, 1.4, 1.5_

  - [x] 6.3 Write property tests for policy enforcement gate
    - **Property 5: Policy enforcement gate**
    - Generate all combinations of policies.ai (0, 1, 2) × voiceBackend ("none", "nova-sonic", "openai-realtime"), verify activation gate decisions
    - **Validates: Requirements 14.1, 14.2, 14.3**

  - [x] 6.4 Write property tests for credential validation
    - **Property 6: Credential validation before connection**
    - Generate activation attempts with varying credential states, verify rejection with descriptive errors when credentials missing
    - **Validates: Requirements 1.3, 1.4, 1.5**

- [ ] 7. QML — VoiceAgentService core state machine
  - [-] 7.1 Create `VoiceAgentService.qml` singleton with state machine and process management
    - Create `configs/quickshell/ii/services/VoiceAgentService.qml`
    - Define State enum: Idle, Connecting, Listening, Thinking, Speaking, ToolExecuting, Error
    - Implement `activate()`: validate credentials/policy, create FIFO, launch pw-cat → FIFO, launch helper with args
    - Implement `deactivate()`: send STOP to helper stdin, close FIFO, kill processes, transition to Idle
    - Implement 5-second connection timeout (Connecting → Error/fallback)
    - Handle helper stdout via SplitParser (JSON lines), route events to state transitions
    - Implement `bargeIn()`: kill pw-play, send BARGE_IN, transition to Listening
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 10.1, 14.1, 14.2_

  - [ ] 7.2 Register VoiceAgentService in qmldir
    - Add `singleton VoiceAgentService 1.0 VoiceAgentService.qml` to `configs/quickshell/ii/services/qmldir`
    - _Requirements: 2.1_

  - [ ] 7.3 Write property tests for state machine valid transitions
    - **Property 4: State machine valid transitions**
    - Generate random sequences of helper events, verify state machine only follows valid edges and Connecting never exceeds 5s without transition
    - **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 10.1**

- [ ] 8. QML — Audio pipeline and playback
  - [ ] 8.1 Implement audio capture (pw-cat → FIFO) and playback (AUDIO_RESPONSE → pw-play)
    - Launch `pw-cat --record --format=s16 --rate={16000|24000} --channels=1` writing to named FIFO
    - Decode base64 from AUDIO_RESPONSE events, pipe to `pw-play` process stdin
    - Handle pw-cat/pw-play unexpected exit (send STOP, transition to Error)
    - Configure sample rate based on backend (16kHz Nova Sonic, 24kHz OpenAI)
    - _Requirements: 13.1, 13.2, 13.3, 13.5, 4.1, 4.4_

  - [ ] 8.2 Implement RMS audio level calculation for waveform indicator
    - Compute running RMS amplitude from captured audio for `audioLevel` property (0.0–1.0)
    - Update at ~10Hz for smooth waveform display
    - _Requirements: 13.4, 11.1_

  - [ ] 8.3 Write property tests for barge-in interrupts playback
    - **Property 7: Barge-in interrupts playback**
    - Generate states where Speaking is active, simulate activation key tap, verify pw-play terminated, BARGE_IN sent, transition to Listening within 200ms
    - **Validates: Requirements 4.5, 7.5**

- [ ] 9. QML — Tool call routing through ActionPalette
  - [ ] 9.1 Add `executeToolDirect` function to ActionPalette and wire tool call flow
    - Add `function executeToolDirect(toolName, arguments, callback)` to `configs/quickshell/ii/services/ActionPalette.qml`
    - Map tool names from backend to existing action execution logic
    - Handle 15s timeout → error TOOL_RESULT
    - Handle unknown tool names → error TOOL_RESULT
    - In VoiceAgentService: on TOOL_CALL event → parse name/args → call executeToolDirect → on result → sendToolResult to helper stdin
    - Transition to ToolExecuting state during execution
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

- [ ] 10. QML — Session context injection and transcript logging
  - [ ] 10.1 Implement session context retrieval and transcript append
    - On activate: read recent messages from `Ai.getCurrentSessionMessages` (last 20)
    - Serialize to temp JSON file, pass path to helper via `--context`
    - On SESSION_END: append user utterances and AI responses to active sidebar session
    - Fall back to "Free Dictation" session if no active session
    - Clean up temp context file on session end
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_

- [ ] 11. Checkpoint — QML service complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 12. QML — DictationIndicator streaming states
  - [ ] 12.1 Extend DictationIndicator with streaming voice agent state display
    - Modify `configs/quickshell/ii/modules/dictation/DictationIndicator.qml`
    - Bind to `VoiceAgentService.voiceAgentState`, `partialText`, `responseText`, `audioLevel`, `currentToolName`
    - Implement state-specific displays: Connecting (spinner), Listening (waveform + partial text), Thinking (pulsing), Speaking (speaker icon + response text), ToolExecuting (gear icon + tool name), Error (auto-dismiss 5s)
    - Animate partial text with fade-in transition
    - Dynamic width expansion up to 500px, truncate from left when exceeded
    - Show "Ready..." with muted mic when listening but no speech
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 11.1, 11.2, 11.3, 11.4, 11.5, 11.6_

- [ ] 13. QML — Fallback logic and error handling
  - [ ] 13.1 Implement graceful fallback to batch mode and error state handling
    - On 5-second timeout without READY: kill helper, activate DictationService batch pipeline
    - On FALLBACK event: save buffered audio, submit through batch pipeline
    - On `voiceBackend == "none"`: activate batch pipeline directly
    - On unexpected helper exit: capture exit code + stderr, display in indicator, Error state
    - Log fallback events with reason to Quickshell journal
    - Update DictationIndicator to show standard recording UI when falling back
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 2.6_

- [ ] 14. Checkpoint — UI integration complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 15. Integration wiring and turn-taking
  - [ ] 15.1 Wire automatic turn-taking and activation key toggle
    - Rely on backend VAD for turn boundaries (no manual end-of-turn required)
    - On TURN_END event: transition DictationIndicator to "Thinking..."
    - On manual activation key during turn: send explicit end-of-turn signal to helper (which forwards `input_audio_buffer.commit` or equivalent)
    - Continue accepting audio during response generation (barge-in support)
    - Toggle behavior: first tap activates session, second tap deactivates
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 2.3, 2.4_

  - [ ] 15.2 Wire live transcription display flow end-to-end
    - PARTIAL_TRANSCRIPT → update `partialText` → DictationIndicator displays
    - TURN_COMPLETE → clear `partialText`, show finalized utterance briefly, then response
    - Audio level → waveform animation
    - Response text alongside audio playback
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 4.2, 4.3_

  - [ ] 15.3 Implement policy enforcement in activation path
    - Check `policies.ai` before any activation
    - Block activation when policy = 0
    - Block remote backends when policy = 2
    - Ensure no audio sent to remote endpoints when policy forbids
    - No raw audio persisted to disk during or after session
    - Persist only text transcript to chat session
    - _Requirements: 14.1, 14.2, 14.3, 14.4_

- [ ] 16. Deployment and final integration
  - [ ] 16.1 Deploy all files and verify Quickshell restart
    - rsync `configs/quickshell/ii/` to `~/.config/quickshell/ii/`
    - Restart quickshell: `systemctl --user restart quickshell`
    - Verify no QML errors in journal logs
    - Verify VoiceAgentService registered and accessible
    - Verify Config.voiceBackend property works
    - _Requirements: 1.1, 1.2, 2.1_

- [ ] 17. Final checkpoint — End-to-end verification
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation after helper protocol, QML service, UI integration, and end-to-end
- Property tests validate universal correctness properties using `hypothesis` (already in project)
- Python tests go in a `tests/` directory adjacent to `voice-agent-stream.py` or project root
- The FIFO-based audio/control separation is the critical architectural pattern — audio flows through a named pipe, JSON control through stdin/stdout
- Deploy workflow: edit repo → rsync to `~/.config/quickshell/ii/` → restart quickshell

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "6.1"] },
    { "id": 1, "tasks": ["1.2", "6.2"] },
    { "id": 2, "tasks": ["1.3", "1.4", "2.1", "3.1", "6.3", "6.4"] },
    { "id": 3, "tasks": ["2.2", "3.2", "4.1", "7.1"] },
    { "id": 4, "tasks": ["4.2", "4.3", "7.2", "7.3"] },
    { "id": 5, "tasks": ["8.1", "9.1", "10.1"] },
    { "id": 6, "tasks": ["8.2", "8.3", "12.1"] },
    { "id": 7, "tasks": ["13.1", "15.1"] },
    { "id": 8, "tasks": ["15.2", "15.3"] },
    { "id": 9, "tasks": ["16.1"] }
  ]
}
```
