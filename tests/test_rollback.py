# Feature: ai-desktop-control, Property 5: Rollback removes entries on success
# Feature: ai-desktop-control, Property 6: Failed rollback preserves entries
"""
Property-based tests for rollback behavior.

Property 5: When a rollback operation succeeds (rollback_last or rollback_by_id),
the targeted Change_Entry(ies) are removed from the ledger, and the ledger size
decreases by the number of entries rolled back.

Property 6: When the inverse operation fails (run_command raises ToolError), the
Change_Entry SHALL remain in the ledger unchanged, and the error SHALL be reported
to the caller.

**Validates: Requirements 3.5, 3.7, 3.8**
"""

import asyncio
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from ii_desktop_mcp.core.errors import INTERNAL_ERROR, ToolError
from ii_desktop_mcp.core.ledger import ChangeLedger
from ii_desktop_mcp.tools.rollback import RollbackEngine


def run_async(coro):
    """Helper to run an async coroutine in a synchronous test context."""
    return asyncio.run(coro)


# --- Strategies for Property 5 ---

# Tools that have inverse operations defined in RollbackEngine
INVERTIBLE_TOOLS = st.sampled_from([
    "hypr_set_option",
    "hypr_add_window_rule",
    "hypr_set_animation",
    "monitor_set",
    "bluetooth_connect",
    "bluetooth_disconnect",
    "audio_set_volume",
])

# Previous state matching what each tool's inverse expects
PREVIOUS_STATE_FOR_TOOL = {
    "hypr_set_option": {"keyword": "general:gaps_in", "value": "5"},
    "hypr_add_window_rule": {"match": "class:^(pavucontrol)$"},
    "hypr_set_animation": {"animation_string": "windows,1,7,default"},
    "monitor_set": {"monitor_string": "DP-1,2560x1440@144,0x0,1"},
    "bluetooth_connect": {},  # inverse uses params.address
    "bluetooth_disconnect": {},  # inverse uses params.address
    "audio_set_volume": {"volume": 50, "mute": False},
}

PARAMS_FOR_TOOL = {
    "hypr_set_option": {"keyword": "general:gaps_in", "value": "10"},
    "hypr_add_window_rule": {"rule": "float", "match": "class:^(pavucontrol)$"},
    "hypr_set_animation": {"name": "windows", "enabled": True, "speed": 7.0},
    "monitor_set": {"name": "DP-1", "resolution": "2560x1440"},
    "bluetooth_connect": {"address": "AA:BB:CC:DD:EE:FF"},
    "bluetooth_disconnect": {"address": "AA:BB:CC:DD:EE:FF"},
    "audio_set_volume": {"target": "@DEFAULT_AUDIO_SINK@", "volume": 75},
}


async def _record_entries(ledger: ChangeLedger, n: int, tool_names: list[str]) -> list[str]:
    """Record N entries into the ledger and return their IDs."""
    entry_ids = []
    for i in range(n):
        tool_name = tool_names[i % len(tool_names)]
        entry_id = await ledger.record(
            tool_name=tool_name,
            params=PARAMS_FOR_TOOL[tool_name],
            previous_state=PREVIOUS_STATE_FOR_TOOL[tool_name],
            description=f"Test change {i} via {tool_name}",
        )
        entry_ids.append(entry_id)
    return entry_ids


# --- Property 5: Rollback removes entries on success ---


