# Feature: ai-desktop-control, Property 18: Ledger ordering is reverse chronological
"""
Property-based test for Change Ledger ordering.

The Change Ledger stores entries in chronological order internally (appending
new entries at the end) and `get_entries()` returns `list(reversed(entries))`
— so newest first. This test verifies that by recording entries in sequence
and checking the returned order.

**Validates: Requirements 3.9**
"""

import asyncio
from pathlib import Path

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from ii_desktop_mcp.core.ledger import ChangeLedger, ChangeEntry


@pytest.fixture
def ledger(tmp_path: Path) -> ChangeLedger:
    """Create a ChangeLedger using an isolated temporary path."""
    return ChangeLedger(path=tmp_path / "change-ledger.json")


def run_async(coro):
    """Helper to run an async coroutine in a synchronous test context."""
    return asyncio.run(coro)


@settings(max_examples=100)
@given(n=st.integers(min_value=2, max_value=50))
def test_ledger_ordering_reverse_chronological(tmp_path_factory, n):
    """
    Property 18: For any set of N entries recorded sequentially,
    get_entries() returns them newest first (reverse order of recording).

    We record N entries and verify that the returned list has the last-recorded
    entry first, second-to-last entry second, etc.

    **Validates: Requirements 3.9**
    """
    tmp_path = tmp_path_factory.mktemp("ledger")
    ledger = ChangeLedger(path=tmp_path / "change-ledger.json")

    # Record N entries sequentially, tracking their IDs in recording order
    recorded_ids: list[str] = []

    async def record_entries():
        for i in range(n):
            entry_id = await ledger.record(
                tool_name=f"test_tool_{i}",
                params={"index": i},
                previous_state={"value": f"prev_{i}"},
                description=f"Change {i}",
            )
            recorded_ids.append(entry_id)

    run_async(record_entries())

    # Get entries — should be newest first
    entries = run_async(ledger.get_entries())

    # The returned entries should be in reverse order of recording
    returned_ids = [e.id for e in entries]
    expected_ids = list(reversed(recorded_ids))

    assert returned_ids == expected_ids, (
        f"Expected entries in reverse chronological order (newest first). "
        f"Recorded order: {recorded_ids}, "
        f"Expected reversed: {expected_ids}, "
        f"Got: {returned_ids}"
    )

    # Additionally verify that the first returned entry is the last recorded
    assert entries[0].id == recorded_ids[-1], (
        f"First entry from get_entries() should be the last recorded. "
        f"Got {entries[0].id}, expected {recorded_ids[-1]}"
    )

    # And the last returned entry is the first recorded
    assert entries[-1].id == recorded_ids[0], (
        f"Last entry from get_entries() should be the first recorded. "
        f"Got {entries[-1].id}, expected {recorded_ids[0]}"
    )
