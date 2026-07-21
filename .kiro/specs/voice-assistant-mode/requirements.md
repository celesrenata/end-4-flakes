# Requirements Document

## Introduction

The Voice Assistant Mode transforms the existing dictation system into a full voice assistant layer. Currently, dictated text routes to either the AI sidebar chat (when open) or the overview/action palette (when closed). This feature adds: direct action execution without opening the overview UI, concise spoken-style AI responses, text-to-speech talkback, a persistent "Free Dictation" session for logging voice interactions, local STT provider configuration for external hosts, a settings UI for dictation/TTS providers, and intent detection to distinguish commands from pure dictation.

## Glossary

- **Voice_Assistant_Service**: The orchestration layer within DictationService that manages the voice assistant pipeline: intent detection, action execution, response generation, and talkback
- **Intent_Classifier**: The component that determines whether transcribed speech is a command/question (routed to ActionPalette) or pure dictation (captured into Free_Dictation_Session)
- **TTS_Engine**: The text-to-speech subsystem that converts AI response text into spoken audio played through PipeWire
- **Free_Dictation_Session**: A persistent, always-available chat session in the sidebar that logs all voice assistant interactions (user input and AI responses)
- **Talkback**: The configurable behavior of speaking the AI's response back to the user via the TTS_Engine after action execution
- **Floating_Response_Indicator**: A transient overlay that displays the AI's concise response text (and optionally plays audio) without opening the full overview or sidebar
- **STT_Provider**: A speech-to-text backend configured for transcription (OpenAI Whisper API, faster-whisper server, whisper.cpp server, or custom endpoint)
- **Action_Pipeline**: The sequence of ActionPalette.submitQuery → action plan generation → execution, invoked directly without UI when the sidebar is closed
- **Provider_Settings_Panel**: The section in the shell settings UI where the user configures STT and TTS providers, endpoints, models, and talkback preferences

## Requirements

### Requirement 1: Direct Action Execution (Skip Overlay)

**User Story:** As a user, I want voice commands executed directly without opening the overview dropdown, so that I get results faster with minimal visual disruption.

#### Acceptance Criteria

1. WHEN dictation completes with the sidebar closed and the Intent_Classifier classifies the transcription as a command or question, THE Voice_Assistant_Service SHALL invoke the Action_Pipeline directly without opening the overview
2. WHEN the Action_Pipeline returns an Action_Plan, THE Voice_Assistant_Service SHALL execute the plan automatically (applying config.set, hyprland.dispatch, and app.launch actions without user confirmation)
3. WHEN the Action_Pipeline contains a shell.exec action, THE Voice_Assistant_Service SHALL display an approval prompt via the Floating_Response_Indicator before executing the command
4. WHEN the Action_Pipeline execution completes, THE Voice_Assistant_Service SHALL display the action plan summary in the Floating_Response_Indicator for 4 seconds
5. WHEN the Action_Pipeline returns an informational response (no executable actions, only a summary), THE Voice_Assistant_Service SHALL display the summary text in the Floating_Response_Indicator
6. IF the Action_Pipeline request fails or times out, THEN THE Voice_Assistant_Service SHALL display the error in the Floating_Response_Indicator for 3 seconds

### Requirement 2: Concise AI Responses

**User Story:** As a user, I want the AI to respond with brief, spoken-style answers scaled to query complexity, so that voice interactions feel natural and quick.

#### Acceptance Criteria

1. WHEN the Voice_Assistant_Service sends a query to the Action_Pipeline in voice assistant mode, THE Voice_Assistant_Service SHALL append a system instruction requiring responses be concise, conversational, and scaled to query complexity
2. THE Voice_Assistant_Service SHALL instruct the LLM to limit informational responses to a single sentence for simple queries (time, weather, single-value lookups)
3. THE Voice_Assistant_Service SHALL instruct the LLM to provide up to three sentences for moderate queries (disk space summary, system status overview)
4. THE Voice_Assistant_Service SHALL instruct the LLM to provide detailed responses only when the user explicitly requests detail (using words like "breakdown", "list all", "explain")
5. WHEN generating a response for voice assistant mode, THE Voice_Assistant_Service SHALL instruct the LLM to use natural spoken language (contractions, informal units like "gigs" instead of "GiB") rather than formatted markdown or tables

