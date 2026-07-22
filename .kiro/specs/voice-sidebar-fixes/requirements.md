# Requirements Document

## Introduction

This specification addresses three related UX issues in the Quickshell sidebar and dictation system:

1. **Voice providers missing from ProviderPanel** — The ProviderPanel only displays AI model providers (OpenAI, Anthropic, etc.) but not STT/TTS voice providers (whisper.cpp, Vosk, Piper, etc.), even though `sttProviders` and `ttsProviders` JsonObjects exist in Config.qml.
2. **Dictation debounce** — The Logitech button fires Ctrl+H three times in ~300ms, causing DictationService to cycle through states rapidly. A debounce mechanism is needed to collapse rapid repeated signals into a single activation.
3. **Chat ListView message ordering** — The chat ListView uses `verticalLayoutDirection: ListView.BottomToTop` to anchor new messages at the bottom, but this may have visually reversed the message order so that the newest message appears at the top instead of the bottom.

## Glossary

- **ProviderPanel**: The QML component (`modules/sidebarLeft/ProviderPanel.qml`) that displays provider cards for configuring API keys and discovering models.
- **ModelDiscoveryService**: The QML Singleton service (`services/ModelDiscoveryService.qml`) that manages provider configurations, API key validation, and model discovery for AI providers.
- **DictationService**: The QML Singleton service (`services/DictationService.qml`) managing dictation state transitions, recording, and transcription.
- **Config**: The QML Singleton (`modules/common/Config.qml`) holding all shell configuration, including `sttProviders` and `ttsProviders` JsonObjects under `dictation`.
- **STT_Provider**: A speech-to-text provider configuration (whisper.cpp, Faster Whisper, Vosk, Whisper Live) defined in `Config.options.dictation.sttProviders`.
- **TTS_Provider**: A text-to-speech provider configuration (Piper, Coqui, Mimic3, espeak-ng) defined in `Config.options.dictation.ttsProviders`.
- **Voice_Provider_Section**: A dedicated section in the ProviderPanel UI that displays STT and TTS provider entries separately from AI model providers.
- **Debounce_Guard**: A timing mechanism in DictationService that suppresses duplicate dictation activation signals arriving within a configurable window.
- **Debounce_Window**: The time period (default 500ms) after activation during which subsequent activation signals are ignored.
- **Dictation_Tap_Signal**: The GlobalShortcut signal named "dictationTap" received from Hyprland when the dictation key is pressed.
- **AiChat_ListView**: The `StyledListView` component in `modules/sidebarLeft/AiChat.qml` that displays chat messages with `verticalLayoutDirection: ListView.BottomToTop`.
- **Message_Model**: The `ScriptModel` providing message IDs to the AiChat_ListView, sourced from `Ai.messageIDs`.

## Requirements

### Requirement 1: Display STT Providers in ProviderPanel

**User Story:** As a user, I want to see my configured STT providers (whisper.cpp, Faster Whisper, Vosk, Whisper Live) in the sidebar ProviderPanel, so that I can view their status and configure endpoints without editing config files manually.

#### Acceptance Criteria

1. WHEN the ProviderPanel is rendered, THE ProviderPanel SHALL display a "Voice: Speech-to-Text" section listing each STT_Provider entry from `Config.options.dictation.sttProviders`, showing the provider name and endpoint URL per list item.
2. WHEN a STT_Provider entry is selected, THE ProviderPanel SHALL show a detail view with editable fields for the provider name (read-only label), endpoint URL (text input), protocol (constrained to "rest" or "websocket"), model (text input), and language (text input).
3. THE ProviderPanel SHALL display the "Voice: Speech-to-Text" section after the AI model providers list and before any TTS_Provider section, or at the end of the panel if no TTS section is present.
4. WHEN any STT_Provider field (endpoint, protocol, model, or language) is modified in the detail view, THE ProviderPanel SHALL persist the change to `Config.options.dictation.sttProviders` via `Config.setNestedValue` using the key path `dictation.sttProviders.<providerKey>.<fieldName>`.
5. WHEN the back action is triggered from the STT_Provider detail view, THE ProviderPanel SHALL return to the "Voice: Speech-to-Text" list view without persisting uncommitted changes.

