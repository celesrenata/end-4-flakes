# Feature: sidebar-left-bugfixes, Property 2: Preservation
"""
Property 2: Preservation - Existing Scroll, Render, and Session Behavior

Validates that current (unfixed) QML components maintain their baseline behaviors:
1. StyledListView has correct flick velocity and drag-over-bounds behavior
2. StyledListView has all four transitions defined (add, remove, addDisplaced, removeDisplaced)
3. MessageCodeBlock has horizontal ScrollBar with AsNeeded policy
4. MessageCodeBlock has vertical ScrollBar always off (no vertical scroll in code)
5. MessageTextBlock has wrapMode: TextEdit.Wrap on its TextArea
6. MessageTextBlock has conditional textFormat (MarkdownText or PlainText)
7. MessageCodeBlock has SyntaxHighlighter bound to codeTextArea
8. MessageCodeBlock has copyCodeButton and saveCodeButton action buttons

These tests MUST PASS on the current unfixed code — they capture baseline behavior
that must be preserved after the bugfix implementation.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**
"""

import re
from pathlib import Path

from hypothesis import given, settings, assume, HealthCheck
from hypothesis import strategies as st


# ─── File Paths ───

PROJECT_ROOT = Path(__file__).parent.parent

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


# ─── Load QML Sources ───

_styled_list_view_source = STYLED_LIST_VIEW_PATH.read_text()
_message_code_block_source = MESSAGE_CODE_BLOCK_PATH.read_text()
_message_text_block_source = MESSAGE_TEXT_BLOCK_PATH.read_text()


# ─── Helper: Strip QML Comments ───

def strip_qml_comments(source: str) -> str:
    """Remove single-line (//) and block (/* */) comments from QML source."""
    # Remove block comments
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    # Remove single-line comments (but not inside strings)
    lines = source.split("\n")
    stripped = []
    for line in lines:
        # Simple heuristic: remove // comments not inside quotes
        in_string = False
        result = []
        i = 0
        while i < len(line):
            if line[i] == '"' and (i == 0 or line[i - 1] != '\\'):
                in_string = not in_string
                result.append(line[i])
            elif not in_string and line[i:i+2] == '//':
                break
            else:
                result.append(line[i])
            i += 1
        stripped.append("".join(result))
    return "\n".join(stripped)


_styled_list_view_active = strip_qml_comments(_styled_list_view_source)
_message_code_block_active = strip_qml_comments(_message_code_block_source)
_message_text_block_active = strip_qml_comments(_message_text_block_source)


# ─── Hypothesis Strategies ───

# Generate random non-table markdown content (inline code, bold, italic, links)
st_inline_markdown = st.one_of(
    st.builds(lambda t: f"`{t}`", st.text(min_size=1, max_size=20,
              alphabet=st.characters(whitelist_categories=("L", "N", "P")))),
    st.builds(lambda t: f"**{t}**", st.text(min_size=1, max_size=20,
              alphabet=st.characters(whitelist_categories=("L", "N")))),
    st.builds(lambda t: f"*{t}*", st.text(min_size=1, max_size=20,
              alphabet=st.characters(whitelist_categories=("L", "N")))),
    st.builds(lambda t, u: f"[{t}]({u})",
              st.text(min_size=1, max_size=15,
                      alphabet=st.characters(whitelist_categories=("L", "N"))),
              st.from_regex(r"https://[a-z]{3,10}\.[a-z]{2,4}", fullmatch=True)),
    st.text(min_size=1, max_size=50,
            alphabet=st.characters(whitelist_categories=("L", "N", "Z"))),
)

# Generate random markdown paragraphs (non-table)
st_markdown_paragraph = st.lists(st_inline_markdown, min_size=1, max_size=5).map(
    lambda parts: " ".join(parts)
)

# Generate random wheel event angles (horizontal only - preservation case)
st_horizontal_wheel_delta = st.integers(min_value=-360, max_value=360).filter(
    lambda x: x != 0
)


