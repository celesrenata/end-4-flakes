# Feature: ai-desktop-control, Property 9: Invalid hex color rejection
# Feature: ai-desktop-control, Property 12: Theme rate limiting
"""
Property-based tests for theme validation: hex color rejection and rate limiting.

Property 9: Any string not matching ^#[0-9A-Fa-f]{6}$ must be rejected by
_validate_hex_color, returning False.

Property 12: The token bucket enforces a maximum of 5 theme changes per 60-second
window. Requests beyond the 5th within the window are rejected. Tokens refill at
1 per 12 seconds (= 5 per 60 seconds).

**Validates: Requirements 1.6, 9.8**
"""

import re
from unittest.mock import patch

import pytest
from hypothesis import given, settings, assume
from hypothesis import strategies as st

from ii_desktop_mcp.tools.theme import (
    _TokenBucket,
    _validate_hex_color,
    _HEX_COLOR_PATTERN,
)


# --- Property 9: Invalid hex color rejection ---

_VALID_HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")


def _is_valid_hex(s: str) -> bool:
    """Ground truth check for valid hex color."""
    return _VALID_HEX_RE.match(s) is not None


# Strategy: strings missing the '#' prefix
_no_hash_prefix = st.text(min_size=1).filter(lambda s: not s.startswith("#"))

# Strategy: strings with # but wrong length (not exactly 7 chars total)
_wrong_length = st.one_of(
    # Too short: # + 1-5 hex chars
    st.integers(min_value=1, max_value=5).flatmap(
        lambda n: st.text(
            alphabet="0123456789ABCDEFabcdef", min_size=n, max_size=n
        ).map(lambda s: "#" + s)
    ),
    # Too long: # + 7+ hex chars
    st.integers(min_value=7, max_value=20).flatmap(
        lambda n: st.text(
            alphabet="0123456789ABCDEFabcdef", min_size=n, max_size=n
        ).map(lambda s: "#" + s)
    ),
)

# Strategy: # + 6 chars but containing non-hex characters
_non_hex_chars = st.text(
    alphabet=st.characters(
        blacklist_categories=(),
        blacklist_characters="0123456789ABCDEFabcdef",
    ),
    min_size=1,
    max_size=6,
).flatmap(
    lambda bad: st.text(
        alphabet="0123456789ABCDEFabcdef", min_size=0, max_size=5
    ).map(lambda good: "#" + (good + bad)[:6])
).filter(lambda s: len(s) == 7 and not _is_valid_hex(s))

# Strategy: empty string
_empty = st.just("")

# Strategy: general text that isn't a valid hex color
_arbitrary_invalid = st.text(min_size=0, max_size=50).filter(
    lambda s: not _is_valid_hex(s)
)

# Combined strategy for all invalid hex colors
_invalid_hex_colors = st.one_of(
    _no_hash_prefix,
    _wrong_length,
    _non_hex_chars,
    _empty,
    _arbitrary_invalid,
)


@settings(max_examples=100)
@given(color=_invalid_hex_colors)
def test_invalid_hex_color_rejected(color: str):
    """
    Property 9: For any string not matching ^#[0-9A-Fa-f]{6}$,
    _validate_hex_color must return False.

    **Validates: Requirements 1.6**
    """
    assert _validate_hex_color(color) is False, (
        f"Expected _validate_hex_color({color!r}) to return False "
        f"for invalid hex color, but got True"
    )


@settings(max_examples=100)
@given(color=_invalid_hex_colors)
def test_hex_color_pattern_rejects_invalid(color: str):
    """
    Property 9: Verify the compiled _HEX_COLOR_PATTERN regex also rejects
    the same invalid inputs.

    **Validates: Requirements 1.6**
    """
    assert _HEX_COLOR_PATTERN.match(color) is None, (
        f"Expected _HEX_COLOR_PATTERN to not match {color!r}, but it did"
    )


@settings(max_examples=100)
@given(
    hex_chars=st.text(
        alphabet="0123456789ABCDEFabcdef", min_size=6, max_size=6
    )
)
def test_valid_hex_color_accepted(hex_chars: str):
    """
    Sanity property: any string of exactly '#' + 6 hex digits must be accepted.
    Confirms the validator works for valid inputs (inverse of Property 9).
    """
    color = "#" + hex_chars
    assert _validate_hex_color(color) is True, (
        f"Expected _validate_hex_color({color!r}) to return True "
        f"for valid hex color, but got False"
    )


# --- Property 12: Theme rate limiting ---


@settings(max_examples=100)
@given(n=st.integers(min_value=6, max_value=20))
def test_theme_rate_limiting_rejects_beyond_capacity(n):
    """
    Property 12: For any N > 5 requests at the same instant (time not advancing),
    exactly the first 5 consume() calls return True, and the remaining N-5
    return False.

    This validates that the rate limiter enforces the 5-per-minute cap by
    rejecting excess requests when no time has elapsed for token refill.

    **Validates: Requirements 9.8**
    """
    fixed_time = 1000000.0

    with patch("ii_desktop_mcp.tools.theme.time.time", return_value=fixed_time):
        bucket = _TokenBucket(capacity=5, refill_rate=1.0 / 12.0)

    results = []
    with patch("ii_desktop_mcp.tools.theme.time.time", return_value=fixed_time):
        for _ in range(n):
            results.append(bucket.consume())

    successes = sum(1 for r in results if r is True)
    failures = sum(1 for r in results if r is False)

    assert successes == 5, (
        f"Expected exactly 5 successful consumes, got {successes} out of {n} attempts"
    )
    assert failures == n - 5, (
        f"Expected {n - 5} rejected consumes, got {failures} out of {n} attempts"
    )

    # First 5 must be True, rest must be False
    assert all(results[:5]), (
        f"First 5 results should all be True, got: {results[:5]}"
    )
    assert not any(results[5:]), (
        f"Results after 5th should all be False, got: {results[5:]}"
    )


@settings(max_examples=100)
@given(n=st.integers(min_value=6, max_value=20))
def test_theme_rate_limiting_refills_after_time(n):
    """
    Property 12 (supplementary): After consuming all 5 tokens, waiting 12+
    seconds allows exactly 1 new token to be available.

    This validates the refill mechanism ensures tokens become available
    over time at the specified rate.

    **Validates: Requirements 9.8**
    """
    initial_time = 1000000.0

    with patch("ii_desktop_mcp.tools.theme.time.time", return_value=initial_time):
        bucket = _TokenBucket(capacity=5, refill_rate=1.0 / 12.0)

    # Exhaust all 5 tokens at initial_time
    with patch("ii_desktop_mcp.tools.theme.time.time", return_value=initial_time):
        for _ in range(5):
            assert bucket.consume() is True

    # Confirm 6th is rejected at the same time
    with patch("ii_desktop_mcp.tools.theme.time.time", return_value=initial_time):
        assert bucket.consume() is False

    # Advance time by 12 seconds — exactly 1 token should refill
    refill_time = initial_time + 12.0
    with patch("ii_desktop_mcp.tools.theme.time.time", return_value=refill_time):
        assert bucket.consume() is True, (
            "After 12 seconds, 1 token should have refilled"
        )
        # But a second consume immediately after should fail
        assert bucket.consume() is False, (
            "Only 1 token refills per 12 seconds"
        )
