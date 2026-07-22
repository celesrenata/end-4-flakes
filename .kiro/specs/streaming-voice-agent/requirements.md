# Requirements Document

## Introduction

Replace the existing batch voice pipeline (record → stop → upload → transcribe → LLM → TTS → play) with bidirectional streaming voice conversations. Two backends are supported: Amazon Nova Sonic (via Bedrock bidirectional streaming) and OpenAI Realtime API (WebSocket). Both enable continuous audio input with live transcription, AI reasoning, and audio output in a single persistent stream — eliminating per-step latency. The existing batch pipeline remains as a fallback when streaming is unavailable. A new Python helper script (`voice-agent-stream.py`) maintains the bidirectional connection, following the proven `dictation-stream.py` pattern of reading audio from stdin and writing JSON events to stdout.

## Glossary

- **Voice_Agent_Service**: The QML component (extension of DictationService) responsible for managing bidirectional streaming voice sessions, including lifecycle, state, and event routing
- **Voice_Agent_Helper**: The Python subprocess (`voice-agent-stream.py`) that maintains the bidirectional WebSocket/HTTP2 connection to the selected backend, reads PCM audio from stdin, and emits structured JSON events on stdout
- **Nova_Sonic_Backend**: Amazon Nova Sonic speech-to-speech model accessed via Bedrock bidirectional streaming API, handling STT, reasoning, and TTS in a single stream
- **OpenAI_Realtime_Backend**: OpenAI Realtime API accessed via WebSocket at `/v1/realtime`, supporting voice-agent mode (audio in → audio + text out) with tool calling
- **Streaming_Session**: A persistent bidirectional connection between the Voice_Agent_Helper and a backend, lasting from activation until explicit stop or timeout
- **Turn**: A complete user utterance followed by the backend response; turn boundaries are detected by the backend via voice activity detection
- **Partial_Transcript**: Intermediate text fragments emitted by the backend as speech is recognized, before the turn is complete
- **Tool_Call**: A structured request from the backend to execute an action (e.g., system commands, queries) during a streaming voice session
- **DictationIndicator**: The floating overlay PanelWindow displaying real-time voice session state (listening waveform, partial transcription, thinking state, response text)
- **Batch_Pipeline**: The existing record-stop-upload-transcribe flow used as a fallback when streaming connections are unavailable
- **Voice_Activity_Detection**: Backend-side detection of speech start/stop used for automatic turn-taking without manual stop
- **Session_Context**: Chat history from the active sidebar session injected into the streaming voice session for continuity

## Requirements

### Requirement 1: Backend Selection

**User Story:** As a user, I want to choose between Nova Sonic and OpenAI Realtime as my streaming voice backend, so that I can use whichever service best fits my needs and credentials.

#### Acceptance Criteria

1. THE Voice_Agent_Service SHALL expose a `voiceBackend` configuration property with values: "nova-sonic", "openai-realtime", and "none" (disabled)
2. WHEN the user selects a voice backend in the dictation settings, THE Voice_Agent_Service SHALL persist the selection to `Config.options.dictation.voiceBackend`
3. WHEN `voiceBackend` is "nova-sonic", THE Voice_Agent_Service SHALL validate that AwsCredentialReader reports `credentialsDetected` as true before activating a session
4. WHEN `voiceBackend` is "openai-realtime", THE Voice_Agent_Service SHALL validate that KeyringStorage contains a non-empty "openai" API key before activating a session
5. IF credentials are missing for the selected backend, THEN THE Voice_Agent_Service SHALL display an error in the DictationIndicator identifying the missing credential and remain in Idle state

### Requirement 2: Bidirectional Streaming Session Lifecycle

**User Story:** As a user, I want to start a streaming voice conversation by tapping my activation key and have it remain active until I explicitly stop it, so that I can have natural multi-turn conversations without repeated activation.

#### Acceptance Criteria

1. WHEN the user activates dictation and a streaming voice backend is configured, THE Voice_Agent_Service SHALL launch the Voice_Agent_Helper subprocess with the appropriate backend arguments
2. WHEN the Voice_Agent_Helper emits a READY event, THE Voice_Agent_Service SHALL transition to StreamingActive state and begin piping audio from `pw-cat --record` to the helper stdin
3. WHILE in StreamingActive state, THE Voice_Agent_Service SHALL maintain the audio pipe and helper process until the user taps the activation key again or a fatal error occurs
4. WHEN the user taps the activation key while in StreamingActive state, THE Voice_Agent_Service SHALL close the audio pipe stdin, signal the helper to finalize, and transition to Processing
5. WHEN the Voice_Agent_Helper emits a SESSION_END event, THE Voice_Agent_Service SHALL terminate the helper subprocess and transition to Idle
6. IF the Voice_Agent_Helper exits unexpectedly, THEN THE Voice_Agent_Service SHALL transition to Error state and display the exit reason in the DictationIndicator