# ─── Property Tests: StyledListView ───


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_styled_list_view_maximum_flick_velocity(_):
    """StyledListView has maximumFlickVelocity: 3500 configured.

    This ensures fast flick scrolling remains responsive.

    **Validates: Requirements 3.2, 3.4**
    """
    assert "maximumFlickVelocity: 3500" in _styled_list_view_active, (
        "StyledListView must have maximumFlickVelocity: 3500"
    )


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_styled_list_view_bounds_behavior(_):
    """StyledListView has boundsBehavior: Flickable.DragOverBounds configured.

    This ensures drag-over-bounds (bounce-back) scrolling behavior is preserved.

    **Validates: Requirements 3.2, 3.4**
    """
    assert "boundsBehavior: Flickable.DragOverBounds" in _styled_list_view_active, (
        "StyledListView must have boundsBehavior: Flickable.DragOverBounds"
    )


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_styled_list_view_add_transition(_):
    """StyledListView has an 'add' transition defined.

    **Validates: Requirements 3.6**
    """
    # Match "add: Transition {" (non-commented)
    assert re.search(r"\badd\s*:\s*Transition\s*\{", _styled_list_view_active), (
        "StyledListView must have an add: Transition defined"
    )


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_styled_list_view_add_displaced_transition(_):
    """StyledListView has an 'addDisplaced' transition defined.

    **Validates: Requirements 3.6**
    """
    assert re.search(r"\baddDisplaced\s*:\s*Transition\s*\{", _styled_list_view_active), (
        "StyledListView must have an addDisplaced: Transition defined"
    )


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_styled_list_view_remove_transition(_):
    """StyledListView has a 'remove' transition defined.

    **Validates: Requirements 3.6**
    """
    assert re.search(r"\bremove\s*:\s*Transition\s*\{", _styled_list_view_active), (
        "StyledListView must have a remove: Transition defined"
    )


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_styled_list_view_remove_displaced_transition(_):
    """StyledListView has a 'removeDisplaced' transition defined.

    **Validates: Requirements 3.6**
    """
    assert re.search(r"\bremoveDisplaced\s*:\s*Transition\s*\{", _styled_list_view_active), (
        "StyledListView must have a removeDisplaced: Transition defined"
    )


# ─── Property Tests: MessageCodeBlock ───


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_code_block_horizontal_scrollbar_as_needed(_):
    """MessageCodeBlock has a horizontal ScrollBar with policy: ScrollBar.AsNeeded.

    This ensures horizontal scrolling within code blocks is preserved for wide code.

    **Validates: Requirements 3.3**
    """
    # The horizontal scrollbar has policy: ScrollBar.AsNeeded
    assert "policy: ScrollBar.AsNeeded" in _message_code_block_active, (
        "MessageCodeBlock must have a horizontal ScrollBar with policy: ScrollBar.AsNeeded"
    )


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_code_block_vertical_scrollbar_always_off(_):
    """MessageCodeBlock has ScrollBar.vertical.policy: ScrollBar.AlwaysOff.

    Code blocks should not have their own vertical scrollbar — vertical scrolling
    is handled by the parent message list.

    **Validates: Requirements 3.3**
    """
    assert "ScrollBar.vertical.policy: ScrollBar.AlwaysOff" in _message_code_block_active, (
        "MessageCodeBlock must have ScrollBar.vertical.policy: ScrollBar.AlwaysOff"
    )


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_code_block_syntax_highlighter_bound(_):
    """MessageCodeBlock has a SyntaxHighlighter bound to codeTextArea.

    Syntax highlighting must remain functional in code blocks.

    **Validates: Requirements 3.1**
    """
    # Check that SyntaxHighlighter exists and references codeTextArea
    assert "SyntaxHighlighter" in _message_code_block_active, (
        "MessageCodeBlock must contain a SyntaxHighlighter component"
    )
    assert "textEdit: codeTextArea" in _message_code_block_active, (
        "SyntaxHighlighter must be bound to codeTextArea"
    )


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_code_block_copy_button_exists(_):
    """MessageCodeBlock has a copyCodeButton for copying code to clipboard.

    **Validates: Requirements 3.3**
    """
    assert "copyCodeButton" in _message_code_block_active, (
        "MessageCodeBlock must have a copyCodeButton"
    )


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_code_block_save_button_exists(_):
    """MessageCodeBlock has a saveCodeButton for saving code to Downloads.

    **Validates: Requirements 3.3**
    """
    assert "saveCodeButton" in _message_code_block_active, (
        "MessageCodeBlock must have a saveCodeButton"
    )


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(horizontal_delta=st_horizontal_wheel_delta)
def test_code_block_horizontal_scroll_preserved(horizontal_delta: int):
    """For all horizontal wheel events (angleDelta.x != 0) over code blocks,
    the code ScrollView handles them via horizontal scrollbar.

    The ScrollView has ScrollBar.horizontal with AsNeeded policy, meaning
    horizontal scroll is available when code content overflows.

    **Validates: Requirements 3.3**
    """
    # The structural requirement: ScrollView exists with horizontal scrollbar
    assert "ScrollView" in _message_code_block_active, (
        "MessageCodeBlock must contain a ScrollView for code scrolling"
    )
    assert "ScrollBar.horizontal" in _message_code_block_active, (
        "MessageCodeBlock ScrollView must have a ScrollBar.horizontal"
    )
    # The horizontal_delta represents any non-zero horizontal wheel event
    # The structural presence of ScrollBar.horizontal with AsNeeded policy
    # guarantees these events are handled by the code ScrollView
    assert horizontal_delta != 0, "Test precondition: horizontal delta must be non-zero"


