"""
Property-based tests for DemoScenes registry structural invariants.

Feature: desktop-demo-driver, Property 3: Scene Registry Invariants

Extracts scene data from DemoScenes.qml and verifies that all scene
definitions satisfy structural integrity constraints: unique names,
kebab-case naming, valid categories, positive durations, non-empty
actions with valid types, and correct field types.

**Validates: Requirements 2.1, 13.1**
"""

import re
from pathlib import Path
from hypothesis import given, settings, assume, HealthCheck
from hypothesis import strategies as st

# Feature: desktop-demo-driver, Property 3: Scene Registry Invariants

DEMO_SCENES_PATH = (
    Path(__file__).parent.parent
    / "configs"
    / "quickshell"
    / "ii"
    / "services"
    / "DemoScenes.qml"
)

# Valid patterns and values from the design
KEBAB_CASE_PATTERN = re.compile(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$")
VALID_CATEGORIES = {"shell", "workspace", "window", "utility", "app-launch", "mcp"}
VALID_ACTION_TYPES = {
    "globalShortcut", "key", "mouseMove", "mouseMoveRelative",
    "click", "scroll", "drag", "notify", "mcp", "exec",
}

# Regex patterns to extract structured data from DemoScenes.qml
# The QML file uses JS object literal notation which is well-structured
NAME_PATTERN = re.compile(r'name:\s*"([^"]+)"')
CATEGORY_PATTERN = re.compile(r'category:\s*"([^"]+)"')
DURATION_PATTERN = re.compile(r'duration:\s*(\d+)')
DESCRIPTION_PATTERN = re.compile(r'description:\s*"([^"]+)"')
CLOSES_MODULE_PATTERN = re.compile(r'closesModule:\s*"([^"]+)"')
ACTION_TYPE_PATTERN = re.compile(r'{\s*type:\s*"([^"]+)"')


def extract_registry_block(content: str) -> str:
    """Extract the registry array from DemoScenes.qml content."""
    # Find the start of the registry property
    start_marker = "readonly property var registry: ["
    start_idx = content.find(start_marker)
    if start_idx == -1:
        raise ValueError("Could not find registry array in DemoScenes.qml")

    # Find matching closing bracket by counting bracket depth
    start_idx += len(start_marker) - 1  # point to the opening [
    depth = 0
    for i in range(start_idx, len(content)):
        if content[i] == "[":
            depth += 1
        elif content[i] == "]":
            depth -= 1
            if depth == 0:
                return content[start_idx:i + 1]

    raise ValueError("Could not find matching ] for registry array")


def extract_scene_blocks(registry_text: str) -> list:
    """Split the registry text into individual scene object blocks."""
    scenes = []
    depth = 0
    current_start = None

    for i, ch in enumerate(registry_text):
        if ch == "{":
            if depth == 0:
                current_start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and current_start is not None:
                block = registry_text[current_start:i + 1]
                # Only include blocks that have a 'name:' field (scene objects)
                if "name:" in block:
                    scenes.append(block)
                current_start = None

    return scenes


def parse_scene(block: str) -> dict:
    """Parse a scene block into a dict with extracted fields."""
    scene = {}

    name_match = NAME_PATTERN.search(block)
    if name_match:
        scene["name"] = name_match.group(1)

    category_match = CATEGORY_PATTERN.search(block)
    if category_match:
        scene["category"] = category_match.group(1)

    duration_match = DURATION_PATTERN.search(block)
    if duration_match:
        scene["duration"] = int(duration_match.group(1))

    description_match = DESCRIPTION_PATTERN.search(block)
    if description_match:
        scene["description"] = description_match.group(1)

    closes_module_match = CLOSES_MODULE_PATTERN.search(block)
    if closes_module_match:
        scene["closesModule"] = closes_module_match.group(1)

    # Extract action types from the actions array
    # Find the actions: [ ... ] block within this scene
    actions_start = block.find("actions: [")
    if actions_start != -1:
        # Find matching ] for actions array
        depth = 0
        actions_text = ""
        for i in range(actions_start + len("actions: [") - 1, len(block)):
            if block[i] == "[":
                depth += 1
            elif block[i] == "]":
                depth -= 1
                if depth == 0:
                    actions_text = block[actions_start:i + 1]
                    break
        scene["actions_text"] = actions_text
        scene["action_types"] = ACTION_TYPE_PATTERN.findall(actions_text)
    else:
        scene["actions_text"] = ""
        scene["action_types"] = []

    # Check for guards array
    guards_start = block.find("guards: [")
    if guards_start != -1:
        scene["has_guards"] = True
        # Find the guards array content
        depth = 0
        for i in range(guards_start + len("guards: [") - 1, len(block)):
            if block[i] == "[":
                depth += 1
            elif block[i] == "]":
                depth -= 1
                if depth == 0:
                    guards_text = block[guards_start:i + 1]
                    scene["guards_text"] = guards_text
                    break
    else:
        scene["has_guards"] = False
        scene["guards_text"] = ""

    return scene


# ─── Load and parse scene data at module level ───

assert DEMO_SCENES_PATH.exists(), (
    f"DemoScenes.qml not found at {DEMO_SCENES_PATH}"
)

QML_CONTENT = DEMO_SCENES_PATH.read_text()
REGISTRY_BLOCK = extract_registry_block(QML_CONTENT)
SCENE_BLOCKS = extract_scene_blocks(REGISTRY_BLOCK)
SCENES = [parse_scene(block) for block in SCENE_BLOCKS]

# Strategy: pick a random scene from the parsed registry
scene_indices = st.integers(min_value=0, max_value=max(0, len(SCENES) - 1))


# ─── Sanity Tests (direct invariant checks on the full registry) ───


def test_registry_is_non_empty():
    """The scene registry must contain at least one scene."""
    assert len(SCENES) > 0, "Scene registry is empty"


def test_all_scene_names_unique():
    """
    All scene names in the registry must be unique (no duplicates).

    **Validates: Requirements 2.1, 13.1**
    """
    names = [s["name"] for s in SCENES if "name" in s]
    duplicates = [n for n in names if names.count(n) > 1]
    assert len(duplicates) == 0, (
        f"Duplicate scene names found: {sorted(set(duplicates))}"
    )


def test_all_scene_names_kebab_case():
    """
    All scene names must match kebab-case: ^[a-z][a-z0-9]*(-[a-z0-9]+)*$

    **Validates: Requirements 2.1, 13.1**
    """
    invalid = [
        s["name"] for s in SCENES
        if "name" in s and not KEBAB_CASE_PATTERN.match(s["name"])
    ]
    assert len(invalid) == 0, (
        f"Scene names not matching kebab-case: {invalid}"
    )


def test_all_scenes_have_valid_category():
    """
    Every scene must have a category that is one of the valid categories.

    **Validates: Requirements 2.1, 13.1**
    """
    invalid = [
        (s.get("name", "?"), s.get("category", "<missing>"))
        for s in SCENES
        if s.get("category") not in VALID_CATEGORIES
    ]
    assert len(invalid) == 0, (
        f"Scenes with invalid/missing category: {invalid}"
    )


def test_all_scenes_have_positive_duration():
    """
    Every scene must have a duration field that is a positive integer.

    **Validates: Requirements 2.1, 13.1**
    """
    invalid = [
        (s.get("name", "?"), s.get("duration"))
        for s in SCENES
        if not isinstance(s.get("duration"), int) or s["duration"] <= 0
    ]
    assert len(invalid) == 0, (
        f"Scenes with non-positive or missing duration: {invalid}"
    )


def test_all_scenes_have_non_empty_actions():
    """
    Every scene must have a non-empty actions array.

    **Validates: Requirements 2.1, 13.1**
    """
    invalid = [
        s.get("name", "?")
        for s in SCENES
        if len(s.get("action_types", [])) == 0 and "delay" not in s.get("actions_text", "")
    ]
    # A scene can have actions that are only delays (no type field), so check
    # that the actions_text is non-trivial
    truly_empty = [
        s.get("name", "?")
        for s in SCENES
        if "actions: [" not in SCENE_BLOCKS[SCENES.index(s)]
        or s.get("actions_text", "").strip() == "actions: []"
    ]
    assert len(truly_empty) == 0, (
        f"Scenes with empty actions array: {truly_empty}"
    )


def test_all_scenes_have_non_empty_description():
    """
    Every scene must have a description field that is a non-empty string.

    **Validates: Requirements 2.1, 13.1**
    """
    invalid = [
        s.get("name", "?")
        for s in SCENES
        if not s.get("description") or len(s["description"].strip()) == 0
    ]
    assert len(invalid) == 0, (
        f"Scenes with empty/missing description: {invalid}"
    )


def test_all_scenes_have_guards_array():
    """
    Every scene's guards field must be an array (may be empty).

    **Validates: Requirements 2.1, 13.1**
    """
    # Every scene block should contain 'guards: [' indicating an array
    missing_guards = [
        s.get("name", "?")
        for s in SCENES
        if not s.get("has_guards")
    ]
    assert len(missing_guards) == 0, (
        f"Scenes missing guards array: {missing_guards}"
    )


def test_closes_module_is_non_empty_string():
    """
    If a scene has closesModule, it must be a non-empty string.

    **Validates: Requirements 2.1, 13.1**
    """
    invalid = [
        s.get("name", "?")
        for s in SCENES
        if "closesModule" in s and (not s["closesModule"] or len(s["closesModule"].strip()) == 0)
    ]
    assert len(invalid) == 0, (
        f"Scenes with empty closesModule: {invalid}"
    )


def test_all_action_types_are_valid():
    """
    All action objects with a type field must use a valid action type.

    **Validates: Requirements 2.1, 13.1**
    """
    invalid_actions = []
    for scene in SCENES:
        for action_type in scene.get("action_types", []):
            if action_type not in VALID_ACTION_TYPES:
                invalid_actions.append((scene.get("name", "?"), action_type))
    assert len(invalid_actions) == 0, (
        f"Actions with invalid type: {invalid_actions}"
    )


def test_all_categories_have_scenes():
    """
    Every valid category should have at least one scene assigned to it.

    **Validates: Requirements 13.1**
    """
    present_categories = {s.get("category") for s in SCENES}
    missing = VALID_CATEGORIES - present_categories
    assert len(missing) == 0, (
        f"Categories with no scenes: {sorted(missing)}"
    )


# ─── Property-Based Tests ───


@given(idx=scene_indices)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_property_any_scene_has_valid_name(idx):
    """
    Property 3: Scene Registry Invariants (Strategy 1 - Name Validity)

    For any randomly chosen scene from the registry, its name must be
    non-empty and match the kebab-case pattern.

    **Validates: Requirements 2.1, 13.1**
    """
    scene = SCENES[idx]
    name = scene.get("name")
    assert name is not None, f"Scene at index {idx} has no name"
    assert len(name) > 0, f"Scene at index {idx} has empty name"
    assert KEBAB_CASE_PATTERN.match(name), (
        f"Scene name '{name}' does not match kebab-case pattern"
    )


@given(idx=scene_indices)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_property_any_scene_has_valid_structure(idx):
    """
    Property 3: Scene Registry Invariants (Strategy 2 - Structural Completeness)

    For any randomly chosen scene from the registry, it must have:
    - a valid category from the allowed set
    - a positive integer duration
    - a non-empty description
    - a guards array (possibly empty)
    - a non-empty actions list with all valid action types

    **Validates: Requirements 2.1, 13.1**
    """
    scene = SCENES[idx]
    name = scene.get("name", f"<index {idx}>")

    # Category check
    category = scene.get("category")
    assert category in VALID_CATEGORIES, (
        f"Scene '{name}': category '{category}' not in {VALID_CATEGORIES}"
    )

    # Duration check
    duration = scene.get("duration")
    assert isinstance(duration, int) and duration > 0, (
        f"Scene '{name}': duration must be a positive int, got {duration}"
    )

    # Description check
    description = scene.get("description")
    assert description and len(description.strip()) > 0, (
        f"Scene '{name}': description must be non-empty"
    )

    # Guards check
    assert scene.get("has_guards"), (
        f"Scene '{name}': must have a guards array"
    )

    # Actions check — must have action types or at least delay entries
    actions_text = scene.get("actions_text", "")
    assert len(actions_text) > len("actions: []"), (
        f"Scene '{name}': actions array must be non-empty"
    )

    # All action types must be valid
    for action_type in scene.get("action_types", []):
        assert action_type in VALID_ACTION_TYPES, (
            f"Scene '{name}': invalid action type '{action_type}'"
        )


@given(idx=scene_indices)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_property_any_scene_name_is_unique(idx):
    """
    Property 3: Scene Registry Invariants (Strategy 3 - Uniqueness)

    For any randomly chosen scene, its name must not appear in any other
    scene in the registry (uniqueness invariant).

    **Validates: Requirements 2.1, 13.1**
    """
    scene = SCENES[idx]
    name = scene.get("name")
    assert name is not None

    # Count occurrences of this name across all scenes
    count = sum(1 for s in SCENES if s.get("name") == name)
    assert count == 1, (
        f"Scene name '{name}' appears {count} times (must be unique)"
    )


@given(
    idx=scene_indices,
    speed=st.floats(min_value=0.5, max_value=3.0, allow_nan=False),
)
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_property_scene_duration_scales_positively(idx, speed):
    """
    Property 3: Scene Registry Invariants (Strategy 4 - Duration Scaling)

    For any scene and any valid speed multiplier, the effective duration
    (duration / speed) must always be positive and finite.

    **Validates: Requirements 2.1, 13.1**
    """
    scene = SCENES[idx]
    duration = scene.get("duration", 0)
    assume(duration > 0)
    assume(speed > 0)

    effective = duration / speed
    assert effective > 0, (
        f"Effective duration must be positive: {duration}/{speed} = {effective}"
    )
    assert effective < float("inf"), (
        f"Effective duration must be finite: {duration}/{speed}"
    )
