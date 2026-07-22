# Implementation Plan: Voice Sidebar Fixes

## Overview

This plan implements three related UX fixes for the Quickshell sidebar: a Voice Provider Panel in ProviderPanel.qml, a debounce guard for DictationService.onKeyTap(), and a message ordering fix for AiChat.qml's BottomToTop ListView. Property tests use the existing fast-check + vitest infrastructure at `tests/js/`.

## Tasks

- [x] 1. Extract pure logic functions for property testing
  - [x] 1.1 Create `tests/js/src/voice-sidebar-logic.js` with extracted pure functions
    - Implement `validateEndpointUrl(url)` — returns true iff url starts with http://, https://, tcp://, or ws://
    - Implement `mapConnectivityResult(httpStatus, timedOut)` — maps status codes to CheckState objects
    - Implement `debounceStateMachine(taps, debounceMs, initialState)` — simulates state transitions for tap sequences
    - Implement `clampDebounceMs(value)` — clamps integer to 0–2000 range
    - Implement `prepareMessageModel(ids, layoutDirection)` — reverses array when BottomToTop
    - Implement `filterProvidersByPolicy(providers, policy)` — filters based on isLocal() and policy value
    - Implement `isLocal(endpoint)` — returns true for localhost/127.0.0.1/10.x/192.168.x endpoints
    - Implement `deriveDetailFields(providerConfig)` — returns array of editable field keys from a provider config object
    - _Requirements: Design Testing Strategy, all correctness properties_

  - [x] 1.2 Create `tests/js/src/voice-sidebar-logic.test.js` test file scaffold
    - Import all functions from voice-sidebar-logic.js
    - Import fc from fast-check and describe/it/expect from vitest
    - Add empty describe blocks for each of the 9 properties
    - _Requirements: Design Testing Strategy_

- [x] 2. Implement Chat ListView ordering fix
  - [x] 2.1 Apply `.slice().reverse()` to ScriptModel values in AiChat.qml
    - Modify the `model: ScriptModel { values: ... }` in `messageListView` to append `.slice().reverse()` after the `.filter()` call
    - File: `configs/quickshell/ii/modules/sidebarLeft/AiChat.qml`
    - _Requirements: 6.1, 6.2_

  - [x] 2.2 Write property test for message chronological ordering (Property 7)
    - **Property 7: Message Chronological Ordering**
    - For any array of message IDs, `prepareMessageModel(ids, "BottomToTop")` returns the reversed array, preserving chronological reading order
    - **Validates: Requirements 6.1, 6.2**

- [x] 3. Implement dictation debounce guard
  - [x] 3.1 Add `debounceMs` property to Config.qml dictation JsonObject
    - Add `property int debounceMs: 500` to `dictation` JsonObject in `configs/quickshell/ii/modules/common/Config.qml`
    - _Requirements: 5.1_

  - [x] 3.2 Add debounce state and timer to DictationService.qml
    - Add `property int debounceMs: Config.options.dictation.debounceMs` binding
    - Add `property bool _debounceActive: false` state flag
    - Add `Timer { id: debounceTimer; interval: root.debounceMs; repeat: false; onTriggered: root._debounceActive = false }`
    - Ensure debounceTimer stops on transition to Idle (in existing state transitions)
    - File: `configs/quickshell/ii/services/DictationService.qml`
    - _Requirements: 4.1, 4.2, 4.3, 4.5, 5.2_

  - [x] 3.3 Modify `onKeyTap()` to apply debounce guard
    - At the top of `onKeyTap()`, if `_debounceActive` is true, log `GATE_REJECT | reason=debounce` and return
    - After the existing idle-state activation logic, set `_debounceActive = true` and call `debounceTimer.restart()` when `debounceMs > 0`
    - Ensure stop-recording path (Listening/StreamingActive) is NOT gated by debounce (only reject spurious re-activations)
    - File: `configs/quickshell/ii/services/DictationService.qml`
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 5.3_

  - [x] 3.4 Write property tests for debounce (Properties 3, 4, 5, 6)
    - **Property 3: Debounce State Machine** — For any tap sequence with timestamps, first tap activates, taps within debounceMs are discarded, taps after debounceMs stop recording
    - **Property 4: Debounce Idle Invariant** — When state is Idle, _debounceActive is false
    - **Property 5: Debounce Disabled at Zero** — With debounceMs=0, no taps are ever discarded
    - **Property 6: Debounce Value Clamping** — clampDebounceMs(x) === Math.max(0, Math.min(2000, x))
    - **Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5, 5.3, 5.4**

- [x] 4. Checkpoint — Ensure debounce and chat ordering tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement VoiceProviderCheckService singleton
  - [x] 5.1 Create `configs/quickshell/ii/services/VoiceProviderCheckService.qml`
    - Implement as a `Singleton` with `property var checkStates: ({})`
    - Implement `function checkEndpoint(providerKey, endpoint, protocol)` using curl HEAD for HTTP or timeout-wrapped connect for WebSocket/TCP
    - Implement `function isLocal(endpoint)` returning true for localhost/127.0.0.1/10.x/192.168.x patterns
    - Use a 3-second timeout for all connectivity checks
    - Update `checkStates[providerKey]` with status and message on completion
    - File: `configs/quickshell/ii/services/VoiceProviderCheckService.qml`
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [x] 5.2 Register VoiceProviderCheckService in services/qmldir
    - Add `singleton VoiceProviderCheckService 1.0 VoiceProviderCheckService.qml` to `configs/quickshell/ii/services/qmldir`
    - _Requirements: 3.1_