### Requirement 3: Text-to-Speech Talkback

**User Story:** As a user, I want the AI's response spoken back to me through my speakers, so that I can interact with my desktop hands-free.

#### Acceptance Criteria

1. WHEN talkback is enabled and the Voice_Assistant_Service receives a response, THE TTS_Engine SHALL convert the response text to audio and play it through the PipeWire default audio sink
2. THE TTS_Engine SHALL support the "piper" backend by invoking the piper CLI with the configured voice model and piping output to pw-play
3. THE TTS_Engine SHALL support the "espeak-ng" backend by invoking espeak-ng with the configured voice and piping output to pw-play
4. THE TTS_Engine SHALL support the "openai" backend by sending the response text to the OpenAI TTS API with the configured voice model and playing the returned audio through pw-play
5. WHILE TTS audio is playing, THE Floating_Response_Indicator SHALL display a speaker animation icon indicating active playback
6. WHEN the user taps the dictation activation key during TTS playback, THE TTS_Engine SHALL immediately stop playback and begin a new dictation session
7. IF the TTS_Engine fails to synthesize or play audio, THEN THE Voice_Assistant_Service SHALL display the response text in the Floating_Response_Indicator without audio and log the error to the Quickshell journal

### Requirement 4: Free Dictation Session

**User Story:** As a user, I want all voice assistant interactions logged in a persistent sidebar session, so that I can review, edit, and re-send previous voice commands.

#### Acceptance Criteria

1. THE Voice_Assistant_Service SHALL maintain a persistent chat session named "Free Dictation" in the sidebar session list that cannot be deleted by the user
2. WHEN the Voice_Assistant_Service processes a voice command, THE Free_Dictation_Session SHALL append the user's transcribed text as a user message
3. WHEN the Voice_Assistant_Service receives an AI response (informational or action summary), THE Free_Dictation_Session SHALL append the response as an assistant message
4. WHEN the user opens the Free_Dictation_Session in the sidebar, THE Voice_Assistant_Service SHALL display the full interaction history with timestamps
5. WHEN the user selects a previous message in the Free_Dictation_Session and activates "re-send", THE Voice_Assistant_Service SHALL resubmit that text through the Action_Pipeline as a new voice command
6. THE Free_Dictation_Session SHALL persist across Quickshell restarts using the existing session storage mechanism

### Requirement 5: Local STT Provider Support

**User Story:** As a user running faster-whisper or whisper.cpp on my GPU server, I want to configure STT endpoints on any network host, so that I can use my own hardware for transcription.

#### Acceptance Criteria

1. THE Voice_Assistant_Service SHALL support configuring STT_Provider endpoints at any network address (not limited to localhost), accepting both IP addresses and hostnames
2. WHEN the STT_Provider is "faster-whisper" or "whisper-cpp", THE Voice_Assistant_Service SHALL support HTTP batch endpoints (POST to /v1/audio/transcriptions) at the configured address
3. WHEN the STT_Provider is "faster-whisper" or "whisper-cpp" and a WebSocket endpoint is configured, THE Voice_Assistant_Service SHALL use the WebSocket endpoint for streaming transcription
4. THE Voice_Assistant_Service SHALL validate endpoint connectivity by performing a health check (HTTP GET to the base URL) when the endpoint configuration changes, displaying the connection status in the Provider_Settings_Panel
5. WHEN the configured STT endpoint is unreachable during a dictation session, THE Voice_Assistant_Service SHALL fall back to the next available provider in order: configured endpoint → localhost → OpenAI API (if allowed by policy)
6. THE Voice_Assistant_Service SHALL read the STT endpoint from `Config.options.dictation.streamingEndpoint` for WebSocket connections and from a new `Config.options.dictation.httpEndpoint` key for batch HTTP connections

### Requirement 6: Dictation Provider Settings UI

**User Story:** As a user, I want a dedicated settings section to configure my STT and TTS providers, so that I can manage voice assistant preferences without editing config files.

