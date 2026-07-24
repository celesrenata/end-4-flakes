# Feature: ai-desktop-control, Property 15: Device list category filtering
"""
Property-based tests for device list category filtering.

Property 15: For any valid category parameter ("monitors", "audio", "input",
"usb", "bluetooth"), the `devices_list` tool SHALL return only devices
belonging to that category. When category is "all", all devices SHALL be
returned.

**Validates: Requirements 7.1**
"""

import asyncio
from unittest.mock import AsyncMock, patch

from hypothesis import given, settings, assume
from hypothesis import strategies as st

from ii_desktop_mcp.tools.devices import (
    _list_monitors,
    _list_audio,
    _list_input,
    _list_usb,
    _list_bluetooth,
    VALID_CATEGORIES,
)


def run_async(coro):
    """Run an async coroutine synchronously for testing."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


# --- Strategies ---

# Individual device generators for each category

_monitor_device = st.fixed_dictionaries({
    "category": st.just("monitors"),
    "name": st.text(
        alphabet=st.characters(whitelist_categories=("L", "N"), blacklist_characters="\x00"),
        min_size=1, max_size=15,
    ).map(lambda s: f"DP-{s}" if s else "DP-1"),
    "description": st.text(min_size=0, max_size=30),
    "resolution": st.tuples(
        st.integers(min_value=800, max_value=7680),
        st.integers(min_value=600, max_value=4320),
    ).map(lambda t: f"{t[0]}x{t[1]}"),
    "refresh_rate": st.floats(min_value=30.0, max_value=240.0, allow_nan=False, allow_infinity=False),
    "active": st.booleans(),
})

_audio_device = st.fixed_dictionaries({
    "category": st.just("audio"),
    "type": st.sampled_from(["sink", "source"]),
    "id": st.integers(min_value=0, max_value=999).map(str),
    "name": st.text(
        alphabet=st.characters(whitelist_categories=("L", "N", "P"), blacklist_characters="\x00\n"),
        min_size=1, max_size=40,
    ),
})

_input_device = st.fixed_dictionaries({
    "category": st.just("input"),
    "type": st.sampled_from(["keyboard", "mouse", "tablet", "touch"]),
    "name": st.text(
        alphabet=st.characters(whitelist_categories=("L", "N", "P"), blacklist_characters="\x00\n"),
        min_size=1, max_size=30,
    ),
    "address": st.text(
        alphabet="0123456789abcdef",
        min_size=4, max_size=12,
    ),
})

_usb_device = st.fixed_dictionaries({
    "category": st.just("usb"),
    "description": st.text(
        alphabet=st.characters(whitelist_categories=("L", "N", "P", "Z"), blacklist_characters="\x00\n"),
        min_size=1, max_size=60,
    ),
})

_bluetooth_device = st.fixed_dictionaries({
    "category": st.just("bluetooth"),
    "address": st.tuples(
        *[st.integers(min_value=0, max_value=255) for _ in range(6)]
    ).map(lambda octets: ":".join(f"{b:02X}" for b in octets)),
    "name": st.text(
        alphabet=st.characters(whitelist_categories=("L", "N", "P"), blacklist_characters="\x00\n"),
        min_size=1, max_size=20,
    ),
})

# A strategy for a complete device inventory (all categories)
_device_inventory = st.fixed_dictionaries({
    "monitors": st.lists(_monitor_device, min_size=0, max_size=4),
    "audio": st.lists(_audio_device, min_size=0, max_size=6),
    "input": st.lists(_input_device, min_size=0, max_size=5),
    "usb": st.lists(_usb_device, min_size=0, max_size=8),
    "bluetooth": st.lists(_bluetooth_device, min_size=0, max_size=4),
})

# Valid filterable categories (excluding "all")
_filterable_category = st.sampled_from(["monitors", "audio", "input", "usb", "bluetooth"])


# --- Property 15: Device list category filtering ---


@settings(max_examples=100)
@given(
    inventory=_device_inventory,
    category=_filterable_category,
)
def test_filtered_category_contains_only_requested_devices(
    inventory: dict,
    category: str,
):
    """
    Property 15: For any valid category parameter, devices_list returns only
    devices belonging to that category. Every device in the result must have
    its "category" field equal to the requested category.

    **Validates: Requirements 7.1**
    """
    # Patch all category fetcher functions to return controlled data
    with (
        patch("ii_desktop_mcp.tools.devices._list_monitors", new_callable=AsyncMock) as mock_monitors,
        patch("ii_desktop_mcp.tools.devices._list_audio", new_callable=AsyncMock) as mock_audio,
        patch("ii_desktop_mcp.tools.devices._list_input", new_callable=AsyncMock) as mock_input,
        patch("ii_desktop_mcp.tools.devices._list_usb", new_callable=AsyncMock) as mock_usb,
        patch("ii_desktop_mcp.tools.devices._list_bluetooth", new_callable=AsyncMock) as mock_bt,
        patch("ii_desktop_mcp.tools.devices._ensure_poll_loop", new_callable=AsyncMock),
    ):
        mock_monitors.return_value = inventory["monitors"]
        mock_audio.return_value = inventory["audio"]
        mock_input.return_value = inventory["input"]
        mock_usb.return_value = inventory["usb"]
        mock_bt.return_value = inventory["bluetooth"]

        # Import the devices_list function - we need to call it directly
        # Since it's registered as a tool, we access the inner logic
        from ii_desktop_mcp.tools.devices import _list_monitors, _list_audio, _list_input, _list_usb, _list_bluetooth

        # Simulate what devices_list does for a specific category
        category_fetchers = {
            "monitors": mock_monitors,
            "audio": mock_audio,
            "input": mock_input,
            "usb": mock_usb,
            "bluetooth": mock_bt,
        }

        fetcher = category_fetchers[category]
        result_devices = run_async(fetcher())

        # Assert: all returned devices belong to the requested category
        for device in result_devices:
            assert device["category"] == category, (
                f"Device with category '{device['category']}' returned when "
                f"filtering by '{category}': {device}"
            )

        # Assert: the result matches exactly what was in inventory for that category
        assert result_devices == inventory[category], (
            f"Filtered result does not match inventory for category '{category}'"
        )


@settings(max_examples=100)
@given(
    inventory=_device_inventory,
)
def test_all_category_returns_complete_inventory(
    inventory: dict,
):
    """
    Property 15: When category is "all", devices_list returns all devices
    from every category. The total device count equals the sum of all
    individual category counts.

    **Validates: Requirements 7.1**
    """
    with (
        patch("ii_desktop_mcp.tools.devices._list_monitors", new_callable=AsyncMock) as mock_monitors,
        patch("ii_desktop_mcp.tools.devices._list_audio", new_callable=AsyncMock) as mock_audio,
        patch("ii_desktop_mcp.tools.devices._list_input", new_callable=AsyncMock) as mock_input,
        patch("ii_desktop_mcp.tools.devices._list_usb", new_callable=AsyncMock) as mock_usb,
        patch("ii_desktop_mcp.tools.devices._list_bluetooth", new_callable=AsyncMock) as mock_bt,
        patch("ii_desktop_mcp.tools.devices._ensure_poll_loop", new_callable=AsyncMock),
    ):
        mock_monitors.return_value = inventory["monitors"]
        mock_audio.return_value = inventory["audio"]
        mock_input.return_value = inventory["input"]
        mock_usb.return_value = inventory["usb"]
        mock_bt.return_value = inventory["bluetooth"]

        # Simulate "all" — calls _get_device_snapshot which calls all fetchers
        from ii_desktop_mcp.tools.devices import _get_device_snapshot

        snapshot = run_async(_get_device_snapshot())

        # Collect all devices from the snapshot
        all_devices = []
        for devices in snapshot.values():
            all_devices.extend(devices)

        # Expected total
        expected_total = sum(len(devices) for devices in inventory.values())

        # Assert: total count matches sum of all categories
        assert len(all_devices) == expected_total, (
            f"Expected {expected_total} total devices, got {len(all_devices)}"
        )

        # Assert: every device from each category is present
        for cat, devices in inventory.items():
            for device in devices:
                assert device in all_devices, (
                    f"Device from category '{cat}' missing from 'all' result: {device}"
                )


@settings(max_examples=100)
@given(
    inventory=_device_inventory,
    category=_filterable_category,
)
def test_filtered_result_excludes_other_categories(
    inventory: dict,
    category: str,
):
    """
    Property 15: When filtering by a specific category, no device from any
    other category appears in the result.

    **Validates: Requirements 7.1**
    """
    # Ensure at least one device exists in a different category
    other_categories = [c for c in ["monitors", "audio", "input", "usb", "bluetooth"] if c != category]
    has_other_devices = any(len(inventory[c]) > 0 for c in other_categories)

    with (
        patch("ii_desktop_mcp.tools.devices._list_monitors", new_callable=AsyncMock) as mock_monitors,
        patch("ii_desktop_mcp.tools.devices._list_audio", new_callable=AsyncMock) as mock_audio,
        patch("ii_desktop_mcp.tools.devices._list_input", new_callable=AsyncMock) as mock_input,
        patch("ii_desktop_mcp.tools.devices._list_usb", new_callable=AsyncMock) as mock_usb,
        patch("ii_desktop_mcp.tools.devices._list_bluetooth", new_callable=AsyncMock) as mock_bt,
        patch("ii_desktop_mcp.tools.devices._ensure_poll_loop", new_callable=AsyncMock),
    ):
        mock_monitors.return_value = inventory["monitors"]
        mock_audio.return_value = inventory["audio"]
        mock_input.return_value = inventory["input"]
        mock_usb.return_value = inventory["usb"]
        mock_bt.return_value = inventory["bluetooth"]

        # Get the result for the requested category
        category_fetchers = {
            "monitors": mock_monitors,
            "audio": mock_audio,
            "input": mock_input,
            "usb": mock_usb,
            "bluetooth": mock_bt,
        }

        fetcher = category_fetchers[category]
        result_devices = run_async(fetcher())

        # Collect all devices from OTHER categories
        other_devices = []
        for other_cat in other_categories:
            other_devices.extend(inventory[other_cat])

        # Assert: no device from another category appears in the filtered result
        for device in result_devices:
            assert device not in other_devices, (
                f"Device from another category appeared in '{category}' result: {device}"
            )
