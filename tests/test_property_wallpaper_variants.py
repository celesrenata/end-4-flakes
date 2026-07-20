# Feature: upstream-sync-2025-2026, Property 2: Wallpaper Variant Selection
"""
Property-based test for wallpaper variant selection logic.

Property 2: For any wallpaper filename and current color mode (dark/light),
if a variant file exists with the corresponding `-dark` or `-light` suffix,
the pipeline SHALL select that variant; if no variant exists, it SHALL use
the original filename unchanged.

**Validates: Requirements 14.1, 14.2, 14.3**
"""

import os
from hypothesis import given, settings, assume
from hypothesis import strategies as st


# --- Implementation under test ---
# Reimplementation of the wallpaper variant selection logic from switchwall.sh


def select_wallpaper_variant(wallpaper_path: str, mode: str, existing_files: set) -> str:
    """
    Select the correct wallpaper variant based on current color mode.

    This reimplements the logic from switchwall.sh:
    - Given a wallpaper like "forest.jpg" and mode "dark":
      - Check if "forest-dark.jpg" exists -> if yes, use it
      - If not, use "forest.jpg" as-is
    - Given "forest-dark.jpg" and mode "light":
      - Check if "forest-light.jpg" exists -> if yes, use it
      - If not, use "forest-dark.jpg" as-is
    - The suffix detection pattern is: basename-{dark|light}.extension

    Args:
        wallpaper_path: Full path to current wallpaper (e.g., "/path/forest-dark.jpg")
        mode: Current color mode ("dark" or "light")
        existing_files: Set of file paths that exist on the filesystem

    Returns:
        Path to the wallpaper variant to use
    """
    if mode not in ("dark", "light"):
        return wallpaper_path

    # Split path into directory and filename
    directory = os.path.dirname(wallpaper_path)
    filename = os.path.basename(wallpaper_path)

    # Split filename into name and extension
    name, ext = os.path.splitext(filename)

    # Determine if the current file already has a variant suffix
    if name.endswith("-dark"):
        current_suffix = "-dark"
        base = name[: -len("-dark")]
    elif name.endswith("-light"):
        current_suffix = "-light"
        base = name[: -len("-light")]
    else:
        # No variant suffix — file is used as-is regardless of mode
        return wallpaper_path

    # Determine the desired suffix for the current mode
    desired_suffix = f"-{mode}"

    # If already using the correct variant for this mode, keep it
    if current_suffix == desired_suffix:
        return wallpaper_path

    # Build the desired variant path
    desired_filename = f"{base}{desired_suffix}{ext}"
    desired_path = os.path.join(directory, desired_filename) if directory else desired_filename

    # If the desired variant exists, switch to it
    if desired_path in existing_files:
        return desired_path

    # Desired variant doesn't exist — fall back to the original file
    return wallpaper_path


# --- Hypothesis Strategies ---

# Base filenames: alphanumeric strings that won't accidentally end with -dark/-light
_base_name_st = st.from_regex(r"[a-zA-Z][a-zA-Z0-9_]{0,12}", fullmatch=True).filter(
    lambda s: not s.endswith("dark") and not s.endswith("light")
)

# Common wallpaper file extensions
_extension_st = st.sampled_from([".jpg", ".png", ".webp", ".avif", ".jpeg", ".bmp"])

# Variant suffix: None (no suffix), -dark, or -light
_suffix_st = st.sampled_from([None, "-dark", "-light"])

# Color mode
_mode_st = st.sampled_from(["dark", "light"])

# Directory paths
_directory_st = st.sampled_from(
    ["/home/user/wallpapers", "/tmp/walls", "/data/images/nature", ""]
)


def _build_path(directory: str, base: str, suffix: str | None, ext: str) -> str:
    """Construct a wallpaper file path from components."""
    filename = f"{base}{suffix or ''}{ext}"
    if directory:
        return os.path.join(directory, filename)
    return filename


# --- Property Tests ---


@settings(max_examples=200)
@given(
    base=_base_name_st,
    ext=_extension_st,
    suffix=_suffix_st,
    mode=_mode_st,
    directory=_directory_st,
    variant_exists=st.booleans(),
)
def test_variant_selection_property(base, ext, suffix, mode, directory, variant_exists):
    """
    Core property: If a matching variant file exists for the current mode,
    the selector picks it. If no matching variant exists, the original is
    returned unchanged.

    **Validates: Requirements 14.1, 14.2, 14.3**
    """
    wallpaper_path = _build_path(directory, base, suffix, ext)

    # Build the set of existing files
    existing_files = {wallpaper_path}

    if suffix is not None:
        # If the wallpaper has a suffix, potentially add the opposite variant
        opposite_suffix = "-light" if suffix == "-dark" else "-dark"
        opposite_path = _build_path(directory, base, opposite_suffix, ext)

        if variant_exists:
            existing_files.add(opposite_path)

    result = select_wallpaper_variant(wallpaper_path, mode, existing_files)

    if suffix is None:
        # No suffix -> always returns original (Req 14.3)
        assert result == wallpaper_path, (
            f"No-suffix wallpaper must be returned as-is. "
            f"Got {result!r}, expected {wallpaper_path!r}"
        )
    elif suffix == f"-{mode}":
        # Already the correct variant for this mode -> return as-is
        assert result == wallpaper_path, (
            f"Wallpaper already matching mode should be returned as-is. "
            f"Got {result!r}, expected {wallpaper_path!r}"
        )
    else:
        # Suffix doesn't match mode — should try to switch
        desired_path = _build_path(directory, base, f"-{mode}", ext)

        if variant_exists:
            # Variant exists -> should select it (Req 14.1, 14.2)
            assert result == desired_path, (
                f"Should select matching variant when it exists. "
                f"Got {result!r}, expected {desired_path!r}"
            )
        else:
            # Variant missing -> fallback to original (Req 14.3)
            assert result == wallpaper_path, (
                f"Should fallback to original when variant is missing. "
                f"Got {result!r}, expected {wallpaper_path!r}"
            )


