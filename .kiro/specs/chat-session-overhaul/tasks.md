# Implementation Plan: Chat Session Overhaul

## Overview

Transform the Quickshell sidebar chat from a basic session-aware interface into a full session management platform with viewport anchoring, search, archiving, smart dictation routing, and HyprMCP integration. Implementation uses extracted pure-logic modules for testability, modifying Ai.qml, AiChat.qml, DictationService.qml, Config.qml, and creating SearchPanel.qml plus test files.

QML constraints apply throughout: no spread operator (use Object.assign), no replaceAll (use split/join), indexed for loops, pragma Singleton + ComponentBehavior: Bound.

## Tasks

- [x] 1. Extract pure logic module and set up test infrastructure
  - [x] 1.1 Create `tests/js/src/chat-session-logic.js` with extracted pure functions
    - Implement `saveLoadRoundTrip(messages)` — serialize/deserialize message list
    - Implement `validateSessionName(name, existingNames)` — returns {valid, reason}
    - Implement `formatContextMeter(ratio, contextLimit)` — returns formatted string
    - Implement `shouldShowAutoCompact(currentRatio, previousRatio, alreadyShown)` — threshold crossing
    - Implement `filterByKeyword(messages, keyword)` — case-insensitive substring match
    - Implement `filterByDateRange(messages, startDate, endDate)` — timestamp range filter
    - Implement `filterBySubject(sessions, subjectFilter)` — substring match on subject
    - Implement `filterByGroup(sessions, groupFilter)` — exact match on group
    - Implement `wrapSearchIndex(currentIndex, totalResults, direction)` — wrapping navigation
    - Implement `classifyIntent(text)` — returns "command" | "dictation" | "ambiguous"
    - Implement `routeDictation(text, activeSessionName)` — returns {action, target}
    - Implement `validateGroupLabel(label)` — 1-64 chars, not whitespace-only
    - Implement `validateSubject(subject)` — 1-128 chars, not whitespace-only
    - Implement `sortGroupHeaders(groups)` — case-insensitive alphabetical
    - Implement `verifyMismatchMessage(expected, actual)` — builds error message
    - _Requirements: All (testable logic extraction)_

  - [x] 1.2 Create `tests/js/src/chat-session-logic.test.js` scaffold
    - Set up imports for vitest, fast-check, and chat-session-logic module
    - Create describe blocks for all 21 correctness properties
    - _Requirements: All_

