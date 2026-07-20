# Feature: upstream-sync-2025-2026, Property 4: Custom Keybind Injection
"""
Property 4: Custom Keybind Injection

For any string value substituted for @CUSTOM_KEYBINDS@, the processed keybind
configuration SHALL contain that exact string content at the designated injection
point, after all other bind declarations.

**Validates: Requirements 20.3**
"""

import re
from pathlib import Path

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


def substitute_custom_keybinds(template: str, custom: str) -> str:
    """Substitute @CUSTOM_KEYBINDS@ with the given custom keybind string."""
    return template.replace("@CUSTOM_KEYBINDS@", custom)


# Strategy for generating keybind-like lines simulating user-defined keybinds
keybind_line = st.builds(
    lambda prefix, mods, key, cmd: f"{prefix} = {mods}, {key}, exec, {cmd}",
    prefix=st.sampled_from(["bind", "bindd", "binde", "bindl", "bindle", "bindm"]),
    mods=st.sampled_from([
        "SUPER", "SUPER SHIFT", "SUPER+Shift", "SUPER+Ctrl", "Alt",
        "Ctrl+Alt", "SUPER+Alt", "Super", "Super+Shift",
    ]),
    key=st.sampled_from([
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
        "Return", "Space", "Tab", "code:87", "code:88", "code:89",
    ]),
    cmd=st.text(
        alphabet=st.characters(
            whitelist_categories=("L", "N", "P", "Z"),
            whitelist_characters=" -_/.",
        ),
        min_size=1,
        max_size=60,
    ),
)

# Strategy for multi-line keybind blocks (1-10 lines)
keybind_block = st.lists(keybind_line, min_size=1, max_size=10).map(
    lambda lines: "\n".join(lines)
)


@settings(max_examples=100)
@given(custom_keybinds=keybind_block)
def test_custom_keybind_injection_presence(custom_keybinds: str):
    """Generated keybind string appears verbatim in the processed output.

    **Validates: Requirements 20.3**
    """
    result = substitute_custom_keybinds(TEMPLATE_CONTENT, custom_keybinds)

    assert custom_keybinds in result, (
        f"Custom keybinds not found in substituted output.\n"
        f"Expected to find:\n{custom_keybinds!r}"
    )

    # The @CUSTOM_KEYBINDS@ placeholder should be consumed
    assert "@CUSTOM_KEYBINDS@" not in result, (
        "Placeholder @CUSTOM_KEYBINDS@ still present after substitution"
    )


@settings(max_examples=100)
@given(custom_keybinds=keybind_block)
def test_custom_keybind_injection_position(custom_keybinds: str):
    """Injected content appears after all other bind declarations in the template.

    **Validates: Requirements 20.3**
    """
    result = substitute_custom_keybinds(TEMPLATE_CONTENT, custom_keybinds)

    # Find the position of the injected content
    inject_pos = result.find(custom_keybinds)
    assert inject_pos >= 0, "Custom keybinds not found in result"

    # All original bind lines from the template (before @CUSTOM_KEYBINDS@)
    # should appear before the injection point in the output
    template_before_placeholder = TEMPLATE_CONTENT.split("@CUSTOM_KEYBINDS@")[0]
    original_bind_lines = [
        line for line in template_before_placeholder.split("\n")
        if re.match(r"^\s*bind", line)
    ]

    if original_bind_lines:
        last_original_bind = original_bind_lines[-1]
        last_bind_pos = result.find(last_original_bind)
        assert last_bind_pos < inject_pos, (
            f"Injection point ({inject_pos}) is not after "
            f"last original bind ({last_bind_pos})"
        )


@settings(max_examples=100)
@given(custom_keybinds=keybind_block)
def test_other_placeholders_unaffected(custom_keybinds: str):
    """No other @VARIABLE@ placeholders are affected by the substitution.

    **Validates: Requirements 20.3**
    """
    original_placeholders = get_other_placeholders(TEMPLATE_CONTENT)

    result = substitute_custom_keybinds(TEMPLATE_CONTENT, custom_keybinds)

    remaining_placeholders = get_other_placeholders(result)
    assert original_placeholders == remaining_placeholders, (
        f"Placeholders changed after substitution.\n"
        f"Missing: {original_placeholders - remaining_placeholders}\n"
        f"Added: {remaining_placeholders - original_placeholders}"
    )


@settings(max_examples=100)
@given(
    content=st.text(
        alphabet=st.characters(
            whitelist_categories=("L", "N", "P", "Z", "S"),
            whitelist_characters=",+=_-/. #!$%^&*(){}[]|\\:;\"'<>?\n\t",
        ),
        min_size=0,
        max_size=500,
    )
)
def test_arbitrary_multiline_content_preserved(content: str):
    """Any arbitrary multi-line string substituted for @CUSTOM_KEYBINDS@ appears verbatim.

    **Validates: Requirements 20.3**
    """
    # Skip content containing the placeholder itself (would be ambiguous)
    assume("@CUSTOM_KEYBINDS@" not in content)

    result = substitute_custom_keybinds(TEMPLATE_CONTENT, content)

    assert content in result, (
        f"Arbitrary content not found in substituted output.\n"
        f"Content: {content!r}"
    )
    assert "@CUSTOM_KEYBINDS@" not in result, (
        "Placeholder @CUSTOM_KEYBINDS@ still present after substitution"
    )