- [x] 6. Implement Voice Provider Panel UI components
  - [x] 6.1 Create `configs/quickshell/ii/modules/sidebarLeft/VoiceProviderListItem.qml`
    - RippleButton delegate displaying provider key name, endpoint URL, and status indicator
    - Accept `providerKey`, `providerConfig`, `statusState` properties
    - Status indicator shows colored dot: grey=idle, spinning=checking, green=reachable, red=unreachable, blue=local
    - Emit `clicked()` signal
    - _Requirements: 1.1, 2.1, 3.1_

  - [x] 6.2 Create `configs/quickshell/ii/modules/sidebarLeft/VoiceProviderDetailView.qml`
    - Detail view with editable fields dynamically derived from provider config object keys
    - For STT providers: endpoint (text input with URL validation), protocol (rest/websocket selector), model, language fields
    - For TTS providers: endpoint, protocol, voice fields OR voice/speed/pitch fields (when no endpoint)
    - Provider name displayed as read-only label at top
    - Persist changes via `Config.setNestedValue("dictation.<type>Providers.<key>.<field>", value)`
    - Inline validation error for invalid endpoint URLs (must start with http://, https://, tcp://, ws://)
    - Trigger connectivity check via VoiceProviderCheckService.checkEndpoint() on view load
    - Emit `back()` signal
    - _Requirements: 1.2, 1.4, 1.5, 2.2, 2.4, 2.5, 3.2_

  - [x] 6.3 Create `configs/quickshell/ii/modules/sidebarLeft/VoiceProviderSection.qml`
    - Section component with `sectionTitle`, `providerType` (stt/tts), `providerData`, `aiPolicy` properties
    - Compute `filteredProviders` based on policy: policy=0 → empty, policy=1 → all, policy=2 → local-only + no-endpoint
    - ListView with VoiceProviderListItem delegates for each filtered provider
    - On item click, load VoiceProviderDetailView for selected provider
    - Back navigation returns to list view
    - Emit `providerSelected(providerKey)` signal
    - _Requirements: 1.1, 1.3, 2.1, 2.3, 7.1, 7.2, 7.4_

  - [x] 6.4 Integrate VoiceProviderSection into ProviderPanel.qml
    - Add two VoiceProviderSection instances after the AI provider ListView
    - First section: title="Voice: Speech-to-Text", providerType="stt", providerData=Config.options.dictation.sttProviders
    - Second section: title="Voice: Text-to-Speech", providerType="tts", providerData=Config.options.dictation.ttsProviders
    - Both sections bind aiPolicy to Config.options.policies.ai
    - Hide both sections entirely when policy=0
    - On policy change 1→2, deselect any non-local provider
    - _Requirements: 1.3, 2.3, 7.1, 7.2, 7.3, 7.4_

- [x] 7. Checkpoint — Ensure voice provider panel renders and connectivity checks work
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Property tests for voice provider logic
  - [x] 8.1 Write property test for endpoint URL validation (Property 1)
    - **Property 1: Endpoint URL Validation**
    - For any string, validateEndpointUrl returns true iff it starts with http://, https://, tcp://, or ws://
    - **Validates: Requirements 2.5**

  - [x] 8.2 Write property test for connectivity status mapping (Property 2)
    - **Property 2: Connectivity Status Mapping**
    - For HTTP status in [200, 499]: result is "reachable". For status 0/>=500/timeout: result is "unreachable"
    - **Validates: Requirements 3.3, 3.4**

  - [x] 8.3 Write property test for voice provider policy filtering (Property 8)
    - **Property 8: Voice Provider Policy Filtering**
    - policy=1 → full list, policy=2 → only local/no-endpoint, policy=0 → empty
    - **Validates: Requirements 7.1, 7.4, 7.2**

  - [x] 8.4 Write property test for TTS detail view field derivation (Property 9)
    - **Property 9: TTS Detail View Field Derivation**
    - For any provider config object, deriveDetailFields returns exactly the set of keys in the config
    - **Validates: Requirements 2.2**

- [x] 9. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests use fast-check + vitest (existing infrastructure at `tests/js/`)
- Pure logic functions are extracted from QML into `tests/js/src/voice-sidebar-logic.js` for testability
- QML constraints: no spread operator (use Object.assign), no replaceAll (use split/join), indexed for loops, Process + SplitParser for subprocess stdout, pragma Singleton + ComponentBehavior: Bound
- The `qmldir` file MUST be updated when adding VoiceProviderCheckService singleton
- Deploy workflow: after editing repo files, rsync to `~/.config/quickshell/ii/` and restart quickshell

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "3.1"] },
    { "id": 1, "tasks": ["1.2", "2.1", "3.2"] },
    { "id": 2, "tasks": ["2.2", "3.3", "5.1"] },
    { "id": 3, "tasks": ["3.4", "5.2"] },
    { "id": 4, "tasks": ["6.1", "6.2"] },
    { "id": 5, "tasks": ["6.3"] },
    { "id": 6, "tasks": ["6.4"] },
    { "id": 7, "tasks": ["8.1", "8.2", "8.3", "8.4"] }
  ]
}
```
