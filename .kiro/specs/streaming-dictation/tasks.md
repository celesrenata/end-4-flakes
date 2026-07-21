# Implementation Plan: Streaming Dictation

## Overview

Extend the existing voice dictation system to support real-time streaming transcription. A Python helper process (`dictation-stream.py`) manages WebSocket/HTTP transport, communicating with the QML DictationService via a line protocol. The DictationIndicator gains a live text display area, and the state machine adds a StreamingActive state. Three transport modes are supported: streaming (WebSocket), chunked (HTTP), and batch fallback (existing behavior).

## Tasks

- [x] 1. Extend Config and add streaming configuration fields
  - [x] 1.1 Add streaming config fields to Config.qml
    - Add `streamingEndpoint` (string, default: "") and `chunkDurationMs` (int, default: 3000) to the `dictation` JsonObject in `configs/quickshell/modules/common/Config.qml`
    - _Requirements: 6.1, 6.4_

- [x] 2. Implement the Python streaming helper process
  - [x] 2.1 Create `dictation-stream.py` with CLI argument parsing and line protocol
    - Create `configs/quickshell/ii/scripts/dictation-stream.py`
    - Implement `StreamHelperConfig` dataclass from CLI args (mode, endpoint, api-key, provider, chunk-duration, sample-rate, channels, sample-format)
    - Implement stdout line protocol output: READY, PARTIAL, FINAL, ERROR, FALLBACK messages
    - Implement main loop that reads stdin (audio bytes) and dispatches to transport handler
    - _Requirements: 5.1, 5.2, 7.3_

  - [x] 2.2 Implement WebSocket streaming transport in the helper
    - Implement `StreamingTransport` class that opens a persistent WebSocket connection
    - For OpenAI provider: base64-encode PCM frames, wrap in `input_audio_buffer.append` JSON, send `input_audio_buffer.commit` on EOF
    - For local providers: send raw PCM binary frames directly
    - Parse incoming partial/final messages and emit PARTIAL/FINAL lines on stdout
    - Implement connection timeout (3 seconds) and one reconnection attempt within 2 seconds on drop
    - On connection failure or reconnection failure, emit FALLBACK line
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 10.1, 10.2, 10.3, 10.4, 11.1, 11.2, 11.3_

  - [x] 2.3 Implement chunked HTTP transport in the helper
    - Implement `ChunkedTransport` class that buffers audio for configured `chunk_duration` ms
    - When a chunk completes, write to a temporary WAV file and POST to the transcription endpoint
    - Parse response JSON and emit PARTIAL line for each chunk result
    - On stdin EOF, submit remaining audio as final chunk, emit FINAL with concatenated results
    - On per-chunk failure, skip the failed chunk and continue processing
    - On all-chunks-fail, emit FALLBACK line
    - Clean up temporary chunk files after submission
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 5.3_

  - [x] 2.4 Implement capability probing and fallback logic in the helper
    - On startup, attempt to connect to the streaming endpoint (if mode is "streaming")
    - If streaming connection fails within 3 seconds, attempt chunked mode if applicable
    - If chunked also unavailable, emit FALLBACK with reason
    - Emit READY:<actual_mode> once transport is established
    - _Requirements: 9.1, 9.2, 11.4, 11.5_

  - [x] 2.5 Implement policy enforcement in the helper
    - Accept `--policy-ai` CLI arg
    - When policy is 2 (local-only), verify endpoint is localhost/127.0.0.1/::1 before connecting
    - If endpoint is remote under policy 2, emit ERROR and exit
    - _Requirements: 12.2, 12.4_

  - [x] 2.6 Write property tests for capability detection (Property 1)
    - **Property 1: Capability Detection Always Returns Valid Mode**
    - Test that for any provider string and endpoint config, detection returns exactly one of "streaming", "chunked", or "batch"
    - **Validates: Requirements 1.1, 1.5**

  - [x] 2.7 Write property tests for audio frame integrity (Property 2)
    - **Property 2: Audio Frame Forwarding Integrity**
    - Test that any sequence of PCM frames forwarded through the helper arrives without loss, corruption, or reordering
    - **Validates: Requirements 2.2, 5.1**

  - [x] 2.8 Write property tests for base64 round-trip (Property 10)
    - **Property 10: Base64 PCM Round-Trip (OpenAI)**
    - Test that encoding any raw PCM frame to base64 and decoding produces the identical original frame
    - **Validates: Requirements 10.2**

  - [x] 2.9 Write property tests for chunk duration compliance (Property 6)
    - **Property 6: Chunk Duration Compliance**
    - Test that for any audio stream and chunk duration config, chunks are within ±100ms of configured duration (except final chunk)
    - **Validates: Requirements 3.1, 6.4**

  - [x] 2.10 Write property tests for chunk submission count (Property 7)
    - **Property 7: Chunk Submission Count**
    - Test that for any recording duration D and chunk duration C, submissions equal ceil(D / C)
    - **Validates: Requirements 3.2, 3.4**

  - [x] 2.11 Write property tests for chunk failure isolation (Property 8)
    - **Property 8: Chunk Failure Isolation**
    - Test that a chunk failure at position N does not prevent submission of chunks at positions > N
    - **Validates: Requirements 3.6**

  - [x] 2.12 Write property tests for policy enforcement (Property 12)
    - **Property 12: Policy Enforcement for Remote Providers**
    - Test that remote endpoints are rejected when policy is 2, and local endpoints (localhost/127.0.0.1/::1) are allowed
    - **Validates: Requirements 12.2, 12.4**

  - [x] 2.13 Write property tests for custom endpoint override (Property 14)
    - **Property 14: Custom Endpoint Override**
    - Test that any non-empty streamingEndpoint config is used verbatim regardless of provider
    - **Validates: Requirements 6.5**

