# Feature: ai-desktop-control, Property 1: Ledger records all mutations before returning
"""
Property-based integration test for Change Ledger mutation recording.

Property 1: For each mutating tool (theme_apply_wallpaper, theme_apply_color,
hypr_set_option, hypr_add_window_rule, hypr_set_animation), invoking the tool
with valid parameters (mocked subprocess) SHALL result in the Change Ledger
containing an entry with the correct tool_name and params.

The key property: after a successful invocation, the ledger always has at least
one entry with the correct tool_name.

**Validates: Requirements 1.8, 2.2, 2.5, 2.8, 4.3, 5.9, 8.1**
"""

import asyncio
import json
from pathlib import Path
from unittest.mock import AsyncMock, patch, MagicMock

from hypothesis import given, settings
from hypothesis import strategies as st
from mcp.server.fastmcp import FastMCP

from ii_desktop_mcp.core.ledger import ChangeLedger
from ii_desktop_mcp.core.subprocess import CommandResult


def run_async(coro):
    """Helper to run an async coroutine in a synchronous test context."""
    return asyncio.run(coro)


# --- Strategies ---

# Safe Hyprland keywords (no denylist segments)
_safe_keywords = st.sampled_from([
    "general:gaps_in",
    "general:gaps_out",
    "decoration:rounding",
    "animations:enabled",
    "decoration:blur:size",
    "general:border_size",
    "decoration:shadow:range",
    "misc:vfr",
])

# Simple string values for hyprctl keywords
_keyword_values = st.sampled_from(["0", "1", "5", "10", "15", "20", "true", "false"])

# Window rule strings
_window_rules = st.sampled_from([
    "float",
    "tile",
    "size 800 600",
    "move 100 100",
    "opacity 0.9",
    "pin",
    "nofocus",
])

# Window match criteria
_window_matches = st.sampled_from([
    "class:^(pavucontrol)$",
    "class:^(firefox)$",
    "title:^(Open File)$",
    "class:^(kitty)$",
    "title:^(Volume Control)$",
])

# Animation names
_animation_names = st.sampled_from([
    "windows",
    "fade",
    "border",
    "borderangle",
    "workspaces",
])

# Valid color scheme variants
_schemes = st.sampled_from([
    "tonalSpot",
    "content",
    "expressive",
    "fidelity",
    "neutral",
    "monochrome",
    "vibrant",
    "rainbow",
    "fruitSalad",
])

# Valid hex colors
_hex_colors = st.text(
    alphabet="0123456789ABCDEFabcdef", min_size=6, max_size=6
).map(lambda s: "#" + s)


# --- Helpers ---


def _make_mock_run_command():
    """Create a mock run_command that returns a successful CommandResult."""
    mock = AsyncMock(return_value=CommandResult(stdout="ok", stderr="", returncode=0))
    return mock


def _make_hyprctl_getoption_mock():
    """Create a mock that returns valid hyprctl getoption JSON."""
    result = CommandResult(
        stdout=json.dumps({"option": "general:gaps_in", "int": 5, "set": True}),
        stderr="",
        returncode=0,
    )
    return AsyncMock(return_value=result)


# --- Property Tests ---


@settings(max_examples=100)
@given(keyword=_safe_keywords, value=_keyword_values)
def test_hypr_set_option_records_ledger_entry(tmp_path_factory, keyword, value):
    """
    Property 1 (hypr_set_option): After invoking hypr_set_option with a valid
    keyword and value, the ledger SHALL contain an entry with tool_name
    "hypr_set_option" and correct params.

    **Validates: Requirements 2.2, 8.1**
    """
    tmp_path = tmp_path_factory.mktemp("ledger_hypr_set")
    test_ledger = ChangeLedger(path=tmp_path / "change-ledger.json")

    async def run_test():
        mock_run = AsyncMock(return_value=CommandResult(
            stdout=json.dumps({"option": keyword, "int": 5, "set": True}),
            stderr="",
            returncode=0,
        ))

        with patch("ii_desktop_mcp.tools.hypr_config._ledger", test_ledger), \
             patch("ii_desktop_mcp.tools.hypr_config.run_command", mock_run):

            mcp = FastMCP("test")
            from ii_desktop_mcp.tools.hypr_config import register
            register(mcp)

            tools = {t.name: t.fn for t in mcp._tool_manager.list_tools()}
            result = await tools["hypr_set_option"](keyword=keyword, value=value)

        # The tool should succeed (not return an error)
        assert result.get("status") == "applied" or "error" not in result, (
            f"Tool invocation failed unexpectedly: {result}"
        )

        # Assert ledger has an entry with correct tool_name
        entries = await test_ledger.get_entries()
        assert len(entries) >= 1, (
            f"Expected at least 1 ledger entry after hypr_set_option, got {len(entries)}"
        )

        # Find the entry for this tool
        matching = [e for e in entries if e.tool_name == "hypr_set_option"]
        assert len(matching) >= 1, (
            f"Expected ledger entry with tool_name='hypr_set_option', "
            f"found tool_names: {[e.tool_name for e in entries]}"
        )

        entry = matching[0]
        assert entry.params["keyword"] == keyword, (
            f"Ledger entry params.keyword mismatch: expected {keyword}, got {entry.params['keyword']}"
        )
        assert entry.params["value"] == value, (
            f"Ledger entry params.value mismatch: expected {value}, got {entry.params['value']}"
        )

    run_async(run_test())