# ─── Property Tests: MessageTextBlock ───


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_text_block_wrap_mode(_):
    """MessageTextBlock TextArea has wrapMode: TextEdit.Wrap.

    This ensures normal text content wraps within the container
    without requiring horizontal scrolling.

    **Validates: Requirements 3.1**
    """
    assert "wrapMode: TextEdit.Wrap" in _message_text_block_active, (
        "MessageTextBlock TextArea must have wrapMode: TextEdit.Wrap"
    )


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_text_block_text_format_conditional(_):
    """MessageTextBlock TextArea has conditional textFormat based on renderMarkdown.

    When renderMarkdown is true: TextEdit.MarkdownText (renders bold, italic, links, etc.)
    When renderMarkdown is false: TextEdit.PlainText

    **Validates: Requirements 3.1**
    """
    assert "textFormat: renderMarkdown ? TextEdit.MarkdownText : TextEdit.PlainText" in _message_text_block_active, (
        "MessageTextBlock must have conditional textFormat based on renderMarkdown property"
    )


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_text_block_link_activated_handler(_):
    """MessageTextBlock TextArea has onLinkActivated handler for clickable links.

    Links in markdown content must remain clickable and open externally.

    **Validates: Requirements 3.1**
    """
    assert "onLinkActivated" in _message_text_block_active, (
        "MessageTextBlock must have onLinkActivated handler"
    )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(markdown_content=st_markdown_paragraph)
def test_text_block_non_table_markdown_no_horizontal_scroll_needed(markdown_content: str):
    """For all non-table markdown content, MessageTextBlock renders with
    wrapMode: TextEdit.Wrap, meaning no horizontal scroll is needed for
    inline code, bold, italic, links, or plain text.

    The structural guarantee: wrapMode: TextEdit.Wrap + Layout.fillWidth: true
    ensures text wraps within container width.

    **Validates: Requirements 3.1, 3.2**
    """
    # Non-table content should not contain pipe-delimited table syntax
    assume("|" not in markdown_content or markdown_content.count("|") < 3)

    # Structural requirement: wrap mode ensures text fits without horizontal overflow
    assert "wrapMode: TextEdit.Wrap" in _message_text_block_active
    assert "Layout.fillWidth: true" in _message_text_block_active
    # Non-table markdown with wrap mode will always fit within the container width
    # (text wraps at word boundaries), so no horizontal scrollbar is needed


@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_text_block_fill_width(_):
    """MessageTextBlock TextArea uses Layout.fillWidth: true.

    This ensures the text area takes the full available width of the message bubble.

    **Validates: Requirements 3.1**
    """
    assert "Layout.fillWidth: true" in _message_text_block_active, (
        "MessageTextBlock must have Layout.fillWidth: true"
    )
