# Feature: ai-desktop-control, Property 19: Monitor resolution validation against available modes
"""
Property-based test for monitor resolution validation against available modes.

The `_validate_resolution_refresh` function checks whether a requested
resolution/refresh_rate combination exists in the monitor's available modes.
If the combination is not available, it returns a non-None error string
(validation_error). If valid, it returns None.

**Validates: Requirements 9.6**
"""

from hypothesis import given, settings, assume
from hypothesis import strategies as st

from ii_desktop_mcp.tools.monitor import _validate_resolution_refresh


# --- Test Fixtures ---

# A fixed set of known available modes for testing
KNOWN_MODES = [
    "2560x1440@143.97Hz",
    "1920x1080@60.00Hz",
    "1920x1080@144.00Hz",
    "3840x2160@60.00Hz",
    "1280x720@60.00Hz",
]

# Parsed versions of those modes for generating valid combos
VALID_RESOLUTIONS = ["2560x1440", "1920x1080", "3840x2160", "1280x720"]
VALID_COMBOS = [
    ("2560x1440", 143.97),
    ("1920x1080", 60.00),
    ("1920x1080", 144.00),
    ("3840x2160", 60.00),
    ("1280x720", 60.00),
]


def _make_monitor(available_modes=None):
    """Create a fake monitor dict with known available modes."""
    if available_modes is None:
        available_modes = KNOWN_MODES
    return {
        "name": "DP-1",
        "width": 2560,
        "height": 1440,
        "refreshRate": 143.97,
        "x": 0,
        "y": 0,
        "scale": 1.0,
        "availableModes": available_modes,
    }


# --- Strategies ---

# Resolutions that do NOT match any known mode
# Use widths/heights that avoid the known set
invalid_width = st.integers(min_value=100, max_value=9999).filter(
    lambda w: w not in (2560, 1920, 3840, 1280)
)
invalid_height = st.integers(min_value=100, max_value=9999).filter(
    lambda h: h not in (1440, 1080, 2160, 720)
)

# Strategy for resolutions not in the available modes (at least width or height differs)
invalid_resolution = st.builds(
    lambda w, h: f"{w}x{h}",
    w=invalid_width,
    h=invalid_height,
)

# Strategy for refresh rates that don't match any known mode (outside 1.0 Hz tolerance)
# Known refresh rates: 143.97, 60.00, 144.00
# Must differ by more than 1.0 Hz from all of those
invalid_refresh_rate = st.floats(min_value=30.0, max_value=300.0).filter(
    lambda r: all(abs(r - known) > 1.0 for known in (143.97, 60.00, 144.00))
)

# Strategy for valid resolution strings that exist in modes
valid_resolution = st.sampled_from(VALID_RESOLUTIONS)

# Strategy for valid combo (resolution + matching refresh)
valid_combo = st.sampled_from(VALID_COMBOS)


# --- Property Tests ---


@settings(max_examples=100)
@given(resolution=invalid_resolution, refresh_rate=st.floats(min_value=30.0, max_value=300.0))
def test_invalid_resolution_returns_error(resolution, refresh_rate):
    """
    Property 19: For any resolution where both width AND height are not in
    the available modes, _validate_resolution_refresh returns a non-None
    error string regardless of refresh rate.

    **Validates: Requirements 9.6**
    """
    monitor = _make_monitor()
    result = _validate_resolution_refresh(monitor, resolution, refresh_rate)
    assert result is not None, (
        f"Expected validation error for unsupported resolution '{resolution}@{refresh_rate}Hz', "
        f"but got None (valid). Available modes: {KNOWN_MODES}"
    )
    assert isinstance(result, str), (
        f"Expected error string, got {type(result)}"
    )
    assert "Unsupported mode" in result or "Invalid" in result, (
        f"Error message should indicate unsupported mode, got: {result}"
    )


@settings(max_examples=100)
@given(
    resolution=valid_resolution,
    refresh_rate=invalid_refresh_rate,
)
def test_valid_resolution_invalid_refresh_returns_error(resolution, refresh_rate):
    """
    Property 19: For a valid resolution paired with a refresh rate that
    doesn't match any mode (outside 1.0 Hz tolerance), the function returns
    a non-None error string.

    **Validates: Requirements 9.6**
    """
    # Filter: ensure this combo isn't accidentally valid
    # (a valid resolution with a non-matching refresh must still fail)
    monitor = _make_monitor()
    result = _validate_resolution_refresh(monitor, resolution, refresh_rate)
    assert result is not None, (
        f"Expected validation error for '{resolution}@{refresh_rate}Hz' "
        f"(refresh not in available modes), but got None. "
        f"Available modes: {KNOWN_MODES}"
    )
    assert isinstance(result, str)


@settings(max_examples=100)
@given(combo=valid_combo)
def test_valid_resolution_and_refresh_returns_none(combo):
    """
    Property 19 (positive case): For resolution/refresh combinations that
    DO exist in available modes (within 1.0 Hz tolerance), the function
    returns None (valid).

    **Validates: Requirements 9.6**
    """
    resolution, refresh_rate = combo
    monitor = _make_monitor()
    result = _validate_resolution_refresh(monitor, resolution, refresh_rate)
    assert result is None, (
        f"Expected None (valid) for supported mode '{resolution}@{refresh_rate}Hz', "
        f"but got error: {result}"
    )


@settings(max_examples=100)
@given(refresh_rate=invalid_refresh_rate)
def test_refresh_only_invalid_returns_error(refresh_rate):
    """
    Property 19: When only refresh_rate is specified (resolution=None),
    the function uses the monitor's current resolution. If the refresh rate
    doesn't match any mode for that resolution, it returns an error.

    The monitor's current resolution is 2560x1440, available refresh: 143.97Hz.
    Any refresh_rate outside ±1.0 Hz of 143.97 should fail.

    **Validates: Requirements 9.6**
    """
    monitor = _make_monitor()
    result = _validate_resolution_refresh(monitor, None, refresh_rate)
    assert result is not None, (
        f"Expected validation error for current resolution 2560x1440 with "
        f"refresh {refresh_rate}Hz (only 143.97Hz available), but got None."
    )
    assert isinstance(result, str)


@settings(max_examples=100)
@given(data=st.data())
def test_neither_resolution_nor_refresh_always_valid(data):
    """
    Property 19 (boundary): When neither resolution nor refresh_rate is
    specified (both None), validation always passes (returns None).

    **Validates: Requirements 9.6**
    """
    monitor = _make_monitor()
    result = _validate_resolution_refresh(monitor, None, None)
    assert result is None, (
        f"Expected None when no resolution/refresh specified, got: {result}"
    )
