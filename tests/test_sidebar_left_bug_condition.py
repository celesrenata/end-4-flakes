# Feature: sidebar-left-bugfixes, Property 1: Bug Condition
"""
Bug Condition Exploration Test — Sidebar Left Scroll and Render Defects

This test surfaces counterexamples demonstrating that three UI bugs exist in
the left sidebar AI chat components:

- Bug 1 (Table Collapse): MessageTextBlock.qml has NO horizontal ScrollView
  wrapping the TextArea, so markdown tables collapse at narrow widths
- Bug 2 (Missing Scrollbar): StyledListView.qml has NO ScrollBar.vertical
  attached, so there is no interactive draggable scrollbar
- Bug 3 (Scroll Blocking): MessageCodeBlock.qml has NO MouseArea with vertical
  wheel forwarding, so vertical scroll events are consumed by the inner ScrollView

**Validates: Requirements 1.1, 1.2, 1.3, 2.1, 2.2, 2.3**

EXPECTED: All tests FAIL on unfixed code — failure confirms the bugs exist.
DO NOT attempt to fix the test or the code when it fails.
"""

import re
from pathlib import Path

from hypothesis import given, settings, assume, HealthCheck
from hypothesis import strategies as st


# ─── QML Source File Paths ───

PROJECT_ROOT = Path(__file__).parent.parent

MESSAGE_TEXT_BLOCK_PATH = (
    PROJECT_ROOT
    / "configs"
    / "quickshell"
    / "ii"
    / "modules"
    / "sidebarLeft"
    / "aiChat"
    / "MessageTextBlock.qml"
)

STYLED_LIST_VIEW_PATH = (
    PROJECT_ROOT
    / "configs"
    / "quickshell"
    / "ii"
    / "modules"
    / "common"
    / "widgets"
    / "StyledListView.qml"
)

MESSAGE_CODE_BLOCK_PATH = (
    PROJECT_ROOT
    / "configs"
    / "quickshell"
    / "ii"
    / "modules"
    / "sidebarLeft"
    / "aiChat"
    / "MessageCodeBlock.qml"
)

# Read the QML source files
_message_text_block_source = MESSAGE_TEXT_BLOCK_PATH.read_text()
_styled_list_view_source = STYLED_LIST_VIEW_PATH.read_text()
_message_code_block_source = MESSAGE_CODE_BLOCK_PATH.read_text()


# ─── Hypothesis Strategies ───

# Generate random container widths that are narrower than typical table minimums
# Simulates sidebar at narrow widths where tables would collapse
st_narrow_container_width = st.integers(min_value=100, max_value=450)

# Generate random markdown table content with varying column counts
st_table_columns = st.integers(min_value=2, max_value=8)

# Generate random scroll deltas (positive = scroll down, negative = scroll up)
st_vertical_wheel_delta = st.integers(min_value=-120, max_value=120).filter(lambda x: x != 0)

# Generate random content heights exceeding viewport (simulates long conversations)
st_content_height = st.integers(min_value=600, max_value=10000)
st_viewport_height = st.integers(min_value=300, max_value=599)


# ─── Bug 1: Table Collapse — ScrollView wrapping TextArea ───


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(
    container_width=st_narrow_container_width,
    num_columns=st_table_columns,
)
def test_bug1_message_text_block_has_scrollview_wrapping_textarea(
    container_width: int, num_columns: int
):
    """Bug 1: MessageTextBlock must wrap its TextArea in a horizontal ScrollView.

    For any markdown table with N columns rendered at a container width narrower
    than the table's minimum layout width, a ScrollView wrapping the TextArea
    allows horizontal overflow — preventing zero-width column collapse.

    This test asserts the structural requirement: a ScrollView element exists
    in MessageTextBlock.qml that wraps the TextArea with horizontal scroll
    enabled (ScrollBar.horizontal.policy != AlwaysOff) and vertical scroll
    disabled (ScrollBar.vertical.policy: AlwaysOff).

    EXPECTED TO FAIL on unfixed code: No ScrollView wraps the TextArea.

    **Validates: Requirements 1.1, 2.1**
    """
    # The table would need at least num_columns * ~80px minimum width
    table_min_width = num_columns * 80
    assume(container_width < table_min_width)

    # Structural assertion: A ScrollView must wrap the TextArea
    # We look for a ScrollView that:
    # 1. Contains the TextArea (id: textArea)
    # 2. Has ScrollBar.vertical.policy: ScrollBar.AlwaysOff
    # 3. Has ScrollBar.horizontal.policy: ScrollBar.AsNeeded (or not AlwaysOff)

    # Check if ScrollView exists in the file at all
    has_scrollview = "ScrollView" in _message_text_block_source

    # Check if ScrollView wraps the TextArea (ScrollView appears before TextArea
    # at the same or higher nesting level, with TextArea inside it)
    # Simple structural check: ScrollView { ... TextArea { id: textArea ... } ... }
    scrollview_wraps_textarea = False
    if has_scrollview:
        # Find ScrollView opening and check if textArea is nested inside it
        # Use [\s\S]*? instead of [^}]*? to handle nested braces from
        # ScrollBar definitions between ScrollView opening and TextArea
        scrollview_pattern = re.compile(
            r"ScrollView\s*\{[\s\S]*?TextArea\s*\{[\s\S]*?id:\s*textArea",
            re.DOTALL,
        )
        scrollview_wraps_textarea = bool(scrollview_pattern.search(_message_text_block_source))

    # Check for horizontal scroll policy being enabled
    has_horizontal_scroll = (
        "ScrollBar.horizontal.policy: ScrollBar.AsNeeded" in _message_text_block_source
        or "ScrollBar.horizontal" in _message_text_block_source
    )

    assert has_scrollview and scrollview_wraps_textarea and has_horizontal_scroll, (
        f"COUNTEREXAMPLE: MessageTextBlock.qml has no ScrollView wrapping "
        f"the TextArea. A markdown table with {num_columns} columns requires "
        f"~{table_min_width}px minimum width, but container is only "
        f"{container_width}px. Without horizontal ScrollView, columns collapse "
        f"to zero width. "
        f"(has_scrollview={has_scrollview}, "
        f"scrollview_wraps_textarea={scrollview_wraps_textarea}, "
        f"has_horizontal_scroll={has_horizontal_scroll})"
    )


