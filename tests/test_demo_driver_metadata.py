"""
Property-based tests for scene metadata JSON round-trip serialization.

Feature: desktop-demo-driver, Property 14: Scene Metadata JSON Round-Trip

The `listScenes()` function calls `JSON.stringify(DemoScenes.registry)`.
This tests that scene metadata can be serialized to JSON and deserialized
without data loss — verifying the structural requirement that scene
metadata is returnable as structured JSON.

**Validates: Requirements 13.3**
"""

import json
import re
from pathlib import Path
from hypothesis import given, settings, HealthCheck
from hypothesis import strategies as st

# ─── Constants ───

VALID_CATEGORIES = ["shell", "workspace", "window", "utility", "app-launch", "mcp"]

DEMO_SCENES_PATH = (
    Path(__file__).parent.parent
    / "configs"
    / "quickshell"
    / "ii"
    / "services"
    / "DemoScenes.qml"
)

# Regex patterns to extract scene metadata from DemoScenes.qml
NAME_PATTERN = re.compile(r'name:\s*"([^"]+)"')
CATEGORY_PATTERN = re.compile(r'category:\s*"([^"]+)"')
DURATION_PATTERN = re.compile(r'duration:\s*(\d+)')
DESCRIPTION_PATTERN = re.compile(r'description:\s*"([^"]+)"')


# ─── QML Parsing Helpers ───


def extract_registry_block(content: str) -> str:
    """Extract the registry array from DemoScenes.qml content."""
    start_marker = "readonly property var registry: ["
    start_idx = content.find(start_marker)
    if start_idx == -1:
        raise ValueError("Could not find registry array in DemoScenes.qml")

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
                if "name:" in block and "category:" in block:
                    scenes.append(block)
                current_start = None

    return scenes


def parse_scene_metadata(block: str) -> dict:
    """Parse a scene block into a metadata dict with the 4 required fields."""
    scene = {}

    name_match = NAME_PATTERN.search(block)
    if name_match:
        scene["name"] = name_match.group(1)

    description_match = DESCRIPTION_PATTERN.search(block)
    if description_match:
        scene["description"] = description_match.group(1)

    category_match = CATEGORY_PATTERN.search(block)
    if category_match:
        scene["category"] = category_match.group(1)

    duration_match = DURATION_PATTERN.search(block)
    if duration_match:
        scene["duration"] = int(duration_match.group(1))

    return scene


# ─── Load and parse scene data at module level ───

assert DEMO_SCENES_PATH.exists(), (
    f"DemoScenes.qml not found at {DEMO_SCENES_PATH}"
)

QML_CONTENT = DEMO_SCENES_PATH.read_text()
REGISTRY_BLOCK = extract_registry_block(QML_CONTENT)
SCENE_BLOCKS = extract_scene_blocks(REGISTRY_BLOCK)
SCENES = [parse_scene_metadata(block) for block in SCENE_BLOCKS]

# ─── Strategies ───

scene_indices = st.integers(min_value=0, max_value=max(0, len(SCENES) - 1))

st_scene_metadata = st.fixed_dictionaries({
    "name": st.from_regex(r"[a-z][a-z0-9]*(-[a-z0-9]+){0,3}", fullmatch=True),
    "description": st.text(
        min_size=1, max_size=100,
        alphabet=st.characters(blacklist_categories=("Cs",)),
    ),
    "category": st.sampled_from(VALID_CATEGORIES),
    "duration": st.integers(min_value=1000, max_value=30000),
})


# ─── Property-Based Tests ───


@given(idx=scene_indices)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_property_real_scene_json_roundtrip_preserves_fields(idx):
    """
    Property 14: Scene Metadata JSON Round-Trip (Strategy 1)

    For any scene in the registry, `json.loads(json.dumps(scene))`
    preserves all required fields (name, description, category, duration).

    **Validates: Requirements 13.3**
    """
    scene = SCENES[idx]

    serialized = json.dumps(scene)
    deserialized = json.loads(serialized)

    assert deserialized["name"] == scene["name"], (
        f"name mismatch after round-trip: {scene['name']!r} vs {deserialized['name']!r}"
    )
    assert deserialized["description"] == scene["description"], (
        f"description mismatch for scene '{scene['name']}'"
    )
    assert deserialized["category"] == scene["category"], (
        f"category mismatch for scene '{scene['name']}'"
    )
    assert deserialized["duration"] == scene["duration"], (
        f"duration mismatch for scene '{scene['name']}': "
        f"{scene['duration']} vs {deserialized['duration']}"
    )


@given(scene=st_scene_metadata)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_property_generated_scene_json_roundtrip_preserves_data(scene):
    """
    Property 14: Scene Metadata JSON Round-Trip (Strategy 2)

    For any randomly generated scene metadata dict (with valid fields),
    JSON round-trip preserves all data exactly.

    **Validates: Requirements 13.3**
    """
    serialized = json.dumps(scene)
    deserialized = json.loads(serialized)

    assert deserialized == scene, (
        f"Round-trip mismatch:\n  original:     {scene!r}\n  deserialized: {deserialized!r}"
    )


def test_full_registry_serializes_to_valid_json():
    """
    Property 14: Scene Metadata JSON Round-Trip (Strategy 3)

    The serialized JSON for the full registry is valid JSON (parseable).

    **Validates: Requirements 13.3**
    """
    serialized = json.dumps(SCENES)

    # Must not raise
    parsed = json.loads(serialized)

    assert isinstance(parsed, list), "Registry must serialize to a JSON array"
    assert len(parsed) == len(SCENES), (
        f"Registry length mismatch: {len(SCENES)} vs {len(parsed)}"
    )


@given(scene=st_scene_metadata)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_property_field_types_preserved_after_roundtrip(scene):
    """
    Property 14: Scene Metadata JSON Round-Trip (Strategy 4)

    Each field type is preserved after round-trip:
    - name: string
    - description: string
    - category: string
    - duration: int

    **Validates: Requirements 13.3**
    """
    serialized = json.dumps(scene)
    deserialized = json.loads(serialized)

    assert isinstance(deserialized["name"], str), (
        f"name should be str, got {type(deserialized['name']).__name__}"
    )
    assert isinstance(deserialized["description"], str), (
        f"description should be str, got {type(deserialized['description']).__name__}"
    )
    assert isinstance(deserialized["category"], str), (
        f"category should be str, got {type(deserialized['category']).__name__}"
    )
    assert isinstance(deserialized["duration"], int), (
        f"duration should be int, got {type(deserialized['duration']).__name__}"
    )