- [x] 2. Session persistence and switch logic (Ai.qml)
  - [x] 2.1 Enhance sessions-index.json schema handling in Ai.qml
    - Add `archived`, `group`, `subject`, `protected` fields to session index read/write
    - Ensure backward-compatible loading (default `archived: false`, `group: ""`, `subject: ""`)
    - Migrate existing index entries on first load by adding missing fields
    - _Requirements: 7.1, 7.2, 7.3, 7.5_

  - [x] 2.2 Implement `purgeSession(name)` in Ai.qml
    - Clear all messages from the named session's file (write empty array)
    - Preserve session entry in sessions index with all metadata intact
    - Update lastModified timestamp
    - If purging active session, clear messageIDs and messageByID in memory
    - _Requirements: 4.1_

  - [x] 2.3 Implement `renameSession(oldName, newName)` in Ai.qml
    - Validate newName: non-empty, no `/` or `\`, not duplicate, not "Free Dictation" target
    - Rename persisted file on disk
    - Update sessions index entry name
    - Update Persistent.states.ai.activeSession if renaming active session
    - _Requirements: 4.2, 4.6, 4.7_

  - [x] 2.4 Add `sessionSwitchStarted` / `sessionSwitchCompleted` signals
    - Emit `sessionSwitchStarted` before clearing messages on switch
    - Emit `sessionSwitchCompleted` after new messages are loaded and rendered
    - Ensure switch disables input during transition
    - _Requirements: 3.1, 3.2, 3.3_

  - [x] 2.5 Implement failed session load fallback logic
    - Wrap loadSession in try/catch for file missing and JSON parse errors
    - On failure: preserve current state, display error, stay on current session
    - Fallback to most recently modified session if persisted name is invalid on startup
    - Create default session if index is empty on restore
    - _Requirements: 2.4, 2.5, 3.5_

  - [x] 2.6 Write property tests for session save/load round-trip
    - **Property 1: Session save/load round-trip**
    - **Validates: Requirements 2.3**

  - [x] 2.7 Write property test for session switch persists active name
    - **Property 2: Session switch persists active name**
    - **Validates: Requirements 2.1**

  - [x] 2.8 Write property test for session switch clears previous messages
    - **Property 3: Session switch clears previous messages**
    - **Validates: Requirements 3.2**

  - [x] 2.9 Write property test for failed session load preserves state
    - **Property 4: Failed session load preserves current state**
    - **Validates: Requirements 3.5**

  - [x] 2.10 Write property test for purge clears messages but preserves index
    - **Property 5: Purge clears messages but preserves index entry**
    - **Validates: Requirements 4.1**

  - [x] 2.11 Write property test for rename updates state correctly
    - **Property 6: Rename updates state correctly**
    - **Validates: Requirements 4.2**

  - [x] 2.12 Write property test for rename validation rejects invalid names
    - **Property 7: Rename validation rejects invalid names**
    - **Validates: Requirements 4.6, 4.7**

- [x] 3. Checkpoint - Session persistence verified
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Context compaction and summarization (Ai.qml)
  - [x] 4.1 Implement `/compact` command handler in Ai.qml
    - Send conversation history to current model with summarization prompt
    - On success: replace messageIDs/messageByID with single system-role summary message
    - On failure: preserve original messages, display error
    - Save compacted session to disk
    - _Requirements: 5.1, 5.3_

  - [x] 4.2 Implement `/summarize` command handler in Ai.qml
    - Send conversation to model requesting title (max 50 chars) and summary
    - Create new session with model-generated title
    - Populate with single system-role summary message
    - Switch to new session, leave original unchanged
    - _Requirements: 5.2, 5.3_

  - [x] 4.3 Implement context meter display formatting
    - Add `contextMeterText` computed property to Ai.qml
    - Format as `"{percentage}% of {limit}"` with limit as k/M notation
    - Track context usage ratio from token counting
    - _Requirements: 5.4_

  - [x] 4.4 Implement auto-compact threshold notification
    - Track `autoCompactShown` per session (resets on session load)
    - Trigger non-blocking notification when ratio crosses 0.85 for first time
    - At 100%: disable input field, show compact/model-switch actions
    - _Requirements: 5.5, 5.6_

  - [x] 4.5 Write property test for failed compact preserves messages
    - **Property 8: Failed compact preserves messages**
    - **Validates: Requirements 5.3**

  - [x] 4.6 Write property test for context meter format
    - **Property 9: Context meter format**
    - **Validates: Requirements 5.4**

  - [x] 4.7 Write property test for auto-compact threshold crossing
    - **Property 10: Auto-compact threshold crossing detection**
    - **Validates: Requirements 5.5**

- [x] 5. Checkpoint - Context compaction verified
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Chat viewport anchoring (AiChat.qml)
  - [x] 6.1 Implement scroll-position guards in AiChat.qml
    - Add `isNearBottom` computed property (contentY within 10px threshold for BottomToTop)
    - Auto-scroll to bottom on new message only when `isNearBottom` is true
    - Preserve scroll position when user is scrolled up and new message arrives
    - Cancel active auto-scroll animation on user scroll-up interaction
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

  - [x] 6.2 Position viewport at bottom on session load and visibility change
    - On Chat_View `onVisibleChanged`: scroll to bottom within 200ms
    - On `sessionSwitchCompleted`: scroll to bottom
    - Ensure BottomToTop layout positions newest messages at visual bottom
    - _Requirements: 1.1, 1.2, 3.4_

- [x] 7. Search system (SearchPanel.qml + Ai.qml)
  - [x] 7.1 Create `SearchPanel.qml` component
    - Keyword input with 2-char minimum validation
    - Date range pickers (start/end, either optional)
    - Subject filter text input
    - Group filter text input
    - Match count display and next/prev navigation buttons
    - Clear/close search button
    - _Requirements: 6.1, 6.6, 6.7, 6.8_

  - [x] 7.2 Implement `searchMessages()` in Ai.qml
    - Keyword filter: case-insensitive substring match on rawContent (min 2 chars)
    - Date range filter: compare message timestamps against [start, end] inclusive
    - Subject filter: case-insensitive substring on session subject metadata
    - Group filter: exact match on session group metadata
    - Return SearchResult[] with messageIndex, matchStart, matchEnd
    - Store results in `searchResults` property, maintain `searchIndex`
    - _Requirements: 6.2, 6.3, 6.4, 6.5_

  - [x] 7.3 Integrate SearchPanel into AiChat.qml toolbar
    - Add search toggle button to chat toolbar
    - Show/hide SearchPanel based on `searchOpen` property
    - Highlight matching text in message delegates when search active
    - Scroll to current match on next/prev navigation
    - _Requirements: 6.1, 6.6_

  - [x] 7.4 Write property test for keyword search filter correctness
    - **Property 11: Keyword search filter correctness**
    - **Validates: Requirements 6.2**

  - [x] 7.5 Write property test for date range filter correctness
    - **Property 12: Date range filter correctness**
    - **Validates: Requirements 6.3**

  - [x] 7.6 Write property test for search navigation wrapping
    - **Property 13: Search navigation wrapping**
    - **Validates: Requirements 6.6**

- [x] 8. Checkpoint - Search system verified
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Prior chat management (Ai.qml + AiChat.qml session drawer)
  - [x] 9.1 Implement archive/unarchive in Ai.qml
    - `archiveSession(name)`: set `archived=true` in index, persist
    - `unarchiveSession(name)`: set `archived=false` in index, persist
    - Preserve all other metadata on archive/unarchive
    - _Requirements: 7.1, 7.2_

  - [x] 9.2 Implement group and subject management in Ai.qml
    - `setSessionGroup(name, group)`: validate 1-64 chars non-whitespace, assign
    - `setSessionSubject(name, subject)`: validate 1-128 chars non-whitespace, assign
    - Reject empty/whitespace-only/over-length values with no state change
    - _Requirements: 7.3, 7.4, 7.5_

  - [x] 9.3 Implement session deletion with guards in Ai.qml
    - `deleteSession(name)`: reject if name === activeSessionName
    - On confirmation: remove file, remove from sessions index, persist
    - _Requirements: 7.6, 7.7_

  - [x] 9.4 Enhance Session_Drawer UI in AiChat.qml
    - Show purge and rename actions for all sessions except Free Dictation
    - Show only purge for Free Dictation (no rename)
    - Display archived sessions in collapsible section below active list
    - Display group labels as alphabetically-sorted section headers
    - Add archive/unarchive, group, edit subject, delete actions per session
    - _Requirements: 4.3, 4.4, 4.5, 7.8, 7.9_

  - [x] 9.5 Write property test for archive/unarchive round-trip
    - **Property 14: Archive/unarchive round-trip**
    - **Validates: Requirements 7.1, 7.2**

  - [x] 9.6 Write property test for group label validation
    - **Property 15: Group label validation and assignment**
    - **Validates: Requirements 7.3, 7.4**

  - [x] 9.7 Write property test for subject assignment
    - **Property 16: Subject assignment**
    - **Validates: Requirements 7.5**

  - [x] 9.8 Write property test for active session deletion rejection
    - **Property 17: Active session deletion rejection**
    - **Validates: Requirements 7.7**

  - [x] 9.9 Write property test for group headers alphabetical ordering
    - **Property 18: Group headers alphabetical ordering**
    - **Validates: Requirements 7.9**

- [x] 10. Checkpoint - Prior chat management verified
  - Ensure all tests pass, ask the user if questions arise.

- [x] 11. Smart dictation routing (DictationService.qml + Config.qml)
  - [x] 11.1 Add `smartRouting` option to Config.qml
    - Add `property bool smartRouting: false` to the `dictation` JsonObject
    - Expose in sidebar settings as togglable option
    - _Requirements: 8.4_

  - [x] 11.2 Implement intent classifier in DictationService.qml
    - Heuristic classification: imperative verb prefix → "command", question patterns → "dictation"
    - Under 20 words + no heuristic match → "ambiguous" (defaults to normal message)
    - When `Config.options.dictation.intentMode === "ai"`: call LLM for classification
    - 5-second timeout fallback to normal message send
    - _Requirements: 8.1, 8.5, 8.6_

  - [x] 11.3 Implement smart routing logic in DictationService.qml
    - When smartRouting enabled and session is Free Dictation:
      - Trivial commands → route to Action_Pipeline, skip chat
      - Non-trivial → send with last 5 messages + active window title to model for summarization
    - When smartRouting disabled or not Free Dictation session: existing behavior
    - _Requirements: 8.2, 8.3_

  - [x] 11.4 Implement auto-submit dictation routing in AiChat.qml
    - On `transcriptionComplete`: if active session is "Free Dictation", auto-submit via `Ai.sendUserMessage(text)`
    - If not Free Dictation: insert at cursor (existing behavior)
    - Skip empty/whitespace-only transcriptions
    - Clear input field after auto-submit
    - _Requirements: 10.1, 10.2, 10.3, 10.4_

  - [x] 11.5 Write property test for intent classifier validity
    - **Property 19: Intent classifier returns valid classification**
    - **Validates: Requirements 8.1**

  - [x] 11.6 Write property test for dictation routing by active session
    - **Property 20: Dictation routing by active session**
    - **Validates: Requirements 10.1, 10.2, 10.4**

- [x] 12. Checkpoint - Dictation routing verified
  - Ensure all tests pass, ask the user if questions arise.

- [x] 13. HyprMCP integration (Ai.qml)
  - [x] 13.1 Register HyprMCP tool definitions in Ai.qml
    - Add `hypr_config_read`, `hypr_config_set`, `hypr_set_keyword` to `root.tools` array
    - Include tool schemas for each API format (OpenAI, Gemini, Ollama function calling)
    - _Requirements: 9.1_

  - [x] 13.2 Implement HyprMCP tool call handlers in Ai.qml
    - `handleHyprMCPTool(name, args)`: dispatch to appropriate curl call to `http://localhost:7580`
    - `config_read`: invoke MCP endpoint, return state to model
    - `config_set`: write → read-back → verify → report
    - `set_keyword`: write → read-back → verify → report
    - Use existing Process + SplitParser pattern for subprocess calls
    - _Requirements: 9.2, 9.3, 9.6_

  - [x] 13.3 Implement read-back verification pipeline
    - After write: read back value within 3 seconds
    - Compare expected vs actual value
    - On match: report success to model
    - On mismatch: report both expected and actual values to model and user
    - On MCP unreachable/error: display error with failure reason
    - Never present modification as successful without verification
    - _Requirements: 9.3, 9.4, 9.5, 9.7_

  - [x] 13.4 Write property test for HyprMCP verification mismatch reporting
    - **Property 21: HyprMCP verification mismatch reporting**
    - **Validates: Requirements 9.4**

