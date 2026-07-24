# Feature: desktop-demo-driver, Property 4: Execution Filter Correctness
"""
Property 4: Execution Filter Correctness

Mirror the `getScenes(filter, filterType)` logic in Python and verify:
1. No filter returns all scenes
2. Category filter returns only matching scenes
3. Category filter is exhaustive (union of all categories = full registry)
4. Scene filter returns at most 1 result (names are unique)
5. Invalid filter returns all scenes
6. Filter preserves ordering from the registry

**Validates: Requirements 2.2, 2.3, 2.4**
"""

import re
from pathlib import Path
from itertools import groupby

from hypothesis import given, settings, assume, HealthCheck
from hypothesis import strategies as st


# ─── Parse DemoScenes.qml to extract scene data ───

DEMO_SCENES_PATH = (
    Path(__file__).parent.parent
    / "configs"
    / "quickshell"
    / "ii"
    / "services"
    / "DemoScenes.qml"
)

_qml_source = DEMO_SCENES_PATH.read_text()

# The valid categories defined in the file
CATEGORIES: list[str] = ["shell", "workspace", "window", "utility", "app-launch", "mcp"]


def _parse_scenes(source: str) -> list[dict]:
    """Parse scene entries from DemoScenes.qml registry.

    Scene-level name/category fields are at ~12 spaces indentation,
    distinguished from action-level fields which are deeper indented.
    We find scene blocks by matching consecutive name: + category: lines.
    """
    scenes = []
    lines = source.split("\n")
    i = 0
    while i < len(lines):
        # Match scene-level name (indented with spaces, starts the scene block)
        name_match = re.match(r"^\s{8,16}name:\s*\"([^\"]+)\"", lines[i])
        if name_match:
            name = name_match.group(1)
            # Look ahead for category (within next few lines of same block)
            cat = None
            for j in range(i + 1, min(i + 6, len(lines))):
                cat_match = re.match(r"^\s{8,16}category:\s*\"([^\"]+)\"", lines[j])
                if cat_match:
                    cat = cat_match.group(1)
                    break
            if cat is not None:
                scenes.append({"name": name, "category": cat})
        i += 1
    return scenes


REGISTRY: list[dict] = _parse_scenes(_qml_source)
SCENE_NAMES: list[str] = [s["name"] for s in REGISTRY]

# Sanity checks
assert len(REGISTRY) > 0, "Failed to parse any scenes from DemoScenes.qml"
assert all(s["category"] in CATEGORIES for s in REGISTRY), (
    "Parsed scene with unknown category"
)


# ─── Python mirror of getScenes(filter, filterType) ───

def get_scenes(registry: list[dict], filter_val, filter_type) -> list[dict]:
    """Python equivalent of DemoScenes.getScenes()."""
    if not filter_val:
        return registry
    if filter_type == "category":
        return [s for s in registry if s["category"] == filter_val]
    if filter_type == "scene":
        return [s for s in registry if s["name"] == filter_val]
    return registry


# ─── Hypothesis Strategies ───

st_valid_category = st.sampled_from(CATEGORIES)
st_valid_scene_name = st.sampled_from(SCENE_NAMES)

# Generate strings that are NOT valid scene names or categories
st_invalid_filter = st.text(
    alphabet=st.characters(whitelist_categories=("L", "N"), whitelist_characters="-_"),
    min_size=1,
    max_size=30,
).filter(lambda s: s not in SCENE_NAMES and s not in CATEGORIES)

# Filter type including invalid ones
st_filter_type = st.sampled_from(["category", "scene", "invalid", None, "", "foo"])


# ─── Property Tests ───


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None), st.just(None))
def test_no_filter_returns_all(filter_val, filter_type):
    """No filter returns the full registry unchanged.

    **Validates: Requirements 2.2, 2.3, 2.4**
    """
    result = get_scenes(REGISTRY, filter_val, filter_type)
    assert result == REGISTRY
    assert len(result) == len(REGISTRY)


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(category=st_valid_category)
def test_category_filter_subset(category: str):
    """Category filter returns only scenes matching the given category.

    **Validates: Requirements 2.2, 2.3, 2.4**
    """
    result = get_scenes(REGISTRY, category, "category")

    # All returned scenes must belong to the requested category
    for scene in result:
        assert scene["category"] == category, (
            f"Scene '{scene['name']}' has category '{scene['category']}' "
            f"but filter was '{category}'"
        )

    # Must include ALL scenes of that category (completeness)
    expected = [s for s in REGISTRY if s["category"] == category]
    assert result == expected


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(st.just(None))
def test_category_filter_exhaustive(_):
    """The union of all category-filtered results equals the full registry.

    **Validates: Requirements 2.2, 2.3, 2.4**
    """
    union = []
    for cat in CATEGORIES:
        union.extend(get_scenes(REGISTRY, cat, "category"))

    # Every scene in the registry must appear exactly once in the union
    assert len(union) == len(REGISTRY), (
        f"Union has {len(union)} scenes, registry has {len(REGISTRY)}"
    )
    # Verify same scenes (order may differ across categories but within a category order is preserved)
    registry_names = set(s["name"] for s in REGISTRY)
    union_names = set(s["name"] for s in union)
    assert registry_names == union_names, (
        f"Missing from union: {registry_names - union_names}, "
        f"Extra in union: {union_names - registry_names}"
    )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(scene_name=st_valid_scene_name)
def test_scene_filter_returns_exactly_one(scene_name: str):
    """Scene name filter returns exactly 1 result since names are unique.

    **Validates: Requirements 2.2, 2.3, 2.4**
    """
    result = get_scenes(REGISTRY, scene_name, "scene")
    assert len(result) == 1, (
        f"Expected exactly 1 result for scene '{scene_name}', got {len(result)}"
    )
    assert result[0]["name"] == scene_name


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(random_str=st_invalid_filter)
def test_invalid_filter_returns_all(random_str: str):
    """An invalid filterType (not 'category' or 'scene') returns all scenes.

    **Validates: Requirements 2.2, 2.3, 2.4**
    """
    # Using a filter value with a filter type that's not "category" or "scene"
    result = get_scenes(REGISTRY, random_str, None)
    assert result == REGISTRY

    result2 = get_scenes(REGISTRY, random_str, "invalid")
    assert result2 == REGISTRY

    result3 = get_scenes(REGISTRY, random_str, "")
    assert result3 == REGISTRY


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(category=st_valid_category)
def test_category_filter_preserves_order(category: str):
    """Filtered results maintain their original ordering from the registry.

    **Validates: Requirements 2.2, 2.3, 2.4**
    """
    result = get_scenes(REGISTRY, category, "category")

    # Get the indices of matching scenes in the original registry
    indices = [i for i, s in enumerate(REGISTRY) if s["category"] == category]

    # Indices must be strictly increasing (order preserved)
    for i in range(len(indices) - 1):
        assert indices[i] < indices[i + 1]

    # Result order matches registry order
    expected_names = [REGISTRY[i]["name"] for i in indices]
    result_names = [s["name"] for s in result]
    assert result_names == expected_names, (
        f"Order mismatch. Expected {expected_names}, got {result_names}"
    )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(scene_name=st_valid_scene_name)
def test_scene_filter_preserves_order(scene_name: str):
    """Scene filter result maintains its position info from registry.

    **Validates: Requirements 2.2, 2.3, 2.4**
    """
    result = get_scenes(REGISTRY, scene_name, "scene")
    assert len(result) == 1

    # The single result should match the registry entry at the same position
    registry_entry = next(s for s in REGISTRY if s["name"] == scene_name)
    assert result[0] == registry_entry