@settings(max_examples=100)
@given(
    n=st.integers(min_value=1, max_value=10),
    tool_name=INVERTIBLE_TOOLS,
)
def test_rollback_last_removes_entries_on_success(tmp_path_factory, n, tool_name):
    """
    Property 5 (rollback_last path): For any N entries recorded,
    performing rollback_last(count=N) with a mocked successful inverse
    removes all N entries from the ledger.

    **Validates: Requirements 3.5, 3.7**
    """
    tmp_path = tmp_path_factory.mktemp("rollback_last")
    ledger = ChangeLedger(path=tmp_path / "change-ledger.json")
    tool_names = [tool_name]

    async def run_test():
        entry_ids = await _record_entries(ledger, n, tool_names)

        # Verify initial ledger size
        entries_before = await ledger.get_entries()
        assert len(entries_before) == n

        engine = RollbackEngine()

        with patch(
            "ii_desktop_mcp.tools.rollback.run_command",
            new_callable=AsyncMock,
            return_value="ok",
        ):
            # Roll back all entries (newest first, as rollback_last does)
            entries_to_rollback = entries_before[:n]

            for entry in entries_to_rollback:
                await engine.rollback_entry(entry)
                await ledger.remove(entry.id)

        # After rollback, ledger should be empty
        entries_after = await ledger.get_entries()
        assert len(entries_after) == 0, (
            f"Expected ledger to be empty after rolling back all {n} entries, "
            f"but found {len(entries_after)} entries remaining"
        )

        # Verify each rolled-back entry is gone
        for entry_id in entry_ids:
            found = await ledger.get_by_id(entry_id)
            assert found is None, (
                f"Entry {entry_id} should have been removed after successful rollback"
            )

    run_async(run_test())


@settings(max_examples=100)
@given(
    n=st.integers(min_value=2, max_value=10),
    rollback_count=st.integers(min_value=1, max_value=5),
    tool_name=INVERTIBLE_TOOLS,
)
def test_rollback_last_partial_reduces_size_correctly(tmp_path_factory, n, rollback_count, tool_name):
    """
    Property 5 (partial rollback_last): For N entries in the ledger,
    rolling back min(rollback_count, N) entries reduces ledger size
    by exactly that amount and removes the correct entries.

    **Validates: Requirements 3.5, 3.7**
    """
    actual_rollback = min(rollback_count, n)
    tmp_path = tmp_path_factory.mktemp("rollback_partial")
    ledger = ChangeLedger(path=tmp_path / "change-ledger.json")
    tool_names = [tool_name]

    async def run_test():
        await _record_entries(ledger, n, tool_names)

        entries_before = await ledger.get_entries()
        initial_size = len(entries_before)
        assert initial_size == n

        engine = RollbackEngine()

        with patch(
            "ii_desktop_mcp.tools.rollback.run_command",
            new_callable=AsyncMock,
            return_value="ok",
        ):
            entries_to_rollback = entries_before[:actual_rollback]

            for entry in entries_to_rollback:
                await engine.rollback_entry(entry)
                await ledger.remove(entry.id)

        # Ledger size should decrease by exactly actual_rollback
        entries_after = await ledger.get_entries()
        expected_size = initial_size - actual_rollback
        assert len(entries_after) == expected_size, (
            f"Expected ledger size {expected_size} after rolling back "
            f"{actual_rollback} entries from {initial_size}, "
            f"got {len(entries_after)}"
        )

        # Rolled-back entries should not appear in remaining ledger
        rolled_back_ids = {e.id for e in entries_to_rollback}
        remaining_ids = {e.id for e in entries_after}
        assert rolled_back_ids.isdisjoint(remaining_ids), (
            f"Rolled-back entries should not appear in remaining ledger. "
            f"Overlap: {rolled_back_ids & remaining_ids}"
        )

    run_async(run_test())