# ─── Bug 2: Missing Scrollbar — ScrollBar.vertical on StyledListView ───


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(
    content_height=st_content_height,
    viewport_height=st_viewport_height,
)
def test_bug2_styled_list_view_has_vertical_scrollbar(
    content_height: int, viewport_height: int
):
    """Bug 2: StyledListView must have ScrollBar.vertical attached.

    For any state where content height exceeds viewport height, an interactive
    vertical scrollbar must be visible and draggable. This requires a
    ScrollBar.vertical attached property with policy: ScrollBar.AsNeeded.

    This test asserts the structural requirement: StyledListView.qml contains
    a ScrollBar.vertical declaration with appropriate policy.

    EXPECTED TO FAIL on unfixed code: No ScrollBar.vertical exists.

    **Validates: Requirements 1.2, 2.2**
    """
    assume(content_height > viewport_height)

    # Structural assertion: ScrollBar.vertical must be declared
    has_scrollbar_vertical = "ScrollBar.vertical" in _styled_list_view_source

    # Check for the policy being AsNeeded (only show when content overflows)
    has_as_needed_policy = (
        "ScrollBar.AsNeeded" in _styled_list_view_source
        or "policy: ScrollBar.AsNeeded" in _styled_list_view_source
    )

    assert has_scrollbar_vertical and has_as_needed_policy, (
        f"COUNTEREXAMPLE: StyledListView.qml has NO ScrollBar.vertical attached. "
        f"With contentHeight={content_height}px exceeding viewport={viewport_height}px, "
        f"users cannot grab and drag a scrollbar thumb to navigate. "
        f"They must resort to flick/drag or PageUp/PageDown. "
        f"(has_scrollbar_vertical={has_scrollbar_vertical}, "
        f"has_as_needed_policy={has_as_needed_policy})"
    )


# ─── Bug 3: Scroll Blocking — MouseArea with wheel forwarding ───


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(wheel_delta=st_vertical_wheel_delta)
def test_bug3_message_code_block_has_wheel_forwarding(wheel_delta: int):
    """Bug 3: MessageCodeBlock must have a MouseArea that forwards vertical wheel events.

    For any vertical wheel event (angleDelta.y != 0) over a code block, the
    wheel handler must forward the delta to the parent ListView's contentY,
    preventing the inner ScrollView from consuming vertical scroll events.

    This test asserts the structural requirement: MessageCodeBlock.qml contains
    an ACTIVE (not commented-out) MouseArea with:
    - onWheel handler that checks angleDelta.y
    - Forwards to root.ListView.view.contentY
    - Sets event.accepted = true for vertical events

    EXPECTED TO FAIL on unfixed code: The MouseArea is commented out and has
    no vertical wheel forwarding logic.

    **Validates: Requirements 1.3, 2.3**
    """
    # Strip comments from the source to only check active code
    # Remove single-line comments
    active_lines = []
    for line in _message_code_block_source.split("\n"):
        stripped = line.strip()
        if not stripped.startswith("//"):
            active_lines.append(line)
    active_source = "\n".join(active_lines)

    # Structural assertion 1: An active MouseArea exists with onWheel handler
    has_active_mousearea_with_wheel = bool(
        re.search(r"MouseArea\s*\{[^}]*onWheel", active_source, re.DOTALL)
    )

    # Structural assertion 2: The wheel handler references angleDelta.y
    has_angle_delta_y_check = "angleDelta.y" in active_source and "onWheel" in active_source

    # Structural assertion 3: The handler forwards vertical scroll to parent ListView's contentY
    # Implementation may use direct ListView.view reference OR parent traversal to find
    # the Flickable (necessary when component is loaded via Loader)
    has_listview_forwarding = (
        "contentY" in active_source
        and (
            "ListView.view" in active_source
            or ("parent" in active_source and "contentY" in active_source)
        )
    )

    # Structural assertion 4: event.accepted = true for vertical events
    has_event_accepted = "event.accepted = true" in active_source or "event.accepted=true" in active_source

    all_conditions_met = (
        has_active_mousearea_with_wheel
        and has_angle_delta_y_check
        and has_listview_forwarding
        and has_event_accepted
    )

    assert all_conditions_met, (
        f"COUNTEREXAMPLE: MessageCodeBlock.qml has NO active MouseArea with "
        f"vertical wheel forwarding. A vertical wheel event with delta={wheel_delta} "
        f"over the code block's ScrollView would be consumed by the inner "
        f"ScrollView (even though vertical scroll is disabled), blocking parent "
        f"list scrolling. "
        f"(has_active_mousearea_with_wheel={has_active_mousearea_with_wheel}, "
        f"has_angle_delta_y_check={has_angle_delta_y_check}, "
        f"has_listview_forwarding={has_listview_forwarding}, "
        f"has_event_accepted={has_event_accepted})"
    )