- [x] 3. Checkpoint — Helper process tests
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Extend DictationService state machine and streaming process management
  - [x] 4.1 Add StreamingActive state and new properties to DictationService.qml
    - Add `StreamingActive` to the State enum (Idle, Listening, StreamingActive, Processing, Error)
    - Add `property string transcriptionMode: "batch"` (streaming/chunked/batch)
    - Add `property string partialText: ""`
    - Add config shortcut properties: `streamingEndpoint`, `chunkDurationMs`
    - _Requirements: 7.1, 7.3, 1.5_

  - [x] 4.2 Implement provider capability detection function in DictationService
    - Implement `detectCapability(provider, streamingEndpoint)` function
    - Return "streaming" if explicit endpoint configured or provider is "openai" or known local provider
    - Return "batch" for unknown providers
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [x] 4.3 Implement streaming activation flow in DictationService
    - In `activate()`, after existing gates pass, call `detectCapability()` to determine mode
    - Set `transcriptionMode` property
    - If mode is "batch", use existing flow (Listening state, pw-record)
    - If mode is "streaming" or "chunked", transition to StreamingActive and launch the piped audio+helper process
    - Construct shell command: `pw-cat --record --target=@DEFAULT_SOURCE@ --format=s16 --rate=16000 --channels=1 - | python3 <path>/dictation-stream.py --mode=<mode> --endpoint=<ep> --api-key=<key> --provider=<prov> --chunk-duration=<ms> --policy-ai=<n>`
    - _Requirements: 5.1, 5.2, 7.2, 1.2, 1.3_

  - [x] 4.4 Implement stream helper stdout parsing in DictationService
    - Add a Process component for the piped streaming command
    - Parse stdout lines with SplitParser: handle READY, PARTIAL, FINAL, ERROR, FALLBACK messages
    - On READY: confirm transcriptionMode
    - On PARTIAL: update `partialText`
    - On FINAL: set `partialText` to final text, transition to Processing, route text
    - On ERROR: transition to Error state, set errorMessage
    - On FALLBACK: switch to batch mode mid-session (transition to Listening, start pw-record with existing flow)
    - _Requirements: 2.3, 2.5, 3.3, 3.5, 7.4, 7.5, 7.6, 9.3_

  - [x] 4.5 Implement stop-recording for StreamingActive state
    - When `stopRecording()` called in StreamingActive state, terminate the piped process (sends EOF to helper stdin, triggering end-of-stream)
    - Transition to Processing while awaiting FINAL message
    - _Requirements: 2.4, 7.4_

  - [x] 4.6 Implement final text routing and cleanup for streaming mode
    - On FINAL received: route via existing logic (sidebar → Ai.sendUserMessage, else → action palette)
    - Use Final_Result for routing, not last Partial_Result
    - Clean up: no temp files in streaming mode (audio was piped), clear partialText, reset to Idle
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 12.3_

  - [x] 4.7 Write property tests for state machine transitions (Property 11)
    - **Property 11: State Machine Transitions**
    - Test that streaming/chunked activation → StreamingActive, stop → Processing, error → Error
    - Model the state machine and verify transitions match spec
    - **Validates: Requirements 7.2, 7.4, 7.6**

  - [x] 4.8 Write property tests for partial result updates (Property 3)
    - **Property 3: Partial Result Updates Reflect Backend Output**
    - Test that partial messages update partialText correctly — replacing for streaming, accumulating for chunked
    - **Validates: Requirements 2.3, 3.3, 10.3, 11.3**

  - [x] 4.9 Write property tests for final result routing (Property 4)
    - **Property 4: Final Result Replaces Partial and Routes Correctly**
    - Test that Final_Result replaces partialText, transitions to Idle, and routes the final (not partial) text
    - **Validates: Requirements 2.5, 7.5, 8.1, 8.2**

  - [x] 4.10 Write property tests for connection drop recovery (Property 5)
    - **Property 5: Connection Drop Recovery**
    - Test that connection drops either reconnect within 2s or fall back to batch — never hang
    - **Validates: Requirements 2.6, 9.1**

  - [x] 4.11 Write property test for no audio persistence (Property 13)
    - **Property 13: No Audio Persistence in Streaming Mode**
    - Test that after a streaming session completes, no audio data remains on disk
    - **Validates: Requirements 12.3, 8.4**

