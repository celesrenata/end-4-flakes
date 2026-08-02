# Sidebar Left Bugfixes Design

## Overview

The left sidebar's AI Chat panel has three usability bugs and one documentation gap:

1. **Markdown tables collapse** — Qt's `TextEdit.MarkdownText` renders tables using the internal `QTextDocument` layout engine, which distributes column widths based on the `TextEdit`'s available width. When the sidebar is at or near its minimum width (~450px minus padding), columns with longer header text get zero-width cells because the layout algorithm cannot fit all columns. The fix wraps the `TextArea` in a horizontal `ScrollView`/`Flickable` so that table content can overflow and scroll horizontally, preventing zero-width collapse.

2. **No interactive scrollbar** — `StyledListView` (which extends `ListView`) has no `ScrollBar.vertical` attached. Users can flick/drag to scroll but cannot grab and drag a scrollbar thumb. The fix attaches a styled `ScrollBar.vertical` to the `StyledListView` component.

3. **Code blocks eat vertical scroll** — `MessageCodeBlock`'s inner `ScrollView` (used for horizontal code scrolling) implicitly captures vertical wheel events, preventing them from propagating to the parent `messageListView`. The fix adds a `WheelHandler` that intercepts vertical wheel events and forwards them to the parent `ListView` by adjusting its `contentY` directly, setting `event.accepted = true` so the inner ScrollView doesn't consume them.

4. **Architecture review** — Documentation gap, addressed with a doc comment block in the `Ai.qml` service file.

## Glossary

- **Bug_Condition (C)**: The set of conditions that trigger each visual or interaction defect
- **Property (P)**: The desired behavior when those conditions hold
- **Preservation**: Existing behaviors (mouse clicks, flick scrolling, horizontal code scroll, session management) that must remain unchanged
- **StyledListView**: Reusable `ListView` component at `modules/common/widgets/StyledListView.qml` — animated list with transitions
- **MessageCodeBlock**: Component at `modules/sidebarLeft/aiChat/MessageCodeBlock.qml` — renders fenced code blocks with syntax highlighting
- **MessageTextBlock**: Component at `modules/sidebarLeft/aiChat/MessageTextBlock.qml` — renders markdown text segments including tables
- **messageListView**: The `StyledListView` instance in `AiChat.qml` that displays the conversation history (BottomToTop layout)
- **ScrollBar.vertical (attached)**: Qt Quick Controls property that attaches an interactive scrollbar to any `Flickable`/`ListView`

## Bug Details

### Bug Condition

The bugs manifest across three independent conditions:

1. **Table collapse** — when a markdown table is rendered inside a `TextArea` using `TextEdit.MarkdownText` and the TextArea's effective width is less than the minimum width required by the table's column layout (sum of minimum column content widths).

2. **Missing scrollbar** — always present; `StyledListView` has no `ScrollBar.vertical` attached, so there is never a draggable scrollbar thumb regardless of content length.

3. **Scroll blocking** — when the mouse cursor is positioned over the `ScrollView` inside `MessageCodeBlock` and the user rotates the mouse wheel vertically. The `ScrollView` consumes the vertical wheel event even though `ScrollBar.vertical.policy` is `AlwaysOff`.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type UserInteraction
  OUTPUT: boolean

  // Bug 1: Table collapse
  IF input.type == "markdownRender"
     AND input.content CONTAINS markdownTable
     AND input.containerWidth < tableMinimumLayoutWidth(input.content)
  THEN RETURN true

  // Bug 2: Missing scrollbar
  IF input.type == "scrollAttempt"
     AND input.method == "scrollbarDrag"
     AND input.target == "messageListView"
  THEN RETURN true

  // Bug 3: Scroll blocking on code
  IF input.type == "wheelEvent"
     AND input.direction == "vertical"
     AND input.cursorOver == "MessageCodeBlock.ScrollView"
  THEN RETURN true

  RETURN false
