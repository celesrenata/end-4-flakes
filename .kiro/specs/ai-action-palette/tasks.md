# Implementation Plan: AI Action Palette

## Overview

Implements an AI-powered action palette integrated into the overview/launcher search. The implementation proceeds in layers: config foundation → service skeleton → prefix detection → LLM request pipeline → response parsing → UI components → execution engine → preview mode → debounce/cancellation → property-based tests → integration tests. Each layer builds on the previous, ensuring the code is always wirable and testable incrementally.

## Tasks

- [x] 1. Configuration foundation and service registration
  - [x] 1.1 Add AI prefix and debounce config keys to Config.qml
    - Add `property string ai: "?"` to `JsonObject prefix` inside `JsonObject search`
    - Add `property int aiDebounceMs: 600` to `JsonObject search`
    - File: `modules/common/Config.qml`
    - _Requirements: 1.2, 7.4_

  - [x] 1.2 Register ActionPalette singleton in services/qmldir
    - Add `singleton ActionPalette 1.0 ActionPalette.qml` to `services/qmldir`
    - File: `services/qmldir`
    - _Requirements: 1.1_

  - [x] 1.3 Create ActionPalette.qml service skeleton with state enum and properties
    - Create `services/ActionPalette.qml` as a Singleton with state enum (Idle, Debouncing, Loading, Ready, Executing, Previewing, Error)
    - Declare all public properties: `state`, `actionPlan`, `errorMessage`, `canRetry`, `lastQuery`, `configSnapshot`, `previewActive`, `currentResults`
    - Declare all signals: `actionPlanReady`, `executionComplete`, `executionFailed`, `previewStarted`, `previewEnded`, `approvalRequired`
    - Stub all public functions: `submitQuery`, `cancelRequest`, `retry`, `applyPlan`, `previewPlan`, `commitPreview`, `revertPreview`, `approveCommand`, `rejectCommand`
    - File: `services/ActionPalette.qml`
    - _Requirements: 1.1, 2.1_

- [x] 2. Checkpoint — Foundation verified
  - Ensure services/qmldir is syntactically correct, Config.qml loads without errors, and ActionPalette singleton is importable. Ask the user if questions arise.

- [x] 3. AI prefix detection and search widget integration
  - [x] 3.1 Add AI prefix detection branch in SearchWidget.qml
    - Insert an early-return branch in `ScriptModel.values` that checks `root.searchingText.startsWith(Config.options.search.prefix.ai)`
    - When prefix-only (no query after space): return placeholder hint entry with `materialSymbol: "auto_awesome"` and type "AI Action"
    - When valid query: return `ActionPalette.currentResults`
    - Ensure AI prefix takes priority over other prefix checks (clipboard, emojis)
    - File: `modules/overview/SearchWidget.qml`
    - _Requirements: 1.1, 1.3, 1.5_

  - [x] 3.2 Wire SearchWidget to call ActionPalette.submitQuery on valid AI input
    - When AI intent detected and query text changes, call `ActionPalette.submitQuery(afterPrefix.trim())`
    - When prefix removed or search cleared, call `ActionPalette.cancelRequest()`
    - File: `modules/overview/SearchWidget.qml`
    - _Requirements: 1.1, 7.2, 7.3_

