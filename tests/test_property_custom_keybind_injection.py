# Feature: upstream-sync-2025-2026, Property 4: Custom Keybind Injection
"""
Property 4: Custom Keybind Injection

For any string value substituted for @CUSTOM_KEYBINDS@, the processed keybind
configuration SHALL contain that exact string content at the designated injection
point, after all other bind declarations.

**Validates: Requirements 20.3**
"""

import os
import re
from pathlib import Path

import hypothesis
from hypothesis import given, settings, assume
import hypothesis.strategies as st

# Path to the real template
TEMPLATE_PATH = Path(__file__).parent.parent / "configs" / "hypr" / "keybinds.conf.template"

# Read the template once at module level
TEMPLATE_CONTENT = TEMPLATE_PATH.read_text()

# Regex to find @VARIABLE@ placeholders (excluding @CUSTOM_KEYBINDS@)
PLACEHOLDER_PATTERN = re.compile(r"@[A-Z_]+@")


def get_other_placeholders(template: str) -> set[str]:
    """Extract all @VAR@ placeholders except @CUSTOM_KEYBINDS@."""
    all_placeholders = set(PLACEHOLDER_PATTERN.findall(template))
    all_placeholders.discard("@CUSTOM_KEYBINDS@")
    return all_placeholders


# Strategy for generating keybind-like characters
keybind_chars = st.characters(
    whitelist_categories=("L", "N", "P", "Z"),
    whitelist_characters=",+=_-/. @#!",
)

# Strategy for a single keybind line
keybind_line = st.sampled_from(["bind", "bindd", "binde", "bindl", "bindle"]).flatmap(
    lambda prefix: st.tuples(
        st.sampled_from(["Super", "Super+Shift", "Super+Ctrl", "Alt", "Ctrl+Alt", "Super+Alt"]),
        st.sampled_from(
            ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
             "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
             "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
             "Return", "Space", "Tab", "Escape", "code:87", "code:88"]
        ),
        st.text(alphabet=keybind_chars, min_size=1, max_size=50),
    ).map(lambda t: f"{prefix} = {t[0]}, {t[1]}, exec, {t[2]}")
)

# Strategy for multi-line keybind blocks (1-10 lines)
keybind_block = st.lists(keybind_line, min_size=1, max_size=10).map(
    lambda lines: "\n".join(lines)
)

# Strategy for arbitrary text content (to test the general substitution property)
arbitrary_content = st.text(
    alphabet=st.characters(
        whitelist_categories=("L", "N", "P", "Z", "S"),
        whitelist_characters=",+=_-/. @#!$%^&*(){}[]|\\:;\"'<>?~`\n\t",
    ),
    min_size=0,
    max_size=500,
)


def substitute_custom_keybinds(template: str, custom: str) -> str:
    """Substitute @CUSTOM_KEYBINDS@ with the given custom keybind string."""
    return template.replace("@CUSTOM_KEYBINDS@", custom)


@settings(max_examples=100)
@given(custom_keybinds=keybind_block)
def test_injection_presence(custom_keybinds: str):
    """After substitution, the generated keybind string appears verbatim in the result.

    **Validates: Requirements 20.3**
    """
    result = substitute_custom_keybinds(TEMPLATE_CONTENT, custom_keybinds)
    assert custom_keybinds in result, (
        f"Custom keybinds not found in substituted output.\n"
        f"Expected to find:\n{custom_keybinds!r}"
    )


@settings(max_examples=100)
@given(custom_keybinds=keybind_block)
def test_injection_position(custom_keybinds: str):
    """The injected content appears after all other bind declarations in the template.

    **Validates: Requirements 20.3**
    """
    result = substitute_custom_keybinds(TEMPLATE_CONTENT, custom_keybinds)

    # Find the position of the injected content
    inject_pos = result.find(custom_keybinds)
    assert inject_pos >= 0, "Custom keybinds not found in result"

    # Find the last bind declaration BEFORE the injection point
    # The @CUSTOM_KEYBINDS@ placeholder is at the end of the template,
    # so our injected content should come after the last original bind line
    lines_before_injection = result[:inject_pos].rstrip().split("\n")

    # Get all bind lines in the original template (before the placeholder)
    template_before_placeholder = TEMPLATE_CONTENT.split("@CUSTOM_KEYBINDS@")[0]
    original_bind_lines = [
        line for line in template_before_placeholder.split("\n")
        if re.match(r"^bind", line.strip())
    ]

    # All original bind lines should appear before the injection point
    if original_bind_lines:
        last_original_bind = original_bind_lines[-1]
        last_bind_pos = result.find(last_original_bind)
        assert last_bind_pos < inject_pos, (
            f"Injection point ({inject_pos}) is not after last original bind ({last_bind_pos})"
        )


@settings(max_examples=100)
@given(custom_keybinds=keybind_block)
def test_other_placeholders_preserved(custom_keybinds: str):
    """No other @VAR@ patterns are affected by the @CUSTOM_KEYBINDS@ injection.

    **Validates: Requirements 20.3**
    """
    # Get placeholders from original template (excluding @CUSTOM_KEYBINDS@)
    original_placeholders = get_other_placeholders(TEMPLATE_CONTENT)

    # Perform substitution
    result = substitute_custom_keybinds(TEMPLATE_CONTENT, custom_keybinds)

    # All other placeholders should still be present
    remaining_placeholders = get_other_placeholders(result)
    assert original_placeholders == remaining_placeholders, (
        f"Placeholders changed after substitution.\n"
        f"Missing: {original_placeholders - remaining_placeholders}\n"
        f"Added: {remaining_placeholders - original_placeholders}"
    )


@settings(max_examples=100)
@given(content=arbitrary_content)
def test_arbitrary_content_substitution(content: str):
    """Any valid multi-line string substituted for @CUSTOM_KEYBINDS@ appears in the output.

    **Validates: Requirements 20.3**
    """
    # Skip content that contains @CUSTOM_KEYBINDS@ itself (would create ambiguity)
    assume("@CUSTOM_KEYBINDS@" not in content)

    result = substitute_custom_keybinds(TEMPLATE_CONTENT, content)

    # The content should appear in the result
    assert content in result, (
        f"Arbitrary content not found in substituted output.\n"
        f"Content: {content!r}"
    )

    # @CUSTOM_KEYBINDS@ should no longer be in the result
    assert "@CUSTOM_KEYBINDS@" not in result, (
        "Placeholder @CUSTOM_KEYBINDS@ still present after substitution"
    )