### Requirement 3: Live Transcription Display

**User Story:** As a user, I want to see my words appear in real time as I speak during a streaming session, so that I can confirm the system is hearing me correctly.

#### Acceptance Criteria

1. WHEN the Voice_Agent_Helper emits a PARTIAL_TRANSCRIPT event, THE Voice_Agent_Service SHALL update the `partialText` property with the transcript content
2. WHILE in StreamingActive state, THE DictationIndicator SHALL display the current `partialText` below the state indicator
3. WHEN `partialText` updates, THE DictationIndicator SHALL animate new text appearing with a fade-in transition
4. WHEN the backend completes a turn and emits TURN_COMPLETE, THE Voice_Agent_Service SHALL clear `partialText` and display the finalized user utterance briefly before showing the response
5. THE DictationIndicator SHALL expand dynamically to accommodate transcription text up to a maximum width of 500 pixels, truncating from the left when exceeded

### Requirement 4: Voice Response Playback

**User Story:** As a user, I want to hear the AI response spoken back to me through my speakers during a streaming session, so that I can have a hands-free conversation.

#### Acceptance Criteria

1. WHEN the Voice_Agent_Helper emits AUDIO_RESPONSE events containing PCM audio data, THE Voice_Agent_Service SHALL pipe the audio data to `pw-play` for playback
2. WHILE audio response is playing, THE DictationIndicator SHALL display a "Speaking..." state indicator
3. WHEN the backend provides a text transcript of the response alongside audio, THE Voice_Agent_Service SHALL update `responseText` with the response transcript
4. WHEN audio playback completes, THE Voice_Agent_Service SHALL resume listening for the next user turn (re-enable audio capture to the helper)
5. IF the user taps the activation key during audio playback, THEN THE Voice_Agent_Service SHALL stop playback immediately and resume listening (barge-in)

### Requirement 5: Nova Sonic Backend Protocol

**User Story:** As a user with AWS credentials, I want the system to connect to Nova Sonic via Bedrock bidirectional streaming, so that I get speech-to-speech AI responses with minimal latency.

#### Acceptance Criteria

1. WHEN `voiceBackend` is "nova-sonic", THE Voice_Agent_Helper SHALL establish a bidirectional HTTP/2 stream to the Bedrock Runtime `invoke-model-with-bidirectional-stream` endpoint for the `amazon.nova-sonic-v1:0` model
2. THE Voice_Agent_Helper SHALL authenticate using the AWS credentials (region and profile) provided by AwsCredentialReader
3. WHILE the stream is active, THE Voice_Agent_Helper SHALL send audio input events containing PCM audio frames encoded per the Nova Sonic input event schema
4. WHEN Nova Sonic emits transcript events, THE Voice_Agent_Helper SHALL output PARTIAL_TRANSCRIPT events on stdout
5. WHEN Nova Sonic emits audio response events, THE Voice_Agent_Helper SHALL output AUDIO_RESPONSE events containing the PCM audio data on stdout
6. WHEN Nova Sonic emits a tool-use event, THE Voice_Agent_Helper SHALL output a TOOL_CALL event on stdout and pause audio input until a TOOL_RESULT is received on stdin
7. THE Voice_Agent_Helper SHALL send a system prompt event at session start containing the voice assistant context and session history

### Requirement 6: OpenAI Realtime Backend Protocol

**User Story:** As a user with an OpenAI API key, I want the system to connect to OpenAI Realtime API for streaming voice conversations, so that I get GPT-powered voice responses in real time.

#### Acceptance Criteria

