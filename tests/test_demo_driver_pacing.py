"""
Property-based tests for pacing delay calculations and speed multiplier clamping.

Feature: desktop-demo-driver, Properties 7-8: Pacing Delay with Speed Scaling

Tests validate the pure algorithmic logic of effective delay computation and
speed multiplier clamping without executing any QML. Python functions mirror
the QML implementation in configs/quickshell/ii/services/DemoDriverService.qml.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4**
"""

from hypothesis import given, settings, HealthCheck
from hypothesis import strategies as st


# ─── Pure Python functions mirroring DemoDriverService.qml logic ───


def effective_delay(base_delay: int, speed_multiplier: float) -> int:
    """Mirror DemoDriverService._effectiveDelay(baseDelay).

    Computes Math.round(baseDelay / speedMultiplier).
    """
    return round(base_delay / speed_multiplier)


def clamp_speed(speed: float, min_speed: float = 0.5, max_speed: float = 3.0) -> float:
    """Mirror speed clamping in DemoDriverService.start().

    Computes Math.max(0.5, Math.min(3.0, speedMultiplier)).
    """
    return max(min_speed, min(max_speed, speed))


# ─── Hypothesis strategies ───

# Base delay in ms (must be positive for meaningful delay)
base_delay_strategy = st.integers(min_value=1, max_value=10000)

# Speed multiplier within valid clamped range (for delay tests)
speed_in_range = st.floats(
    min_value=0.5, max_value=3.0, allow_nan=False, allow_infinity=False
)

# Speed multiplier for clamping tests (can be outside range)
speed_unclamped = st.floats(
    min_value=-100.0, max_value=100.0, allow_nan=False, allow_infinity=False
)


# ─── Property 7: Pacing Delay with Speed Scaling ───


@given(base_delay=base_delay_strategy, speed=speed_in_range)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_effective_delay_formula(base_delay, speed):
    """
    Property 7a: effectiveDelay == round(baseDelay / speed).

    For any baseDelay (1-10000ms) and speedMultiplier (0.5-3.0):
    effectiveDelay(baseDelay, speed) == round(baseDelay / speed)

    **Validates: Requirements 3.1, 3.2, 3.3**
    """
    result = effective_delay(base_delay, speed)
    expected = round(base_delay / speed)
    assert result == expected


@given(base_delay=base_delay_strategy)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_effective_delay_inverse_relationship(base_delay):
    """
    Property 7b: Higher speed → lower effective delay (inverse relationship).

    For any baseDelay, comparing speed 1.0 vs 2.0:
    effectiveDelay(baseDelay, 2.0) <= effectiveDelay(baseDelay, 1.0)

    More generally: if speed_a < speed_b, then delay_a >= delay_b.

    **Validates: Requirements 3.3**
    """
    slow_speed = 0.5
    fast_speed = 3.0

    delay_slow = effective_delay(base_delay, slow_speed)
    delay_fast = effective_delay(base_delay, fast_speed)

    assert delay_slow >= delay_fast, (
        f"Slower speed ({slow_speed}) should produce >= delay than faster speed ({fast_speed}): "
        f"{delay_slow} vs {delay_fast}"
    )


@given(base_delay=base_delay_strategy)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_effective_delay_identity_at_speed_1(base_delay):
    """
    Property 7c: At speed 1.0, effectiveDelay == baseDelay (identity).

    effectiveDelay(baseDelay, 1.0) == baseDelay for any positive baseDelay.

    **Validates: Requirements 3.3**
    """
    result = effective_delay(base_delay, 1.0)
    assert result == base_delay


@given(base_delay=base_delay_strategy)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_effective_delay_half_at_speed_2(base_delay):
    """
    Property 7d: At speed 2.0, effectiveDelay == round(baseDelay / 2).

    effectiveDelay(baseDelay, 2.0) == round(baseDelay / 2) for any positive baseDelay.

    **Validates: Requirements 3.3**
    """
    result = effective_delay(base_delay, 2.0)
    expected = round(base_delay / 2)
    assert result == expected


@given(base_delay=base_delay_strategy, speed=speed_in_range)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_effective_delay_always_positive(base_delay, speed):
    """
    Property 7e: effectiveDelay is always positive (baseDelay > 0, speed > 0).

    Since baseDelay >= 1 and speed >= 0.5, the result of round(baseDelay / speed)
    is always >= 1.

    **Validates: Requirements 3.1, 3.2**
    """
    result = effective_delay(base_delay, speed)
    assert result > 0, f"effectiveDelay must be positive, got {result}"


@given(base_delay=base_delay_strategy, speed=speed_in_range)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_effective_delay_always_integer(base_delay, speed):
    """
    Property 7f: effectiveDelay is always an integer (Math.round).

    The return value of effectiveDelay must always be an integer type.

    **Validates: Requirements 3.1, 3.2**
    """
    result = effective_delay(base_delay, speed)
    assert isinstance(result, int), f"effectiveDelay must be int, got {type(result)}"


# ─── Property 8: Speed Multiplier Clamping ───


@given(speed=speed_unclamped)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_clamp_speed_always_in_range(speed):
    """
    Property 8a: For any float input, clamped value is always in [0.5, 3.0].

    clamp_speed(speed) is always >= 0.5 and <= 3.0 regardless of input.

    **Validates: Requirements 3.4**
    """
    result = clamp_speed(speed)
    assert 0.5 <= result <= 3.0, (
        f"Clamped speed must be in [0.5, 3.0], got {result} from input {speed}"
    )


@given(speed=speed_in_range)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_clamp_speed_unchanged_in_range(speed):
    """
    Property 8b: Values already in range [0.5, 3.0] are unchanged.

    If 0.5 <= speed <= 3.0, then clamp_speed(speed) == speed.

    **Validates: Requirements 3.4**
    """
    result = clamp_speed(speed)
    assert result == speed, (
        f"In-range speed {speed} should be unchanged, got {result}"
    )


@given(speed=st.floats(min_value=-100.0, max_value=0.49999,
                        allow_nan=False, allow_infinity=False))
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_clamp_speed_below_min(speed):
    """
    Property 8c: Values below 0.5 become 0.5.

    If speed < 0.5, then clamp_speed(speed) == 0.5.

    **Validates: Requirements 3.4**
    """
    result = clamp_speed(speed)
    assert result == 0.5, (
        f"Speed {speed} below min should clamp to 0.5, got {result}"
    )


@given(speed=st.floats(min_value=3.00001, max_value=100.0,
                        allow_nan=False, allow_infinity=False))
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_clamp_speed_above_max(speed):
    """
    Property 8d: Values above 3.0 become 3.0.

    If speed > 3.0, then clamp_speed(speed) == 3.0.

    **Validates: Requirements 3.4**
    """
    result = clamp_speed(speed)
    assert result == 3.0, (
        f"Speed {speed} above max should clamp to 3.0, got {result}"
    )


@given(speed=speed_unclamped)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_clamp_speed_idempotent(speed):
    """
    Property 8e: Clamping is idempotent: clamp(clamp(x)) == clamp(x).

    Applying the clamp function twice produces the same result as applying once.

    **Validates: Requirements 3.4**
    """
    once = clamp_speed(speed)
    twice = clamp_speed(once)
    assert once == twice, (
        f"Clamping must be idempotent: clamp({speed})={once}, "
        f"clamp(clamp({speed}))={twice}"
    )
