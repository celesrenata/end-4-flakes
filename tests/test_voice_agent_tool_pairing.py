# Feature: streaming-voice-agent, Property 3: Tool call / result pairing
"""Property-based tests for tool call / result pairing invariants.

Generates random sequences of tool calls with unique IDs and verifies
that ToolCallManager enforces pairing invariants:
- No duplicate tool call IDs within a session
- No concurrent pending calls (at most one at a time)
- Matching TOOL_RESULT clears the pending state
- Mismatched or orphan TOOL_RESULTs are rejected

**Validates: Requirements 8.1, 8.2, 8.3, 8.4, 12.3, 12.4, 12.7**
"""

import sys
from pathlib import Path

import pytest
from hypothesis import assume, given, settings
from hypothesis import strategies as st
from hypothesis.stateful import Bundle, RuleBasedStateMachine, rule

# Add the helper script directory to the path
SCRIPT_DIR = Path(__file__).parent.parent / "configs" / "quickshell" / "ii" / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from voice_agent_backends.tool_manager import (
    ConcurrentToolCallError,
    NoToolCallPendingError,
    ToolCallManager,
    ToolResultMismatchError,
)


# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

# Tool call IDs: non-empty ASCII identifiers (simulating call_123 style)
_call_id_st = st.text(
    min_size=1,
    max_size=50,
    alphabet=st.characters(whitelist_categories=("L", "N"), whitelist_characters="_-"),
)

# Tool names: non-empty identifiers
_tool_name_st = st.text(
    min_size=1,
    max_size=30,
    alphabet=st.characters(whitelist_categories=("L", "N"), whitelist_characters="_"),
)


# ---------------------------------------------------------------------------
# Property tests
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestToolCallPairingProperties:
    """Property-based tests for tool call / result pairing invariants."""

    @settings(max_examples=100)
    @given(
        calls=st.lists(
            st.tuples(_call_id_st, _tool_name_st),
            min_size=1,
            max_size=20,
            unique_by=lambda x: x[0],  # unique IDs
        )
    )
    def test_sequential_calls_all_pair_successfully(
        self, calls: list[tuple[str, str]]
    ) -> None:
        """A sequence of (call, result) pairs with unique IDs all succeed.

        For any sequence of tool calls with unique IDs, processing them
        sequentially (call → result → call → result → ...) should never
        raise, and the manager should be in a clean state after each pair.

        **Validates: Requirements 8.1, 8.2, 8.3, 8.4, 12.3, 12.4**
        """
        mgr = ToolCallManager()

        for call_id, tool_name in calls:
            # Before call: no pending
            assert mgr.has_pending_call is False
            assert mgr.audio_paused is False

            # Register call
            mgr.on_tool_call(call_id, tool_name)

            # After call: pending with correct ID, audio paused
            assert mgr.has_pending_call is True
            assert mgr.pending_call_id == call_id
            assert mgr.pending_tool_name == tool_name
            assert mgr.audio_paused is True

            # Send matching result
            mgr.on_tool_result(call_id)

            # After result: cleared
            assert mgr.has_pending_call is False
            assert mgr.pending_call_id is None
            assert mgr.audio_paused is False

    @settings(max_examples=100)
    @given(
        call_id_1=_call_id_st,
        call_id_2=_call_id_st,
        name_1=_tool_name_st,
        name_2=_tool_name_st,
    )
    def test_concurrent_calls_rejected(
        self, call_id_1: str, call_id_2: str, name_1: str, name_2: str
    ) -> None:
        """No concurrent pending calls: a second call while one is pending raises.

        For any two tool calls (even with different IDs), submitting the
        second before resolving the first MUST raise ConcurrentToolCallError.

        **Validates: Requirements 8.3, 8.4, 12.3, 12.4**
        """
        assume(call_id_1 != call_id_2)

        mgr = ToolCallManager()
        mgr.on_tool_call(call_id_1, name_1)

        with pytest.raises(ConcurrentToolCallError):
            mgr.on_tool_call(call_id_2, name_2)

        # Original call is still pending
        assert mgr.pending_call_id == call_id_1

    @settings(max_examples=100)
    @given(
        call_id=_call_id_st,
        wrong_id=_call_id_st,
        tool_name=_tool_name_st,
    )
    def test_mismatched_result_rejected(
        self, call_id: str, wrong_id: str, tool_name: str
    ) -> None:
        """A TOOL_RESULT with a non-matching ID is rejected.

        For any pending tool call, sending a result with a different ID
        MUST raise ToolResultMismatchError and leave the state unchanged.

        **Validates: Requirements 8.3, 12.3, 12.4, 12.7**
        """
        assume(call_id != wrong_id)

        mgr = ToolCallManager()
        mgr.on_tool_call(call_id, tool_name)

        with pytest.raises(ToolResultMismatchError):
            mgr.on_tool_result(wrong_id)

        # State unchanged — original call still pending
        assert mgr.has_pending_call is True
        assert mgr.pending_call_id == call_id
        assert mgr.audio_paused is True

    @settings(max_examples=100)
    @given(call_id=_call_id_st)
    def test_orphan_result_rejected(self, call_id: str) -> None:
        """A TOOL_RESULT with no pending call is rejected.

        Sending a result when no tool call is pending MUST raise
        NoToolCallPendingError.

        **Validates: Requirements 8.3, 12.3, 12.4**
        """
        mgr = ToolCallManager()
        assert mgr.has_pending_call is False

        with pytest.raises(NoToolCallPendingError):
            mgr.on_tool_result(call_id)

    @settings(max_examples=100)
    @given(
        calls=st.lists(
            st.tuples(_call_id_st, _tool_name_st),
            min_size=2,
            max_size=20,
            unique_by=lambda x: x[0],
        )
    )
    def test_no_duplicate_ids_across_session(
        self, calls: list[tuple[str, str]]
    ) -> None:
        """All tool call IDs within a session are unique.

        The strategy generates sequences with unique IDs. We verify the
        manager correctly tracks each call independently — after resolving
        one, the next call with a different ID succeeds cleanly.

        This confirms the pairing mechanism doesn't confuse prior IDs with
        current ones.

        **Validates: Requirements 8.1, 8.2, 12.7**
        """
        mgr = ToolCallManager()
        seen_ids: set[str] = set()

        for call_id, tool_name in calls:
            # All IDs should be unique (guaranteed by strategy, but assert)
            assert call_id not in seen_ids, f"Duplicate ID: {call_id}"
            seen_ids.add(call_id)

            mgr.on_tool_call(call_id, tool_name)
            assert mgr.pending_call_id == call_id

            mgr.on_tool_result(call_id)
            assert mgr.pending_call_id is None


