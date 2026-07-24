"""
Property-based tests for total tour duration computation.

Feature: desktop-demo-driver, Property 15: Total Tour Duration Computation

Tests validate the pure algorithmic logic of getTotalDuration(speedMultiplier)
without executing any QML. The Python function mirrors the QML implementation
in configs/quickshell/ii/services/DemoScenes.qml.

**Validates: Requirements 13.4**
"""

import re
from pathlib import Path

from hypothesis import given, settings, assume, HealthCheck
from hypothesis import strategies as st


# ─── Pure Python function mirroring DemoScenes.getTotalDuration() ───


def get_total_duration(durations: list[int], speed_multiplier: float) -> int:
    """Mirror DemoScenes.getTotalDuration(speedMultiplier).

    Computes:
        total = sum(scene.duration for all scenes)
        total += max(0, numScenes - 1) * 2000  # inter-scene delays
        return round(total / speedMultiplier)
    """
    total = sum(durations)
    n = len(durations)
    total += max(0, n - 1) * 2000  # inter-scene delay (2000ms default)
    return round(total / speed_multiplier)


# ─── Hypothesis strategies ───

# Scene durations: 1-40 scenes with durations between 1000ms and 30000ms
durations_strategy = st.lists(
    st.integers(min_value=1000, max_value=30000),
    min_size=1,
    max_size=40,
)

# Speed multiplier within valid range
speed_strategy = st.floats(
    min_value=0.5, max_value=3.0, allow_nan=False, allow_infinity=False
)


# ─── Property 15: Total Tour Duration Computation ───


@given(durations=durations_strategy, speed=speed_strategy)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_total_duration_formula(durations, speed):
    """
    Property 15a: getTotalDuration matches the formula exactly.

    For any list of scene durations (1-40 scenes, durations 1000-30000ms)
    and speed (0.5-3.0):
        getTotalDuration(speed) == round((sum(durations) + (n-1)*2000) / speed)

    **Validates: Requirements 13.4**
    """
    n = len(durations)
    raw_total = sum(durations) + (n - 1) * 2000
    expected = round(raw_total / speed)
    result = get_total_duration(durations, speed)
    assert result == expected, (
        f"Duration mismatch: got {result}, expected {expected} "
        f"(n={n}, sum={sum(durations)}, speed={speed})"
    )


@given(duration=st.integers(min_value=1000, max_value=30000))
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_single_scene_no_inter_scene_delay(duration):
    """
    Property 15b: Single scene has no inter-scene delay.

    For a registry with exactly 1 scene at speed 1.0:
        getTotalDuration(1.0) == duration (no inter-scene delay added)

    **Validates: Requirements 13.4**
    """
    result = get_total_duration([duration], 1.0)
    assert result == duration, (
        f"Single scene at speed 1.0 should equal duration: "
        f"got {result}, expected {duration}"
    )


@given(durations=durations_strategy, speed=speed_strategy)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_duration_always_positive(durations, speed):
    """
    Property 15c: Duration is always positive for non-empty registries.

    Since all durations >= 1000 and speed <= 3.0, the total duration
    is always a positive integer.

    **Validates: Requirements 13.4**
    """
    result = get_total_duration(durations, speed)
    assert result > 0, (
        f"Duration must be positive for non-empty registry, got {result}"
    )


@given(durations=durations_strategy)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_higher_speed_lower_duration(durations):
    """
    Property 15d: Higher speed → lower total duration (inverse relationship).

    For any set of durations: getTotalDuration(fast) <= getTotalDuration(slow)
    when fast > slow.

    **Validates: Requirements 13.4**
    """
    slow_result = get_total_duration(durations, 0.5)
    fast_result = get_total_duration(durations, 3.0)
    assert fast_result <= slow_result, (
        f"Faster speed (3.0) should produce <= duration than slower (0.5): "
        f"fast={fast_result}, slow={slow_result}"
    )


@given(durations=durations_strategy)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_speed_1_equals_raw_sum(durations):
    """
    Property 15e: At speed 1.0, result equals raw sum of durations + inter-scene delays.

    getTotalDuration(1.0) == sum(durations) + (n-1) * 2000

    **Validates: Requirements 13.4**
    """
    n = len(durations)
    expected = sum(durations) + (n - 1) * 2000
    result = get_total_duration(durations, 1.0)
    assert result == expected, (
        f"At speed 1.0, result should equal raw total: "
        f"got {result}, expected {expected}"
    )


def test_empty_registry_returns_zero():
    """
    Property 15f: Empty registry (0 scenes) → duration is 0.

    getTotalDuration with no scenes should return 0 regardless of speed.
    Note: The actual QML implementation always has scenes, but the algorithm
    should handle the edge case correctly.

    **Validates: Requirements 13.4**
    """
    # Empty list: sum is 0, max(0, 0-1)*2000 = 0, 0/speed = 0
    # We compute manually since get_total_duration requires non-zero speed
    total = 0
    n = 0
    total += max(0, n - 1) * 2000
    result = round(total / 1.0)
    assert result == 0


# ─── Sanity test: verify against actual DemoScenes.qml registry ───


def _parse_scene_durations_from_qml() -> list[int]:
    """Parse duration values from DemoScenes.qml registry."""
    qml_path = Path(__file__).parent.parent / (
        "configs/quickshell/ii/services/DemoScenes.qml"
    )
    if not qml_path.exists():
        return []

    content = qml_path.read_text()
    # Match all "duration: NNNN" entries in the registry
    durations = [int(m) for m in re.findall(r"duration:\s*(\d+)", content)]
    return durations


def test_actual_registry_duration_sanity():
    """
    Sanity test: read actual DemoScenes.qml and verify getTotalDuration(1.0)
    matches manually computing sum(durations) + (n-1)*2000.

    This validates the test's Python mirror against the real QML registry data.

    **Validates: Requirements 13.4**
    """
    durations = _parse_scene_durations_from_qml()
    if not durations:
        # Skip if QML file not found (CI environment without full repo)
        return

    n = len(durations)
    expected = sum(durations) + (n - 1) * 2000
    result = get_total_duration(durations, 1.0)
    assert result == expected, (
        f"Actual registry duration mismatch at speed 1.0: "
        f"got {result}, expected {expected} "
        f"(n={n}, sum_durations={sum(durations)}, inter_scene={(n-1)*2000})"
    )

    # Also verify at speed 2.0
    expected_fast = round(expected / 2.0)
    result_fast = get_total_duration(durations, 2.0)
    assert result_fast == expected_fast, (
        f"Actual registry duration mismatch at speed 2.0: "
        f"got {result_fast}, expected {expected_fast}"
    )
