# Implementation Plan: Dictation Debounce & Indicator Enhancement

## Overview

This plan adds a debounce guard to DictationService to suppress rapid-fire Logitech button signals, exposes an `audioDetected` property driven by the silence monitor, and enhances the DictationIndicator with three color-coded visual states (amber/green/blue) plus a fade-out dismissal animation.

## Tasks

- [ ] 1. Add debounce guard to DictationService
  - [ ] 1.1 Add debounce properties and Timer to DictationService.qml
    - Add `property int debounceMs: 500` public property
    - Add `property bool _debounceActive: false` internal flag
    - Add a `Timer { id: debounceTimer }` with `interval: root.debounceMs`, `repeat: false`, that sets `_debounceActive = false` on triggered
    - _Requirements: 1.1, 2.1_

  - [ ] 1.2 Modify `onKeyTap()` to enforce debounce logic
    - At the top of `onKeyTap()`, check `if (root._debounceActive) { console.log(...); return }` to discard taps during the window
    - Move the existing "already recording → stop" check after the debounce guard
    - Before calling `activate()`, start the debounce: `if (root.debounceMs > 0) { root._debounceActive = true; debounceTimer.restart() }`
    - When `debounceMs === 0`, skip debounce activation (all taps pass through)
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.2_

- [ ] 2. Add audioDetected property to DictationService
  - [ ] 2.1 Add `audioDetected` property and wire silence monitor
    - Add `property bool audioDetected: false` to DictationService
    - Modify the `silenceMonitor` stdout `SplitParser.onRead` handler: when `data.trim() === "AUDIO"` and `!root.audioDetected`, set `root.audioDetected = true`
    - Ensure `silenceMonitor` also runs when `state === DictationService.State.StreamingActive` (update `running` binding)
    - _Requirements: 8.1_

  - [ ] 2.2 Reset `audioDetected` on transition to Idle
    - In `_setState()`, add: `if (newState === DictationService.State.Idle) { root.audioDetected = false }`
    - _Requirements: 8.2_

- [ ] 3. Checkpoint - Verify debounce and audioDetected logic
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 4. Enhance DictationIndicator with color-coded visual states
  - [ ] 4.1 Change mic icon color based on audioDetected
    - Replace the static `color: Appearance.m3colors.m3error` on the mic `MaterialSymbol` with a ternary: `DictationService.audioDetected ? "#4CAF50" : "#FFA000"`
    - This gives amber when initializing (no audio yet) and green when recording (audio detected)
    - _Requirements: 3.1, 3.2, 4.1, 4.2_

  - [ ] 4.2 Change border color to reflect current visual state
    - Update `indicatorContent.border.color` to use state-aware logic:
      - Processing → `"#2196F3"` (blue)
      - Listening/StreamingActive with audioDetected → `"#4CAF50"` (green)
      - Listening/StreamingActive without audioDetected → `"#FFA000"` (amber)
      - Error → `Appearance.m3colors.m3error`
    - _Requirements: 3.1, 4.1, 5.1_

  - [ ] 4.3 Update processing spinner to blue color
    - Change `spinnerIcon.color` from `Appearance.m3colors.m3primary` to `"#2196F3"`
    - Add "Transcribing..." label alongside the spinner (already present in status text logic — verify it's correct)
    - _Requirements: 5.1, 5.2_

  - [ ] 4.4 Adjust pulse animation for initializing vs recording
    - Initializing (amber): keep the existing opacity pulse (0.4→1.0 at 600ms)
    - Recording (green): use a subtler steady pulse (0.7→1.0 at 800ms) — change animation parameters based on `DictationService.audioDetected`
    - _Requirements: 3.1, 4.2_

- [ ] 5. Add fade-out dismissal animation
  - [ ] 5.1 Implement opacity fade-out on indicatorWindow
    - Add `opacity` property binding: `(root.isActive || root.hasResponseText || root.isAwaitingApproval) ? 1.0 : 0.0`
    - Add `Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }`
    - Change `visible` binding to: `opacity > 0 && !GlobalStates.screenLocked` so the window stays alive during fade
    - _Requirements: 6.1_

  - [ ] 5.2 Add error display delay before fade-out
    - Modify the existing 2-second error dismiss Timer: instead of immediately setting state to Idle, set it so the 2s timer fires first (showing the error), then transition to Idle triggers the fade-out
    - Ensure error shows for 2 seconds before fade begins (existing timer already handles this — verify behavior with new opacity animation)
    - _Requirements: 6.2_

- [ ] 6. Checkpoint - Verify visual states and animations
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. Property-based tests for debounce and audioDetected
  - [ ]* 7.1 Write property test for debounce filtering
    - **Property 1: Debounce Filtering**
    - Generate random tap sequences with timestamps within [0, debounceMs]. Simulate state machine. Assert only the first tap from Idle causes a state transition; all subsequent taps within the window are discarded.
    - **Validates: Requirements 1.1, 1.2, 1.3**

  - [ ]* 7.2 Write property test for debounce bypass when disabled
    - **Property 2: Debounce Bypass When Disabled**
    - Generate tap sequences with debounceMs=0. Assert every tap is processed immediately — no suppression regardless of timing.
    - **Validates: Requirements 2.2**

  - [ ]* 7.3 Write property test for stop after debounce expiry
    - **Property 3: Stop Preserves After Debounce Expiry**
    - Generate debounce durations and a tap arriving after expiry while in recording state. Assert the tap transitions state to Processing.
    - **Validates: Requirements 1.4**

  - [ ]* 7.4 Write property test for audioDetected lifecycle
    - **Property 4: audioDetected Lifecycle**
    - Generate sequences of "AUDIO"/"SILENCE" reports and state transitions. Assert audioDetected is false at activation start, true after first "AUDIO", and false after any transition to Idle.
    - **Validates: Requirements 8.1, 8.2**

- [ ] 8. Deploy, sync, and commit
  - [ ] 8.1 Sync repo to deployed config and restart quickshell
    - Run `rsync -av --delete configs/quickshell/ii/ ~/.config/quickshell/ii/`
    - Run `systemctl --user restart quickshell`
    - Check logs: `journalctl --user -u quickshell --since "10 sec ago" --no-pager`
    - _Requirements: All (deployment verification)_

  - [ ] 8.2 Commit changes to git
    - Stage modified files: `DictationService.qml`, `DictationIndicator.qml`, and the new test file
    - Commit with message: `feat(dictation): add debounce guard and color-coded indicator states`
    - _Requirements: All (deployment via flake)_

- [ ] 9. Final checkpoint - Full verification
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- The deploy step (8.1) syncs repo → `~/.config/quickshell/ii/` and restarts quickshell
- The git commit (8.2) ensures nixos-rebuild picks up changes via the flake

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1"] },
    { "id": 1, "tasks": ["1.2", "2.2"] },
    { "id": 2, "tasks": ["4.1", "4.2", "4.3", "4.4"] },
    { "id": 3, "tasks": ["5.1", "5.2"] },
    { "id": 4, "tasks": ["7.1", "7.2", "7.3", "7.4"] },
    { "id": 5, "tasks": ["8.1"] },
    { "id": 6, "tasks": ["8.2"] }
  ]
}
```