END FUNCTION
```

### Examples

- **Bug 1**: AI responds with a 4-column comparison table (e.g., Quickshell vs AGS). Sidebar is at default width (~450px). The "Widget placement" and "Bluetooth" columns collapse to zero width — only the first column header is visible.
- **Bug 2**: User has a 50-message conversation. They want to jump to the middle. No scrollbar thumb exists to grab. They must flick/drag or use PageUp/PageDown.
- **Bug 3**: User scrolls through messages. Cursor passes over a code block. Scrolling stops. User must move cursor off the code block to continue scrolling.
- **Edge case**: Code block is taller than viewport — user cannot scroll past it at all without moving the cursor outside its bounds.

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Mouse clicks on message actions (copy, save, approve/reject) must continue to work
- Horizontal scrolling within code blocks must continue to work via the existing horizontal scrollbar
- Flick/drag scrolling of the message list must continue to work with existing bounce-back behavior
- Auto-scroll to bottom when new messages arrive must continue to work
- PageUp/PageDown keyboard navigation must continue to work
- Session switching, saving, loading must continue to work
- Inline code, bold, italic, links, and all other non-table markdown formatting must render correctly
- Code block syntax highlighting must continue to work
- LaTeX rendering in MessageTextBlock must continue to work
- The `scrollBehavior` animated contentY behavior on messageListView must continue to work

**Scope:**
All inputs that do NOT involve (1) markdown tables in narrow containers, (2) scrollbar drag interactions on the message list, or (3) vertical wheel events over code blocks should be completely unaffected by these fixes. This includes:
- Horizontal wheel events over code blocks (should still scroll code horizontally)
- Normal markdown text rendering without tables
- Touch/trackpad scrolling gestures
- All chat command processing (/model, /save, /load, etc.)

## Hypothesized Root Cause

Based on code analysis:

1. **Table Collapse** — `MessageTextBlock.qml` renders content in a `TextArea` with `wrapMode: TextEdit.Wrap` and `Layout.fillWidth: true`. When `textFormat` is `MarkdownText`, Qt's internal markdown-to-rich-text converter creates a `QTextTable`. The `QTextDocument` layout engine distributes column widths proportionally within the available width. When the available width is too small, some columns get rounded down to zero. There is no overflow/scroll mechanism — the TextArea is the full width of the message bubble.

2. **Missing Scrollbar** — `StyledListView.qml` defines transitions and layout properties but never attaches `ScrollBar.vertical`. The `ListView` base type supports it via the `Flickable` attached property, but it's simply never declared.

3. **Scroll Blocking on Code** — `MessageCodeBlock.qml` uses a `ScrollView` (line ~180) for horizontal code scrolling. Even though `ScrollBar.vertical.policy: ScrollBar.AlwaysOff` is set, the `ScrollView`'s internal `Flickable` still accepts vertical wheel events (setting `event.accepted = true` by default), preventing propagation to the parent `messageListView`. The commented-out `MouseArea` at the bottom of the file (lines ~244-251) was a previous attempt to solve this but was disabled.

4. **Architecture Review** — No formal documentation exists for the chat lifecycle (session creation → message flow → context compaction → session persistence). The `Ai.qml` service is ~3000 lines with no module-level architecture doc.

## Correctness Properties

Property 1: Bug Condition - Markdown Tables Remain Readable at Narrow Widths

_For any_ markdown content containing a table rendered in a `MessageTextBlock` where the sidebar width is at or near minimum, the fixed component SHALL render all table cell content visibly, allowing horizontal scroll to access overflowing columns rather than collapsing them to zero width.

**Validates: Requirements 2.1**

Property 2: Bug Condition - Interactive Scrollbar Present on Message List

_For any_ state where the message list content height exceeds the viewport height, the fixed `StyledListView` SHALL display an interactive vertical scrollbar that responds to mouse drag for position-based navigation.

**Validates: Requirements 2.2**

Property 3: Bug Condition - Vertical Wheel Events Propagate Past Code Blocks

_For any_ vertical wheel event occurring while the cursor is over a `MessageCodeBlock`, the fixed component SHALL forward the vertical scroll delta to the parent message list, allowing uninterrupted vertical scrolling.

**Validates: Requirements 2.3**

Property 4: Preservation - Existing Scroll and Rendering Behavior

_For any_ input where none of the three bug conditions hold (non-table markdown, flick/drag scrolling, horizontal code scroll, session management, auto-scroll), the fixed code SHALL produce exactly the same behavior as the original code, preserving all existing functionality.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**

## Fix Implementation

### Changes Required

**File**: `modules/common/widgets/StyledListView.qml`

**Change: Add vertical ScrollBar**

Add a `ScrollBar.vertical` attached property with styling consistent with the project's existing horizontal scrollbar pattern (seen in `MessageCodeBlock.qml` and `MessageToolBlock.qml`):

```qml
ScrollBar.vertical: ScrollBar {
    padding: 3
    policy: ScrollBar.AsNeeded
    opacity: active || size < 1 ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    contentItem: Rectangle {
        implicitWidth: 6
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2Active
    }
}
```

---

**File**: `modules/sidebarLeft/aiChat/MessageCodeBlock.qml`

**Change: Add WheelHandler to forward vertical scroll events**

Add a `WheelHandler` on the code block's outer `Rectangle` (the code background container) that intercepts vertical wheel events and forwards them to the parent `ListView`. The key insight from Qt documentation: setting `event.accepted = true` in a `WheelHandler`'s `onWheel` signal prevents the event from reaching the inner `ScrollView`, while we manually adjust the parent list's `contentY`.

The approach: add a `MouseArea` overlay (with `acceptedButtons: Qt.NoButton`) that has an `onWheel` handler which:
1. Detects vertical scroll (angleDelta.y != 0)
2. Forwards the delta to the parent ListView by adjusting contentY
3. Accepts the event to prevent the inner ScrollView from consuming it

```qml
// Inside the RowLayout's second Rectangle (code background), over the ScrollView
MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    onWheel: (event) => {
        // Forward vertical scroll to parent message list
        if (event.angleDelta.y !== 0) {
            const listView = root.ListView.view
            if (listView) {
                listView.contentY -= event.angleDelta.y
                listView.returnToBounds()
            }
            event.accepted = true
        } else {
            event.accepted = false
        }
    }
}
```

Note: Since the `ScrollView` has `ScrollBar.vertical.policy: ScrollBar.AlwaysOff`, the vertical scrolling within the code block is never needed anyway. We only need to preserve horizontal wheel events (which have `angleDelta.x != 0`).

---

**File**: `modules/sidebarLeft/aiChat/MessageTextBlock.qml`

**Change: Wrap TextArea in horizontal ScrollView for table overflow**

Wrap the `TextArea` in a `ScrollView` that allows horizontal scrolling when table content overflows. Set `contentWidth` to the TextArea's `implicitWidth` so that when a markdown table needs more space than the container provides, horizontal scrolling becomes available:

```qml
ScrollView {
    Layout.fillWidth: true
    contentWidth: Math.max(availableWidth, textArea.implicitWidth)
    clip: true
    ScrollBar.vertical.policy: ScrollBar.AlwaysOff
    ScrollBar.horizontal.policy: textArea.implicitWidth > width ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

    TextArea {
        id: textArea
        // ... existing properties ...
        wrapMode: TextEdit.Wrap
    }
}
```

However, this approach has a risk: `wrapMode: TextEdit.Wrap` combined with a `ScrollView` may not correctly report the implicit width needed for tables. An alternative approach is to detect when the content contains a table and conditionally disable wrap mode or set a minimum width:

**Alternative (preferred)**: Set `implicitWidth` to `Math.max(parent.width, contentWidth)` on the TextArea, or disable `wrapMode` for table-containing content. Since table detection in rendered MarkdownText is unreliable from QML, the simpler approach is to always allow horizontal overflow by wrapping in a Flickable/ScrollView and letting the TextArea report its natural width.

The cleanest solution: wrap the TextArea in a `Flickable` with a horizontal `ScrollBar` that only appears when needed, and remove `wrapMode: TextEdit.Wrap` only when rendering results in zero-width columns (which is hard to detect). The pragmatic fix is:

1. Wrap the TextArea in a `ScrollView`
2. Keep `wrapMode: TextEdit.Wrap` for normal text
3. Set the ScrollView's `contentWidth` to the TextArea's `contentWidth` property
4. The horizontal scrollbar appears only when the internal document layout (tables) exceeds the available width

---

**File**: `services/Ai.qml`

**Change: Add architecture documentation header**

Add a module-level doc comment at the top of `Ai.qml` describing the chat system architecture:
- Session lifecycle (creation, switching, persistence, deletion)
- Message flow (user input → API request → streaming response → message storage)
- Context management (token estimation, context ratio, auto-compact threshold)
- Message versioning (session switch forces view refresh via `messageVersion`)
- Persistence model (sessions index file + per-session message files)

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, confirm the bugs exist on unfixed code via visual inspection and manual testing (since these are Qt rendering/event bugs that require a running Quickshell instance), then verify the fixes work correctly and preserve existing behavior.

### Exploratory Bug Condition Checking

**Goal**: Confirm each bug exists on the current unfixed code before applying changes.

**Test Plan**: Deploy current code, open the sidebar, and exercise each bug condition. Document the observed failures.

**Test Cases**:
1. **Table Collapse Test**: Send `/test` command which renders a markdown table. Observe that columns collapse at default sidebar width (will show zero-width columns on unfixed code)
2. **Missing Scrollbar Test**: Load a long conversation (or send multiple messages). Observe that no scrollbar thumb appears even when content exceeds viewport (will confirm no scrollbar on unfixed code)
3. **Code Block Scroll Block Test**: Send `/test` command which includes a code block. Position cursor over the code block and scroll vertically. Observe that scrolling stops (will confirm scroll blocking on unfixed code)
4. **Horizontal Scroll Preservation Test**: Position cursor over a wide code block and scroll horizontally. Confirm it works (establishes baseline for preservation)

**Expected Counterexamples**:
- Table columns rendered with zero width at narrow sidebar widths
- No scrollbar element visible or interactable in the message list
- Vertical scroll events consumed by code block's ScrollView

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed components produce the expected behavior.

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := renderComponent_fixed(input)
  ASSERT expectedBehavior(result)
END FOR
```