1. WHEN `voiceBackend` is "openai-realtime", THE Voice_Agent_Helper SHALL establish a WebSocket connection to `wss://api.openai.com/v1/realtime` with the model parameter set to `gpt-4o-realtime-preview`
2. THE Voice_Agent_Helper SHALL authenticate using the OpenAI API key passed via the `--api-key` argument and send the required `OpenAI-Beta: realtime=v1` header
3. WHILE the session is active, THE Voice_Agent_Helper SHALL send `input_audio_buffer.append` events containing base64-encoded PCM audio frames
4. WHEN the OpenAI Realtime API emits `response.audio_transcript.delta` events, THE Voice_Agent_Helper SHALL output PARTIAL_TRANSCRIPT events on stdout
5. WHEN the OpenAI Realtime API emits `response.audio.delta` events, THE Voice_Agent_Helper SHALL output AUDIO_RESPONSE events containing the decoded audio data on stdout
6. WHEN the OpenAI Realtime API emits `response.function_call_arguments.done` events, THE Voice_Agent_Helper SHALL output a TOOL_CALL event on stdout
7. THE Voice_Agent_Helper SHALL configure the session with server-side voice activity detection (turn detection) enabled by sending a `session.update` event at connection start
8. THE Voice_Agent_Helper SHALL include the voice assistant system prompt and session context in the `session.update` instructions field

### Requirement 7: Automatic Turn-Taking

**User Story:** As a user, I want the system to automatically detect when I stop speaking and begin responding, so that I do not need to manually signal end-of-turn for short queries.

#### Acceptance Criteria

1. WHILE in StreamingActive state, THE Voice_Agent_Service SHALL rely on the backend Voice_Activity_Detection to determine turn boundaries
2. WHEN the backend detects end-of-speech and begins generating a response, THE Voice_Agent_Helper SHALL emit a TURN_END event on stdout
3. WHEN the Voice_Agent_Service receives a TURN_END event, THE DictationIndicator SHALL transition to display "Thinking..." state
4. WHEN the user manually taps the activation key during a turn, THE Voice_Agent_Service SHALL send an explicit end-of-turn signal to the Voice_Agent_Helper (which forwards `input_audio_buffer.commit` or equivalent to the backend)
5. WHILE the backend is generating a response, THE Voice_Agent_Service SHALL continue accepting audio input to support barge-in detection by the backend

### Requirement 8: Tool Calling During Voice Sessions

**User Story:** As a user, I want the AI to be able to execute actions (check system status, control my desktop, query information) during our streaming conversation, so that voice interactions are as capable as chat interactions.

#### Acceptance Criteria

1. WHEN the Voice_Agent_Helper emits a TOOL_CALL event, THE Voice_Agent_Service SHALL parse the tool name and arguments from the event payload
2. THE Voice_Agent_Service SHALL execute the tool call using the existing ActionPalette tool execution infrastructure
3. WHEN tool execution completes, THE Voice_Agent_Service SHALL send a TOOL_RESULT event to the Voice_Agent_Helper via stdin containing the serialized result
4. THE Voice_Agent_Helper SHALL forward the tool result to the backend in the appropriate format (Nova Sonic tool result event or OpenAI `conversation.item.create` with tool output)
5. WHILE a tool call is executing, THE DictationIndicator SHALL display "Executing [tool_name]..." state
6. IF tool execution fails, THEN THE Voice_Agent_Service SHALL send a TOOL_RESULT event with an error message so the backend can inform the user vocally

### Requirement 9: Session Context Injection

**User Story:** As a user, I want my streaming voice conversation to have access to the current chat context, so that the AI understands what we have been discussing and can provide relevant responses.

#### Acceptance Criteria

1. WHEN a streaming session starts, THE Voice_Agent_Service SHALL retrieve the recent message history from the active sidebar chat session (via Ai.getCurrentSessionMessages)
2. THE Voice_Agent_Service SHALL pass the session context to the Voice_Agent_Helper via a `--context` argument or initial stdin event containing the serialized messages
3. THE Voice_Agent_Helper SHALL include the session context in the backend session configuration (system prompt for Nova Sonic, instructions for OpenAI Realtime)
4. WHEN the streaming session ends, THE Voice_Agent_Service SHALL append the conversation transcript (user utterances and AI responses) to the active sidebar chat session
5. IF no active sidebar session exists, THEN THE Voice_Agent_Service SHALL use the "Free Dictation" session for context and transcript logging

### Requirement 10: Graceful Fallback to Batch Mode

**User Story:** As a user, I want dictation to always work even if the streaming connection fails, so that I never lose my spoken input.

#### Acceptance Criteria

1. IF the Voice_Agent_Helper fails to establish a connection within 5 seconds, THEN THE Voice_Agent_Service SHALL terminate the helper and activate the existing Batch_Pipeline
2. IF the Voice_Agent_Helper emits a FALLBACK event during a session, THEN THE Voice_Agent_Service SHALL save the buffered audio and submit it through the Batch_Pipeline
3. WHEN falling back to batch mode, THE DictationIndicator SHALL update to show the standard recording UI (duration counter, no partial text)
4. WHEN `voiceBackend` is "none", THE Voice_Agent_Service SHALL activate the Batch_Pipeline directly without attempting a streaming connection
5. THE Voice_Agent_Service SHALL log fallback events with the reason to the Quickshell journal for debugging