- [x] 14. Final integration and wiring
  - [x] 14.1 Wire session drawer actions to Ai.qml functions
    - Connect purge, rename, archive, unarchive, group, subject, delete UI actions
    - Add confirmation dialog for delete
    - Add inline error display for rename validation failures
    - _Requirements: 4.2, 4.3, 4.6, 7.6_

  - [x] 14.2 Wire context meter to AiChat.qml display
    - Bind context meter text from `Ai.contextMeterText`
    - Show/hide auto-compact notification on threshold
    - Display context-full overlay with action buttons at 100%
    - _Requirements: 5.4, 5.5, 5.6_

  - [x] 14.3 Register SearchPanel.qml in module qmldir
    - Add SearchPanel to `modules/sidebarLeft/qmldir`
    - Ensure component is importable from AiChat.qml
    - _Requirements: 6.1_

  - [x] 14.4 Deploy and validate
    - Run `rsync -av --delete configs/quickshell/ii/ ~/.config/quickshell/ii/`
    - Restart quickshell: `systemctl --user restart quickshell`
    - Check logs: `journalctl --user -u quickshell --since "10 sec ago" --no-pager`
    - Verify no QML errors in startup
    - _Requirements: All_

- [x] 15. Final checkpoint - Full integration verified
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation after each major feature group
- Property tests validate the 21 universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- QML constraints: no spread operator (Object.assign instead), no replaceAll (split/join), indexed for loops, pragma Singleton + ComponentBehavior: Bound
- Deploy workflow: rsync to ~/.config/quickshell/ii/ + restart quickshell service
- The `qmldir` files must be updated for any new .qml singletons or components

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "2.1"] },
    { "id": 2, "tasks": ["2.2", "2.3", "2.4", "2.5", "11.1"] },
    { "id": 3, "tasks": ["2.6", "2.7", "2.8", "2.9", "2.10", "2.11", "2.12"] },
    { "id": 4, "tasks": ["4.1", "4.2", "4.3", "4.4", "6.1", "6.2"] },
    { "id": 5, "tasks": ["4.5", "4.6", "4.7", "7.1"] },
    { "id": 6, "tasks": ["7.2", "9.1", "9.2", "9.3"] },
    { "id": 7, "tasks": ["7.3", "7.4", "7.5", "7.6", "9.4"] },
    { "id": 8, "tasks": ["9.5", "9.6", "9.7", "9.8", "9.9"] },
    { "id": 9, "tasks": ["11.2", "11.3", "11.4", "13.1"] },
    { "id": 10, "tasks": ["11.5", "11.6", "13.2"] },
    { "id": 11, "tasks": ["13.3"] },
    { "id": 12, "tasks": ["13.4", "14.1", "14.2", "14.3"] },
    { "id": 13, "tasks": ["14.4"] }
  ]
}
```