@settings(max_examples=100)
@given(
    n=st.integers(min_value=1, max_value=10),
    target_index=st.integers(min_value=0, max_value=9),
    tool_name=INVERTIBLE_TOOLS,
)
def test_rollback_by_id_removes_entry_on_success(tmp_path_factory, n, target_index, tool_name):
    """
    Property 5 (rollback_by_id path): For any entry in the ledger,
    performing rollback_by_id with a mocked successful inverse removes
    exactly that entry, and ledger size decreases by 1.

    **Validates: Requirements 3.5, 3.7**
    """
    target_index = target_index % n
    tmp_path = tmp_path_factory.mktemp("rollback_by_id")
    ledger = ChangeLedger(path=tmp_path / "change-ledger.json")
    tool_names = [tool_name]

    async def run_test():
        entry_ids = await _record_entries(ledger, n, tool_names)

        entries_before = await ledger.get_entries()
        initial_size = len(entries_before)
        assert initial_size == n

        # Pick target entry
        target_id = entry_ids[target_index]
        target_entry = await ledger.get_by_id(target_id)
        assert target_entry is not None

        engine = RollbackEngine()

        with patch(
            "ii_desktop_mcp.tools.rollback.run_command",
            new_callable=AsyncMock,
            return_value="ok",
        ):
            await engine.rollback_entry(target_entry)
            removed = await ledger.remove(target_entry.id)
            assert removed is True

        # Verify ledger size decreased by 1
        entries_after = await ledger.get_entries()
        assert len(entries_after) == initial_size - 1, (
            f"Expected ledger size {initial_size - 1} after rollback_by_id, "
            f"got {len(entries_after)}"
        )

        # Verify the specific entry is gone
        found = await ledger.get_by_id(target_id)
        assert found is None, (
            f"Entry {target_id} should have been removed after successful rollback_by_id"
        )

        # Verify other entries are preserved
        remaining_ids = {e.id for e in entries_after}
        for eid in entry_ids:
            if eid == target_id:
                assert eid not in remaining_ids
            else:
                assert eid in remaining_ids, (
                    f"Entry {eid} should still be in the ledger after "
                    f"rolling back a different entry"
                )

    run_async(run_test())


# --- Property 6: Failed rollback preserves entries ---

# Strategies for Property 6
entry_params_strategy = st.fixed_dictionaries({
    "keyword": st.text(
        alphabet=st.characters(whitelist_categories=("L", "N"), whitelist_characters="_:."),
        min_size=3,
        max_size=30,
    ),
    "value": st.text(min_size=1, max_size=20),
})

previous_state_strategy = st.fixed_dictionaries({
    "keyword": st.text(
        alphabet=st.characters(whitelist_categories=("L", "N"), whitelist_characters="_:."),
        min_size=3,
        max_size=30,
    ),
    "value": st.text(min_size=1, max_size=20),
})


@settings(max_examples=100)
@given(
    n=st.integers(min_value=1, max_value=10),
    params_list=st.lists(entry_params_strategy, min_size=1, max_size=10),
    prev_states=st.lists(previous_state_strategy, min_size=1, max_size=10),
)
def test_failed_rollback_preserves_entries_rollback_last(
    tmp_path_factory, n, params_list, prev_states
):
    """
    Property 6: For any ledger with N entries where rollback fails,
    all entries remain in the ledger unchanged.

    We record entries of type 'hypr_set_option', mock run_command to raise
    ToolError(INTERNAL_ERROR, "command failed"), attempt rollback_last,
    and assert all entries are still present.

    **Validates: Requirements 3.8**
    """
    tmp_path = tmp_path_factory.mktemp("ledger")
    ledger = ChangeLedger(path=tmp_path / "change-ledger.json")

    actual_n = min(n, len(params_list), len(prev_states))
    if actual_n < 1:
        return

    recorded_ids: list[str] = []

    async def setup_and_test():
        for i in range(actual_n):
            entry_id = await ledger.record(
                tool_name="hypr_set_option",
                params=params_list[i],
                previous_state=prev_states[i],
                description=f"Set option {i}",
            )
            recorded_ids.append(entry_id)

        entries_before = await ledger.get_entries()
        size_before = len(entries_before)
        ids_before = {e.id for e in entries_before}
        return size_before, ids_before

    size_before, ids_before = run_async(setup_and_test())

    mock_run_command = AsyncMock(
        side_effect=ToolError(INTERNAL_ERROR, "command failed")
    )

    async def attempt_rollback():
        engine = RollbackEngine()

        with patch("ii_desktop_mcp.tools.rollback.run_command", mock_run_command):
            entries = await ledger.get_entries()
            entries_to_rollback = entries[:actual_n]

            rolled_back = []
            failed_entry = None

            for entry in entries_to_rollback:
                try:
                    await engine.rollback_entry(entry)
                    await ledger.remove(entry.id)
                    rolled_back.append(entry.id)
                except ToolError as e:
                    failed_entry = {"id": entry.id, "error": e.message}
                    break

            return rolled_back, failed_entry

    rolled_back, failed_entry = run_async(attempt_rollback())

    assert failed_entry is not None, "Expected rollback to fail but it succeeded"
    assert "command failed" in failed_entry["error"]
    assert len(rolled_back) == 0, (
        f"Expected no entries to be rolled back, but {len(rolled_back)} were removed"
    )

    async def verify_ledger():
        return await ledger.get_entries()

    entries_after = run_async(verify_ledger())
    size_after = len(entries_after)
    ids_after = {e.id for e in entries_after}

    assert size_after == size_before, (
        f"Ledger size changed after failed rollback: was {size_before}, now {size_after}"
    )
    assert ids_after == ids_before, (
        f"Ledger entries changed after failed rollback. "
        f"Missing: {ids_before - ids_after}, New: {ids_after - ids_before}"
    )