- [x] 5. Checkpoint — Service state machine verification
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Extend DictationIndicator with live transcription display
  - [x] 6.1 Add live partial text display to DictationIndicator.qml
    - Add a StyledText element below the mic icon row, visible when `DictationService.state === DictationService.State.StreamingActive && DictationService.partialText !== ""`
    - Bind text to `DictationService.partialText`
    - Set `clip: true` with right-aligned text (elide from left) when content exceeds max width
    - _Requirements: 4.1, 4.4_

  - [x] 6.2 Implement dynamic width and max-width constraint for the indicator
    - Adjust `indicatorContent` implicitWidth to accommodate text: `Math.min(textMetrics.width + padding, 400)`
    - When text exceeds 400px, truncate from the left showing only the most recent portion
    - _Requirements: 4.3, 4.4_

  - [x] 6.3 Add text appearance animation
    - Add a Behavior or Transition on partialText changes for a fade-in or slide-in-from-right effect
    - _Requirements: 4.2_

  - [x] 6.4 Add StreamingActive state handling to indicator icons and status text
    - Show pulsing mic icon during StreamingActive state (same as Listening)
    - Show duration counter during StreamingActive state
    - On FALLBACK (state changes to Listening), hide partial text area and show standard recording UI
    - _Requirements: 4.5, 9.3_

  - [x] 6.5 Write property test for indicator width constraint (Property 9)
    - **Property 9: Indicator Width Constraint**
    - Test that for any partialText content, computed width never exceeds 400px
    - **Validates: Requirements 4.3, 4.4**

- [x] 7. Wire components together and integration
  - [x] 7.1 Wire API key retrieval for streaming mode
    - In the streaming activation path, retrieve the API key from KeyringStorage (same as existing batch transcription)
    - Pass the key to the helper process via CLI arg
    - _Requirements: 10.5_

  - [x] 7.2 Implement batch fallback mid-session transition
    - When FALLBACK received from helper: kill streaming process, start pw-record, set state to Listening
    - Hide partial text area in indicator (driven by state change to Listening)
    - Log fallback reason to console.warn() for Quickshell journal
    - _Requirements: 9.1, 9.2, 9.3, 9.4_

  - [x] 7.3 Implement policy enforcement in QML activation path
    - Before launching streaming process, check `policies.ai`
    - If policies.ai === 0: block activation (existing behavior)
    - If policies.ai === 2 and provider is remote: show error "Online transcription disallowed by policy"
    - Pass policy value to helper for endpoint verification
    - _Requirements: 12.1, 12.2_

  - [x] 7.4 Write integration tests for full streaming flow
    - Test complete flow with mocked WebSocket server: connect → send frames → receive partials → finalize
    - Test chunked flow with mocked HTTP endpoint
    - Test fallback from streaming to batch on connection failure
    - Test policy enforcement blocking remote streaming
    - Test helper protocol parsing (READY/PARTIAL/FINAL/ERROR/FALLBACK)
    - _Requirements: 2.1–2.6, 3.1–3.6, 9.1–9.4_

- [x] 8. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document using Hypothesis (Python)
- The Python helper is independently testable without the QML runtime
- QML state machine behavior can be tested via protocol simulation (feeding helper output lines)
- The piped process pattern (`pw-cat | dictation-stream.py`) is a single Process component in QML

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1"] },
    { "id": 1, "tasks": ["2.2", "2.3", "2.4", "2.5"] },
    { "id": 2, "tasks": ["2.6", "2.7", "2.8", "2.9", "2.10", "2.11", "2.12", "2.13"] },
    { "id": 3, "tasks": ["4.1", "4.2"] },
    { "id": 4, "tasks": ["4.3", "4.4", "4.5"] },
    { "id": 5, "tasks": ["4.6", "4.7", "4.8", "4.9", "4.10", "4.11"] },
    { "id": 6, "tasks": ["6.1", "6.2", "6.3", "6.4"] },
    { "id": 7, "tasks": ["6.5", "7.1", "7.2", "7.3"] },
    { "id": 8, "tasks": ["7.4"] }
  ]
}
```