Specifically:
- After fix: markdown tables at narrow width should show a horizontal scrollbar or maintain visible column content
- After fix: message list should show a draggable vertical scrollbar when content exceeds viewport
- After fix: vertical wheel events over code blocks should scroll the parent list

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed components produce the same result as the original.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT renderComponent_original(input) = renderComponent_fixed(input)
END FOR
```

**Testing Approach**: Manual testing is primary for Qt/QML UI bugs since there is no headless QML test runner configured in this project. Property-based testing applies to the logic layer (e.g., session management) but not to the rendering layer.

**Test Cases**:
1. **Horizontal Code Scroll Preservation**: Verify that horizontal scrolling within code blocks still works after the WheelHandler is added
2. **Flick/Drag Scroll Preservation**: Verify that flick/drag scrolling of the message list continues to work with the new ScrollBar attached
3. **Auto-Scroll Preservation**: Verify that auto-scroll to bottom on new messages continues when the ScrollBar is present
4. **Markdown Rendering Preservation**: Verify that inline code, bold, italic, links render correctly in MessageTextBlock after the ScrollView wrapper is added
5. **Session Management Preservation**: Verify /new, /switch, /save, /load, /delete commands still work correctly (should be unaffected)

### Unit Tests

- Verify that the WheelHandler in MessageCodeBlock only intercepts vertical events (angleDelta.y != 0) and passes through horizontal events
- Verify that the ScrollBar appears when contentHeight > height and disappears otherwise
- Verify that the MessageTextBlock ScrollView correctly reports contentWidth matching the TextArea's internal document width

### Property-Based Tests

- Generate random markdown content (with and without tables) and verify that MessageTextBlock never renders zero-width columns when wrapped in a ScrollView
- Generate random wheel event sequences (vertical and horizontal) over code blocks and verify vertical events reach the parent list while horizontal events still scroll the code
- Generate random conversation lengths and verify the scrollbar thumb size is proportional to visible/total content ratio

### Integration Tests

- Full conversation flow: send messages with tables, code blocks, and plain text — verify all three render correctly and scrolling works throughout
- Session switching with scrollbar: switch sessions and verify scrollbar resets to bottom position
- Resize sidebar while viewing tables: verify table remains readable (scrollbar appears/disappears appropriately)