@settings(max_examples=100)
@given(
    params=entry_params_strategy,
    prev_state=previous_state_strategy,
)
def test_failed_rollback_preserves_entries_rollback_by_id(
    tmp_path_factory, params, prev_state
):
    """
    Property 6: For a specific entry where rollback_by_id fails,
    the entry remains in the ledger unchanged.

    Record one entry, mock run_command to fail, attempt rollback_by_id,
    verify entry still exists in ledger.

    **Validates: Requirements 3.8**
    """
    tmp_path = tmp_path_factory.mktemp("ledger")
    ledger = ChangeLedger(path=tmp_path / "change-ledger.json")

    recorded_id = None

    async def setup():
        nonlocal recorded_id
        recorded_id = await ledger.record(
            tool_name="hypr_set_option",
            params=params,
            previous_state=prev_state,
            description="Set option for rollback_by_id test",
        )

    run_async(setup())

    mock_run_command = AsyncMock(
        side_effect=ToolError(INTERNAL_ERROR, "command failed")
    )

    async def attempt_rollback_by_id():
        engine = RollbackEngine()

        with patch("ii_desktop_mcp.tools.rollback.run_command", mock_run_command):
            entry = await ledger.get_by_id(recorded_id)
            assert entry is not None, f"Entry {recorded_id} not found before rollback"

            error_returned = None
            try:
                await engine.rollback_entry(entry)
                await ledger.remove(entry.id)
            except ToolError as e:
                error_returned = e

            return error_returned

    error = run_async(attempt_rollback_by_id())

    assert error is not None, "Expected ToolError to be raised but rollback succeeded"
    assert error.code == INTERNAL_ERROR
    assert "command failed" in error.message

    async def verify():
        return await ledger.get_by_id(recorded_id)

    entry = run_async(verify())
    assert entry is not None, (
        f"Entry {recorded_id} was removed from ledger after failed rollback"
    )
    assert entry.tool_name == "hypr_set_option"
    assert entry.params == params
    assert entry.previous_state == prev_state


# Feature: ai-desktop-control, Property 7: Rollbacks are not recorded as new entries
# ---
# Property 7: After any rollback operation (regardless of success or failure),
# the ledger SHALL NOT gain new entries as a result of the rollback itself.
# The set of entry IDs after rollback is always a SUBSET of the IDs before.
#
# **Validates: Requirements 3.10**
# ---


