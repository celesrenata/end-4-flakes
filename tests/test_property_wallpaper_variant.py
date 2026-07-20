# Feature: upstream-sync-2025-2026, Property 2: Wallpaper Variant Selection
"""
Property-based test for wallpaper variant selection logic.

The wallpaper variant selector picks the correct wallpaper file based on the
current color mode (dark/light) and available variant files on disk.

**Validates: Requirements 14.1, 14.2, 14.3**
"""

import os
from hypothesis import given, settings, assume
from hypothesis import strategies as st


# --- Implementation under test ---


def select_wallpaper_variant(wallpaper_path: str, mode: str, existing_files: set) -> str:
    """
    Select the correct wallpaper variant based on current mode.

    Args:
        wallpaper_path: Full path to current wallpaper (e.g., "/path/forest-dark.jpg")
        mode: Current color mode ("dark" or "light")
        existing_files: Set of files that exist on the filesystem

    Returns:
        Path to the wallpaper to use
    """
    if mode not in ("dark", "light"):
        return wallpaper_path

    # Split path into directory, base name, and extension
    directory = os.path.dirname(wallpaper_path)
    filename = os.path.basename(wallpaper_path)

    # Split filename into name and extension
    name, ext = os.path.splitext(filename)

    # Determine current suffix and base
    if name.endswith("-dark"):
        current_suffix = "-dark"
        base = name[: -len("-dark")]
    elif name.endswith("-light"):
        current_suffix = "-light"
        base = name[: -len("-light")]
    else:
        # No suffix — use as-is regardless of mode
        return wallpaper_path

    # Determine desired suffix based on mode
    desired_suffix = f"-{mode}"

    # If already using the correct variant, return as-is
    if current_suffix == desired_suffix:
        return wallpaper_path

    # Build the desired variant path
    desired_filename = f"{base}{desired_suffix}{ext}"
    desired_path = os.path.join(directory, desired_filename)

    # If the desired variant exists, use it
    if desired_path in existing_files:
        return desired_path

    # Desired variant doesn't exist — fall back to original
    return wallpaper_path


# --- Strategies ---

# Base names: non-empty strings of letters and digits, avoiding accidental -dark/-light
base_name_st = st.from_regex(r"[a-zA-Z][a-zA-Z0-9_]{0,15}", fullmatch=True).filter(
    lambda s: not s.endswith("-dark")
    and not s.endswith("-light")
    and "-dark-" not in s
    and "-light-" not in s
)

extension_st = st.sampled_from([".jpg", ".png", ".webp", ".avif", ".jpeg", ".bmp"])

suffix_st = st.sampled_from([None, "-dark", "-light"])

mode_st = st.sampled_from(["dark", "light"])

directory_st = st.sampled_from(
    ["/home/user/wallpapers", "/tmp/walls", "/data/images", ""]
)


def build_path(directory: str, base: str, suffix: str | None, ext: str) -> str:
    """Helper to construct a wallpaper path."""
    filename = f"{base}{suffix or ''}{ext}"
    if directory:
        return os.path.join(directory, filename)
    return filename


# --- Property Tests ---