### Requirement 2: Display TTS Providers in ProviderPanel

**User Story:** As a user, I want to see my configured TTS providers (Piper, Coqui, Mimic3, espeak-ng) in the sidebar ProviderPanel, so that I can view their status and adjust voice settings.

#### Acceptance Criteria

1. WHEN the ProviderPanel is rendered, THE ProviderPanel SHALL display a "Voice: Text-to-Speech" section listing all entries from `Config.options.dictation.ttsProviders` as a vertical list, where each entry displays the provider key name (piper, coqui, mimic3, espeakNg).
2. WHEN a TTS_Provider entry is selected by the user clicking its list item, THE ProviderPanel SHALL show a detail view displaying: the provider name; and for providers that define an `endpoint` property (piper, coqui, mimic3), the endpoint URL, protocol, and voice fields; and for providers that define no `endpoint` property (espeakNg), the voice, speed, and pitch fields.
3. THE ProviderPanel SHALL display the "Voice: Text-to-Speech" section below the AI provider list section.
4. WHEN a TTS_Provider field value is modified in the detail view, THE ProviderPanel SHALL persist the change to the corresponding property path under `Config.options.dictation.ttsProviders.<providerKey>.<fieldName>` via `Config.setNestedValue` within 500 milliseconds of the user completing the edit.
5. IF a TTS_Provider endpoint field is modified to a value that is not a valid URL (does not begin with `http://`, `https://`, `tcp://`, or `ws://`), THEN THE ProviderPanel SHALL display an inline error indication adjacent to the endpoint field and SHALL NOT persist the invalid value.

### Requirement 3: Voice Provider Status Indication

**User Story:** As a user, I want to see at a glance whether each voice provider endpoint is reachable, so that I know which providers are available for use.

#### Acceptance Criteria

1. WHEN the ProviderPanel displays a STT_Provider or TTS_Provider with an HTTP or WebSocket endpoint, THE ProviderPanel SHALL show a connectivity status indicator with one of four states: idle (not yet checked), checking (request in-flight), reachable (successful response), or unreachable (failed or timed out).
2. WHEN a user selects a voice provider entry, THE ProviderPanel SHALL initiate an asynchronous HTTP HEAD request (for HTTP endpoints) or WebSocket connect attempt (for WebSocket endpoints) to the configured endpoint without blocking panel rendering.
3. IF the connectivity check receives a response with HTTP status 2xx or 4xx (server is reachable), THEN THE ProviderPanel SHALL display the provider status as "reachable".
4. IF the connectivity check fails, times out after 3 seconds, or receives a network error, THEN THE ProviderPanel SHALL display the provider status as "unreachable" with the error reason.
5. WHEN a STT_Provider or TTS_Provider has no endpoint defined (local CLI tool such as espeak-ng), THE ProviderPanel SHALL display the status as "local" without performing any network check.

### Requirement 4: Dictation Activation Debounce

**User Story:** As a user with a Logitech button that fires multiple signals in rapid succession, I want duplicate activation signals to be ignored after the first one, so that dictation does not enter a start-stop loop.

#### Acceptance Criteria

1. WHEN a Dictation_Tap_Signal triggers `onKeyTap()` and DictationService state is Idle, THE Debounce_Guard SHALL allow the activation to proceed and immediately start the Debounce_Window timer (default 500ms).
2. WHILE the Debounce_Window timer is running AND DictationService transitioned from Idle to Listening or StreamingActive on the initial signal, THE Debounce_Guard SHALL discard any incoming Dictation_Tap_Signal, logging a `GATE_REJECT | reason=debounce` message, without changing DictationService state.
3. WHEN the Debounce_Window timer expires, THE Debounce_Guard SHALL allow subsequent Dictation_Tap_Signals to be processed normally (i.e., stop recording if in Listening/StreamingActive state).
4. THE Debounce_Guard SHALL only apply to activations originating from the Idle state. WHEN DictationService is in Listening or StreamingActive state and the Debounce_Window has expired, a Dictation_Tap_Signal SHALL immediately stop recording without any debounce delay.
5. WHEN DictationService transitions to Idle from any state (Processing complete, Error dismissed, etc.), THE Debounce_Guard timer SHALL be stopped if still running, resetting the guard to allow the next activation.