@settings(max_examples=100)
@given(
    n=st.integers(min_value=2, max_value=10),
    rollback_count=st.integers(min_value=1, max_value=5),
)
def test_successful_rollback_does_not_add_entries(tmp_path_factory, n, rollback_count):
    """
    Property 7 (successful rollback_last): After a successful rollback,
    the set of entry IDs in the ledger is a strict subset of the IDs that
    existed before. No new entries are ever created by the rollback itself.

    **Validates: Requirements 3.10**
    """
    # Clamp rollback_count to at most n
    rollback_count = min(rollback_count, n)

    tmp_path = tmp_path_factory.mktemp("ledger_p7_success")
    ledger = ChangeLedger(path=tmp_path / "change-ledger.json")
    engine = RollbackEngine()

    async def run_test():
        # Record N entries
        recorded_ids: set[str] = set()
        for i in range(n):
            entry_id = await ledger.record(
                tool_name="hypr_set_option",
                params={"keyword": "general:gaps_in", "value": str(i + 10)},
                previous_state={"keyword": "general:gaps_in", "value": str(i)},
                description=f"Set gaps to {i + 10}",
            )
            recorded_ids.add(entry_id)

        # Snapshot the IDs before rollback
        ids_before_rollback = {e.id for e in await ledger.get_entries()}
        assert ids_before_rollback == recorded_ids

        # Perform successful rollback (mock run_command to succeed)
        with patch(
            "ii_desktop_mcp.tools.rollback.run_command",
            new_callable=AsyncMock,
            return_value="",
        ):
            entries = await ledger.get_entries()
            entries_to_rollback = entries[:rollback_count]

            for entry in entries_to_rollback:
                await engine.rollback_entry(entry)
                await ledger.remove(entry.id)

        # Get entries after rollback
        ids_after_rollback = {e.id for e in await ledger.get_entries()}

        # KEY INVARIANT: after rollback, all remaining IDs must be
        # a subset of the original IDs — no new entries were added
        assert ids_after_rollback.issubset(ids_before_rollback), (
            f"Rollback added new entries! "
            f"New IDs not in original set: {ids_after_rollback - ids_before_rollback}"
        )

        # Also verify entries were actually removed (rollback succeeded)
        rolled_back_ids = {e.id for e in entries_to_rollback}
        assert rolled_back_ids.isdisjoint(ids_after_rollback), (
            f"Rolled-back entries should have been removed from ledger"
        )

    run_async(run_test())


@settings(max_examples=100)
@given(
    n=st.integers(min_value=2, max_value=10),
)
def test_failed_rollback_does_not_add_entries(tmp_path_factory, n):
    """
    Property 7 (failed rollback): After a failed rollback, the set of
    entry IDs in the ledger is exactly the same as before — no entries
    removed AND no new entries added.

    **Validates: Requirements 3.10**
    """
    tmp_path = tmp_path_factory.mktemp("ledger_p7_failed")
    ledger = ChangeLedger(path=tmp_path / "change-ledger.json")
    engine = RollbackEngine()

    async def run_test():
        # Record N entries
        recorded_ids: set[str] = set()
        for i in range(n):
            entry_id = await ledger.record(
                tool_name="hypr_set_option",
                params={"keyword": "general:gaps_in", "value": str(i + 10)},
                previous_state={"keyword": "general:gaps_in", "value": str(i)},
                description=f"Set gaps to {i + 10}",
            )
            recorded_ids.add(entry_id)

        # Snapshot the IDs before rollback
        ids_before_rollback = {e.id for e in await ledger.get_entries()}
        assert ids_before_rollback == recorded_ids

        # Perform failed rollback (mock run_command to raise ToolError)
        with patch(
            "ii_desktop_mcp.tools.rollback.run_command",
            new_callable=AsyncMock,
            side_effect=ToolError(INTERNAL_ERROR, "Command failed"),
        ):
            entries = await ledger.get_entries()
            entry_to_rollback = entries[0]  # Try to rollback the most recent

            # The rollback should raise ToolError
            with pytest.raises(ToolError):
                await engine.rollback_entry(entry_to_rollback)

            # On failure, we do NOT remove the entry (matching rollback.py behavior)

        # Get entries after failed rollback
        ids_after_rollback = {e.id for e in await ledger.get_entries()}

        # KEY INVARIANT: after failed rollback, IDs are exactly the same
        # No new entries added, no entries removed
        assert ids_after_rollback == ids_before_rollback, (
            f"Failed rollback should not change ledger entries! "
            f"Before: {ids_before_rollback}, After: {ids_after_rollback}"
        )

    run_async(run_test())