### Requirement 11: DictationIndicator State Display

**User Story:** As a user, I want the floating indicator to show me exactly what stage the voice conversation is in at all times, so that I know when to speak, when to wait, and when the AI is responding.

#### Acceptance Criteria

1. WHILE in StreamingActive state and the user is speaking, THE DictationIndicator SHALL display "Listening..." with an animated audio level indicator derived from the input audio amplitude
2. WHILE in StreamingActive state and partial transcript is available, THE DictationIndicator SHALL display the live partial transcript text alongside the level indicator
3. WHEN a TURN_END event is received, THE DictationIndicator SHALL display "Thinking..." with a pulsing animation
4. WHILE audio response is playing, THE DictationIndicator SHALL display the response text (if available) with a speaker icon indicating active playback
5. WHEN the streaming session is idle between turns (listening but no speech detected), THE DictationIndicator SHALL display a subtle "Ready..." state with a muted mic icon
6. IF an error occurs, THEN THE DictationIndicator SHALL display the error message for 5 seconds before returning to Idle

### Requirement 12: Voice Agent Helper Protocol

**User Story:** As a developer, I want a well-defined line protocol between the QML service and the Python helper, so that the two processes can communicate reliably about session state, transcription, audio, and tool calls.

#### Acceptance Criteria

1. THE Voice_Agent_Helper SHALL emit events on stdout as newline-delimited JSON objects with a `type` field indicating the event kind
2. THE Voice_Agent_Helper SHALL support the following output event types: READY, PARTIAL_TRANSCRIPT, TURN_END, TURN_COMPLETE, AUDIO_RESPONSE, TOOL_CALL, SESSION_END, ERROR, FALLBACK
3. THE Voice_Agent_Helper SHALL accept input events on stdin as newline-delimited JSON objects with a `type` field
4. THE Voice_Agent_Helper SHALL support the following input event types: TOOL_RESULT, STOP, BARGE_IN
5. THE Voice_Agent_Helper SHALL encode audio data in AUDIO_RESPONSE events as base64-encoded PCM (16kHz, mono, 16-bit signed)
6. THE Voice_Agent_Helper SHALL include a `text` field in PARTIAL_TRANSCRIPT and TURN_COMPLETE events containing the transcript content
7. THE Voice_Agent_Helper SHALL include `name` and `arguments` fields in TOOL_CALL events identifying the tool and its JSON-encoded parameters

### Requirement 13: Audio Pipeline Configuration

**User Story:** As a user, I want the streaming voice system to capture and play audio through PipeWire at the correct format for each backend, so that audio quality is maintained throughout the conversation.

#### Acceptance Criteria

1. THE Voice_Agent_Service SHALL capture audio using `pw-cat --record --format=s16 --rate=16000 --channels=1` and pipe to Voice_Agent_Helper stdin for Nova Sonic
2. THE Voice_Agent_Service SHALL capture audio using `pw-cat --record --format=s16 --rate=24000 --channels=1` and pipe to Voice_Agent_Helper stdin for OpenAI Realtime (which requires 24kHz PCM)
3. THE Voice_Agent_Service SHALL play response audio by piping AUDIO_RESPONSE data to `pw-play` with format parameters matching the backend output format
4. WHILE audio capture is active, THE Voice_Agent_Service SHALL compute a running RMS amplitude from the audio stream for the DictationIndicator level display
5. IF the audio capture process exits unexpectedly, THEN THE Voice_Agent_Service SHALL emit a STOP event to the helper and transition to Error state

### Requirement 14: Policy Enforcement

**User Story:** As a user with privacy policies configured, I want the streaming voice system to respect the same AI policies as the rest of the system, so that my audio data is handled according to my preferences.

#### Acceptance Criteria

1. WHEN `policies.ai` equals 0, THE Voice_Agent_Service SHALL not activate streaming voice sessions
2. WHEN `policies.ai` equals 2 (local-only) and `voiceBackend` is "nova-sonic" or "openai-realtime", THE Voice_Agent_Service SHALL reject activation and display an error stating that streaming voice requires remote API access
3. WHILE a streaming session is active, THE Voice_Agent_Service SHALL not persist raw audio data to disk (audio is streamed directly through pipes)
4. WHEN a streaming session ends, THE Voice_Agent_Service SHALL persist only the text transcript to the chat session, not audio recordings