### Requirement 5: Debounce Configuration

**User Story:** As a user, I want the debounce duration to be configurable, so that I can tune it for my specific hardware behavior.

#### Acceptance Criteria

1. THE Config SHALL expose a `dictation.debounceMs` integer property with a default value of 500 and a valid range of 0 to 2000 (inclusive).
2. THE DictationService SHALL reactively bind to `Config.options.dictation.debounceMs` such that changes to the value take effect on the next Dictation_Tap_Signal without requiring a service restart or shell reload.
3. WHEN `debounceMs` is set to 0, THE Debounce_Guard SHALL be disabled and all Dictation_Tap_Signals SHALL be processed immediately regardless of timing.
4. WHEN `debounceMs` is set to a value outside the range 0–2000, THE Config SHALL clamp the value to the nearest bound (0 or 2000) before persisting.

### Requirement 6: Chat ListView Correct Chronological Order

**User Story:** As a user, I want chat messages to display in chronological order with the newest message visible at the bottom of the viewport, so that the conversation reads naturally from top to bottom.

#### Acceptance Criteria

1. THE AiChat_ListView SHALL display messages in chronological order: oldest messages at the top, newest messages at the bottom, such that for any two visible messages A and B where A was sent before B, A appears at a higher vertical position than B.
2. WHEN `verticalLayoutDirection` is set to `ListView.BottomToTop`, THE AiChat_ListView SHALL reverse the Message_Model array (last element at index 0) so that the visual rendering preserves chronological top-to-bottom reading order despite Qt rendering index 0 at the visual bottom.
3. WHEN a new message is appended to the conversation and the viewport is already showing the latest message region, THE AiChat_ListView SHALL scroll to keep the newest message fully visible at the bottom of the viewport within 500 milliseconds without requiring manual user scrolling.
4. WHEN the user has scrolled up such that the bottom-most message is not visible in the viewport, THE AiChat_ListView SHALL NOT auto-scroll to the bottom upon receiving new messages, preserving the user's current scroll position until the user manually scrolls back to within one viewport height of the bottom.
5. WHEN the conversation contains zero messages, THE AiChat_ListView SHALL display the empty-state placeholder instead of a blank list area.

### Requirement 7: Voice Provider Panel Respects AI Policy

**User Story:** As a user with local-only AI policy, I want voice providers with remote endpoints to be hidden or flagged, so that the panel respects my privacy settings.

#### Acceptance Criteria

1. WHILE `Config.options.policies.ai` is set to 2 (local-only), THE ProviderPanel SHALL only display STT_Provider and TTS_Provider entries whose endpoint property begins with `http://localhost`, `http://127.0.0.1`, `ws://localhost`, `ws://127.0.0.1`, `tcp://localhost`, `tcp://127.0.0.1`, or an IP address in the 10.0.0.0/8 or 192.168.0.0/16 range.
2. WHILE `Config.options.policies.ai` is set to 0 (AI disabled), THE ProviderPanel SHALL hide the Voice_Provider_Section and not render any STT_Provider or TTS_Provider entries.
3. WHEN `Config.options.policies.ai` changes from 1 (allowed) to 2 (local-only), IF the currently selected `dictation.provider` or `dictation.ttsProvider` has an endpoint that does not resolve to a local address as defined in criterion 1, THEN THE ProviderPanel SHALL deselect that provider and set the value to the empty string.
4. WHILE `Config.options.policies.ai` is set to 1 (allowed), THE ProviderPanel SHALL display all configured STT_Provider and TTS_Provider entries regardless of endpoint address.
