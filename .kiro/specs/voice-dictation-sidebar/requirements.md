# Requirements: Voice Dictation + Sidebar Popout

## Overview

Two related features: (1) a voice dictation system activated by double-tapping Right Control that transcribes speech and routes it to either the AI action palette or the sidebar AI chat, and (2) a sidebar "popout" mode that claims exclusive zone on the left, compressing tiled windows to the right while remaining resizable.

## Functional Requirements

### 1. Dictation Activation

1.1. Double-tap `Control_R` (within 400ms, configurable as "double-click speed") activates dictation mode.
1.2. A single tap of `Control_R` does nothing special (passes through normally).
1.3. Triple-tap or faster should not trigger multiple activations — debounce after activation.
1.4. When dictation is active, a visual indicator appears (floating mic icon or bar notification).
1.5. Tapping `Control_R` once while dictation is active immediately stops recording and processes the audio.
1.6. If no speech is detected for 3 seconds (silence timeout), dictation automatically stops and processes.
1.7. The activation keybind is configurable via config.

### 2. Speech-to-Text Backend

2.1. Transcription uses a configurable model from the Providers panel (local or remote).
2.2. Local backends: whisper.cpp, faster-whisper, or any Whisper-compatible local endpoint.
2.3. Remote backends: OpenAI Whisper API, or any OpenAI-compatible transcription endpoint.
2.4. The provider/model for transcription is configured via `Config.options.dictation.provider` and `Config.options.dictation.model`.
2.5. If no transcription provider is configured, show an error directing the user to set one up.
2.6. Audio is recorded from the PipeWire default input device (as configured in system audio settings).
2.7. Audio format: WAV or OGG (whatever the transcription backend prefers), recorded to a temp file.

### 3. Dictation Routing

3.1. If the left sidebar is CLOSED when dictation activates: transcribed text is sent to the AI Action Palette (same as typing `? <text>` in the overview search).
3.2. If the left sidebar is OPEN when dictation activates: transcribed text is sent as a message to the sidebar AI chat.
3.3. When routing to the Action Palette: open the overview, set the search text to `? <transcribed text>`, trigger the AI request.
3.4. When routing to the sidebar chat: insert the text into the chat input field and auto-send.

### 4. Audio Recording

4.1. Record from the PipeWire default source (same device shown in the audio mixer panel).
4.2. Use `pw-record` or equivalent PipeWire-native tool for capture.
4.3. Recording starts immediately on activation (no additional user action needed).
4.4. Recording stops on: (a) user taps `Control_R`, (b) 3-second silence detected, or (c) 60-second max duration (safety limit).
4.5. Temp audio files are stored in `/tmp/quickshell-dictation/` and cleaned up after processing.

### 5. Visual Feedback

5.1. While recording: show a floating indicator (pulsing mic icon) in a corner of the screen.
5.2. The indicator shows recording duration in seconds.
5.3. While transcribing (after recording stops): show a "Transcribing..." state on the indicator.
5.4. On success: indicator dismisses and the text is routed.
5.5. On error: indicator shows error briefly (2 seconds), then dismisses.

### 6. Configuration

6.1. Config key `dictation.enabled` — master toggle (default: true).
6.2. Config key `dictation.activationKey` — keybind for activation (default: "Control_R").
6.3. Config key `dictation.doubleTapMs` — max interval for double-tap detection (default: 400).
6.4. Config key `dictation.silenceTimeoutMs` — silence duration before auto-stop (default: 3000).
6.5. Config key `dictation.maxDurationMs` — maximum recording duration (default: 60000).
6.6. Config key `dictation.provider` — transcription provider ID (e.g., "openai", "local-whisper").
6.7. Config key `dictation.model` — transcription model ID (e.g., "whisper-1", "base.en").

### 7. Sidebar Popout Mode

7.1. The left sidebar has a "popout" toggle (keybind: `Ctrl+P` when sidebar is focused, or a button in the sidebar header).
7.2. When popped out: the sidebar PanelWindow sets `exclusiveZone` to its current width, claiming space on the left.
7.3. Hyprland automatically compresses/shunts tiled windows to the right when exclusive zone is claimed.
7.4. The sidebar remains anchored to the left edge of the screen in popout mode.
7.5. The sidebar is still resizable in popout mode (drag the right edge) — exclusive zone updates as width changes.
7.6. Clicking outside the sidebar does NOT close it in popout mode (unlike normal overlay mode).
7.7. The sidebar content, tabs, and functionality remain identical in popout mode.
7.8. Toggling popout off restores the sidebar to normal overlay behavior (exclusiveZone: 0, click-outside-to-close).
7.9. The popout state is persisted via `Persistent.states.sidebar.poppedOut` (survives Quickshell restart).
7.10. When in popout mode, the HyprlandFocusGrab is disabled (no click-outside-to-close).

### 8. Policy Enforcement

8.1. If `policies.ai === 0`, dictation is disabled (no activation).
8.2. If `policies.ai === 2` and transcription provider is remote, show error directing user to configure a local provider.
8.3. Audio data is never persisted beyond the temp file during processing.

## Non-Functional Requirements

9.1. Double-tap detection must not interfere with normal `Control_R` usage (modifiers, keyboard shortcuts).
9.2. Audio recording latency from activation to actual recording start: < 200ms.
9.3. The floating dictation indicator must not steal keyboard focus.
9.4. All QML follows existing project patterns.
9.5. Sidebar popout width change should smoothly animate tiled window repositioning (Hyprland handles this natively via exclusive zone transitions).
