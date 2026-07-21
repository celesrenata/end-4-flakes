# Implementation Plan: Chat Context Management

## Overview

Extend the `Ai.qml` singleton and sidebar chat UI with multi-session management, token-based context window tracking, a `/compact` slash command for conversation summarization, and proactive context limit handling with model upgrade suggestions. Implementation uses the existing patterns: `Persistent.qml` with `JsonAdapter` for persisted state, `FileView` + `Directories.aiChats` for session files, and the `allCommands` array in `AiChat.qml` for slash command routing.

## Tasks

- [x] 1. Extend AiModel and add context tracking core
  - [x] 1.1 Add `context_length` property to AiModel.qml and set per-model values
    - Add `property int context_length: 128000` to the AiModel QtObject
    - Set actual context lengths for each model definition in Ai.qml (e.g., Gemini 2.5 Flash = 1048576, DeepSeek R1 = 65536)
    - _Requirements: 2.3, 2.4_

  - [x] 1.2 Add token estimation and context usage properties to Ai.qml
    - Add `function estimateTokens(text)` that returns `Math.ceil((text || "").length / 4)` (return 0 for null/undefined/empty)
    - Add `readonly property int contextTokens` that sums `estimateTokens(systemPrompt)` + all message `rawContent` tokens
    - Add `readonly property int contextLimit: models[currentModelId]?.context_length ?? 128000`
    - Add `readonly property real contextUsageRatio: contextLimit > 0 ? contextTokens / contextLimit : 0`
    - Add `readonly property bool contextFull: contextUsageRatio >= 1.0`
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [x] 1.3 Write property tests for token estimation (Property 1)
    - **Property 1: Token estimation is deterministic ceiling division**
    - Test that for any string, `estimateTokens(str)` equals `math.ceil(len(str) / 4)`, and empty string returns 0
    - **Validates: Requirements 2.1**

  - [x] 1.4 Write property tests for context usage calculation (Property 2)
    - **Property 2: Context usage is the sum of all message tokens plus system prompt**
    - Test that contextTokens equals the sum of estimateTokens for the system prompt plus all messages
    - **Validates: Requirements 2.2**

  - [x] 1.5 Write property tests for context indicator color thresholds (Property 3)
    - **Property 3: Context indicator color follows threshold rules**
    - Test that for any ratio value, the color logic returns error when > 0.9, warning when > 0.7, default otherwise
    - **Validates: Requirements 2.6, 2.7**

