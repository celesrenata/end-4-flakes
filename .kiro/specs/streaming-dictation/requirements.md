# Requirements Document

## Introduction

Enhance the existing voice dictation system to stream transcription results back to the UI in real-time as the user speaks, rather than waiting for the entire recording to complete before transcribing. The DictationIndicator expands to show live partial text as it arrives. The final transcription still routes to the sidebar chat or action palette via existing routing logic. The system supports both true streaming backends (WebSocket-based) and chunked processing for non-streaming backends, with graceful fallback to the existing batch mode when the configured provider lacks streaming support.

## Glossary

- **Streaming_Transcription_Service**: The component within DictationService.qml responsible for managing the streaming or chunked transcription connection during a dictation session
- **DictationIndicator**: The floating overlay PanelWindow (DictationIndicator.qml) that displays recording state and live transcription text
- **Partial_Result**: An intermediate transcription fragment produced by the backend before the audio stream is finalized; may change as more context arrives
- **Final_Result**: The definitive transcription text produced after the audio stream ends and the backend has processed all audio
- **Streaming_Backend**: A speech-to-text backend that accepts audio in real-time via a persistent connection (e.g., WebSocket) and returns partial results incrementally
- **Chunked_Backend**: A speech-to-text backend that accepts discrete audio segments via repeated HTTP requests and returns a result per chunk
- **Batch_Backend**: A speech-to-text backend that only accepts a complete audio file and returns a single transcription result (the existing behavior)
- **Audio_Chunker**: The component that segments the live audio stream from PipeWire into time-bounded chunks for submission to a Chunked_Backend
- **Provider_Capability**: A metadata attribute indicating whether a configured transcription provider supports streaming, chunked, or batch-only operation

## Requirements

### Requirement 1: Streaming Mode Detection

**User Story:** As a user, I want the dictation system to automatically use the best available transcription mode for my configured provider, so that I get real-time feedback when possible without manual configuration.

#### Acceptance Criteria

1. WHEN dictation activates, THE Streaming_Transcription_Service SHALL determine the Provider_Capability of the configured transcription provider
2. WHEN the configured provider supports streaming, THE Streaming_Transcription_Service SHALL use the streaming transport (WebSocket or equivalent persistent connection)
3. WHEN the configured provider supports chunked operation but not streaming, THE Streaming_Transcription_Service SHALL use the chunked transport (repeated segment submissions)
4. WHEN the configured provider supports only batch operation, THE Streaming_Transcription_Service SHALL fall back to the existing batch transcription flow without user intervention
5. THE Streaming_Transcription_Service SHALL expose a `transcriptionMode` property indicating the active mode: "streaming", "chunked", or "batch"

### Requirement 2: Streaming Transport

**User Story:** As a user, I want to see transcription words appear as I speak when using a streaming-capable backend, so that I get immediate visual feedback of what the system is hearing.

#### Acceptance Criteria

1. WHEN the streaming transport is active, THE Streaming_Transcription_Service SHALL open a persistent connection to the backend before audio capture begins
2. WHILE the streaming transport is active, THE Streaming_Transcription_Service SHALL forward audio data from PipeWire to the backend continuously in real-time
3. WHEN the backend emits a Partial_Result, THE Streaming_Transcription_Service SHALL update a `partialText` property with the current partial transcription
4. WHEN recording stops, THE Streaming_Transcription_Service SHALL signal end-of-stream to the backend and await the Final_Result
5. WHEN the Final_Result arrives, THE Streaming_Transcription_Service SHALL replace the `partialText` with the Final_Result and proceed to text routing
6. IF the streaming connection drops during recording, THEN THE Streaming_Transcription_Service SHALL attempt one reconnection within 2 seconds, and if reconnection fails, fall back to batch mode with the audio recorded so far

### Requirement 3: Chunked Transport

**User Story:** As a user with a provider that does not support true streaming, I want chunked processing to show progressive results while I speak, so that I still get near-real-time feedback.

#### Acceptance Criteria