@settings(max_examples=100)
@given(rule=_window_rules, match=_window_matches)
def test_hypr_add_window_rule_records_ledger_entry(tmp_path_factory, rule, match):
    """
    Property 1 (hypr_add_window_rule): After invoking hypr_add_window_rule,
    the ledger SHALL contain an entry with tool_name "hypr_add_window_rule"
    and the correct rule and match params.

    **Validates: Requirements 2.5, 8.1**
    """
    tmp_path = tmp_path_factory.mktemp("ledger_window_rule")
    test_ledger = ChangeLedger(path=tmp_path / "change-ledger.json")

    async def run_test():
        mock_run = _make_mock_run_command()

        with patch("ii_desktop_mcp.tools.hypr_config._ledger", test_ledger), \
             patch("ii_desktop_mcp.tools.hypr_config.run_command", mock_run):

            mcp = FastMCP("test")
            from ii_desktop_mcp.tools.hypr_config import register
            register(mcp)

            tools = {t.name: t.fn for t in mcp._tool_manager.list_tools()}
            result = await tools["hypr_add_window_rule"](rule=rule, match=match)

        assert result.get("status") == "applied", (
            f"Tool invocation failed: {result}"
        )

        entries = await test_ledger.get_entries()
        assert len(entries) >= 1, (
            f"Expected at least 1 ledger entry after hypr_add_window_rule, got {len(entries)}"
        )

        matching = [e for e in entries if e.tool_name == "hypr_add_window_rule"]
        assert len(matching) >= 1, (
            f"Expected ledger entry with tool_name='hypr_add_window_rule', "
            f"found tool_names: {[e.tool_name for e in entries]}"
        )

        entry = matching[0]
        assert entry.params["rule"] == rule
        assert entry.params["match"] == match

    run_async(run_test())


@settings(max_examples=100)
@given(
    name=_animation_names,
    enabled=st.booleans(),
    speed=st.one_of(st.none(), st.floats(min_value=0.1, max_value=20.0)),
    curve=st.one_of(st.none(), st.sampled_from(["default", "linear", "easeOut"])),
    style=st.one_of(st.none(), st.sampled_from(["slide", "popin", "fade"])),
)
def test_hypr_set_animation_records_ledger_entry(
    tmp_path_factory, name, enabled, speed, curve, style
):
    """
    Property 1 (hypr_set_animation): After invoking hypr_set_animation,
    the ledger SHALL contain an entry with tool_name "hypr_set_animation"
    and correct params.

    **Validates: Requirements 2.8, 8.1**
    """
    tmp_path = tmp_path_factory.mktemp("ledger_animation")
    test_ledger = ChangeLedger(path=tmp_path / "change-ledger.json")

    async def run_test():
        mock_run = _make_mock_run_command()

        with patch("ii_desktop_mcp.tools.hypr_config._ledger", test_ledger), \
             patch("ii_desktop_mcp.tools.hypr_config.run_command", mock_run):

            mcp = FastMCP("test")
            from ii_desktop_mcp.tools.hypr_config import register
            register(mcp)

            tools = {t.name: t.fn for t in mcp._tool_manager.list_tools()}
            result = await tools["hypr_set_animation"](
                name=name, enabled=enabled, speed=speed, curve=curve, style=style
            )

        assert result.get("status") == "applied", (
            f"Tool invocation failed: {result}"
        )

        entries = await test_ledger.get_entries()
        assert len(entries) >= 1, (
            f"Expected at least 1 ledger entry after hypr_set_animation, got {len(entries)}"
        )

        matching = [e for e in entries if e.tool_name == "hypr_set_animation"]
        assert len(matching) >= 1, (
            f"Expected ledger entry with tool_name='hypr_set_animation', "
            f"found tool_names: {[e.tool_name for e in entries]}"
        )

        entry = matching[0]
        assert entry.params["name"] == name
        assert entry.params["enabled"] == enabled

    run_async(run_test())


