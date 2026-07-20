"""
Property-based test for template placeholder integrity.

Feature: upstream-sync-2025-2026, Property 1: Template Placeholder Integrity

For any .conf.template file in configs/hypr/, all @VARIABLE@ placeholders
shall be present after random edits that don't target placeholder lines.

**Validates: Requirements 4.3, 7.4, 17.3, 20.3**
"""

import re
from pathlib import Path
from hypothesis import given, settings, assume, HealthCheck
from hypothesis import strategies as st

# Feature: upstream-sync-2025-2026, Property 1: Template Placeholder Integrity

TEMPLATE_DIR = Path(__file__).parent.parent / "configs" / "hypr"
PLACEHOLDER_PATTERN = re.compile(r"@[A-Z_]+@")

# Required placeholders for keybinds.conf.template as specified in the design
KEYBINDS_REQUIRED_PLACEHOLDERS = {
    "@TERMINAL_APPS@",
    "@BROWSER_APPS@",
    "@QUICKSHELL_BIN@",
    "@CUSTOM_KEYBINDS@",
    "@FUZZEL_BIN@",
    "@FILE_MANAGER_APPS@",
    "@CODE_EDITOR_APPS@",
    "@OFFICE_APPS@",
    "@TEXT_EDITOR_APPS@",
    "@VOLUME_MIXER_APPS@",
    "@SETTINGS_APPS@",
    "@TASK_MANAGER_APPS@",
    "@BRIGHTNESSCTL_BIN@",
    "@WPCTL_BIN@",
    "@PLAYERCTL_BIN@",
    "@CLIPHIST_BIN@",
    "@WL_COPY_BIN@",
    "@WLOGOUT_BIN@",
    "@HYPRSHOT_BIN@",
    "@GRIM_BIN@",
    "@SLURP_BIN@",
    "@TESSERACT_BIN@",
    "@HYPRPICKER_BIN@",
}


def get_template_files():
    """Discover all .conf.template files in the hypr config directory."""
    return sorted(TEMPLATE_DIR.glob("*.conf.template"))


def extract_placeholders(content: str) -> set:
    """Extract all @VARIABLE@ placeholders from template content."""
    return set(PLACEHOLDER_PATTERN.findall(content))


def get_lines_with_placeholders(lines: list) -> set:
    """Return indices of lines that contain at least one placeholder."""
    return {i for i, line in enumerate(lines) if PLACEHOLDER_PATTERN.search(line)}


# Load template data once at module level for efficiency
TEMPLATES = {}
for tf in get_template_files():
    content = tf.read_text()
    TEMPLATES[tf.name] = {
        "content": content,
        "lines": content.splitlines(keepends=True),
        "placeholders": extract_placeholders(content),
        "placeholder_line_indices": get_lines_with_placeholders(
            content.splitlines(keepends=True)
        ),
    }

# Strategy: choose a template file name
template_names = st.sampled_from(list(TEMPLATES.keys())) if TEMPLATES else st.nothing()

# Strategy: random text that doesn't contain placeholder patterns
safe_text = st.text(
    alphabet=st.characters(
        blacklist_characters="@",
        blacklist_categories=("Cs",),
    ),
    min_size=0,
    max_size=120,
)

# Strategy: random Hyprland bind lines (realistic insertions)
hyprland_bind_line = st.builds(
    lambda mod, key, dispatcher, args: f"bind = {mod}, {key}, {dispatcher}, {args}\n",
    mod=st.sampled_from(["Super", "Super+Shift", "Super+Alt", "Ctrl+Super", "Alt"]),
    key=st.sampled_from(
        ["A", "B", "C", "D", "E", "F", "G", "H", "Return", "Space", "F1", "F2"]
    ),
    dispatcher=st.sampled_from(
        ["exec", "killactive", "workspace", "movetoworkspace", "togglefloating"]
    ),
    args=st.sampled_from(
        ["notify-send test", "1", "2", "+1", "-1", "r+1", ""]
    ),
)