#### Acceptance Criteria

1. THE Provider_Settings_Panel SHALL display a section titled "Voice Assistant" within the existing shell settings panel
2. THE Provider_Settings_Panel SHALL provide a dropdown to select the STT_Provider from: "openai", "faster-whisper", "whisper-cpp", "custom"
3. THE Provider_Settings_Panel SHALL provide a text input for the STT endpoint URL, pre-populated from `Config.options.dictation.streamingEndpoint` or `Config.options.dictation.httpEndpoint`
4. THE Provider_Settings_Panel SHALL provide a text input for the STT model name, pre-populated from `Config.options.dictation.model`
5. THE Provider_Settings_Panel SHALL provide a dropdown to select the TTS provider from: "none", "piper", "espeak-ng", "openai"
6. THE Provider_Settings_Panel SHALL provide a text input for the TTS voice or model identifier
7. THE Provider_Settings_Panel SHALL provide a toggle for enabling or disabling talkback, mapped to `Config.options.dictation.talkback`
8. WHEN the user modifies any setting in the Provider_Settings_Panel, THE Provider_Settings_Panel SHALL persist the change to the corresponding Config key immediately
9. WHEN the STT_Provider selection changes, THE Provider_Settings_Panel SHALL update the endpoint URL placeholder text to show the default endpoint for the selected provider

### Requirement 7: Intent Detection

**User Story:** As a user, I want the system to distinguish between voice commands and pure dictation, so that saying "open Firefox" executes an action while dictating an email just captures text.

#### Acceptance Criteria

1. WHEN dictation completes, THE Intent_Classifier SHALL classify the transcribed text as either "command" (routed to the Action_Pipeline) or "dictation" (captured into the Free_Dictation_Session without execution)
2. THE Intent_Classifier SHALL classify text as "command" when it matches any of: starts with an imperative verb (open, close, launch, set, change, toggle, switch, move, kill, run, show, hide, play, pause, stop, mute, unmute), contains a question mark, starts with "what", "how", "when", "where", "who", "which", "is", "are", "can", "do", "does"
3. THE Intent_Classifier SHALL classify text as "dictation" when it does not match any command pattern and exceeds 20 words in length
4. WHERE the user has configured `Config.options.dictation.intentMode` as "ai", THE Intent_Classifier SHALL use the configured LLM to classify ambiguous inputs (those not matching explicit command or dictation heuristics)
5. WHERE the user has configured `Config.options.dictation.intentMode` as "heuristic" or the value is not set, THE Intent_Classifier SHALL use only the pattern-matching rules without LLM calls
6. WHEN the Intent_Classifier classifies text as "dictation", THE Voice_Assistant_Service SHALL append the text to the Free_Dictation_Session as a user message without triggering the Action_Pipeline
7. IF the Intent_Classifier cannot determine intent with confidence (ambiguous short text under 20 words that does not match command patterns), THEN THE Voice_Assistant_Service SHALL default to "command" classification

### Requirement 8: Floating Response Indicator

**User Story:** As a user, I want voice assistant results shown in a minimal floating overlay rather than opening the full overview, so that my workflow is not disrupted.

#### Acceptance Criteria

1. THE Floating_Response_Indicator SHALL appear as a PanelWindow overlay anchored to the top-right corner of the focused monitor, below the existing bar
2. THE Floating_Response_Indicator SHALL display the AI response text with a maximum width of 500 pixels, wrapping text as needed
3. THE Floating_Response_Indicator SHALL auto-dismiss after 4 seconds of inactivity when no TTS is playing
4. WHILE TTS audio is playing, THE Floating_Response_Indicator SHALL remain visible until playback completes
5. WHEN the user clicks the Floating_Response_Indicator, THE Voice_Assistant_Service SHALL copy the response text to the clipboard and dismiss the indicator
6. THE Floating_Response_Indicator SHALL not steal keyboard focus or interfere with window management
7. WHEN a shell.exec approval is required, THE Floating_Response_Indicator SHALL display the command text with [Approve] and [Reject] buttons, remaining visible until the user responds