@settings(max_examples=100)
@given(scheme=_schemes)
def test_theme_apply_wallpaper_records_ledger_entry(tmp_path_factory, scheme):
    """
    Property 1 (theme_apply_wallpaper): After invoking theme_apply_wallpaper
    with a valid image path, the ledger SHALL contain an entry with tool_name
    "theme_apply_wallpaper" and correct params.

    **Validates: Requirements 1.8, 8.1**
    """
    tmp_path = tmp_path_factory.mktemp("ledger_wallpaper")
    test_ledger = ChangeLedger(path=tmp_path / "change-ledger.json")

    # Use a path under $HOME so path validation passes
    img_path = Path.home() / "test-wallpaper-pbt.png"

    async def run_test():
        mock_run = _make_mock_run_command()

        # Mock _read_current_state to return a valid previous state
        mock_state = {
            "wallpaper_path": "/home/test/old-wallpaper.jpg",
            "scheme": "tonalSpot",
            "palette": {"primary": "#000000"},
        }

        with patch("ii_desktop_mcp.tools.theme._ledger", test_ledger), \
             patch("ii_desktop_mcp.tools.theme.run_command", mock_run), \
             patch("ii_desktop_mcp.tools.theme._read_current_state", return_value=mock_state), \
             patch("ii_desktop_mcp.tools.theme._validate_path", return_value=None), \
             patch("ii_desktop_mcp.tools.theme.Path") as MockPath, \
             patch("ii_desktop_mcp.tools.theme._rate_limiter") as mock_limiter:

            # Make rate limiter always allow
            mock_limiter.consume.return_value = True

            # Mock Path(path).resolve().is_file() to return True
            mock_resolved = MagicMock()
            mock_resolved.is_file.return_value = True
            mock_resolved.__str__ = lambda self: str(img_path)
            mock_path_instance = MagicMock()
            mock_path_instance.resolve.return_value = mock_resolved
            mock_path_instance.name = "test-wallpaper-pbt.png"
            MockPath.return_value = mock_path_instance
            MockPath.home.return_value = Path.home()

            mcp = FastMCP("test")
            from ii_desktop_mcp.tools.theme import register
            register(mcp)

            tools = {t.name: t.fn for t in mcp._tool_manager.list_tools()}
            result = await tools["theme_apply_wallpaper"](
                path=str(img_path), scheme=scheme
            )

        assert result.get("status") == "applied", (
            f"Tool invocation failed: {result}"
        )

        entries = await test_ledger.get_entries()
        assert len(entries) >= 1, (
            f"Expected at least 1 ledger entry after theme_apply_wallpaper, got {len(entries)}"
        )

        matching = [e for e in entries if e.tool_name == "theme_apply_wallpaper"]
        assert len(matching) >= 1, (
            f"Expected ledger entry with tool_name='theme_apply_wallpaper', "
            f"found tool_names: {[e.tool_name for e in entries]}"
        )

        entry = matching[0]
        assert entry.params["path"] == str(img_path)
        assert entry.params["scheme"] == scheme

    run_async(run_test())


@settings(max_examples=100)
@given(color=_hex_colors, scheme=_schemes)
def test_theme_apply_color_records_ledger_entry(tmp_path_factory, color, scheme):
    """
    Property 1 (theme_apply_color): After invoking theme_apply_color with a
    valid hex color, the ledger SHALL contain an entry with tool_name
    "theme_apply_color" and correct params.

    **Validates: Requirements 1.8, 8.1**
    """
    tmp_path = tmp_path_factory.mktemp("ledger_color")
    test_ledger = ChangeLedger(path=tmp_path / "change-ledger.json")

    async def run_test():
        mock_run = _make_mock_run_command()

        mock_state = {
            "wallpaper_path": "/home/test/current-wallpaper.jpg",
            "scheme": "tonalSpot",
            "palette": {"primary": "#112233"},
        }

        with patch("ii_desktop_mcp.tools.theme._ledger", test_ledger), \
             patch("ii_desktop_mcp.tools.theme.run_command", mock_run), \
             patch("ii_desktop_mcp.tools.theme._read_current_state", return_value=mock_state), \
             patch("ii_desktop_mcp.tools.theme._rate_limiter") as mock_limiter:

            mock_limiter.consume.return_value = True

            mcp = FastMCP("test")
            from ii_desktop_mcp.tools.theme import register
            register(mcp)

            tools = {t.name: t.fn for t in mcp._tool_manager.list_tools()}
            result = await tools["theme_apply_color"](color=color, scheme=scheme)

        assert result.get("status") == "applied", (
            f"Tool invocation failed: {result}"
        )

        entries = await test_ledger.get_entries()
        assert len(entries) >= 1, (
            f"Expected at least 1 ledger entry after theme_apply_color, got {len(entries)}"
        )

        matching = [e for e in entries if e.tool_name == "theme_apply_color"]
        assert len(matching) >= 1, (
            f"Expected ledger entry with tool_name='theme_apply_color', "
            f"found tool_names: {[e.tool_name for e in entries]}"
        )

        entry = matching[0]
        assert entry.params["color"] == color
        assert entry.params["scheme"] == scheme

    run_async(run_test())