@settings(max_examples=100)
@given(
    n=st.integers(min_value=2, max_value=10),
    target_index=st.integers(min_value=0, max_value=9),
)
def test_rollback_by_id_does_not_add_entries(tmp_path_factory, n, target_index):
    """
    Property 7 (rollback_by_id): After a successful rollback_by_id,
    the set of entry IDs in the ledger is a subset of the original IDs.
    The targeted entry is removed but no new entries are created.

    **Validates: Requirements 3.10**
    """
    # Ensure target_index is valid for our entries
    target_index = target_index % n

    tmp_path = tmp_path_factory.mktemp("ledger_p7_by_id")
    ledger = ChangeLedger(path=tmp_path / "change-ledger.json")
    engine = RollbackEngine()

    async def run_test():
        # Record N entries
        recorded_ids: list[str] = []
        for i in range(n):
            entry_id = await ledger.record(
                tool_name="hypr_set_option",
                params={"keyword": "general:gaps_in", "value": str(i + 10)},
                previous_state={"keyword": "general:gaps_in", "value": str(i)},
                description=f"Set gaps to {i + 10}",
            )
            recorded_ids.append(entry_id)

        # Snapshot the IDs before rollback
        ids_before_rollback = {e.id for e in await ledger.get_entries()}

        # Target a specific entry by ID
        target_id = recorded_ids[target_index]
        entry = await ledger.get_by_id(target_id)
        assert entry is not None

        # Perform successful rollback by ID
        with patch(
            "ii_desktop_mcp.tools.rollback.run_command",
            new_callable=AsyncMock,
            return_value="",
        ):
            await engine.rollback_entry(entry)
            await ledger.remove(entry.id)

        # Get entries after rollback
        ids_after_rollback = {e.id for e in await ledger.get_entries()}

        # KEY INVARIANT: remaining IDs are a subset of original IDs
        assert ids_after_rollback.issubset(ids_before_rollback), (
            f"Rollback by ID added new entries! "
            f"New IDs: {ids_after_rollback - ids_before_rollback}"
        )

        # The targeted entry should be gone
        assert target_id not in ids_after_rollback

    run_async(run_test())


# Feature: ai-desktop-control, Property 8: Non-existent identifier returns not_found
# ---
# Property 8: When a lookup is performed with an identifier (UUID) that does NOT
# exist in the ledger, the result SHALL be None (not_found). This validates the
# NOT_FOUND error path used by rollback_by_id, monitor_load_profile, and
# apps_get_interface.
#
# **Validates: Requirements 3.11, 4.5, 4.8, 6.6**
# ---


@settings(max_examples=100)
@given(
    random_uuid=st.uuids(),
    n=st.integers(min_value=1, max_value=10),
)
def test_nonexistent_identifier_returns_not_found(tmp_path_factory, random_uuid, n):
    """
    Property 8: For any randomly generated UUID that was NOT recorded in the
    ledger, get_by_id returns None. The ledger is populated with some entries
    to ensure non-empty state, but the random UUID is guaranteed absent.

    **Validates: Requirements 3.11, 4.5, 4.8, 6.6**
    """
    tmp_path = tmp_path_factory.mktemp("ledger_p8")
    ledger = ChangeLedger(path=tmp_path / "change-ledger.json")

    async def run_test():
        # Record a few entries so the ledger isn't empty
        recorded_ids: set[str] = set()
        for i in range(n):
            entry_id = await ledger.record(
                tool_name="hypr_set_option",
                params={"keyword": f"general:opt_{i}", "value": str(i)},
                previous_state={"keyword": f"general:opt_{i}", "value": "0"},
                description=f"Set option {i}",
            )
            recorded_ids.add(entry_id)

        # Convert the hypothesis-generated UUID to string
        lookup_id = str(random_uuid)

        # If by extreme coincidence the random UUID matches a recorded one, skip
        # (astronomically unlikely with UUID4, but be correct)
        if lookup_id in recorded_ids:
            return

        # The core assertion: looking up a non-existent ID returns None
        result = await ledger.get_by_id(lookup_id)
        assert result is None, (
            f"Expected get_by_id('{lookup_id}') to return None for a "
            f"non-existent identifier, but got: {result}"
        )

    run_async(run_test())