### Requirement 9: Configuration Keys

**User Story:** As a developer, I want all voice assistant settings stored in the existing Config.qml structure, so that they integrate cleanly with the shell's configuration system.

#### Acceptance Criteria

1. THE Voice_Assistant_Service SHALL read TTS provider from `Config.options.dictation.ttsProvider` with a default value of "none"
2. THE Voice_Assistant_Service SHALL read TTS voice/model from `Config.options.dictation.ttsVoice` with a default value of "" (empty string, uses provider default)
3. THE Voice_Assistant_Service SHALL read talkback enabled state from `Config.options.dictation.talkback` with a default value of false
4. THE Voice_Assistant_Service SHALL read intent classification mode from `Config.options.dictation.intentMode` with a default value of "heuristic"
5. THE Voice_Assistant_Service SHALL read HTTP endpoint from `Config.options.dictation.httpEndpoint` with a default value of "" (empty string, auto-derived from provider)
6. WHEN any dictation configuration key changes at runtime, THE Voice_Assistant_Service SHALL apply the new value for the next dictation session without requiring a Quickshell restart

### Requirement 10: Policy Enforcement

**User Story:** As a user with privacy policies configured, I want the voice assistant to respect AI policies for all its components, so that my data handling preferences are honored.

#### Acceptance Criteria

1. WHEN `policies.ai` equals 0, THE Voice_Assistant_Service SHALL disable all voice assistant functionality (no dictation activation, no TTS, no intent classification)
2. WHEN `policies.ai` equals 2 and the configured TTS provider is "openai", THE TTS_Engine SHALL not send text to the remote API and SHALL fall back to a local TTS provider if one is configured, or disable talkback
3. WHEN `policies.ai` equals 2 and the configured STT_Provider is "openai", THE Voice_Assistant_Service SHALL reject activation and display an error directing the user to configure a local STT provider
4. WHEN `policies.ai` equals 2 and `intentMode` is "ai", THE Intent_Classifier SHALL verify the LLM endpoint is local before sending classification requests
5. THE Voice_Assistant_Service SHALL not persist audio recordings beyond the transcription processing phase (existing behavior preserved)

### Requirement 11: TTS Audio Pipeline

**User Story:** As a user, I want TTS audio played through my system's default speaker using PipeWire, so that it integrates with my existing audio setup.

#### Acceptance Criteria

1. WHEN the TTS_Engine generates audio, THE TTS_Engine SHALL play the audio through the PipeWire default audio sink using pw-play or pw-cat --playback
2. THE TTS_Engine SHALL support PCM WAV and OGG audio formats for local TTS providers (piper, espeak-ng)
3. THE TTS_Engine SHALL support MP3 and OPUS audio formats for the OpenAI TTS API response
4. WHEN multiple TTS requests are queued (rapid successive voice commands), THE TTS_Engine SHALL cancel any in-progress playback before starting the new response
5. THE TTS_Engine SHALL clean up temporary audio files immediately after playback completes

### Requirement 12: Voice Assistant Mode Integration with Existing Routing

**User Story:** As a user, I want voice assistant mode to work alongside existing dictation routing, so that the sidebar-open behavior remains unchanged while sidebar-closed behavior gains the new assistant capabilities.

#### Acceptance Criteria

1. WHEN the sidebar is open during dictation, THE Voice_Assistant_Service SHALL route transcribed text to the sidebar AI chat input exactly as the current system does (no voice assistant processing)
2. WHEN the sidebar is closed during dictation, THE Voice_Assistant_Service SHALL process the transcribed text through the Intent_Classifier and voice assistant pipeline instead of opening the overview
3. WHEN the sidebar is closed and intent is "command", THE Voice_Assistant_Service SHALL invoke the Action_Pipeline directly and display results in the Floating_Response_Indicator
4. WHEN the sidebar is closed and intent is "dictation", THE Voice_Assistant_Service SHALL append the text to the Free_Dictation_Session and display a brief confirmation in the Floating_Response_Indicator
5. THE Voice_Assistant_Service SHALL emit the existing `transcriptionComplete` signal after processing completes, regardless of routing path