1. WHEN the chunked transport is active, THE Audio_Chunker SHALL segment the audio stream into chunks of configurable duration (default: 3 seconds)
2. WHILE recording is in progress, THE Audio_Chunker SHALL submit each completed chunk to the transcription backend as a separate request
3. WHEN a chunk transcription result returns, THE Streaming_Transcription_Service SHALL append the chunk result to the accumulated `partialText`
4. WHEN recording stops, THE Audio_Chunker SHALL submit any remaining audio as a final chunk
5. WHEN the final chunk result returns, THE Streaming_Transcription_Service SHALL concatenate all chunk results as the Final_Result and proceed to text routing
6. IF a chunk request fails, THEN THE Streaming_Transcription_Service SHALL skip the failed chunk and continue processing subsequent chunks

### Requirement 4: Live Transcription Display

**User Story:** As a user, I want to see the transcribed words appearing in the floating indicator as I speak, so that I can confirm the system is hearing me correctly.

#### Acceptance Criteria

1. WHILE dictation is in the Listening state with streaming or chunked mode active, THE DictationIndicator SHALL display the current `partialText` below the mic icon and duration counter
2. WHEN `partialText` updates, THE DictationIndicator SHALL animate the new text appearing (fade-in or slide-in from the right)
3. THE DictationIndicator SHALL expand its width dynamically to accommodate the transcription text, up to a maximum width of 400 pixels
4. WHEN the displayed text exceeds the maximum width, THE DictationIndicator SHALL truncate from the left, showing only the most recent portion of the transcription
5. WHILE in batch fallback mode, THE DictationIndicator SHALL display only the existing recording UI (mic icon and duration) without a text area

### Requirement 5: Audio Pipeline for Streaming

**User Story:** As a user, I want the system to capture audio in a format suitable for streaming to the backend, so that real-time transcription works reliably.

#### Acceptance Criteria

1. WHEN streaming or chunked mode is active, THE Streaming_Transcription_Service SHALL capture audio using `pw-cat --record` (or equivalent) in a streamable format (16kHz, mono, 16-bit PCM)
2. THE Streaming_Transcription_Service SHALL pipe audio data directly to the streaming connection rather than writing to an intermediate file
3. WHEN chunked mode is active, THE Audio_Chunker SHALL buffer audio in memory and write temporary chunk files only when submitting to the backend
4. WHEN batch fallback is active, THE Streaming_Transcription_Service SHALL use the existing `pw-record` file-based capture unchanged
5. IF the audio capture process exits unexpectedly, THEN THE Streaming_Transcription_Service SHALL transition to the Processing state and process any audio captured so far

### Requirement 6: Provider Configuration for Streaming

**User Story:** As a user, I want to configure streaming-capable providers with their connection details, so that the system can establish real-time connections.

#### Acceptance Criteria

1. THE Streaming_Transcription_Service SHALL read streaming endpoint configuration from `Config.options.dictation.streamingEndpoint` (default: empty, auto-derived from provider)
2. WHEN `streamingEndpoint` is empty and the provider is "openai", THE Streaming_Transcription_Service SHALL use the OpenAI Realtime API WebSocket endpoint
3. WHEN `streamingEndpoint` is empty and the provider is a known local provider, THE Streaming_Transcription_Service SHALL use the local WebSocket endpoint at `ws://localhost:8765` (configurable)
4. THE Streaming_Transcription_Service SHALL read chunk duration from `Config.options.dictation.chunkDurationMs` (default: 3000)
5. WHERE the user has configured a custom `streamingEndpoint`, THE Streaming_Transcription_Service SHALL use that endpoint regardless of auto-detection logic

### Requirement 7: State Machine Extension

**User Story:** As a developer, I want the dictation state machine to accommodate streaming states, so that the UI and service correctly reflect real-time operation.

#### Acceptance Criteria

1. THE DictationService SHALL extend the state enum to include: Idle, Listening, StreamingActive, Processing, Error
2. WHEN dictation activates with streaming or chunked mode, THE DictationService SHALL transition from Idle to StreamingActive
3. WHILE in StreamingActive state, THE DictationService SHALL expose both `partialText` (updating live) and `recordingDuration`
4. WHEN recording stops in StreamingActive state, THE DictationService SHALL transition to Processing while awaiting the Final_Result
5. WHEN the Final_Result is received in Processing state, THE DictationService SHALL transition to Idle and route the text
6. IF an error occurs in StreamingActive state, THEN THE DictationService SHALL transition to Error and display the error in the DictationIndicator

