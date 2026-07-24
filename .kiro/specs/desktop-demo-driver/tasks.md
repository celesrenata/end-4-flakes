# Implementation Plan: Desktop Demo Driver

## Overview

Implement a scene-based demo orchestration engine for the Hyprland/Quickshell desktop. The work extends the existing Ydotool singleton with mouse emulation, adds two new QML singletons (DemoDriverService, DemoScenes), a CLI shell script wrapper, keybind registration, and comprehensive property-based + unit tests in Python.

## Tasks

- [x] 1. Extend Ydotool service with mouse emulation
  - [x] 1.1 Add mouse emulation functions to Ydotool.qml
    - Add `available` and `lastError` properties with Process-based availability check
    - Add `moveMouse(x, y)` for absolute pointer positioning via `ydotool mousemove --absolute`
    - Add `moveMouseRelative(dx, dy)` for relative pointer movement
    - Add `click(button)` using ydotool button codes (0xC0=left, 0xC1=right, 0xC2=middle)
    - Add `doubleClick(button)` with `--repeat 2 --next-delay 50`
    - Add `scroll(direction, amount)` using `ydotool mousemove --wheel`
    - Add `drag(startX, startY, endX, endY, button)` with press-move-release sequence
    - Add `keyCombo(keycodes)` for multi-key press/release sequences
    - Add `_logUnavailable(fn)` guard that logs and early-returns when ydotool is down
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7_

  - [x] 1.2 Write property tests for Ydotool command construction
    - **Property 1: Mouse/Scroll Command Construction**
    - **Property 2: Drag Sequence Ordering**
    - **Validates: Requirements 1.1, 1.2, 1.5, 1.6**

- [x] 2. Implement DemoScenes registry singleton
  - [x] 2.1 Create DemoScenes.qml with scene registry and query functions
    - Create `configs/quickshell/ii/services/DemoScenes.qml` as a `pragma Singleton`
    - Define `categories` readonly property: ["shell", "workspace", "window", "utility", "app-launch", "mcp"]
    - Define `registry` readonly property containing all scene definition objects with name, description, category, duration, closesModule, guards, actions
    - Implement shell module scenes: sidebar-left, sidebar-right, overview, cheatsheet, media-controls, on-screen-keyboard, session-menu, clipboard-history, emoji-picker, bar-toggle, dock
    - Implement workspace scenes: workspace-switching, workspace-overview, window-move-workspace, workspace-scroll, special-workspace
    - Implement window management scenes: window-tile-float, window-fullscreen, window-focus, window-resize, window-close
    - Implement utility scenes: screenshot, color-picker, zoom, wallpaper, light-dark-toggle
    - Implement app-launch scenes: launch-terminal, launch-browser, launch-file-manager, launch-from-overview
    - Implement MCP scenes: mcp-system-info, mcp-audio-control, mcp-workspace-query, mcp-network-status, mcp-clipboard, mcp-diagnostics
    - Implement `getScenes(filter, filterType)` returning filtered subset or full registry
    - Implement `getCategories()`, `getSceneByName(name)`, `getTotalDuration(speedMultiplier)`
    - _Requirements: 2.1, 4.1–4.11, 5.1–5.5, 6.1–6.5, 7.1–7.5, 8.1–8.4, 9.1–9.6, 13.1, 13.2, 13.4_

  - [x] 2.2 Write property tests for scene registry invariants
    - **Property 3: Scene Registry Invariants**
    - **Validates: Requirements 2.1, 13.1**

  - [x] 2.3 Write property tests for execution filter correctness
    - **Property 4: Execution Filter Correctness**
    - **Validates: Requirements 2.2, 2.3, 2.4**

