# Implementation Plan: Voice Dictation + Sidebar Popout

## Overview

Two features: (1) voice dictation activated by double-tap Control_R, recording from PipeWire default input, transcribing via configurable provider, routing to action palette or sidebar chat. (2) Sidebar popout mode that claims exclusive zone on the left edge, compressing tiled windows right, while remaining resizable. Implementation: sidebar popout first (simpler), then dictation service.

## Tasks

- [x] 1. Sidebar Popout Mode
  - [x] 1.1 Add poppedOut state to Persistent.qml
    - Add `property bool poppedOut: false` to `JsonObject sidebar` in Persistent.qml
    - File: `ii/modules/common/Persistent.qml`
    - _Requirements: 7.9_

  - [x] 1.2 Implement popout toggle in SidebarLeft.qml
    - Add `property bool poppedOut: Persistent.states.sidebar.poppedOut` to sidebarRoot
    - When poppedOut is true: set `exclusionMode: ExclusionMode.Normal` and `exclusiveZone: sidebarWidth`
    - When poppedOut is false: set `exclusionMode: ExclusionMode.Ignore` and `exclusiveZone: 0`
    - When poppedOut is true: set `visible: true` always (override GlobalStates.sidebarLeftOpen)
    - On resize (userWidth changes while popped out): update exclusiveZone to match
    - File: `ii/modules/sidebarLeft/SidebarLeft.qml`
    - _Requirements: 7.2, 7.3, 7.4, 7.5_

  - [x] 1.3 Disable HyprlandFocusGrab in popout mode
    - Set `grab.active: sidebarRoot.visible && !poppedOut`
    - When popped out, clicking outside does nothing (sidebar stays)
    - File: `ii/modules/sidebarLeft/SidebarLeft.qml`
    - _Requirements: 7.6, 7.10_

  - [x] 1.4 Add Ctrl+P keybind and popout button
    - In the existing `Keys.onPressed` handler, add Ctrl+P to toggle `poppedOut`
    - Persist the state: `Persistent.states.sidebar.poppedOut = poppedOut`
    - Add a small icon button in the sidebar header (pin/unpin icon) for mouse users
    - File: `ii/modules/sidebarLeft/SidebarLeft.qml`
    - _Requirements: 7.1, 7.8_

  - [x] 1.5 Add IPC handler for popout toggle
    - Add `function togglePopout()` to the existing sidebarLeft IpcHandler
    - Also add a GlobalShortcut `sidebarLeftTogglePopout`
    - File: `ii/modules/sidebarLeft/SidebarLeft.qml`
    - _Requirements: 7.1_

- [x] 2. Checkpoint — Sidebar popout verified
  - Verify Ctrl+P toggles popout, exclusive zone claims space, windows shunt right, resize updates zone, state persists across restart. Ask the user if questions arise.

- [x] 3. Dictation Configuration
  - [x] 3.1 Add dictation config section to Config.qml
    - Add to `modules/common/Config.qml`:
      ```
      property JsonObject dictation: JsonObject {
          property bool enabled: true
          property string activationKey: "Control_R"
          property int doubleTapMs: 400
          property int silenceTimeoutMs: 3000
          property int maxDurationMs: 60000
          property string provider: ""
          property string model: ""
      }
      ```
    - File: `modules/common/Config.qml`
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7_

- [x] 4. Double-Tap Detection
  - [x] 4.1 Create DictationService.qml singleton
    - Create `services/DictationService.qml` as a singleton
    - State enum: Idle, Listening, Processing, Error
    - Properties: `state`, `recordingDuration`, `errorMessage`
    - Register in `services/qmldir`
    - File: `services/DictationService.qml`
    - _Requirements: 1.1, 1.4_

  - [x] 4.2 Implement double-tap detection via Hyprland keybind
    - Use `bindrit` (release, input-transparent) for `Control_R` in keybinds.conf.template to emit a global signal
    - In DictationService: track release events with a Timer
    - First release: start doubleTapTimer (400ms)
    - Second release within timer: activate dictation
    - Timer expires without second release: reset (normal behavior)
    - Ensure single taps pass through without side effects
    - _Requirements: 1.1, 1.2, 1.3, 9.1_

  - [x] 4.3 Add policy gate check on activation
    - Before activating: check `policies.ai !== 0`
    - Check `dictation.enabled` config
    - If dictation.provider is empty and no default transcription model configured, show error
    - _Requirements: 8.1, 8.2, 2.5_