- [x] 2. Implement session management in Ai.qml
  - [x] 2.1 Add session management properties and Persistent.qml extension
    - Add `property string activeSessionName` bound to `Persistent.states?.ai?.activeSession ?? "Chat 1"`
    - Add `property var sessionsIndex: ({})` for in-memory session index
    - Add `activeSession` string property to the `ai` JsonObject in Persistent.qml
    - _Requirements: 6.2, 1.7_

  - [x] 2.2 Implement `loadSessionsIndex()` and `saveSessionsIndex()` functions
    - Load `sessions-index.json` from `Directories.aiChats` using FileView
    - Parse JSON into `sessionsIndex` property
    - If file missing or corrupt, rebuild index by scanning existing `.json` files in the directory
    - `saveSessionsIndex()` writes the current in-memory index back to the file
    - _Requirements: 6.5_

  - [x] 2.3 Implement `newSession(name)` and `getNextDefaultName()` functions
    - `getNextDefaultName()`: find smallest positive integer N where "Chat {N}" is not in the existing session names
    - `newSession(name)`: validate name (non-empty after trim, no `/` or `\` characters), save current session, create empty message list, set activeSessionName, update Persistent state, update sessions-index with creation timestamp
    - _Requirements: 1.1, 1.2_

  - [x] 2.4 Implement `switchSession(name)` and `loadSession(name)` functions
    - `switchSession(name)`: verify session exists in index, save current session, load target session's JSON file, set activeSessionName, update Persistent state
    - `loadSession(name)`: read `{name}.json` from aiChats directory, parse message array, populate message model
    - If session file doesn't exist, show error listing available sessions
    - _Requirements: 1.3, 6.3_

  - [x] 2.5 Implement `deleteSession(name)` function
    - Reject if name equals activeSessionName (show error message)
    - Remove session JSON file from filesystem
    - Remove entry from sessionsIndex and save the index
    - _Requirements: 1.5, 1.6_

  - [x] 2.6 Implement `listSessions()` function and `saveCurrentSession()` auto-save
    - `listSessions()`: return sorted session entries with names and lastModified timestamps
    - `saveCurrentSession()`: serialize current messages to `{activeSessionName}.json`, update lastModified in sessions-index
    - Hook auto-save to message list changes (message added or removed)
    - _Requirements: 1.4, 1.8, 6.1_

  - [x] 2.7 Implement startup session restoration
    - On Component.onCompleted: call `loadSessionsIndex()`, then load the session from `Persistent.states.ai.activeSession`
    - If the persisted session file doesn't exist, create a new default session
    - _Requirements: 1.7, 6.3, 6.4_

  - [x] 2.8 Write property tests for new session creation (Property 4)
    - **Property 4: New session creation produces empty history**
    - Test that creating a new session results in an empty message list and matching active session name
    - **Validates: Requirements 1.1**

  - [x] 2.9 Write property tests for default naming (Property 5)
    - **Property 5: Default session naming follows sequential pattern**
    - Test that for any set of existing sessions, the generated name is "Chat {N}" where N is the smallest unused positive integer
    - **Validates: Requirements 1.2**

  - [x] 2.10 Write property tests for session switch round-trip (Property 6)
    - **Property 6: Session switch round-trip preserves messages**
    - Test that switching from A to B and back to A restores A's original message list
    - **Validates: Requirements 1.3**

  - [x] 2.11 Write property tests for session deletion (Property 8)
    - **Property 8: Deleting a non-active session reduces session count by one**
    - Test that deleting a non-active session reduces count by one and the deleted session no longer appears
    - **Validates: Requirements 1.5**

  - [x] 2.12 Write property tests for session serialization round-trip (Property 9)
    - **Property 9: Session serialization round-trip preserves data**
    - Test that serializing messages to JSON and deserializing produces equivalent content
    - **Validates: Requirements 1.8, 6.1**

  - [x] 2.13 Write property tests for sessions index (Property 17)
    - **Property 17: Sessions index contains all session metadata**
    - Test that for any set of sessions, the index contains every session with name, creation, and last-modified timestamps
    - **Validates: Requirements 6.5**

- [x] 3. Checkpoint — Core session management
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Implement compact command
  - [x] 4.1 Add compact state properties to Ai.qml
    - Add `property bool compacting: false`
    - Add the summarization system prompt template: "Summarize the following conversation concisely, preserving key context, decisions, and any code or technical details. {focusInstruction}"
    - _Requirements: 3.1, 3.4_

  - [x] 4.2 Implement `compactChat(focusInstruction)` function
    - Set `compacting = true`
    - Build summarization request: use current model, inject summarization system prompt with optional focus instruction, include full conversation history as user content
    - Send request to current model API
    - On success: replace entire message list with a single system-role message containing the summary, recalculate contextUsage, save session, set `compacting = false`
    - On failure (network error or empty response): preserve original messages, show error via interfaceRole message, set `compacting = false`
    - _Requirements: 3.1, 3.2, 3.3, 3.5, 3.6_

  - [x] 4.3 Write property tests for compact focus inclusion (Property 10)
    - **Property 10: Compact with focus includes focus in prompt**
    - Test that any non-empty focus instruction appears in the summarization request payload
    - **Validates: Requirements 3.2**

  - [x] 4.4 Write property tests for successful compact (Property 11)
    - **Property 11: Successful compact replaces history with single summary message**
    - Test that after success, message list contains exactly one system-role message with the summary content
    - **Validates: Requirements 3.3**

  - [x] 4.5 Write property tests for failed compact (Property 12)
    - **Property 12: Failed compact preserves original messages**
    - Test that on failure, message list remains identical to pre-compaction state
    - **Validates: Requirements 3.5**

- [x] 5. Implement context limit handling and AI_Doctor
  - [x] 5.1 Add AI_Doctor property and context-full blocking to Ai.qml
    - Add `readonly property var largerContextModels` that filters modelList for models with `context_length > contextLimit`
    - Add guard in `sendUserMessage()`: if `contextFull`, reject the message and emit a signal or set a flag for the UI to show the context-full state
    - _Requirements: 4.1, 4.2_

  - [x] 5.2 Implement model switch from AI_Doctor suggestion
    - Add `function switchToModel(modelId)` that changes currentModelId and unblocks message sending
    - Recalculate contextUsageRatio with the new model's context_length
    - _Requirements: 4.4_

  - [x] 5.3 Write property tests for context full blocks sending (Property 13)
    - **Property 13: Context full blocks message sending**
    - Test that when contextTokens >= contextLimit, sending is blocked
    - **Validates: Requirements 4.1**

  - [x] 5.4 Write property tests for AI_Doctor suggestions (Property 14)
    - **Property 14: AI_Doctor suggests only models with larger context**
    - Test that suggested models list contains only models with strictly greater context_length
    - **Validates: Requirements 4.2**

- [x] 6. Implement auto-compact notification logic
  - [x] 6.1 Add auto-compact notification state to Ai.qml
    - Add `property bool autoCompactShown: false` (reset per session)
    - Add `property bool autoCompactDismissed: false` (reset per session)
    - Add logic: when contextUsageRatio crosses 0.85 from below and not dismissed, set `autoCompactShown = true`
    - After compaction drops below 0.85 and re-crosses, allow notification again
    - _Requirements: 5.1, 5.5_

  - [x] 6.2 Write property tests for auto-compact threshold (Property 15)
    - **Property 15: Auto-compact notification triggers on threshold crossing**
    - Test that crossing 0.85 from below triggers notification, and after dismiss + re-cross it triggers again
    - **Validates: Requirements 5.1, 5.5**

  - [x] 6.3 Write property tests for non-blocking notification (Property 16)
    - **Property 16: Non-blocking notification allows continued message sending**
    - Test that while notification is visible and ratio < 1.0, messages can still be sent
    - **Validates: Requirements 5.4**

- [x] 7. Checkpoint — Backend logic complete
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Implement slash commands in AiChat.qml
  - [x] 8.1 Add `/new`, `/switch`, `/list`, `/delete` commands to allCommands
    - Add command entries to the `allCommands` array in AiChat.qml
    - `/new [name]`: call `Ai.newSession(name)`, display confirmation message
    - `/switch <name>`: call `Ai.switchSession(name)`, display switch confirmation
    - `/list`: call `Ai.listSessions()`, display formatted list with names and timestamps
    - `/delete <name>`: call `Ai.deleteSession(name)`, display confirmation or error
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

  - [x] 8.2 Add `/compact` command to allCommands
    - `/compact [focus]`: call `Ai.compactChat(focus)`, UI handles compacting state
    - _Requirements: 3.1, 3.2_

- [x] 9. Implement UI components in AiChat.qml
  - [x] 9.1 Create ContextIndicator component
    - Create a `RowLayout`-based component showing token usage percentage and a colored progress segment
    - Bind to `Ai.contextUsageRatio` for the progress bar fill
    - Color logic: default `Appearance.colors.colSubtext`, > 0.7 `Appearance.m3colors.m3tertiary`, > 0.9 `Appearance.m3colors.m3error`
    - Show "Compacting..." text when `Ai.compacting` is true
    - Place in the chat status bar row
    - _Requirements: 2.5, 2.6, 2.7, 3.4_

  - [x] 9.2 Create AutoCompactNotification banner
    - Dismissible banner above the input area, visible when `Ai.autoCompactShown && !Ai.autoCompactDismissed`
    - Contains suggestion text, a dismiss button (sets `Ai.autoCompactDismissed = true`), and a "Compact now" button (calls `Ai.compactChat("")`)
    - Does not block input area
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x] 9.3 Create ContextFullUI overlay
    - Replaces/overlays the input area when `Ai.contextFull` is true
    - Shows "Context window full" message
    - Lists `Ai.largerContextModels` with clickable model names that call `Ai.switchToModel(id)`
    - Shows compact button with an optional focus text field
    - If `Ai.largerContextModels` is empty, hide the model suggestion section
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 10. Wire components together and final integration
  - [x] 10.1 Wire session restore on startup
    - Ensure `Component.onCompleted` in Ai.qml calls session restoration logic
    - Verify Persistent.qml properly stores and retrieves `ai.activeSession`
    - _Requirements: 1.7, 6.2, 6.3, 6.4_

  - [x] 10.2 Wire context usage recalculation triggers
    - Ensure `contextTokens` recalculates on: message added, message removed, system prompt changed, model switch
    - Ensure `contextUsageRatio` updates drive ContextIndicator, AutoCompactNotification, and ContextFullUI reactively
    - _Requirements: 2.2, 3.6, 5.1_

  - [x] 10.3 Wire message sending guard with context-full UI
    - Input area disabled/hidden when contextFull, replaced by ContextFullUI
    - After model switch or successful compact, unblock input and hide ContextFullUI
    - _Requirements: 4.1, 4.3, 4.4_

- [x] 11. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document using Python with Hypothesis
- Test file location: `tests/test_chat_context_management.py`
- Pure functions to extract for testing: `estimateTokens`, `getContextColor`, `getNextDefaultName`, `filterLargerContextModels`, `shouldShowNotification`, `serializeSession`, `deserializeSession`
- QML bindings drive all reactive UI updates — no manual refresh calls needed
- The existing `saveChat`/`loadChat` pattern in Ai.qml is refactored into the formal session management system

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["1.3", "1.4", "1.5", "2.1"] },
    { "id": 2, "tasks": ["2.2", "2.3", "2.4", "2.5", "2.6"] },
    { "id": 3, "tasks": ["2.7", "2.8", "2.9", "2.10", "2.11", "2.12", "2.13"] },
    { "id": 4, "tasks": ["4.1", "4.2"] },
    { "id": 5, "tasks": ["4.3", "4.4", "4.5", "5.1"] },
    { "id": 6, "tasks": ["5.2", "5.3", "5.4", "6.1"] },
    { "id": 7, "tasks": ["6.2", "6.3", "8.1", "8.2"] },
    { "id": 8, "tasks": ["9.1", "9.2", "9.3"] },
    { "id": 9, "tasks": ["10.1", "10.2", "10.3"] }
  ]
}
```