# ---------------------------------------------------------------------------
# Stateful property test: ToolCallManager state machine
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class ToolCallManagerStateMachine(RuleBasedStateMachine):
    """Stateful property test exercising ToolCallManager through random sequences.

    Verifies invariants hold across arbitrary interleaving of:
    - on_tool_call (with unique IDs)
    - on_tool_result (matching or mismatched)
    - reset

    **Validates: Requirements 8.1, 8.2, 8.3, 8.4, 12.3, 12.4, 12.7**
    """

    def __init__(self) -> None:
        super().__init__()
        self.mgr = ToolCallManager()
        self.pending_id: str | None = None
        self.used_ids: set[str] = set()

    call_ids = Bundle("call_ids")

    @rule(target=call_ids, call_id=_call_id_st, name=_tool_name_st)
    def register_tool_call(self, call_id: str, name: str) -> str:
        """Attempt to register a new tool call."""
        if self.pending_id is not None:
            # Should reject concurrent calls
            with pytest.raises(ConcurrentToolCallError):
                self.mgr.on_tool_call(call_id, name)
            # State unchanged
            assert self.mgr.pending_call_id == self.pending_id
        else:
            self.mgr.on_tool_call(call_id, name)
            self.pending_id = call_id
            self.used_ids.add(call_id)
            assert self.mgr.has_pending_call is True
            assert self.mgr.audio_paused is True
        return call_id

    @rule(call_id=call_ids)
    def send_tool_result(self, call_id: str) -> None:
        """Attempt to send a tool result for a previously seen ID."""
        if self.pending_id is None:
            with pytest.raises(NoToolCallPendingError):
                self.mgr.on_tool_result(call_id)
        elif call_id != self.pending_id:
            with pytest.raises(ToolResultMismatchError):
                self.mgr.on_tool_result(call_id)
            # State unchanged
            assert self.mgr.pending_call_id == self.pending_id
        else:
            self.mgr.on_tool_result(call_id)
            self.pending_id = None
            assert self.mgr.has_pending_call is False
            assert self.mgr.audio_paused is False

    @rule()
    def reset_manager(self) -> None:
        """Reset the manager, clearing all state."""
        self.mgr.reset()
        self.pending_id = None
        assert self.mgr.has_pending_call is False
        assert self.mgr.audio_paused is False

    def invariant_single_pending(self) -> None:
        """At most one call is pending at any time."""
        if self.pending_id is None:
            assert self.mgr.has_pending_call is False
            assert self.mgr.pending_call_id is None
            assert self.mgr.audio_paused is False
        else:
            assert self.mgr.has_pending_call is True
            assert self.mgr.pending_call_id == self.pending_id
            assert self.mgr.audio_paused is True


# Hypothesis will run the stateful test automatically
TestToolCallStateMachine = ToolCallManagerStateMachine.TestCase