@settings(max_examples=200)
@given(
    base=base_name_st,
    ext=extension_st,
    suffix=suffix_st,
    mode=mode_st,
    directory=directory_st,
    variant_exists=st.booleans(),
)
def test_correct_variant_selection(base, ext, suffix, mode, directory, variant_exists):
    """
    Property: When a matching variant file exists, the selector picks it.
    When no matching variant exists, it returns the original unchanged.

    **Validates: Requirements 14.1, 14.2, 14.3**
    """
    # Build the input wallpaper path
    wallpaper_path = build_path(directory, base, suffix, ext)

    # Build existing_files set
    existing_files = {wallpaper_path}

    if suffix is not None:
        # Determine the opposite suffix
        opposite_suffix = "-light" if suffix == "-dark" else "-dark"
        opposite_path = build_path(directory, base, opposite_suffix, ext)

        if variant_exists:
            existing_files.add(opposite_path)

    result = select_wallpaper_variant(wallpaper_path, mode, existing_files)

    if suffix is None:
        # No suffix → always return original (Requirement 14.3)
        assert result == wallpaper_path, (
            f"No suffix wallpaper should be returned as-is. "
            f"Got {result!r} instead of {wallpaper_path!r}"
        )
    elif suffix == f"-{mode}":
        # Already correct variant → return as-is
        assert result == wallpaper_path, (
            f"Already correct variant should be returned as-is. "
            f"Got {result!r} instead of {wallpaper_path!r}"
        )
    else:
        # Has a suffix that doesn't match mode
        desired_suffix = f"-{mode}"
        desired_path = build_path(directory, base, desired_suffix, ext)

        if variant_exists:
            # Matching variant exists → should switch (Requirement 14.1)
            assert result == desired_path, (
                f"Should select matching variant. "
                f"Got {result!r} instead of {desired_path!r}"
            )
        else:
            # No matching variant → fallback to original (Requirement 14.3 graceful)
            assert result == wallpaper_path, (
                f"Should fallback to original when variant missing. "
                f"Got {result!r} instead of {wallpaper_path!r}"
            )


@settings(max_examples=200)
@given(
    base=base_name_st,
    ext=extension_st,
    mode=mode_st,
    directory=directory_st,
)
def test_no_suffix_means_no_change(base, ext, mode, directory):
    """
    Property: Files without -dark/-light suffix are always returned as-is,
    regardless of mode.

    **Validates: Requirements 14.3**
    """
    wallpaper_path = build_path(directory, base, None, ext)

    # Even if variant files happen to exist, no-suffix wallpapers don't switch
    dark_path = build_path(directory, base, "-dark", ext)
    light_path = build_path(directory, base, "-light", ext)
    existing_files = {wallpaper_path, dark_path, light_path}

    result = select_wallpaper_variant(wallpaper_path, mode, existing_files)
    assert result == wallpaper_path, (
        f"No-suffix wallpaper must remain unchanged. Got {result!r}"
    )


@settings(max_examples=200)
@given(
    base=base_name_st,
    ext=extension_st,
    suffix=suffix_st,
    mode=mode_st,
    directory=directory_st,
)
def test_idempotency(base, ext, suffix, mode, directory):
    """
    Property: Applying variant selection twice yields the same result as once.
    If already using the correct variant, selecting again returns same result.

    **Validates: Requirements 14.1, 14.2**
    """
    wallpaper_path = build_path(directory, base, suffix, ext)

    # Build a full set of existing files (both variants exist)
    dark_path = build_path(directory, base, "-dark", ext)
    light_path = build_path(directory, base, "-light", ext)
    no_suffix_path = build_path(directory, base, None, ext)
    existing_files = {wallpaper_path, dark_path, light_path, no_suffix_path}

    # First application
    result1 = select_wallpaper_variant(wallpaper_path, mode, existing_files)
    # Second application on the result
    result2 = select_wallpaper_variant(result1, mode, existing_files)

    assert result1 == result2, (
        f"Variant selection must be idempotent. "
        f"First: {result1!r}, Second: {result2!r}"
    )


@settings(max_examples=200)
@given(
    base=base_name_st,
    ext=extension_st,
    suffix=st.sampled_from(["-dark", "-light"]),
    directory=directory_st,
)
def test_graceful_fallback(base, ext, suffix, directory):
    """
    Property: When no matching variant file exists, the original is returned unchanged.

    **Validates: Requirements 14.3**
    """
    wallpaper_path = build_path(directory, base, suffix, ext)

    # Only the current file exists — no variant available
    existing_files = {wallpaper_path}

    # Opposite mode to trigger variant lookup
    opposite_mode = "light" if suffix == "-dark" else "dark"

    result = select_wallpaper_variant(wallpaper_path, opposite_mode, existing_files)
    assert result == wallpaper_path, (
        f"Should fallback to original when variant is missing. "
        f"Got {result!r} instead of {wallpaper_path!r}"
    )