- [x] 5. Audio Recording
  - [x] 5.1 Implement audio recording via pw-record
    - On activation: create Process running `pw-record --target=@DEFAULT_SOURCE@ /tmp/quickshell-dictation/<timestamp>.wav`
    - Store the process reference for later termination
    - Start a duration counter (Timer updating every 100ms)
    - Start silenceTimer (3000ms) and maxTimer (60000ms)
    - File: `services/DictationService.qml`
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [x] 5.2 Implement stop triggers
    - On `Control_R` tap while recording: kill pw-record, transition to Processing
    - On silenceTimer fire: kill pw-record, transition to Processing
    - On maxTimer fire: kill pw-record, transition to Processing
    - Clean up: reset timers
    - _Requirements: 1.5, 1.6, 4.4_

  - [x] 5.3 Implement silence detection
    - Run a parallel `pw-cat --playback --target=@DEFAULT_SOURCE@ --format=f32 -` monitor
    - Read audio levels from its output, reset silenceTimer when level exceeds threshold
    - Alternative: use a simple script that monitors dBFS from pw-record's output
    - Kill the monitor process when recording stops
    - _Requirements: 1.6, 6.4_

- [x] 6. Checkpoint — Recording works
  - Verify double-tap activates, pw-record captures audio, stop triggers work (tap, silence, timeout). Ask the user if questions arise.

- [x] 7. Transcription
  - [x] 7.1 Implement transcription request
    - Read `Config.options.dictation.provider` and `Config.options.dictation.model`
    - For OpenAI-compatible: `curl -F file=@<path>.wav -F model=<model> -H "Authorization: Bearer <key>" <endpoint>/v1/audio/transcriptions`
    - For local whisper-cpp: `whisper-cpp -f <path>.wav --output-txt --model <model>`
    - Parse response (JSON for API, stdout for local)
    - On success: extract text, transition to routing
    - On failure: set error state
    - File: `services/DictationService.qml`
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [x] 7.2 Integrate with Providers/KeyringStorage for API keys
    - Look up the transcription provider's API key from `KeyringStorage.keyringData.apiKeys`
    - Use the same key_id pattern as other providers
    - _Requirements: 2.4_

- [x] 8. Text Routing
  - [x] 8.1 Implement routing logic
    - After successful transcription:
    - If `GlobalStates.sidebarLeftOpen`: call `Ai.sendUserMessage(text)` (routes to sidebar chat)
    - If sidebar closed: set `GlobalStates.overviewOpen = true`, then `SearchWidget.setSearchingText("? " + text)` via IPC
    - Clean up temp audio file after routing
    - File: `services/DictationService.qml`
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [x] 8.2 Add IPC handler for routing to overview search
    - Add IPC handler in overview or GlobalStates to accept `setSearchText(text)` from the dictation service
    - Needed because overview search is in a different scope than the singleton service
    - _Requirements: 3.3_

- [x] 9. Visual Indicator
  - [x] 9.1 Create DictationIndicator.qml floating overlay
    - PanelWindow with WlrLayer.Overlay, no keyboard focus
    - Anchored to top-right corner (below bar)
    - While Listening: show pulsing mic icon + duration in seconds
    - While Processing: show "Transcribing..." + spinner
    - On Error: show error briefly (2s), auto-dismiss
    - On Success: dismiss immediately
    - File: `modules/dictation/DictationIndicator.qml`
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [x] 9.2 Register indicator in shell.qml
    - Add LazyLoader for DictationIndicator (active when dictation.enabled)
    - File: `ii/shell.qml`
    - _Requirements: 5.1_

- [x] 10. Checkpoint — Full dictation flow verified
  - End-to-end: double-tap → record → stop → transcribe → route → indicator dismisses. Ask the user if questions arise.