### Requirement 8: Final Text Routing Compatibility

**User Story:** As a user, I want the final transcribed text to route to the sidebar or action palette exactly as it does today, so that the streaming enhancement does not change my workflow.

#### Acceptance Criteria

1. WHEN the Final_Result is available, THE Streaming_Transcription_Service SHALL route the text using the existing routing logic (sidebar open → AI chat, sidebar closed → action palette)
2. THE Streaming_Transcription_Service SHALL use the Final_Result for routing, not the last Partial_Result
3. WHEN batch fallback mode is active, THE Streaming_Transcription_Service SHALL route text identically to the current non-streaming implementation
4. THE Streaming_Transcription_Service SHALL clean up temporary audio data (in-memory buffers or chunk files) after routing completes

### Requirement 9: Graceful Degradation

**User Story:** As a user, I want dictation to always work even if streaming fails, so that I never lose my spoken input.

#### Acceptance Criteria

1. IF the streaming connection cannot be established within 3 seconds, THEN THE Streaming_Transcription_Service SHALL fall back to batch mode and begin file-based recording
2. IF all chunk requests fail during a chunked session, THEN THE Streaming_Transcription_Service SHALL fall back to batch mode using the full recorded audio
3. WHEN falling back to batch mode mid-session, THE DictationIndicator SHALL update to show the standard recording UI (hiding the partial text area)
4. THE Streaming_Transcription_Service SHALL log fallback events to the Quickshell journal for debugging

### Requirement 10: Backend Support — OpenAI Realtime API

**User Story:** As a user with an OpenAI API key, I want to use the OpenAI Realtime API for true streaming dictation, so that I get the lowest-latency transcription experience.

#### Acceptance Criteria

1. WHEN the provider is "openai" and Provider_Capability indicates streaming support, THE Streaming_Transcription_Service SHALL connect via WebSocket to the OpenAI Realtime API
2. WHILE connected, THE Streaming_Transcription_Service SHALL send audio frames encoded as base64 PCM in the format required by the Realtime API
3. WHEN the Realtime API emits `response.audio_transcript.delta` events, THE Streaming_Transcription_Service SHALL update `partialText` with the accumulated transcript
4. WHEN recording stops, THE Streaming_Transcription_Service SHALL send an `input_audio_buffer.commit` event and await the final transcript
5. THE Streaming_Transcription_Service SHALL authenticate the WebSocket connection using the API key from KeyringStorage

### Requirement 11: Backend Support — Local Streaming (faster-whisper / whisper.cpp)

**User Story:** As a user running local inference, I want to use a local streaming whisper server for real-time transcription, so that my audio never leaves my machine.

#### Acceptance Criteria

1. WHEN the provider is a known local provider and a streaming endpoint is reachable, THE Streaming_Transcription_Service SHALL connect via WebSocket to the local streaming server
2. WHILE connected, THE Streaming_Transcription_Service SHALL send raw PCM audio frames over the WebSocket connection
3. WHEN the local server emits partial transcription messages, THE Streaming_Transcription_Service SHALL update `partialText`
4. IF the local streaming endpoint is not reachable, THEN THE Streaming_Transcription_Service SHALL fall back to chunked mode using the local HTTP transcription endpoint
5. IF neither streaming nor chunked endpoints are reachable for the local provider, THEN THE Streaming_Transcription_Service SHALL fall back to batch mode using the whisper CLI

### Requirement 12: Policy Enforcement for Streaming

**User Story:** As a user with privacy policies configured, I want the streaming system to respect the same AI policies as batch mode, so that my audio data is handled according to my preferences.

#### Acceptance Criteria

1. WHEN `policies.ai` equals 0, THE Streaming_Transcription_Service SHALL not activate (same as existing behavior)
2. WHEN `policies.ai` equals 2 and the configured provider is remote, THE Streaming_Transcription_Service SHALL reject activation and display an error directing the user to configure a local provider
3. WHILE streaming is active, THE Streaming_Transcription_Service SHALL not persist audio data to disk (audio is streamed directly from PipeWire to the backend)
4. WHEN chunked mode is active under `policies.ai` equals 2, THE Streaming_Transcription_Service SHALL verify the chunk submission endpoint is local before sending audio