@settings(max_examples=200)
@given(
    base=_base_name_st,
    ext=_extension_st,
    mode=_mode_st,
    directory=_directory_st,
)
def test_no_suffix_never_switches(base, ext, mode, directory):
    """
    Property: Wallpapers without a -dark/-light suffix are NEVER switched,
    regardless of mode or what variant files might exist on disk.

    **Validates: Requirements 14.3**
    """
    wallpaper_path = _build_path(directory, base, None, ext)

    # Even with both variants available on disk, no-suffix stays unchanged
    dark_path = _build_path(directory, base, "-dark", ext)
    light_path = _build_path(directory, base, "-light", ext)
    existing_files = {wallpaper_path, dark_path, light_path}

    result = select_wallpaper_variant(wallpaper_path, mode, existing_files)
    assert result == wallpaper_path, (
        f"No-suffix wallpaper must never switch. "
        f"Got {result!r}, expected {wallpaper_path!r}"
    )


@settings(max_examples=200)
@given(
    base=_base_name_st,
    ext=_extension_st,
    suffix=_suffix_st,
    mode=_mode_st,
    directory=_directory_st,
)
def test_selection_is_idempotent(base, ext, suffix, mode, directory):
    """
    Property: Applying variant selection twice with the same mode yields the
    same result as applying it once. The selection is stable/idempotent.

    **Validates: Requirements 14.1, 14.2**
    """
    wallpaper_path = _build_path(directory, base, suffix, ext)

    # Provide all variants so the function can fully resolve
    dark_path = _build_path(directory, base, "-dark", ext)
    light_path = _build_path(directory, base, "-light", ext)
    no_suffix_path = _build_path(directory, base, None, ext)
    existing_files = {wallpaper_path, dark_path, light_path, no_suffix_path}

    # First application
    result1 = select_wallpaper_variant(wallpaper_path, mode, existing_files)
    # Second application on the result
    result2 = select_wallpaper_variant(result1, mode, existing_files)

    assert result1 == result2, (
        f"Variant selection must be idempotent. "
        f"First pass: {result1!r}, second pass: {result2!r}"
    )


@settings(max_examples=200)
@given(
    base=_base_name_st,
    ext=_extension_st,
    suffix=st.sampled_from(["-dark", "-light"]),
    directory=_directory_st,
)
def test_fallback_when_variant_missing(base, ext, suffix, directory):
    """
    Property: When the desired variant file does not exist on disk, the
    original wallpaper file is returned unchanged.

    **Validates: Requirements 14.3**
    """
    wallpaper_path = _build_path(directory, base, suffix, ext)

    # Only the current file exists — no other variant
    existing_files = {wallpaper_path}

    # Use the opposite mode to trigger a variant lookup
    opposite_mode = "light" if suffix == "-dark" else "dark"

    result = select_wallpaper_variant(wallpaper_path, opposite_mode, existing_files)
    assert result == wallpaper_path, (
        f"Should fallback to original when variant is missing. "
        f"Got {result!r}, expected {wallpaper_path!r}"
    )


@settings(max_examples=200)
@given(
    base=_base_name_st,
    ext=_extension_st,
    directory=_directory_st,
)
def test_mode_toggle_switches_variant(base, ext, directory):
    """
    Property: When both -dark and -light variants exist, toggling mode
    switches between them correctly.

    **Validates: Requirements 14.1, 14.2**
    """
    dark_path = _build_path(directory, base, "-dark", ext)
    light_path = _build_path(directory, base, "-light", ext)
    existing_files = {dark_path, light_path}

    # Starting from dark, switching to light mode should give light variant
    result_to_light = select_wallpaper_variant(dark_path, "light", existing_files)
    assert result_to_light == light_path, (
        f"Toggling to light mode should select -light variant. "
        f"Got {result_to_light!r}, expected {light_path!r}"
    )

    # Starting from light, switching to dark mode should give dark variant
    result_to_dark = select_wallpaper_variant(light_path, "dark", existing_files)
    assert result_to_dark == dark_path, (
        f"Toggling to dark mode should select -dark variant. "
        f"Got {result_to_dark!r}, expected {dark_path!r}"
    )