- [x] 11. Keybind Integration
  - [x] 11.1 Add Control_R release detection to keybinds.conf.template
    - Add `bindrit = ,Control_R, global, quickshell:dictationTap` (release, input-transparent)
    - This emits a global shortcut signal without consuming the key
    - File: `configs/hypr/keybinds.conf.template`
    - _Requirements: 1.1, 9.1_

  - [x] 11.2 Wire GlobalShortcut in DictationService
    - Listen for `dictationTap` global shortcut
    - Feed tap events into the double-tap state machine
    - _Requirements: 1.1, 1.2_

- [x] 12. Property-based tests
  - [x] 12.1 Write property test: double-tap timing detection
    - Two taps within threshold → activates
    - Two taps outside threshold → no activation
    - Three rapid taps → only one activation
    - File: `tests/js/src/dictation-logic.test.js`
    - _Validates: Requirements 1.1, 1.2, 1.3_

  - [x] 12.2 Write property test: routing logic
    - Sidebar open → text goes to chat
    - Sidebar closed → text goes to action palette with `?` prefix
    - File: `tests/js/src/dictation-logic.test.js`
    - _Validates: Requirements 3.1, 3.2_

  - [x] 12.3 Write property test: exclusive zone matches sidebar width
    - For any width in [minWidth, maxWidth]: popout mode sets exclusiveZone = width
    - File: `tests/js/src/dictation-logic.test.js`
    - _Validates: Requirements 7.2, 7.5_

  - [x] 12.4 Write property test: silence timeout fires after configured duration
    - For any silenceTimeoutMs in [1000, 10000]: timer fires at that interval when no audio
    - File: `tests/js/src/dictation-logic.test.js`
    - _Validates: Requirements 1.6, 6.4_

- [x] 13. Integration tests
  - [x] 13.1 Write integration test: full dictation with mocked audio and transcription
    - Mock pw-record process (simulates recording)
    - Mock transcription API response
    - Verify text routing based on sidebar state
    - File: `tests/js/src/dictation-integration.test.js`
    - _Requirements: 3.1, 3.2, 4.1_

  - [x] 13.2 Write integration test: sidebar popout exclusive zone
    - Verify exclusiveZone changes between 0 and sidebarWidth on toggle
    - Verify focusGrab active state matches popout state
    - File: `tests/js/src/dictation-integration.test.js`
    - _Requirements: 7.2, 7.6, 7.10_

  - [x] 13.3 Write integration test: policy enforcement
    - policies.ai=0 blocks dictation activation
    - policies.ai=2 with remote provider shows error
    - File: `tests/js/src/dictation-integration.test.js`
    - _Requirements: 8.1, 8.2_

- [x] 14. Final checkpoint
  - All tests pass, dictation and popout work end-to-end. Ask the user if questions arise.

## Notes

- Sidebar popout is implemented first since it's simpler and independent of dictation
- The double-tap detection uses `bindrit` (release-only, input-transparent) to avoid consuming the Control_R key for normal shortcuts
- pw-record is the PipeWire-native recording tool — lightweight, no additional dependencies
- Silence detection is the trickiest part — may need iteration to find the right approach
- The transcription endpoint format follows OpenAI's `/v1/audio/transcriptions` API for maximum compatibility
- For local whisper, the user would configure a local endpoint running whisper.cpp's server mode, or use the CLI directly
- The sidebar popout uses Hyprland's native exclusive zone handling — no manual window management needed
- Ctrl+P is already partially wired in the existing SidebarLeft.qml (for the detach feature) — we're replacing/extending that

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "3.1"] },
    { "id": 1, "tasks": ["1.2", "1.3", "1.4", "1.5"] },
    { "id": 2, "tasks": ["4.1", "4.2", "4.3"] },
    { "id": 3, "tasks": ["5.1", "5.2", "5.3"] },
    { "id": 4, "tasks": ["7.1", "7.2"] },
    { "id": 5, "tasks": ["8.1", "8.2"] },
    { "id": 6, "tasks": ["9.1", "9.2", "11.1", "11.2"] },
    { "id": 7, "tasks": ["12.1", "12.2", "12.3", "12.4"] },
    { "id": 8, "tasks": ["13.1", "13.2", "13.3"] }
  ]
}
```