# Strategy: sed-like substitution patterns (simulating template processing)
# These replace literal text fragments but must NOT eat @VARIABLE@ patterns
sed_replacement = st.builds(
    lambda find, replace: (find, replace),
    find=st.text(
        alphabet=st.characters(
            blacklist_characters="@\n\r",
            blacklist_categories=("Cs",),
        ),
        min_size=1,
        max_size=30,
    ),
    replace=st.text(
        alphabet=st.characters(
            blacklist_characters="@\n\r",
            blacklist_categories=("Cs",),
        ),
        min_size=0,
        max_size=30,
    ),
)


@st.composite
def edit_operation(draw, template_name):
    """Generate a random edit operation that avoids placeholder lines."""
    data = TEMPLATES[template_name]
    lines = data["lines"]
    placeholder_indices = data["placeholder_line_indices"]
    num_lines = len(lines)

    # Indices of lines safe to delete or modify (no placeholders)
    safe_indices = [i for i in range(num_lines) if i not in placeholder_indices]

    op_type = draw(st.sampled_from(["insert", "delete", "modify"]))

    if op_type == "insert":
        # Insert a random line at any position
        pos = draw(st.integers(min_value=0, max_value=num_lines))
        text = draw(st.one_of(safe_text, hyprland_bind_line))
        if not text.endswith("\n"):
            text += "\n"
        return ("insert", pos, text)

    elif op_type == "delete" and safe_indices:
        idx = draw(st.sampled_from(safe_indices))
        return ("delete", idx, None)

    elif op_type == "modify" and safe_indices:
        idx = draw(st.sampled_from(safe_indices))
        text = draw(st.one_of(safe_text, hyprland_bind_line))
        if not text.endswith("\n"):
            text += "\n"
        return ("modify", idx, text)

    else:
        # Fallback: insert if delete/modify not possible
        pos = draw(st.integers(min_value=0, max_value=num_lines))
        text = draw(safe_text)
        if not text.endswith("\n"):
            text += "\n"
        return ("insert", pos, text)


@st.composite
def edit_sequence(draw, template_name):
    """Generate a sequence of 1-5 random edit operations for a template."""
    num_ops = draw(st.integers(min_value=1, max_value=5))
    ops = []
    for _ in range(num_ops):
        op = draw(edit_operation(template_name))
        ops.append(op)
    return ops


def apply_edits(lines: list, operations: list) -> str:
    """Apply a sequence of edit operations to lines, returning the result as a string.

    Operations that would affect a placeholder line in the current state are
    skipped to maintain the invariant that edits never target placeholder content.
    """
    result = list(lines)  # work on a copy
    for op_type, idx, text in operations:
        if op_type == "insert":
            # Clamp index to valid range after previous edits
            pos = min(idx, len(result))
            result.insert(pos, text)
        elif op_type == "delete":
            if idx < len(result):
                # Skip if the line at this index now contains a placeholder
                if PLACEHOLDER_PATTERN.search(result[idx]):
                    continue
                result.pop(idx)
        elif op_type == "modify":
            if idx < len(result):
                # Skip if the line at this index now contains a placeholder
                if PLACEHOLDER_PATTERN.search(result[idx]):
                    continue
                result[idx] = text
    return "".join(result)


def apply_sed_substitution(content: str, find: str, replace: str) -> str:
    """Apply a sed-like substitution, but only on non-placeholder portions.

    Splits content around @VARIABLE@ patterns, applies substitution only
    to the non-placeholder segments, then reassembles.
    """
    # Split content into placeholder tokens and surrounding text
    parts = PLACEHOLDER_PATTERN.split(content)
    placeholders = PLACEHOLDER_PATTERN.findall(content)

    # Apply substitution only to non-placeholder parts
    modified_parts = [part.replace(find, replace) for part in parts]

    # Reassemble: interleave modified parts with original placeholders
    result = []
    for i, part in enumerate(modified_parts):
        result.append(part)
        if i < len(placeholders):
            result.append(placeholders[i])
    return "".join(result)


# --- Sanity Test ---