- [x] 3. Implement DemoDriverService orchestration engine
  - [x] 3.1 Create DemoDriverService.qml state machine and public API
    - Create `configs/quickshell/ii/services/DemoDriverService.qml` as a `pragma Singleton`
    - Define State enum: Idle, Running, Paused
    - Expose public properties: state, currentSceneName, currentSceneDescription, scenesCompleted, scenesTotal, speedMultiplier, actionDelay, sceneDelay
    - Implement `start(filter?, filterType?)` — captures state, builds queue, begins execution
    - Implement `stop()` — halts timers, restores state, emits tourCompleted
    - Implement `pause()` and `resume()` — halts/resumes action timer
    - Implement `toggle()` — start or stop based on current state
    - Implement `listScenes()` and `estimatedDuration()`
    - Define signals: sceneStarted, sceneCompleted, tourStarted, tourCompleted
    - _Requirements: 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.9, 3.5, 3.6, 10.4, 10.5_

  - [x] 3.2 Implement scene execution loop with pacing
    - Implement `_executeNextScene()` — dequeues next scene, checks guards, starts actions
    - Implement `_advanceAction()` — executes current action, schedules next via Timer
    - Implement `_executeAction(action)` — switch on action.type dispatching to Ydotool/IPC/exec/notify/MCP
    - Implement `_effectiveDelay(baseDelay)` — applies speed multiplier division
    - Add Timer components `_actionTimer` and `_sceneTimer` for pacing
    - Implement speed multiplier clamping in `start()` (range 0.5–3.0)
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [x] 3.3 Implement state guards and post-condition verification
    - Implement `_checkGuards(scene)` — validates ydotool availability, window existence, audio unmuted
    - Implement `_windowExists(windowClass)` using Hyprland.clients
    - Implement `_verifyPostConditions(scene)` — checks closesModule state and force-closes if needed
    - Implement `_getModuleState(moduleName)` — reads GlobalStates for sidebar/overview/session/osk/media
    - _Requirements: 11.1, 11.2, 11.3, 11.6_

  - [x] 3.4 Implement desktop state snapshot and restore
    - Implement `_captureDesktopState()` — records workspace, zoom, volume, muted, darkMode
    - Implement `_restoreDesktopState()` — restores all captured state via hyprctl/wpctl
    - Add Process component for gsettings dark-mode detection
    - _Requirements: 11.4, 11.7_

  - [x] 3.5 Implement trigger mechanisms (GlobalShortcut, IpcHandler)
    - Add `GlobalShortcut { name: "demoToggle" }` for Super+Alt+F10 toggle
    - Add `GlobalShortcut { name: "demoStart" }` and `GlobalShortcut { name: "demoStop" }`
    - Add `IpcHandler { target: "demo" }` with start/stop/pause/resume/list/speed functions
    - _Requirements: 10.1, 10.2, 10.4_

  - [x] 3.6 Write property tests for scene lifecycle signals
    - **Property 5: Scene Lifecycle Signals**
    - **Validates: Requirements 2.5, 2.6**

  - [x] 3.7 Write property tests for failure skip and continuation
    - **Property 6: Failure Skip and Continuation**
    - **Validates: Requirements 2.8**

  - [x] 3.8 Write property tests for pacing delay with speed scaling
    - **Property 7: Pacing Delay with Speed Scaling**
    - **Property 8: Speed Multiplier Clamping**
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4**

  - [x] 3.9 Write property tests for running tour replacement
    - **Property 10: Running Tour Replacement**
    - **Validates: Requirements 10.5**

  - [x] 3.10 Write property tests for guard skip and state restoration
    - **Property 11: Unresolvable Guard Skip**
    - **Property 12: Desktop State Restoration**
    - **Property 13: Post-Scene Module Cleanup**
    - **Validates: Requirements 11.3, 11.4, 11.6, 11.7**

- [x] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement CLI wrapper and Nix integration
  - [x] 5.1 Create demo-driver.sh CLI script
    - Create `configs/quickshell/ii/scripts/demo-driver.sh`
    - Implement subcommands: start [scene-or-category], stop, pause, resume, list, speed <N>
    - Use `quickshell -c ii ipc call demo <method> [args]` for all IPC dispatching
    - Add usage/help output for invalid arguments
    - _Requirements: 10.3_

  - [x] 5.2 Write property test for CLI argument parsing
    - **Property 9: CLI Argument Parsing**
    - **Validates: Requirements 10.3**

  - [x] 5.3 Add keybind to keybinds.conf.template
    - Add `bindd = Super+Alt, F10, Toggle desktop demo, global, quickshell:demoToggle # Toggle desktop demo` to the Shell section
    - _Requirements: 10.1, 12.3_

  - [x] 5.4 Register new singletons in services qmldir
    - Add `singleton DemoDriverService 1.0 DemoDriverService.qml` to `configs/quickshell/ii/services/qmldir`
    - Add `singleton DemoScenes 1.0 DemoScenes.qml` to `configs/quickshell/ii/services/qmldir`
    - _Requirements: 12.4_

- [x] 6. Property tests for metadata and duration
  - [x] 6.1 Write property test for scene metadata JSON round-trip
    - **Property 14: Scene Metadata JSON Round-Trip**
    - **Validates: Requirements 13.3**

  - [x] 6.2 Write property test for total tour duration computation
    - **Property 15: Total Tour Duration Computation**
    - **Validates: Requirements 13.4**

- [x] 7. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties (15 total from design)
- Unit tests validate specific examples and edge cases
- QML implementation follows existing singleton patterns (DictationService, VoiceAgentService)
- Tests use Python + Hypothesis, mirroring pure logic extracted from QML algorithms
- The Nix packaging (writeShellScriptBin in quickshell-service.nix) is handled during the full flake integration — the script source is created here
- After implementation, deploy with `rsync` + restart for testing, then commit/push/rebuild for permanence

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1"] },
    { "id": 1, "tasks": ["1.2", "2.2", "2.3", "3.1"] },
    { "id": 2, "tasks": ["3.2", "3.3", "3.4"] },
    { "id": 3, "tasks": ["3.5", "3.6", "3.7", "3.8"] },
    { "id": 4, "tasks": ["3.9", "3.10", "5.1"] },
    { "id": 5, "tasks": ["5.2", "5.3", "5.4", "6.1", "6.2"] }
  ]
}
```
