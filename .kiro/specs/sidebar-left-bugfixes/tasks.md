# Implementation Plan

## Overview

Bugfix implementation for the left sidebar AI chat panel addressing three usability defects (table collapse, missing scrollbar, code block scroll blocking) and one documentation gap. The workflow follows the bug condition methodology: explore bugs first with property tests, write preservation tests, then implement fixes and verify.

## Tasks

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Sidebar Left Scroll and Render Defects
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bugs exist
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fixes when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the three bugs exist
  - **Scoped PBT Approach**: Scope the property to the three concrete bug conditions:
    - Bug 1 (Table Collapse): Verify that `MessageTextBlock` wraps its `TextArea` in a horizontal `ScrollView` allowing overflow when markdown table content exceeds container width
    - Bug 2 (Missing Scrollbar): Verify that `StyledListView` has a `ScrollBar.vertical` attached property with `policy: ScrollBar.AsNeeded`
    - Bug 3 (Scroll Blocking): Verify that a `MouseArea` with vertical wheel forwarding exists in `MessageCodeBlock`, forwarding `angleDelta.y` to `root.ListView.view.contentY`
  - **Bug Condition from design**:
    - `isBugCondition(input)` returns true when: (1) markdownRender with table AND containerWidth < tableMinimumLayoutWidth, (2) scrollAttempt with scrollbarDrag on messageListView, (3) wheelEvent vertical over MessageCodeBlock.ScrollView
  - **Expected Behavior from design**:
    - Bug 1: Table cell data visible via horizontal overflow/scroll — no zero-width columns
    - Bug 2: Interactive vertical scrollbar visible and draggable when contentHeight > height
    - Bug 3: Vertical wheel delta reaches parent messageListView.contentY
  - Run test on UNFIXED code - expect FAILURE (confirms bugs exist)
  - Document counterexamples: zero-width columns, missing ScrollBar.vertical, consumed wheel events
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 2.3_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Existing Scroll, Render, and Session Behavior
  - **IMPORTANT**: Follow observation-first methodology
  - **Observe on UNFIXED code**:
    - Horizontal scrolling within code blocks works (`ScrollBar.horizontal` with `policy: ScrollBar.AsNeeded` in MessageCodeBlock `codeScrollView`)
    - Flick/drag scrolling of message list works (`boundsBehavior: Flickable.DragOverBounds` in StyledListView)
    - Non-table markdown (inline code, bold, italic, links) renders correctly via `textFormat: TextEdit.MarkdownText`
    - Code block syntax highlighting functional (SyntaxHighlighter component bound to codeTextArea)
    - Mouse clicks on message actions (copy/save buttons with `copyCodeButton`, `saveCodeButton`) fire correctly
    - StyledListView transitions (add, remove, addDisplaced, removeDisplaced) are defined
  - **Write property-based tests capturing observed behavior**:
    - For all horizontal wheel events (angleDelta.x != 0) over code blocks, the code ScrollView handles them (horizontal scroll preserved)
    - For all non-table markdown content, MessageTextBlock renders with `wrapMode: TextEdit.Wrap` without requiring horizontal scroll
    - StyledListView `maximumFlickVelocity: 3500` and `boundsBehavior: Flickable.DragOverBounds` remain set
    - StyledListView transitions remain defined (add, remove, addDisplaced, removeDisplaced properties are non-null)
  - Verify tests PASS on UNFIXED code (confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [x] 3. Fix for sidebar left scroll and render defects

  - [x] 3.1 Add vertical ScrollBar to StyledListView.qml
    - **File**: `configs/quickshell/ii/modules/common/widgets/StyledListView.qml`
    - Add `ScrollBar.vertical` attached property after `boundsBehavior: Flickable.DragOverBounds` (line 16)
    - Use `policy: ScrollBar.AsNeeded` (only visible when content exceeds viewport)
    - Add `padding: 3` on the ScrollBar
    - Add `opacity` animation using `Appearance.animation.elementMoveFast` (duration, easing.type, easing.bezierCurve)
    - Show when `active || size < 1`; hide otherwise with fade animation
    - `contentItem: Rectangle` with `implicitWidth: 6`, `radius: Appearance.rounding.small`, `color: Appearance.colors.colLayer2Active`
    - Add required import: `import QtQuick.Controls` (if not already present)
    - _Bug_Condition: isBugCondition(input) where input.type == "scrollAttempt" AND input.method == "scrollbarDrag" AND input.target == "messageListView"_
    - _Expected_Behavior: Interactive vertical scrollbar visible and draggable when contentHeight > height_
    - _Preservation: Flick/drag scrolling, auto-scroll, PageUp/PageDown, add/remove transitions must remain unchanged_
    - _Requirements: 2.2, 3.2, 3.4, 3.5, 3.6_

  - [x] 3.2 Add MouseArea wheel handler to MessageCodeBlock.qml for vertical scroll forwarding
    - **File**: `configs/quickshell/ii/modules/sidebarLeft/aiChat/MessageCodeBlock.qml`
    - Inside the second `Rectangle` in the `RowLayout` (the code background container, ~line 130), add a `MouseArea` as the LAST child (after the existing `ColumnLayout`)
    - Set `anchors.fill: parent` and `acceptedButtons: Qt.NoButton` (pass-through for clicks)
    - In `onWheel` handler:
      - Check `event.angleDelta.y !== 0` (vertical scroll detected)
      - Get parent ListView: `const listView = root.ListView.view`
      - Forward: `listView.contentY -= event.angleDelta.y`
      - Call `listView.returnToBounds()` to respect list boundaries
      - Set `event.accepted = true` to prevent inner ScrollView from consuming the event
    - For horizontal-only events (`angleDelta.y === 0`): set `event.accepted = false` to let inner ScrollView handle horizontal scroll
    - Leave the commented-out MouseArea at bottom of file as-is (historical reference)
    - _Bug_Condition: isBugCondition(input) where input.type == "wheelEvent" AND input.direction == "vertical" AND input.cursorOver == "MessageCodeBlock.ScrollView"_
    - _Expected_Behavior: Vertical wheel delta propagates to parent messageListView.contentY_
    - _Preservation: Horizontal scrolling within code blocks via existing ScrollBar.horizontal must continue; copy/save/approve/reject buttons must continue to work_
    - _Requirements: 2.3, 3.3_

  - [x] 3.3 Wrap TextArea in MessageTextBlock.qml with horizontal ScrollView for table overflow
    - **File**: `configs/quickshell/ii/modules/sidebarLeft/aiChat/MessageTextBlock.qml`
    - Wrap the existing `TextArea` (id: textArea, ~line 104) in a `ScrollView`
    - Move `Layout.fillWidth: true` from TextArea to the wrapping ScrollView
    - Set `ScrollBar.vertical.policy: ScrollBar.AlwaysOff` on the ScrollView (vertical scroll handled by parent ListView)
    - Set `ScrollBar.horizontal.policy: ScrollBar.AsNeeded` (appears only when table content overflows)
    - Set `contentWidth: Math.max(availableWidth, textArea.implicitWidth)` so tables can overflow horizontally
    - Set `clip: true` on the ScrollView
    - Style the horizontal ScrollBar with same pattern as code block: `contentItem: Rectangle { implicitHeight: 6; radius: Appearance.rounding.small; color: Appearance.colors.colLayer2Active }`
    - Keep `wrapMode: TextEdit.Wrap` on the TextArea for normal text wrapping
    - Ensure the `MouseArea` for link hover cursor remains functional inside the ScrollView
    - Ensure `onLinkActivated` on TextArea still works (link clicks)
    - Ensure LaTeX rendering (`onTextChanged`, `onSegmentContentChanged`) still functions correctly
    - _Bug_Condition: isBugCondition(input) where input.type == "markdownRender" AND input.content CONTAINS markdownTable AND input.containerWidth < tableMinimumLayoutWidth_
    - _Expected_Behavior: All table cell data visible via horizontal scrolling; no zero-width columns_
    - _Preservation: Inline code, bold, italic, links render correctly; LaTeX rendering works; link click handling (onLinkActivated) works_
    - _Requirements: 2.1, 3.1_

  - [x] 3.4 Add architecture documentation to Ai.qml
    - **File**: `configs/quickshell/ii/services/Ai.qml`
    - Add a module-level doc comment block at the top of the file (after imports, before the root component declaration)
    - Document the following architecture aspects:
      - **Session Lifecycle**: newSession, switchSession, saveSession, loadSession, deleteSession
      - **Message Flow**: user input → API request construction → streaming response → message storage in session model
      - **Context Management**: token estimation, context ratio configuration, auto-compact threshold, context window handling
      - **Message Versioning**: how `messageVersion` property forces view refresh on session switch
      - **Persistence Model**: sessions index file location, per-session message file format, auto-save triggers
      - **Command System**: /model, /save, /load, /new, /switch, /delete, /test, /clear and their handlers
    - This is documentation-only — no behavioral changes to the code
    - _Bug_Condition: Documentation gap, not a runtime defect_
    - _Expected_Behavior: Clear architecture documentation exists in-file for developer reference_
    - _Preservation: No code changes — all existing functionality unchanged_
    - _Requirements: 2.4_

  - [x] 3.5 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Sidebar Left Scroll and Render Defects Fixed
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior for all three bug conditions
    - When this test passes, it confirms:
      - Tables render with visible cells and horizontal scroll at narrow widths
      - StyledListView has an interactive vertical scrollbar
      - Vertical wheel events over code blocks reach the parent ListView
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms all three bugs are fixed)
    - _Requirements: 2.1, 2.2, 2.3_

  - [x] 3.6 Verify preservation tests still pass
    - **Property 2: Preservation** - Existing Scroll, Render, and Session Behavior Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm: horizontal code scroll works, flick/drag scroll works, non-table markdown renders correctly, auto-scroll works, copy/save buttons work, transitions still defined
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [x] 4. Deploy and validate fixes locally
  - Sync repo to deployed config: `rsync -av configs/quickshell/ii/ ~/.config/quickshell/ii/`
  - Restart Quickshell: `systemctl --user restart quickshell`
  - Check logs: `journalctl --user -u quickshell --since "10 sec ago" --no-pager`
  - Manual verification:
    - Open sidebar → send message with markdown table at default width → confirm horizontal scrollbar appears, all column data visible
    - Load long conversation → confirm vertical scrollbar thumb visible and draggable
    - Scroll over a code block → confirm vertical scrolling continues uninterrupted past the code block
    - Scroll horizontally over a wide code block → confirm horizontal scroll still works within the code block
    - Click copy/save buttons on a code block → confirm they still function
    - Send multiple messages → confirm auto-scroll to bottom still works
  - _Note: This is temporary local testing per NixOS workflow. Final deployment requires commit → push → `nix flake update dots-hyprland` → `nixos-rebuild switch`_

- [x] 5. Checkpoint - Ensure all tests pass
  - Ensure all property tests pass (bug condition test passes after fix, preservation tests pass throughout)
  - Ensure no Quickshell runtime errors in journal logs after restart
  - Ensure no visual regressions in the sidebar AI chat
  - Ask the user if questions arise

## Notes

- These are Qt/QML UI bugs requiring a running Quickshell instance for full visual validation
- Property-based testing validates structural correctness (file content, component structure) rather than runtime rendering
- Manual testing is required for visual confirmation of table rendering and scrollbar interaction
- The architecture documentation (task 3.4) is non-functional and can be done in parallel with other fixes
- After all fixes are verified locally, the final deployment path is: commit → push to GitHub → `nix flake update dots-hyprland` in nix-flakes-refactored → `nixos-rebuild switch`
- The horizontal ScrollView wrapper in MessageTextBlock.qml is the highest-risk change — it interacts with LaTeX rendering and markdown text formatting

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1", "2"] },
    { "id": 1, "tasks": ["3.1", "3.2", "3.3", "3.4"] },
    { "id": 2, "tasks": ["3.5", "3.6"] },
    { "id": 3, "tasks": ["4"] },
    { "id": 4, "tasks": ["5"] }
  ]
}
```