def test_keybinds_template_has_all_required_placeholders():
    """
    Sanity check: the keybinds.conf.template file contains all required
    @VARIABLE@ placeholders as specified in the design document.

    **Validates: Requirements 4.3, 7.4, 17.3, 20.3**
    """
    assert "keybinds.conf.template" in TEMPLATES, (
        "keybinds.conf.template not found in configs/hypr/"
    )

    template_data = TEMPLATES["keybinds.conf.template"]
    actual_placeholders = template_data["placeholders"]

    missing = KEYBINDS_REQUIRED_PLACEHOLDERS - actual_placeholders
    assert missing == set(), (
        f"keybinds.conf.template is missing required placeholders: {sorted(missing)}"
    )


# --- Strategy 1: Random edits to non-placeholder lines ---


@given(data=st.data())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_template_placeholder_integrity_random_edits(data):
    """
    Property 1: Template Placeholder Integrity (Strategy 1 - Random Edits)

    For any .conf.template file, random edits to non-placeholder lines
    must preserve all @VARIABLE@ placeholders.

    **Validates: Requirements 4.3, 7.4, 17.3, 20.3**
    """
    assume(len(TEMPLATES) > 0)

    template_name = data.draw(template_names)
    template_data = TEMPLATES[template_name]
    original_placeholders = template_data["placeholders"]
    original_lines = template_data["lines"]

    # Generate and apply edits
    ops = data.draw(edit_sequence(template_name))
    edited_content = apply_edits(original_lines, ops)

    # Extract placeholders from edited content
    surviving_placeholders = extract_placeholders(edited_content)

    # Property: all original placeholders must still be present
    missing = original_placeholders - surviving_placeholders
    assert missing == set(), (
        f"Template '{template_name}': placeholders lost after edits: {missing}"
    )


# --- Strategy 2: Inject random Hyprland bind lines at random positions ---


@given(data=st.data())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_keybinds_placeholder_integrity_bind_injection(data):
    """
    Property 1: Template Placeholder Integrity (Strategy 2 - Bind Injection)

    Injecting random valid Hyprland bind lines at random positions in
    keybinds.conf.template must not remove or corrupt any required placeholders.

    **Validates: Requirements 4.3, 7.4, 17.3, 20.3**
    """
    assume("keybinds.conf.template" in TEMPLATES)

    template_data = TEMPLATES["keybinds.conf.template"]
    original_lines = list(template_data["lines"])
    num_lines = len(original_lines)

    # Generate 1-10 random bind lines and insert at random positions
    num_insertions = data.draw(st.integers(min_value=1, max_value=10))
    for _ in range(num_insertions):
        pos = data.draw(st.integers(min_value=0, max_value=len(original_lines)))
        bind_line = data.draw(hyprland_bind_line)
        original_lines.insert(pos, bind_line)

    edited_content = "".join(original_lines)
    surviving_placeholders = extract_placeholders(edited_content)

    # Property: all required keybinds placeholders must still be present
    missing = KEYBINDS_REQUIRED_PLACEHOLDERS - surviving_placeholders
    assert missing == set(), (
        f"keybinds.conf.template: required placeholders lost after bind injection: {sorted(missing)}"
    )


# --- Strategy 3: sed-like substitutions must not eat placeholders ---


@given(data=st.data())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_keybinds_placeholder_integrity_sed_substitution(data):
    """
    Property 1: Template Placeholder Integrity (Strategy 3 - Sed Substitution)

    Applying random sed-like text substitutions (simulating template processing)
    to keybinds.conf.template must not remove or corrupt any required @VARIABLE@
    placeholders, as long as the find/replace strings don't contain '@'.

    **Validates: Requirements 4.3, 7.4, 17.3, 20.3**
    """
    assume("keybinds.conf.template" in TEMPLATES)

    template_data = TEMPLATES["keybinds.conf.template"]
    content = template_data["content"]

    # Generate 1-3 sed-like substitutions
    num_subs = data.draw(st.integers(min_value=1, max_value=3))
    for _ in range(num_subs):
        find, replace = data.draw(sed_replacement)
        content = apply_sed_substitution(content, find, replace)

    surviving_placeholders = extract_placeholders(content)

    # Property: all required keybinds placeholders must still be present
    missing = KEYBINDS_REQUIRED_PLACEHOLDERS - surviving_placeholders
    assert missing == set(), (
        f"keybinds.conf.template: required placeholders lost after sed substitution: {sorted(missing)}"
    )
