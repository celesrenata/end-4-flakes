# Feature: ai-desktop-control, Property 11: Hyprland keyword denylist enforcement
"""
Property-based test for Hyprland keyword denylist enforcement.

The `_is_keyword_denied` function checks whether any colon-separated segment
of a keyword matches the DANGEROUS_KEYWORDS set. If so, `hypr_set_option`
returns a validation_error and never invokes hyprctl.

**Validates: Requirements 9.5**
"""

from hypothesis import given, settings, assume
from hypothesis import strategies as st

from ii_desktop_mcp.tools.hypr_config import _is_keyword_denied, DANGEROUS_KEYWORDS


# --- Strategies ---

# Strategy for generating a single dangerous keyword (direct match)
dangerous_keyword_direct = st.sampled_from(sorted(DANGEROUS_KEYWORDS))

# Strategy for safe segment names (identifiers that don't collide with denylist)
safe_segment = st.text(
    alphabet=st.characters(whitelist_categories=("Ll", "Lu", "Nd"), whitelist_characters="_-"),
    min_size=1,
    max_size=20,
).filter(lambda s: s not in DANGEROUS_KEYWORDS)

# Strategy for a keyword with a dangerous segment prefixed by safe segments
# e.g. "foo:exec", "bar:baz:plugin"
dangerous_keyword_with_prefix = st.builds(
    lambda parts, dangerous: ":".join(parts + [dangerous]),
    parts=st.lists(safe_segment, min_size=1, max_size=3),
    dangerous=dangerous_keyword_direct,
)

# Strategy for a keyword with a dangerous segment followed by safe segments
# e.g. "exec:bar", "bind:something:else"
dangerous_keyword_with_suffix = st.builds(
    lambda dangerous, parts: ":".join([dangerous] + parts),
    dangerous=dangerous_keyword_direct,
    parts=st.lists(safe_segment, min_size=1, max_size=3),
)

# Strategy for a keyword with a dangerous segment in the middle
# e.g. "foo:exec:bar", "a:plugin:b"
dangerous_keyword_in_middle = st.builds(
    lambda prefix, dangerous, suffix: ":".join(prefix + [dangerous] + suffix),
    prefix=st.lists(safe_segment, min_size=1, max_size=2),
    dangerous=dangerous_keyword_direct,
    suffix=st.lists(safe_segment, min_size=1, max_size=2),
)

# Combined strategy for any keyword that must be denied
any_dangerous_keyword = st.one_of(
    dangerous_keyword_direct,
    dangerous_keyword_with_prefix,
    dangerous_keyword_with_suffix,
    dangerous_keyword_in_middle,
)

# Strategy for completely safe keywords (no segment matches denylist)
safe_keyword = st.builds(
    lambda parts: ":".join(parts),
    parts=st.lists(safe_segment, min_size=1, max_size=4),
)


# --- Property Tests ---


@settings(max_examples=100)
@given(keyword=any_dangerous_keyword)
def test_keyword_denylist_rejects_dangerous_keywords(keyword):
    """
    Property 11: For any keyword containing a colon-separated segment that
    matches an entry in DANGEROUS_KEYWORDS, _is_keyword_denied returns True.

    This covers:
    - Direct matches ("exec", "bind", "plugin")
    - Prefix matches ("foo:exec", "bar:baz:bind")
    - Suffix matches ("exec:bar", "plugin:something")
    - Middle matches ("foo:exec:bar", "a:plugin:b")

    **Validates: Requirements 9.5**
    """
    assert _is_keyword_denied(keyword) is True, (
        f"Expected keyword '{keyword}' to be denied. "
        f"Segments: {keyword.split(':')}, "
        f"Denylist: {DANGEROUS_KEYWORDS}"
    )


@settings(max_examples=100)
@given(keyword=safe_keyword)
def test_keyword_denylist_allows_safe_keywords(keyword):
    """
    Property 11 (inverse): For any keyword where NO colon-separated segment
    matches DANGEROUS_KEYWORDS, _is_keyword_denied returns False.

    This verifies safe keywords like "general:gaps_in", "decoration:rounding"
    pass through without being blocked.

    **Validates: Requirements 9.5**
    """
    assert _is_keyword_denied(keyword) is False, (
        f"Expected keyword '{keyword}' to be allowed. "
        f"Segments: {keyword.split(':')}, "
        f"Denylist: {DANGEROUS_KEYWORDS}"
    )


@settings(max_examples=100)
@given(dangerous=dangerous_keyword_direct)
def test_keyword_denylist_direct_match(dangerous):
    """
    Property 11 (direct): Each entry in the denylist is itself blocked
    when used as a bare keyword.

    **Validates: Requirements 9.5**
    """
    assert _is_keyword_denied(dangerous) is True, (
        f"Direct denylist entry '{dangerous}' should always be denied"
    )