- [x] 4. LLM request pipeline
  - [x] 4.1 Implement debounce timer in ActionPalette
    - Add a `Timer` component with interval bound to `Config.options.search.aiDebounceMs`
    - Validate debounce value: if outside [100, 5000] or not integer, use default 600
    - On `submitQuery`: restart debounce timer, set state to Debouncing
    - On timer trigger: proceed to send request
    - File: `services/ActionPalette.qml`
    - _Requirements: 7.1, 7.4, 7.5_

  - [x] 4.2 Implement buildActionContext function
    - Gather current Shell_Config state via `JSON.stringify(Config.options)`
    - Gather open windows from `HyprlandData` (app IDs, workspace positions)
    - Gather active workspace identifier
    - Return structured context object
    - File: `services/ActionPalette.qml`
    - _Requirements: 2.3_

  - [x] 4.3 Implement buildSystemPrompt function
    - Construct system prompt instructing LLM to return JSON `Action_Plan` with `summary` (max 200 chars) and `actions` array (max 20 items)
    - Include the list of supported action types and their required parameters
    - Include the config key namespace documentation
    - File: `services/ActionPalette.qml`
    - _Requirements: 2.2_

  - [x] 4.4 Implement policy gates (policies.ai checks)
    - Before sending request: check `Config.options.policies.ai === 0` → show "AI disabled" message
    - Check `Config.options.policies.ai === 2` and endpoint doesn't contain "localhost" → show "online models disallowed" message
    - Check `Ai.currentModelHasApiKey` → show key guidance if missing
    - Check `Ai.currentModelId` validity → show model guidance if invalid
    - File: `services/ActionPalette.qml`
    - _Requirements: 2.4, 2.5, 8.3, 8.6_

  - [x] 4.5 Implement LLM request via Process (curl)
    - Create a separate `Process` instance (not shared with Ai.qml's requester)
    - Use the existing `ApiStrategy` pattern to build endpoint, headers, and request body
    - Set 30-second timeout timer; on expiry kill process and show timeout error
    - On process completion: pass stdout to `parseResponse`
    - On non-zero exit: show network error with [Retry] option
    - File: `services/ActionPalette.qml`
    - _Requirements: 2.1, 2.6, 8.1, 8.2, 8.4, 8.5_

  - [x] 4.6 Implement cancelRequest and request state management
    - Kill in-flight process when `cancelRequest` is called
    - Reset state to Idle, clear loading indicator
    - Implement `retry` to re-submit `lastQuery`
    - File: `services/ActionPalette.qml`
    - _Requirements: 7.2, 7.3_

- [x] 5. Checkpoint — Request pipeline verified
  - Ensure debounce fires, policy gates block correctly, and a mocked curl call returns data. Ask the user if questions arise.

- [x] 6. Response parsing and validation
  - [x] 6.1 Implement parseResponse function
    - `JSON.parse` the response text; catch and surface malformed JSON errors
    - Extract `summary` and `actions` array
    - Validate summary length ≤ 500 chars
    - Validate actions array length 0–50
    - On schema mismatch: set error state with descriptive message and [Retry]
    - File: `services/ActionPalette.qml`
    - _Requirements: 3.1, 3.2_

  - [x] 6.2 Implement validateActionPlan and validateAction functions
    - For each action: check `type` is one of `["config.set", "shell.exec", "hyprland.dispatch", "app.launch"]`
    - Check required parameters per type: `config.set` → key+value, `shell.exec` → command, `hyprland.dispatch` → dispatcher+args, `app.launch` → id
    - Mark invalid actions with `valid: false` and `warning` string
    - For `config.set` actions: look up current value via a `getNestedValue` helper
    - File: `services/ActionPalette.qml`
    - _Requirements: 3.3, 3.4, 3.5_

  - [x] 6.3 Implement currentResults property (display model)
    - Build results array compatible with SearchItem delegate format
    - Summary entry (index 0): truncate to 120 chars + "…", icon `auto_awesome`, with [Apply] and [Preview] action buttons
    - Per-action entries: show type-specific display strings (`key: old → new` for config.set, command for shell.exec, etc.)
    - Handle empty actions array: show summary only, disable Apply/Preview buttons
    - Handle loading state: return loading indicator entry
    - Handle error state: return error message with [Retry] action
    - File: `services/ActionPalette.qml`
    - _Requirements: 3.6, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8_

- [x] 7. UI components
  - [x] 7.1 Create ActionPaletteResults.qml delegate
    - QML component that renders AI action plan entries within the search list
    - Reuse `SearchItem.qml` patterns for consistent look with existing results
    - Display per-action icons: `settings` for config.set, `terminal` for shell.exec, `open_with` for hyprland.dispatch, `apps` for app.launch
    - Show warning indicator for invalid actions
    - File: `modules/overview/ActionPaletteResults.qml`
    - _Requirements: 4.1, 4.2_

  - [x] 7.2 Create PreviewIndicator.qml floating bar
    - Floating bar component anchored to bottom of overview
    - Shows "Previewing changes" text with [Commit] and [Revert] buttons
    - Commit calls `ActionPalette.commitPreview()`
    - Revert calls `ActionPalette.revertPreview()`
    - Visible only when `ActionPalette.previewActive` is true
    - File: `modules/overview/PreviewIndicator.qml`
    - _Requirements: 6.2, 6.3, 6.4_

  - [x] 7.3 Create ActionApprovalDialog.qml
    - Dialog component showing full shell command text
    - [Approve] button calls `ActionPalette.approveCommand(actionIndex)`
    - [Reject] button calls `ActionPalette.rejectCommand()`
    - Consistent styling with existing sidebar command approval gate
    - File: `modules/overview/ActionApprovalDialog.qml`
    - _Requirements: 5.3, 5.4_

- [x] 8. Action execution engine
  - [x] 8.1 Implement sequential execution loop in applyPlan
    - Process actions in array order (index 0 to N-1, strictly sequential)
    - Capture previous values for all `config.set` actions before executing
    - For `config.set`: call `Config.setNestedValue(key, value)`
    - For `hyprland.dispatch`: spawn `hyprctl dispatch <dispatcher> <args>`
    - For `app.launch`: look up desktop entry via `AppSearch`, launch if found, fail if not
    - For `shell.exec`: emit `approvalRequired` signal, pause execution until approved/rejected
    - On any failure: stop remaining actions, offer undo of applied config changes
    - On all success: close overview via `GlobalStates.overviewOpen = false`
    - File: `services/ActionPalette.qml`
    - _Requirements: 5.1, 5.2, 5.5, 5.6, 5.7, 5.8, 5.10_

  - [x] 8.2 Implement shell command execution with approval gate
    - When `shell.exec` action reached: set state, emit `approvalRequired(command, index)`
    - On approve: spawn Process with 30s timeout, capture exit code
    - On non-zero exit or timeout: kill process, mark failed, stop execution, offer undo
    - On reject: stop execution, show cancellation message
    - File: `services/ActionPalette.qml`
    - _Requirements: 5.3, 5.4, 5.9_

  - [x] 8.3 Implement config rollback (undo)
    - Store `ConfigSnapshot` with `{ entries: [{ key, previousValue }] }` for each applied config.set
    - On failure or user-triggered undo: iterate snapshot entries, call `Config.setNestedValue(key, previousValue)` for each
    - File: `services/ActionPalette.qml`
    - _Requirements: 5.8_

- [x] 9. Preview mode
  - [x] 9.1 Implement previewPlan function
    - Filter Action_Plan to only `config.set` actions
    - Capture config snapshot before applying
    - Apply each `config.set` via `Config.setNestedValue` (runtime-only, no persistence)
    - Set `previewActive = true`, emit `previewStarted`
    - On failure during preview: revert already-applied changes, exit preview, show error
    - File: `services/ActionPalette.qml`
    - _Requirements: 6.1, 6.6_

  - [x] 9.2 Implement commitPreview and revertPreview
    - `commitPreview`: trigger `FileView.writeAdapter()` to persist, close overview
    - `revertPreview`: restore all keys from snapshot, set `previewActive = false`, emit `previewEnded`
    - File: `services/ActionPalette.qml`
    - _Requirements: 6.3, 6.4_

  - [x] 9.3 Implement auto-revert on overview close during preview
    - Add `Connections` handler on `GlobalStates.overviewOpen`
    - When overview closes while `previewActive`: call `revertPreview()`
    - File: `services/ActionPalette.qml`
    - _Requirements: 6.5_

- [x] 10. Checkpoint — Full feature verified
  - Ensure end-to-end flow works: type `? make it dark`, see loading, receive mocked response, display actions, apply/preview/revert. Ask the user if questions arise.

- [x] 11. Set up fast-check test infrastructure
  - [x] 11.1 Create package.json and vitest config for JS property tests
    - Create `tests/js/package.json` with fast-check, vitest dependencies
    - Create `tests/js/vitest.config.js`
    - Extract pure logic functions from ActionPalette design into testable JS module at `tests/js/src/action-palette-logic.js`
    - Functions to extract: `classifyAiPrefix`, `validatePrefix`, `checkLocalOnlyPolicy`, `parseActionPlan`, `validateAction`, `truncateSummary`, `formatActionDisplay`, `validateDebounceMs`
    - _Requirements: Design Testing Strategy_

- [x] 12. Property-based tests (fast-check)
  - [x] 12.1 Write property test: AI Prefix Classification (Property 1)
    - **Property 1: AI Prefix Classification**
    - For any search input and valid AI prefix (1-3 non-whitespace chars): classifier identifies AI intent iff input starts with prefix + space + non-whitespace
    - AI prefix takes priority over conflicting prefixes
    - File: `tests/js/src/action-palette-logic.test.js`
    - **Validates: Requirements 1.1, 1.5**

  - [x] 12.2 Write property test: Prefix Configuration Validation (Property 2)
    - **Property 2: Prefix Configuration Validation**
    - For any string: `search.prefix.ai` validator accepts iff 1-3 chars and not all whitespace
    - File: `tests/js/src/action-palette-logic.test.js`
    - **Validates: Requirements 1.2**

  - [x] 12.3 Write property test: Local-Only Policy Gate (Property 3)
    - **Property 3: Local-Only Policy Gate**
    - For any endpoint URL and policies.ai=2: gate blocks iff endpoint does not contain "localhost"
    - File: `tests/js/src/action-palette-logic.test.js`
    - **Validates: Requirements 2.5**

  - [x] 12.4 Write property test: Action_Plan Round-Trip (Property 4)
    - **Property 4: Action_Plan Round-Trip**
    - For any valid Action_Plan (summary ≤500, 0-50 valid actions): serialize to JSON then parse back produces deeply equal object
    - File: `tests/js/src/action-palette-logic.test.js`
    - **Validates: Requirements 3.5, 3.1**

  - [x] 12.5 Write property test: Action Schema Validation (Property 5)
    - **Property 5: Action Schema Validation**
    - For any JSON object as Proposed_Action: validator marks valid iff type matches supported types AND all required params present
    - File: `tests/js/src/action-palette-logic.test.js`
    - **Validates: Requirements 3.3, 3.4**

  - [x] 12.6 Write property test: Summary Truncation (Property 6)
    - **Property 6: Summary Truncation**
    - For any summary string: displayed text equals original if ≤120 chars, else first 120 + "…"
    - File: `tests/js/src/action-palette-logic.test.js`
    - **Validates: Requirements 4.1**

  - [x] 12.7 Write property test: Action Display Completeness (Property 7)
    - **Property 7: Action Display Completeness**
    - For any valid Proposed_Action: rendered display contains the type-specific key information
    - File: `tests/js/src/action-palette-logic.test.js`
    - **Validates: Requirements 4.2**

  - [x] 12.8 Write property test: Sequential Execution Order (Property 8)
    - **Property 8: Sequential Execution Order**
    - For any Action_Plan with N actions: execution processes indices 0..N-1 in ascending order, no action i+1 starts before i completes/fails
    - Model-based test using execution trace recording
    - File: `tests/js/src/action-palette-logic.test.js`
    - **Validates: Requirements 5.1**

  - [x] 12.9 Write property test: Config Rollback on Failure (Property 9)
    - **Property 9: Config Rollback on Failure**
    - For any plan with config.set actions where action K fails: all prior config.set actions have captured values, undo restores each
    - File: `tests/js/src/action-palette-logic.test.js`
    - **Validates: Requirements 5.8**

  - [x] 12.10 Write property test: Preview Filters Only config.set (Property 10)
    - **Property 10: Preview Filters Only config.set**
    - For any mixed Action_Plan: preview applies only config.set actions, count of applied changes equals count of config.set in plan
    - File: `tests/js/src/action-palette-logic.test.js`
    - **Validates: Requirements 6.1**

  - [x] 12.11 Write property test: Preview Revert Restores State (Property 11)
    - **Property 11: Preview Revert Restores State**
    - For any set of config.set actions applied during preview: reverting restores every key to pre-preview value
    - File: `tests/js/src/action-palette-logic.test.js`
    - **Validates: Requirements 6.4, 6.5, 6.6**

  - [x] 12.12 Write property test: Debounce Configuration Validation (Property 12)
    - **Property 12: Debounce Configuration Validation**
    - For any value: effective debounce is the value if integer in [100, 5000], else 600
    - File: `tests/js/src/action-palette-logic.test.js`
    - **Validates: Requirements 7.4, 7.5**

- [x] 13. Checkpoint — Property tests pass
  - Ensure all 12 property tests pass with minimum 100 iterations each. Ask the user if questions arise.

- [x] 14. Integration tests
  - [x] 14.1 Write integration test: full request cycle with mocked LLM response
    - Mock curl process to return a valid Action_Plan JSON
    - Verify parsing, validation, and display of results
    - File: `tests/js/src/action-palette-integration.test.js`
    - _Requirements: 2.1, 3.1_

  - [x] 14.2 Write integration test: debounce timer and cancellation
    - Verify debounce fires after idle period
    - Verify in-flight request cancelled on text change
    - Verify request cancelled on prefix removal
    - File: `tests/js/src/action-palette-integration.test.js`
    - _Requirements: 7.1, 7.2, 7.3_

  - [x] 14.3 Write integration test: execution flow with approval gate
    - Verify config.set applies via setNestedValue
    - Verify shell.exec triggers approval dialog
    - Verify rejection stops execution
    - Verify timeout kills process
    - File: `tests/js/src/action-palette-integration.test.js`
    - _Requirements: 5.2, 5.3, 5.4, 5.9_

  - [x] 14.4 Write integration test: preview mode lifecycle
    - Verify preview applies only config.set actions
    - Verify commit persists changes
    - Verify revert restores state
    - Verify overview close auto-reverts
    - File: `tests/js/src/action-palette-integration.test.js`
    - _Requirements: 6.1, 6.3, 6.4, 6.5_

- [x] 15. Final checkpoint — All tests pass
  - Ensure all property tests and integration tests pass, all QML files load without errors. Ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation between phases
- Property tests use fast-check (JavaScript PBT framework) with vitest as runner
- Pure logic functions are extracted from the QML service into a testable JS module for property testing
- The ActionPalette service uses a separate Process instance from Ai.qml to avoid state interference
- Preview mode mutates config in-memory only — persistence requires explicit `writeAdapter()` call
- The `currentResults` property returns data compatible with existing `SearchItem` delegate format
- All QML files follow existing project patterns: `pragma Singleton`, `pragma ComponentBehavior: Bound`, standard imports

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["1.3"] },
    { "id": 2, "tasks": ["3.1", "3.2"] },
    { "id": 3, "tasks": ["4.1", "4.2", "4.3"] },
    { "id": 4, "tasks": ["4.4", "4.5", "4.6"] },
    { "id": 5, "tasks": ["6.1", "6.2"] },
    { "id": 6, "tasks": ["6.3", "7.1", "7.2", "7.3"] },
    { "id": 7, "tasks": ["8.1", "8.2", "8.3"] },
    { "id": 8, "tasks": ["9.1", "9.2", "9.3"] },
    { "id": 9, "tasks": ["11.1"] },
    { "id": 10, "tasks": ["12.1", "12.2", "12.3", "12.4", "12.5", "12.6", "12.7", "12.12"] },
    { "id": 11, "tasks": ["12.8", "12.9", "12.10", "12.11"] },
    { "id": 12, "tasks": ["14.1", "14.2", "14.3", "14.4"] }
  ]
}
```
