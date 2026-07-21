# Feature: chat-context-management
"""
Property-based tests for the Chat Context Management feature.

These tests validate pure logic functions extracted from the QML implementation
using Python reimplementations and Hypothesis for property-based testing.
"""

import math

import pytest
from hypothesis import given, settings
import hypothesis.strategies as st


# ---------------------------------------------------------------------------
# Pure function reimplementations (mirrors QML logic in Ai.qml)
# ---------------------------------------------------------------------------


def estimate_tokens(text: str | None) -> int:
    """Estimate token count for a text string.

    Mirrors the QML function:
        function estimateTokens(text) {
            return Math.ceil((text || "").length / 4);
        }

    Returns math.ceil(len(text) / 4), or 0 for None/empty.
    """
    if not text:
        return 0
    return math.ceil(len(text) / 4)


def calculate_context_tokens(system_prompt: str | None, messages: list[dict]) -> int:
    """Calculate total context token usage.

    Mirrors the QML computed property:
        readonly property int contextTokens: {
            let total = estimateTokens(root.systemPrompt);
            for (const id of root.messageIDs) {
                const msg = root.messageByID[id];
                if (msg) total += estimateTokens(msg.rawContent);
            }
            return total;
        }

    Returns the sum of estimateTokens(system_prompt) plus
    estimateTokens(msg["rawContent"]) for each message.
    """
    total = estimate_tokens(system_prompt)
    for msg in messages:
        total += estimate_tokens(msg.get("rawContent"))
    return total


def get_context_color(ratio: float) -> str:
    """Determine context indicator color based on usage ratio.

    Mirrors QML:
        usage > 0.9 ? Appearance.m3colors.m3error
        : usage > 0.7 ? Appearance.m3colors.m3tertiary
        : Appearance.colors.colSubtext

    Returns:
        "error" when ratio > 0.9
        "warning" when ratio > 0.7
        "default" otherwise
    """
    if ratio > 0.9:
        return "error"
    elif ratio > 0.7:
        return "warning"
    else:
        return "default"


# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

# Arbitrary text for system prompts (including empty and unicode)
_system_prompt_st = st.one_of(
    st.none(),
    st.just(""),
    st.text(min_size=0, max_size=500),
)

# Arbitrary message dicts with rawContent field
_message_st = st.fixed_dictionaries({
    "rawContent": st.one_of(
        st.none(),
        st.just(""),
        st.text(min_size=0, max_size=500),
    ),
})

# List of messages (0 to 50 messages)
_messages_st = st.lists(_message_st, min_size=0, max_size=50)


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 2: Context usage is the sum of
# all message tokens plus system prompt
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestContextUsageCalculation:
    """Feature: chat-context-management, Property 2: Context usage is the sum of all message tokens plus system prompt"""

    @given(
        system_prompt=_system_prompt_st,
        messages=_messages_st,
    )
    @settings(max_examples=200)
    def test_context_tokens_equals_sum_of_all_estimates(
        self, system_prompt: str | None, messages: list[dict]
    ):
        """contextTokens equals estimateTokens(systemPrompt) + sum(estimateTokens(msg.rawContent) for msg in messages).

        **Validates: Requirements 2.2**
        """
        result = calculate_context_tokens(system_prompt, messages)

        # Independently compute the expected value
        expected = estimate_tokens(system_prompt)
        for msg in messages:
            expected += estimate_tokens(msg.get("rawContent"))

        assert result == expected, (
            f"calculate_context_tokens mismatch: got {result}, expected {expected}. "
            f"system_prompt={system_prompt!r}, message_count={len(messages)}"
        )

    @given(
        system_prompt=st.text(min_size=1, max_size=500),
        messages=_messages_st,
    )
    @settings(max_examples=200)
    def test_context_tokens_at_least_system_prompt_tokens(
        self, system_prompt: str, messages: list[dict]
    ):
        """contextTokens is always >= estimateTokens(systemPrompt) since messages add non-negative tokens.

        **Validates: Requirements 2.2**
        """
        result = calculate_context_tokens(system_prompt, messages)
        system_tokens = estimate_tokens(system_prompt)

        assert result >= system_tokens, (
            f"contextTokens ({result}) should be >= system prompt tokens ({system_tokens})"
        )

    @given(messages=_messages_st)
    @settings(max_examples=200)
    def test_empty_system_prompt_equals_message_sum(self, messages: list[dict]):
        """With empty/None system prompt, contextTokens equals just the sum of message tokens.

        **Validates: Requirements 2.2**
        """
        result = calculate_context_tokens(None, messages)
        expected = sum(estimate_tokens(msg.get("rawContent")) for msg in messages)

        assert result == expected, (
            f"With None system prompt: got {result}, expected {expected}"
        )

    @given(system_prompt=_system_prompt_st)
    @settings(max_examples=200)
    def test_no_messages_equals_system_prompt_tokens(self, system_prompt: str | None):
        """With no messages, contextTokens equals just the system prompt tokens.

        **Validates: Requirements 2.2**
        """
        result = calculate_context_tokens(system_prompt, [])
        expected = estimate_tokens(system_prompt)

        assert result == expected, (
            f"With no messages: got {result}, expected {expected}. "
            f"system_prompt={system_prompt!r}"
        )

    @given(
        system_prompt=_system_prompt_st,
        messages=_messages_st,
    )
    @settings(max_examples=200)
    def test_context_tokens_is_non_negative(
        self, system_prompt: str | None, messages: list[dict]
    ):
        """contextTokens is always non-negative regardless of inputs.

        **Validates: Requirements 2.2**
        """
        result = calculate_context_tokens(system_prompt, messages)
        assert result >= 0, f"contextTokens should never be negative, got {result}"


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 3: Context indicator color
# follows threshold rules
# ---------------------------------------------------------------------------
"""
Property 3: Context indicator color follows threshold rules

For any context usage ratio value, the indicator color SHALL be: error color
when ratio > 0.9, warning color when ratio > 0.7, and default color otherwise.

**Validates: Requirements 2.6, 2.7**
"""


@pytest.mark.property_test
class TestContextIndicatorColor:
    """Feature: chat-context-management, Property 3: Context indicator color follows threshold rules"""

    @given(
        ratio=st.floats(min_value=0.0, max_value=2.0, allow_nan=False, allow_infinity=False),
    )
    @settings(max_examples=200)
    def test_color_follows_threshold_rules(self, ratio: float):
        """For any ratio, get_context_color returns the correct color based on thresholds.

        - ratio > 0.9 → "error"
        - ratio > 0.7 (and ≤ 0.9) → "warning"
        - ratio ≤ 0.7 → "default"

        **Validates: Requirements 2.6, 2.7**
        """
        color = get_context_color(ratio)

        if ratio > 0.9:
            assert color == "error", (
                f"Expected 'error' for ratio {ratio} > 0.9, got '{color}'"
            )
        elif ratio > 0.7:
            assert color == "warning", (
                f"Expected 'warning' for ratio {ratio} > 0.7, got '{color}'"
            )
        else:
            assert color == "default", (
                f"Expected 'default' for ratio {ratio} ≤ 0.7, got '{color}'"
            )

    @given(
        ratio=st.floats(
            min_value=0.9 + 1e-10, max_value=2.0,
            allow_nan=False, allow_infinity=False,
        ),
    )
    @settings(max_examples=200)
    def test_above_90_always_error(self, ratio: float):
        """Any ratio strictly above 0.9 always produces error color.

        **Validates: Requirements 2.7**
        """
        assert get_context_color(ratio) == "error", (
            f"Expected 'error' for ratio {ratio}, got '{get_context_color(ratio)}'"
        )

    @given(
        ratio=st.floats(
            min_value=0.7 + 1e-10, max_value=0.9,
            allow_nan=False, allow_infinity=False,
        ),
    )
    @settings(max_examples=200)
    def test_between_70_and_90_always_warning(self, ratio: float):
        """Any ratio in (0.7, 0.9] produces warning color.

        **Validates: Requirements 2.6**
        """
        assert get_context_color(ratio) == "warning", (
            f"Expected 'warning' for ratio {ratio}, got '{get_context_color(ratio)}'"
        )

    @given(
        ratio=st.floats(
            min_value=0.0, max_value=0.7,
            allow_nan=False, allow_infinity=False,
        ),
    )
    @settings(max_examples=200)
    def test_at_or_below_70_always_default(self, ratio: float):
        """Any ratio ≤ 0.7 produces default color.

        **Validates: Requirements 2.6, 2.7**
        """
        assert get_context_color(ratio) == "default", (
            f"Expected 'default' for ratio {ratio}, got '{get_context_color(ratio)}'"
        )


# ---------------------------------------------------------------------------
# Pure function reimplementation: new_session (mirrors QML SessionManager logic)
# ---------------------------------------------------------------------------


def new_session(name: str, existing_sessions: list[str]) -> tuple[str, list]:
    """Create a new session with the given name.

    Mirrors the QML function:
        function newSession(name) {
            // validate name (non-empty after trim, no / or \\ characters)
            // save current session, create empty message list,
            // set activeSessionName, update Persistent state,
            // update sessions-index with creation timestamp
        }

    Args:
        name: The session name to create.
        existing_sessions: List of existing session names (for context, not
            used for validation in this property test).

    Returns:
        Tuple of (active_session_name, messages_list) where messages_list is
        always empty for a new session.

    Raises:
        ValueError: If name is empty after trimming or contains path separators.
    """
    trimmed = name.strip()
    if not trimmed:
        raise ValueError("Session name cannot be empty after trimming")
    if "/" in trimmed or "\\" in trimmed:
        raise ValueError(
            f"Session name cannot contain path separators: {trimmed!r}"
        )
    return (trimmed, [])


# ---------------------------------------------------------------------------
# Strategies for session names
# ---------------------------------------------------------------------------

# Valid session names: non-empty, no path separators (/ or \)
_valid_session_name_st = st.text(
    alphabet=st.characters(
        blacklist_characters="/\\",
        blacklist_categories=("Cs",),  # Exclude surrogate characters
    ),
    min_size=1,
    max_size=100,
).filter(lambda s: len(s.strip()) > 0)

# Invalid session names: either empty/whitespace-only, or containing path separators
_invalid_session_name_empty_st = st.one_of(
    st.just(""),
    st.just("   "),
    st.just("\t\n"),
    st.text(
        alphabet=st.characters(whitelist_categories=("Zs", "Cc")),
        min_size=1,
        max_size=20,
    ).filter(lambda s: len(s.strip()) == 0),
)

_invalid_session_name_path_sep_st = st.one_of(
    st.text(min_size=1, max_size=50).map(lambda s: s + "/"),
    st.text(min_size=1, max_size=50).map(lambda s: s + "\\"),
    st.text(min_size=1, max_size=50).map(lambda s: "/" + s),
    st.text(min_size=1, max_size=50).map(lambda s: "\\" + s),
    st.text(min_size=2, max_size=50).map(
        lambda s: s[: len(s) // 2] + "/" + s[len(s) // 2 :]
    ),
    st.text(min_size=2, max_size=50).map(
        lambda s: s[: len(s) // 2] + "\\" + s[len(s) // 2 :]
    ),
)

# Existing sessions list strategy
_existing_sessions_st = st.lists(
    st.text(
        alphabet=st.characters(blacklist_characters="/\\", blacklist_categories=("Cs",)),
        min_size=1,
        max_size=50,
    ).filter(lambda s: len(s.strip()) > 0),
    min_size=0,
    max_size=20,
)


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 4: New session creation produces
# empty history
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestNewSessionCreation:
    """Feature: chat-context-management, Property 4: New session creation produces empty history"""

    @given(
        name=_valid_session_name_st,
        existing_sessions=_existing_sessions_st,
    )
    @settings(max_examples=200)
    def test_new_session_produces_empty_message_list(
        self, name: str, existing_sessions: list[str]
    ):
        """Creating a new session with a valid name results in an empty message list.

        **Validates: Requirements 1.1**
        """
        active_name, messages = new_session(name, existing_sessions)
        assert messages == [], (
            f"New session should have empty message list, got {messages!r}"
        )

    @given(
        name=_valid_session_name_st,
        existing_sessions=_existing_sessions_st,
    )
    @settings(max_examples=200)
    def test_new_session_active_name_matches_trimmed_input(
        self, name: str, existing_sessions: list[str]
    ):
        """Creating a new session sets the active session name to the trimmed input name.

        **Validates: Requirements 1.1**
        """
        active_name, messages = new_session(name, existing_sessions)
        assert active_name == name.strip(), (
            f"Active session name should be '{name.strip()}', got '{active_name}'"
        )

    @given(
        name=_valid_session_name_st,
        existing_sessions=_existing_sessions_st,
    )
    @settings(max_examples=200)
    def test_new_session_returns_correct_tuple_structure(
        self, name: str, existing_sessions: list[str]
    ):
        """new_session returns a tuple of (str, list) with matching name and empty list.

        **Validates: Requirements 1.1**
        """
        result = new_session(name, existing_sessions)
        assert isinstance(result, tuple), f"Expected tuple, got {type(result)}"
        assert len(result) == 2, f"Expected 2-element tuple, got {len(result)} elements"
        assert isinstance(result[0], str), f"First element should be str, got {type(result[0])}"
        assert isinstance(result[1], list), f"Second element should be list, got {type(result[1])}"

    @given(name=_invalid_session_name_empty_st)
    @settings(max_examples=200)
    def test_new_session_rejects_empty_names(self, name: str):
        """Names that are empty or whitespace-only after trimming raise ValueError.

        **Validates: Requirements 1.1**
        """
        with pytest.raises(ValueError):
            new_session(name, [])

    @given(name=_invalid_session_name_path_sep_st)
    @settings(max_examples=200)
    def test_new_session_rejects_names_with_path_separators(self, name: str):
        """Names containing '/' or '\\' raise ValueError.

        **Validates: Requirements 1.1**
        """
        with pytest.raises(ValueError):
            new_session(name, [])


# ---------------------------------------------------------------------------
# Pure function reimplementation: getNextDefaultName
# ---------------------------------------------------------------------------


def get_next_default_name(existing_names: list[str]) -> str:
    """Generate the next default session name.

    Mirrors the QML function getNextDefaultName():
        Finds the smallest positive integer N where "Chat {N}" is not
        already present in the existing session names.

    Returns "Chat {N}" where N is the smallest unused positive integer.
    """
    n = 1
    while True:
        candidate = f"Chat {n}"
        if candidate not in existing_names:
            return candidate
        n += 1


# ---------------------------------------------------------------------------
# Strategies for Property 5
# ---------------------------------------------------------------------------

# Generate a set of "Chat {N}" names (simulating existing sessions with default names)
_chat_number_st = st.integers(min_value=1, max_value=100)

# Strategy for existing session names: mix of "Chat {N}" patterns and arbitrary names
_existing_names_st = st.lists(
    st.one_of(
        # Default "Chat {N}" pattern names
        st.integers(min_value=1, max_value=50).map(lambda n: f"Chat {n}"),
        # Arbitrary non-Chat names (user-provided names)
        st.text(
            alphabet=st.characters(blacklist_characters="/\\"),
            min_size=1,
            max_size=30,
        ).filter(lambda s: not s.startswith("Chat ")),
    ),
    min_size=0,
    max_size=30,
    unique=True,
)


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 5: Default session naming follows
# sequential pattern
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestDefaultSessionNaming:
    """Feature: chat-context-management, Property 5: Default session naming follows sequential pattern"""

    @given(existing_names=_existing_names_st)
    @settings(max_examples=200)
    def test_generated_name_is_chat_n_with_smallest_unused_n(
        self, existing_names: list[str]
    ):
        """For any set of existing sessions, the generated name is "Chat {N}" where N is the smallest unused positive integer.

        **Validates: Requirements 1.2**
        """
        result = get_next_default_name(existing_names)

        # Result must follow the "Chat {N}" pattern
        assert result.startswith("Chat "), (
            f"Generated name '{result}' does not start with 'Chat '"
        )
        n_str = result[len("Chat "):]
        assert n_str.isdigit(), (
            f"Generated name '{result}' does not have a numeric suffix"
        )
        n = int(n_str)

        # N must be a positive integer
        assert n >= 1, f"N must be >= 1, got {n}"

        # N must be the smallest positive integer not in existing names
        for i in range(1, n):
            assert f"Chat {i}" in existing_names, (
                f"Chat {i} is not in existing names but {n} was chosen. "
                f"Expected smallest unused N to be {i}. "
                f"existing_names={existing_names}"
            )

    @given(existing_names=_existing_names_st)
    @settings(max_examples=200)
    def test_generated_name_not_in_existing_names(
        self, existing_names: list[str]
    ):
        """The generated default name must NOT already be present in existing names.

        **Validates: Requirements 1.2**
        """
        result = get_next_default_name(existing_names)

        assert result not in existing_names, (
            f"Generated name '{result}' is already in existing_names: {existing_names}"
        )

    @given(
        existing_names=st.lists(
            st.integers(min_value=1, max_value=50).map(lambda n: f"Chat {n}"),
            min_size=0,
            max_size=30,
            unique=True,
        )
    )
    @settings(max_examples=200)
    def test_sequential_gap_filling(self, existing_names: list[str]):
        """When existing names are all "Chat {N}" patterns, the result fills the first gap in the sequence.

        **Validates: Requirements 1.2**
        """
        result = get_next_default_name(existing_names)
        n = int(result[len("Chat "):])

        # Verify all integers below n are occupied
        for i in range(1, n):
            assert f"Chat {i}" in existing_names, (
                f"Gap found at Chat {i} but Chat {n} was chosen"
            )

        # Verify n itself is not occupied
        assert f"Chat {n}" not in existing_names

    def test_empty_list_returns_chat_1(self):
        """With no existing sessions, the default name is "Chat 1".

        **Validates: Requirements 1.2**
        """
        assert get_next_default_name([]) == "Chat 1"

    def test_chat_1_taken_returns_chat_2(self):
        """When "Chat 1" exists, "Chat 2" is returned.

        **Validates: Requirements 1.2**
        """
        assert get_next_default_name(["Chat 1"]) == "Chat 2"

    def test_gap_in_sequence(self):
        """When there's a gap in the sequence, the gap is filled.

        **Validates: Requirements 1.2**
        """
        # Chat 1, Chat 2, Chat 4 exist → Chat 3 should be returned
        assert get_next_default_name(["Chat 1", "Chat 2", "Chat 4"]) == "Chat 3"


# ---------------------------------------------------------------------------
# Pure function reimplementation for session switching
# ---------------------------------------------------------------------------


def switch_session(
    store: dict[str, list[dict]],
    current_name: str,
    current_messages: list[dict],
    target_name: str,
) -> list[dict]:
    """Switch from current session to target session.

    Mirrors the QML logic in switchSession():
        1. Save current messages into store[current_name]
        2. Return store[target_name] (the target session's messages)

    This is the core round-trip operation: saving the active session
    and loading another session from the in-memory store.
    """
    store[current_name] = current_messages
    return store.get(target_name, [])


# ---------------------------------------------------------------------------
# Strategies for session switch testing
# ---------------------------------------------------------------------------

# Session names: non-empty strings without path separators
_session_name_st = st.text(
    alphabet=st.characters(
        blacklist_characters="/\\",
        blacklist_categories=("Cs",),  # Exclude surrogates
    ),
    min_size=1,
    max_size=50,
).filter(lambda s: s.strip() != "")

# Message list for a session (reuse the message strategy pattern)
_session_messages_st = st.lists(
    st.fixed_dictionaries({
        "rawContent": st.one_of(
            st.none(),
            st.just(""),
            st.text(min_size=0, max_size=200),
        ),
        "role": st.sampled_from(["user", "assistant", "system"]),
    }),
    min_size=0,
    max_size=30,
)


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 6: Session switch round-trip
# preserves messages
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestSessionSwitchRoundTrip:
    """Feature: chat-context-management, Property 6: Session switch round-trip preserves messages"""

    @given(
        session_a_name=_session_name_st,
        session_b_name=_session_name_st,
        messages_a=_session_messages_st,
        messages_b=_session_messages_st,
    )
    @settings(max_examples=200)
    def test_switch_a_to_b_and_back_restores_a(
        self,
        session_a_name: str,
        session_b_name: str,
        messages_a: list[dict],
        messages_b: list[dict],
    ):
        """Switching from A to B and back to A restores A's original message list.

        For any two sessions with arbitrary message histories, the round-trip
        switch A→B→A SHALL restore session A's original message list
        (content and order).

        **Validates: Requirements 1.3**
        """
        from hypothesis import assume

        # Sessions must have distinct names for a meaningful round-trip
        assume(session_a_name != session_b_name)

        # Initialize the store with session B's messages already present
        store: dict[str, list[dict]] = {
            session_b_name: messages_b,
        }

        # Step 1: Switch from A to B (saves A's messages, loads B's)
        loaded_b = switch_session(store, session_a_name, messages_a, session_b_name)

        # Verify B's messages were loaded correctly
        assert loaded_b == messages_b, (
            f"Expected B's messages after switch A→B, got different content"
        )

        # Step 2: Switch from B back to A (saves B's messages, loads A's)
        loaded_a = switch_session(store, session_b_name, loaded_b, session_a_name)

        # The round-trip must restore A's original messages exactly
        assert loaded_a == messages_a, (
            f"Round-trip A→B→A did not preserve A's messages. "
            f"Original had {len(messages_a)} messages, got {len(loaded_a)}"
        )

    @given(
        session_a_name=_session_name_st,
        session_b_name=_session_name_st,
        messages_a=_session_messages_st,
        messages_b=_session_messages_st,
    )
    @settings(max_examples=200)
    def test_switch_preserves_message_order(
        self,
        session_a_name: str,
        session_b_name: str,
        messages_a: list[dict],
        messages_b: list[dict],
    ):
        """Switching sessions preserves the ordering of messages, not just content.

        **Validates: Requirements 1.3**
        """
        from hypothesis import assume

        assume(session_a_name != session_b_name)

        store: dict[str, list[dict]] = {
            session_b_name: messages_b,
        }

        # Perform the round-trip
        _ = switch_session(store, session_a_name, messages_a, session_b_name)
        restored_a = switch_session(store, session_b_name, messages_b, session_a_name)

        # Verify element-by-element ordering
        assert len(restored_a) == len(messages_a), (
            f"Message count mismatch: expected {len(messages_a)}, got {len(restored_a)}"
        )
        for i, (original, restored) in enumerate(zip(messages_a, restored_a)):
            assert original == restored, (
                f"Message at index {i} differs after round-trip: "
                f"original={original!r}, restored={restored!r}"
            )

    @given(
        session_a_name=_session_name_st,
        session_b_name=_session_name_st,
        messages_a=_session_messages_st,
        messages_b=_session_messages_st,
    )
    @settings(max_examples=200)
    def test_switch_does_not_mutate_other_session(
        self,
        session_a_name: str,
        session_b_name: str,
        messages_a: list[dict],
        messages_b: list[dict],
    ):
        """Switching sessions does not corrupt the other session's stored messages.

        **Validates: Requirements 1.3**
        """
        from hypothesis import assume

        assume(session_a_name != session_b_name)

        # Keep a reference copy of B's original messages
        original_b = [msg.copy() for msg in messages_b]

        store: dict[str, list[dict]] = {
            session_b_name: messages_b,
        }

        # Switch A→B, then B→A
        loaded_b = switch_session(store, session_a_name, messages_a, session_b_name)
        _ = switch_session(store, session_b_name, loaded_b, session_a_name)

        # After the round-trip, B's messages in the store should still match original
        assert store[session_b_name] == original_b, (
            f"Session B's stored messages were corrupted during round-trip"
        )


# ---------------------------------------------------------------------------
# Pure function reimplementation: delete_session
# ---------------------------------------------------------------------------


def delete_session(
    sessions_index: list[dict], active_name: str, name_to_delete: str
) -> list[dict]:
    """Delete a session from the sessions index.

    Mirrors the QML function:
        function deleteSession(name) {
            if (name === activeSessionName) throw error;
            sessionsIndex = sessionsIndex.filter(s => s.name !== name);
        }

    Preconditions:
        - name_to_delete != active_name
        - name_to_delete is present in sessions_index

    Raises ValueError if name_to_delete == active_name.
    Returns the filtered list excluding the deleted session.
    """
    if name_to_delete == active_name:
        raise ValueError(
            f"Cannot delete the active session '{active_name}'"
        )
    return [s for s in sessions_index if s["name"] != name_to_delete]


# ---------------------------------------------------------------------------
# Strategies for session deletion tests
# ---------------------------------------------------------------------------

# Generate a valid session name: non-empty, no path separators
_session_name_st = st.text(
    alphabet=st.characters(
        blacklist_categories=("Cs",),
        blacklist_characters="/\\",
    ),
    min_size=1,
    max_size=30,
).filter(lambda s: s.strip() != "")

# Generate a session entry dict with a name and timestamps
def _session_entry(name: str) -> dict:
    """Create a session entry dict from a name."""
    return {"name": name, "createdAt": 1719500000, "lastModified": 1719501234}


@st.composite
def _sessions_with_deletable(draw):
    """Generate a sessions index with at least 2 distinct-name sessions,
    an active session name, and a different name to delete.

    Returns (sessions_index, active_name, name_to_delete).
    """
    # Generate at least 2 unique session names
    names = draw(
        st.lists(
            _session_name_st,
            min_size=2,
            max_size=10,
            unique=True,
        )
    )
    sessions_index = [_session_entry(n) for n in names]

    # Pick the active session
    active_name = draw(st.sampled_from(names))

    # Pick a different session to delete
    deletable_names = [n for n in names if n != active_name]
    name_to_delete = draw(st.sampled_from(deletable_names))

    return sessions_index, active_name, name_to_delete


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 8: Deleting a non-active session
# reduces session count by one
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestSessionDeletion:
    """Feature: chat-context-management, Property 8: Deleting a non-active session reduces session count by one"""

    @given(data=_sessions_with_deletable())
    @settings(max_examples=200)
    def test_delete_reduces_count_by_one(self, data):
        """Deleting a non-active session reduces session count by exactly one.

        **Validates: Requirements 1.5**
        """
        sessions_index, active_name, name_to_delete = data
        original_count = len(sessions_index)

        result = delete_session(sessions_index, active_name, name_to_delete)

        assert len(result) == original_count - 1, (
            f"Expected count {original_count - 1} after deletion, got {len(result)}. "
            f"Deleted '{name_to_delete}' from {original_count} sessions."
        )

    @given(data=_sessions_with_deletable())
    @settings(max_examples=200)
    def test_deleted_session_no_longer_appears(self, data):
        """After deletion, the deleted session name no longer appears in the index.

        **Validates: Requirements 1.5**
        """
        sessions_index, active_name, name_to_delete = data

        result = delete_session(sessions_index, active_name, name_to_delete)
        result_names = [s["name"] for s in result]

        assert name_to_delete not in result_names, (
            f"Deleted session '{name_to_delete}' still appears in result: {result_names}"
        )

    @given(data=_sessions_with_deletable())
    @settings(max_examples=200)
    def test_active_session_preserved_after_delete(self, data):
        """After deleting a non-active session, the active session still appears in the index.

        **Validates: Requirements 1.5**
        """
        sessions_index, active_name, name_to_delete = data

        result = delete_session(sessions_index, active_name, name_to_delete)
        result_names = [s["name"] for s in result]

        assert active_name in result_names, (
            f"Active session '{active_name}' disappeared after deleting '{name_to_delete}'"
        )

    @given(
        names=st.lists(_session_name_st, min_size=1, max_size=10, unique=True),
    )
    @settings(max_examples=200)
    def test_delete_active_session_raises_error(self, names: list[str]):
        """Attempting to delete the active session raises ValueError.

        **Validates: Requirements 1.5**
        """
        sessions_index = [_session_entry(n) for n in names]
        active_name = names[0]

        with pytest.raises(ValueError):
            delete_session(sessions_index, active_name, active_name)


# ---------------------------------------------------------------------------
# Pure function reimplementations: serialize_session / deserialize_session
# ---------------------------------------------------------------------------

import json


def serialize_session(messages: list[dict]) -> str:
    """Serialize a list of messages to a JSON string.

    Mirrors the QML saveChat logic which writes the messages array
    as a JSON file using JSON.stringify.

    Args:
        messages: List of message dicts with fields like role, rawContent,
            model, thinking, done, annotations, annotationSources,
            functionName, functionCall, functionResponse, visibleToUser.

    Returns:
        JSON string representing the message list.
    """
    return json.dumps(messages)


def deserialize_session(json_str: str) -> list[dict]:
    """Deserialize a JSON string back into a list of messages.

    Mirrors the QML loadChat logic which reads and parses a session JSON file.

    Args:
        json_str: A valid JSON string representing a message list.

    Returns:
        List of message dicts.
    """
    return json.loads(json_str)


# ---------------------------------------------------------------------------
# Strategies for session serialization
# ---------------------------------------------------------------------------

# Strategy for a single message with all defined fields
_full_message_st = st.fixed_dictionaries({
    "role": st.sampled_from(["user", "assistant", "system"]),
    "rawContent": st.text(min_size=0, max_size=300),
    "model": st.text(min_size=0, max_size=50),
    "thinking": st.booleans(),
    "done": st.booleans(),
    "annotations": st.lists(st.text(min_size=0, max_size=50), min_size=0, max_size=5),
    "annotationSources": st.lists(st.text(min_size=0, max_size=100), min_size=0, max_size=5),
    "functionName": st.text(min_size=0, max_size=50),
    "functionCall": st.one_of(
        st.none(),
        st.fixed_dictionaries({
            "name": st.text(min_size=1, max_size=30),
            "arguments": st.text(min_size=0, max_size=100),
        }),
    ),
    "functionResponse": st.text(min_size=0, max_size=200),
    "visibleToUser": st.booleans(),
})

# List of full messages (0 to 30 messages)
_full_messages_st = st.lists(_full_message_st, min_size=0, max_size=30)


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 9: Session serialization
# round-trip preserves data
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestSessionSerializationRoundTrip:
    """Feature: chat-context-management, Property 9: Session serialization round-trip preserves data"""

    @given(messages=_full_messages_st)
    @settings(max_examples=200)
    def test_serialize_deserialize_round_trip_preserves_data(
        self, messages: list[dict]
    ):
        """For any session with arbitrary messages, serializing to JSON and
        deserializing produces an equivalent message list (same roles, content,
        and metadata).

        **Validates: Requirements 1.8, 6.1**
        """
        serialized = serialize_session(messages)
        deserialized = deserialize_session(serialized)

        assert deserialized == messages, (
            f"Round-trip failed: original has {len(messages)} messages, "
            f"deserialized has {len(deserialized)} messages. "
            f"First diff at index "
            f"{next((i for i, (a, b) in enumerate(zip(messages, deserialized)) if a != b), 'length mismatch')}"
        )

    @given(messages=_full_messages_st)
    @settings(max_examples=200)
    def test_serialize_produces_valid_json(self, messages: list[dict]):
        """Serialization always produces a valid JSON string that can be parsed.

        **Validates: Requirements 1.8, 6.1**
        """
        serialized = serialize_session(messages)

        # Should not raise
        parsed = json.loads(serialized)
        assert isinstance(parsed, list), (
            f"Deserialized session should be a list, got {type(parsed)}"
        )

    @given(messages=_full_messages_st)
    @settings(max_examples=200)
    def test_round_trip_preserves_message_count(self, messages: list[dict]):
        """Serialization round-trip preserves the number of messages.

        **Validates: Requirements 1.8, 6.1**
        """
        serialized = serialize_session(messages)
        deserialized = deserialize_session(serialized)

        assert len(deserialized) == len(messages), (
            f"Message count mismatch: original={len(messages)}, "
            f"after round-trip={len(deserialized)}"
        )

    @given(messages=_full_messages_st)
    @settings(max_examples=200)
    def test_round_trip_preserves_each_field(self, messages: list[dict]):
        """Each field in every message is preserved exactly through the round-trip.

        **Validates: Requirements 1.8, 6.1**
        """
        serialized = serialize_session(messages)
        deserialized = deserialize_session(serialized)

        for i, (original, restored) in enumerate(zip(messages, deserialized)):
            for field in [
                "role", "rawContent", "model", "thinking", "done",
                "annotations", "annotationSources", "functionName",
                "functionCall", "functionResponse", "visibleToUser",
            ]:
                assert original[field] == restored[field], (
                    f"Message[{i}].{field} differs: "
                    f"original={original[field]!r}, restored={restored[field]!r}"
                )

    @given(messages=_full_messages_st)
    @settings(max_examples=200)
    def test_double_round_trip_is_idempotent(self, messages: list[dict]):
        """Applying serialize/deserialize twice produces the same result as once.

        **Validates: Requirements 1.8, 6.1**
        """
        first_trip = deserialize_session(serialize_session(messages))
        second_trip = deserialize_session(serialize_session(first_trip))

        assert first_trip == second_trip, (
            "Double round-trip produced different results from single round-trip"
        )


# ---------------------------------------------------------------------------
# Pure function reimplementation: build_sessions_index
# ---------------------------------------------------------------------------


def build_sessions_index(sessions: list[dict]) -> dict:
    """Build the sessions-index.json structure from a list of session metadata.

    Mirrors the QML logic in saveSessionsIndex():
        The sessions-index.json contains an entry for each session with its
        name, creation timestamp (createdAt), and last-modified timestamp
        (lastModified).

    Args:
        sessions: List of dicts, each with "name" (str), "createdAt" (int),
            and "lastModified" (int).

    Returns:
        Dict in the format: {"sessions": [{"name": str, "createdAt": int, "lastModified": int}, ...]}
    """
    return {
        "sessions": [
            {
                "name": s["name"],
                "createdAt": s["createdAt"],
                "lastModified": s["lastModified"],
            }
            for s in sessions
        ]
    }


# ---------------------------------------------------------------------------
# Strategies for sessions index testing
# ---------------------------------------------------------------------------

# Session metadata entry strategy: name + non-negative integer timestamps
_session_metadata_st = st.fixed_dictionaries({
    "name": st.text(
        alphabet=st.characters(
            blacklist_characters="/\\",
            blacklist_categories=("Cs",),
        ),
        min_size=1,
        max_size=50,
    ).filter(lambda s: s.strip() != ""),
    "createdAt": st.integers(min_value=0, max_value=2**53),
    "lastModified": st.integers(min_value=0, max_value=2**53),
})

# List of session metadata entries (0 to 30 sessions)
_sessions_metadata_list_st = st.lists(
    _session_metadata_st,
    min_size=0,
    max_size=30,
)


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 17: Sessions index contains all
# session metadata
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestSessionsIndex:
    """Feature: chat-context-management, Property 17: Sessions index contains all session metadata"""

    @given(sessions=_sessions_metadata_list_st)
    @settings(max_examples=200)
    def test_index_contains_every_input_session(self, sessions: list[dict]):
        """For any set of sessions, the index contains every session from the input.

        **Validates: Requirements 6.5**
        """
        result = build_sessions_index(sessions)
        index_entries = result["sessions"]

        assert len(index_entries) == len(sessions), (
            f"Index has {len(index_entries)} entries but input had {len(sessions)} sessions"
        )

        for i, session in enumerate(sessions):
            entry = index_entries[i]
            assert entry["name"] == session["name"], (
                f"Session at index {i}: expected name '{session['name']}', got '{entry['name']}'"
            )
            assert entry["createdAt"] == session["createdAt"], (
                f"Session '{session['name']}': expected createdAt {session['createdAt']}, "
                f"got {entry['createdAt']}"
            )
            assert entry["lastModified"] == session["lastModified"], (
                f"Session '{session['name']}': expected lastModified {session['lastModified']}, "
                f"got {entry['lastModified']}"
            )

    @given(sessions=_sessions_metadata_list_st)
    @settings(max_examples=200)
    def test_all_entries_have_required_fields(self, sessions: list[dict]):
        """Every entry in the index has name, createdAt, and lastModified fields.

        **Validates: Requirements 6.5**
        """
        result = build_sessions_index(sessions)

        for entry in result["sessions"]:
            assert "name" in entry, f"Entry missing 'name' field: {entry}"
            assert "createdAt" in entry, f"Entry missing 'createdAt' field: {entry}"
            assert "lastModified" in entry, f"Entry missing 'lastModified' field: {entry}"

    @given(sessions=_sessions_metadata_list_st)
    @settings(max_examples=200)
    def test_no_extra_sessions_in_index(self, sessions: list[dict]):
        """The index contains no extra sessions beyond what was provided as input.

        **Validates: Requirements 6.5**
        """
        result = build_sessions_index(sessions)
        index_entries = result["sessions"]

        assert len(index_entries) == len(sessions), (
            f"Index has {len(index_entries)} entries but expected exactly {len(sessions)}"
        )

    @given(sessions=_sessions_metadata_list_st)
    @settings(max_examples=200)
    def test_timestamps_are_non_negative_integers(self, sessions: list[dict]):
        """All timestamps in the index are non-negative integers.

        **Validates: Requirements 6.5**
        """
        result = build_sessions_index(sessions)

        for entry in result["sessions"]:
            assert isinstance(entry["createdAt"], int), (
                f"createdAt should be int, got {type(entry['createdAt'])}"
            )
            assert isinstance(entry["lastModified"], int), (
                f"lastModified should be int, got {type(entry['lastModified'])}"
            )
            assert entry["createdAt"] >= 0, (
                f"createdAt should be non-negative, got {entry['createdAt']}"
            )
            assert entry["lastModified"] >= 0, (
                f"lastModified should be non-negative, got {entry['lastModified']}"
            )

    @given(sessions=_sessions_metadata_list_st)
    @settings(max_examples=200)
    def test_index_has_sessions_key(self, sessions: list[dict]):
        """The index output always has a top-level 'sessions' key containing a list.

        **Validates: Requirements 6.5**
        """
        result = build_sessions_index(sessions)

        assert "sessions" in result, "Index missing top-level 'sessions' key"
        assert isinstance(result["sessions"], list), (
            f"'sessions' should be a list, got {type(result['sessions'])}"
        )

    @given(sessions=_sessions_metadata_list_st)
    @settings(max_examples=200)
    def test_no_extra_fields_in_entries(self, sessions: list[dict]):
        """Each index entry contains exactly the three required fields and nothing else.

        **Validates: Requirements 6.5**
        """
        result = build_sessions_index(sessions)

        expected_keys = {"name", "createdAt", "lastModified"}
        for entry in result["sessions"]:
            assert set(entry.keys()) == expected_keys, (
                f"Entry has unexpected keys: {set(entry.keys()) - expected_keys}. "
                f"Entry: {entry}"
            )


# ---------------------------------------------------------------------------
# Pure function reimplementation: build_compact_prompt
# ---------------------------------------------------------------------------


def build_compact_prompt(template: str, focus_instruction: str | None) -> str:
    """Build the summarization prompt for the compact command.

    Mirrors the QML compactChat logic:
        The template is the base summarization prompt. When a non-empty
        focus_instruction is provided, it gets appended after a space
        (stripped of leading/trailing whitespace). When focus_instruction
        is empty or None, the template is used as-is.

    Args:
        template: The base summarization system prompt, e.g.
            "Summarize the following conversation concisely, preserving
            key context, decisions, and any code or technical details."
        focus_instruction: Optional focus string (e.g., "keep the code examples").
            If non-empty after stripping, it is appended to the template.

    Returns:
        The complete prompt string to send to the model.
    """
    if focus_instruction and focus_instruction.strip():
        return template + " " + focus_instruction.strip()
    return template


# ---------------------------------------------------------------------------
# Strategies for compact prompt testing
# ---------------------------------------------------------------------------

# The base summarization template (fixed as per spec)
_COMPACT_TEMPLATE = (
    "Summarize the following conversation concisely, preserving key context, "
    "decisions, and any code or technical details."
)

# Non-empty focus instructions (at least one non-whitespace character)
_nonempty_focus_st = st.text(min_size=1, max_size=300).filter(
    lambda s: s.strip() != ""
)

# Empty/whitespace-only focus instructions
_empty_focus_st = st.one_of(
    st.none(),
    st.just(""),
    st.text(
        alphabet=st.characters(whitelist_categories=("Zs", "Cc")),
        min_size=1,
        max_size=20,
    ).filter(lambda s: s.strip() == ""),
)


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 10: Compact with focus includes
# focus in prompt
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestCompactFocusInclusion:
    """Feature: chat-context-management, Property 10: Compact with focus includes focus in prompt"""

    @given(focus=_nonempty_focus_st)
    @settings(max_examples=200)
    def test_nonempty_focus_appears_in_prompt(self, focus: str):
        """For any non-empty focus instruction, the resulting prompt contains the
        stripped focus instruction.

        **Validates: Requirements 3.2**
        """
        result = build_compact_prompt(_COMPACT_TEMPLATE, focus)

        assert focus.strip() in result, (
            f"Focus instruction '{focus.strip()}' not found in prompt: '{result}'"
        )

    @given(focus=_nonempty_focus_st)
    @settings(max_examples=200)
    def test_prompt_contains_template_and_focus(self, focus: str):
        """For any non-empty focus, the prompt contains both the template and the focus.

        **Validates: Requirements 3.2**
        """
        result = build_compact_prompt(_COMPACT_TEMPLATE, focus)

        assert _COMPACT_TEMPLATE in result, (
            f"Template not found in prompt: '{result}'"
        )
        assert focus.strip() in result, (
            f"Focus '{focus.strip()}' not found in prompt: '{result}'"
        )

    @given(focus=_nonempty_focus_st)
    @settings(max_examples=200)
    def test_focus_appended_after_template(self, focus: str):
        """For any non-empty focus, the focus appears after the template in the prompt.

        **Validates: Requirements 3.2**
        """
        result = build_compact_prompt(_COMPACT_TEMPLATE, focus)

        template_end = result.find(_COMPACT_TEMPLATE) + len(_COMPACT_TEMPLATE)
        # Search for the focus only in the portion after the template
        focus_start = result.find(focus.strip(), template_end)

        assert focus_start >= template_end, (
            f"Focus should appear after template. "
            f"Template ends at {template_end}, focus not found after template"
        )

    @given(focus=_empty_focus_st)
    @settings(max_examples=200)
    def test_empty_focus_returns_template_only(self, focus: str | None):
        """When focus is empty/None/whitespace-only, the prompt is just the template.

        **Validates: Requirements 3.2**
        """
        result = build_compact_prompt(_COMPACT_TEMPLATE, focus)

        assert result == _COMPACT_TEMPLATE, (
            f"Expected just the template for empty focus, got: '{result}'"
        )


# ---------------------------------------------------------------------------
# Pure function reimplementation: apply_compact_success
# ---------------------------------------------------------------------------


def apply_compact_success(messages: list[dict], summary: str) -> list[dict]:
    """Apply a successful compaction to the message history.

    Mirrors the QML logic in compactChat() on success path:
        On success: replace entire message list with a single system-role
        message containing the summary.

    Args:
        messages: The current message list (any length).
        summary: The non-empty summary string returned by the model.

    Returns:
        A new list containing exactly one system-role message with the
        summary as rawContent.
    """
    return [{"role": "system", "rawContent": summary}]


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 11: Successful compact replaces
# history with single summary message
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestSuccessfulCompactReplacesHistory:
    """Feature: chat-context-management, Property 11: Successful compact replaces history with single summary message"""

    @given(
        messages=_messages_st,
        summary=st.text(min_size=1, max_size=1000),
    )
    @settings(max_examples=200)
    def test_result_has_exactly_one_message(
        self, messages: list[dict], summary: str
    ):
        """After successful compact, the result contains exactly one message.

        **Validates: Requirements 3.3**
        """
        result = apply_compact_success(messages, summary)

        assert len(result) == 1, (
            f"Expected exactly 1 message after compact, got {len(result)}. "
            f"Original had {len(messages)} messages."
        )

    @given(
        messages=_messages_st,
        summary=st.text(min_size=1, max_size=1000),
    )
    @settings(max_examples=200)
    def test_result_message_has_system_role(
        self, messages: list[dict], summary: str
    ):
        """After successful compact, the single message has role "system".

        **Validates: Requirements 3.3**
        """
        result = apply_compact_success(messages, summary)

        assert result[0]["role"] == "system", (
            f"Expected role 'system', got '{result[0]['role']}'"
        )

    @given(
        messages=_messages_st,
        summary=st.text(min_size=1, max_size=1000),
    )
    @settings(max_examples=200)
    def test_result_message_rawcontent_equals_summary(
        self, messages: list[dict], summary: str
    ):
        """After successful compact, the message's rawContent equals the summary string.

        **Validates: Requirements 3.3**
        """
        result = apply_compact_success(messages, summary)

        assert result[0]["rawContent"] == summary, (
            f"Expected rawContent to equal summary. "
            f"Got rawContent={result[0]['rawContent']!r:.100}, "
            f"expected summary={summary!r:.100}"
        )

    @given(
        messages=_messages_st,
        summary=st.text(min_size=1, max_size=1000),
    )
    @settings(max_examples=200)
    def test_original_messages_not_in_result(
        self, messages: list[dict], summary: str
    ):
        """After successful compact, the original messages are fully replaced (not retained).

        **Validates: Requirements 3.3**
        """
        result = apply_compact_success(messages, summary)

        # Result should have exactly one message — no trace of original messages
        assert len(result) == 1, (
            f"Result should contain only the summary message, got {len(result)} messages"
        )
        # The single message is the summary, not any original message
        assert result[0] == {"role": "system", "rawContent": summary}, (
            f"The single result message does not match expected compact output. "
            f"Got: {result[0]!r}"
        )


# ---------------------------------------------------------------------------
# Pure function reimplementation: apply_compact_failure
# ---------------------------------------------------------------------------


def apply_compact_failure(messages: list[dict]) -> list[dict]:
    """Simulate compact failure behavior — return messages unchanged.

    Mirrors the QML compactChat() failure path:
        On failure (network error or empty response): preserve original
        messages, show error via interfaceRole message, set compacting = false.

    The core invariant is that on failure, the message list is returned
    as-is (identity). The error notification is a side effect handled
    elsewhere; this function captures only the message preservation logic.

    Args:
        messages: The current message list before compaction was attempted.

    Returns:
        The same message list, unchanged (identity).
    """
    return messages


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 12: Failed compact preserves
# original messages
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestFailedCompactPreservesMessages:
    """Feature: chat-context-management, Property 12: Failed compact preserves original messages"""

    @given(messages=_full_messages_st)
    @settings(max_examples=200)
    def test_failed_compact_returns_identical_messages(
        self, messages: list[dict]
    ):
        """On failure, the message list remains identical to the pre-compaction state.

        For any message history, if compaction fails (network error or empty
        response), the message list SHALL remain identical to the
        pre-compaction state.

        **Validates: Requirements 3.5**
        """
        result = apply_compact_failure(messages)

        assert result == messages, (
            f"Failed compact should preserve messages exactly. "
            f"Original: {len(messages)} messages, Result: {len(result)} messages"
        )

    @given(messages=_full_messages_st)
    @settings(max_examples=200)
    def test_failed_compact_is_identity(self, messages: list[dict]):
        """The failed compact function is the identity function — it returns
        the exact same list object (not just equal content).

        **Validates: Requirements 3.5**
        """
        result = apply_compact_failure(messages)

        assert result is messages, (
            "Failed compact should return the same list object (identity), "
            "not a copy"
        )

    @given(messages=_full_messages_st)
    @settings(max_examples=200)
    def test_failed_compact_preserves_message_count(
        self, messages: list[dict]
    ):
        """The number of messages is unchanged after a failed compact.

        **Validates: Requirements 3.5**
        """
        result = apply_compact_failure(messages)

        assert len(result) == len(messages), (
            f"Message count changed: expected {len(messages)}, got {len(result)}"
        )

    @given(messages=_full_messages_st)
    @settings(max_examples=200)
    def test_failed_compact_preserves_each_message_content(
        self, messages: list[dict]
    ):
        """Every message field is preserved exactly after a failed compact.

        **Validates: Requirements 3.5**
        """
        result = apply_compact_failure(messages)

        for i, (original, preserved) in enumerate(zip(messages, result)):
            for field in original:
                assert original[field] == preserved[field], (
                    f"Message[{i}].{field} was modified during failed compact: "
                    f"original={original[field]!r}, after={preserved[field]!r}"
                )


# ---------------------------------------------------------------------------
# Pure function reimplementation: is_sending_blocked
# ---------------------------------------------------------------------------


def is_sending_blocked(context_tokens: int, context_limit: int) -> bool:
    """Determine whether message sending is blocked due to context being full.

    Mirrors the QML computed property:
        readonly property bool contextFull: contextUsageRatio >= 1.0

    Where contextUsageRatio = contextTokens / contextLimit (when contextLimit > 0).

    The system blocks sending when context_tokens >= context_limit, i.e.
    the conversation has used up the entire available context window.

    Args:
        context_tokens: Current estimated token count of the conversation.
        context_limit: Maximum context window size in tokens for the model.

    Returns:
        True when context_tokens >= context_limit (sending is blocked),
        False when context_tokens < context_limit (sending is allowed).
    """
    return context_tokens >= context_limit


# ---------------------------------------------------------------------------
# Strategies for Property 13
# ---------------------------------------------------------------------------

# Positive context limits (model context windows are always positive)
_context_limit_st = st.integers(min_value=1, max_value=10_000_000)

# Non-negative token counts
_context_tokens_st = st.integers(min_value=0, max_value=10_000_000)


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 13: Context full blocks message
# sending
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestContextFullBlocksSending:
    """Feature: chat-context-management, Property 13: Context full blocks message sending"""

    @given(
        context_tokens=_context_tokens_st,
        context_limit=_context_limit_st,
    )
    @settings(max_examples=200)
    def test_blocked_when_tokens_at_or_above_limit(
        self, context_tokens: int, context_limit: int
    ):
        """For any state where contextTokens >= contextLimit, sending is blocked.

        When context_tokens >= context_limit, is_sending_blocked SHALL return True.
        When context_tokens < context_limit, is_sending_blocked SHALL return False.

        **Validates: Requirements 4.1**
        """
        result = is_sending_blocked(context_tokens, context_limit)

        if context_tokens >= context_limit:
            assert result is True, (
                f"Expected sending to be blocked when tokens ({context_tokens}) "
                f">= limit ({context_limit}), but got {result}"
            )
        else:
            assert result is False, (
                f"Expected sending NOT to be blocked when tokens ({context_tokens}) "
                f"< limit ({context_limit}), but got {result}"
            )

    @given(context_limit=_context_limit_st)
    @settings(max_examples=200)
    def test_exactly_at_limit_is_blocked(self, context_limit: int):
        """When context_tokens equals context_limit exactly, sending is blocked.

        **Validates: Requirements 4.1**
        """
        result = is_sending_blocked(context_limit, context_limit)

        assert result is True, (
            f"Expected sending blocked when tokens == limit ({context_limit}), "
            f"but got {result}"
        )

    @given(
        context_limit=st.integers(min_value=2, max_value=10_000_000),
    )
    @settings(max_examples=200)
    def test_one_below_limit_is_not_blocked(self, context_limit: int):
        """When context_tokens is one less than context_limit, sending is allowed.

        **Validates: Requirements 4.1**
        """
        result = is_sending_blocked(context_limit - 1, context_limit)

        assert result is False, (
            f"Expected sending allowed when tokens ({context_limit - 1}) "
            f"< limit ({context_limit}), but got {result}"
        )

    @given(
        excess=st.integers(min_value=0, max_value=1_000_000),
        context_limit=_context_limit_st,
    )
    @settings(max_examples=200)
    def test_above_limit_always_blocked(self, excess: int, context_limit: int):
        """When context_tokens exceeds context_limit by any amount, sending is blocked.

        **Validates: Requirements 4.1**
        """
        context_tokens = context_limit + excess
        result = is_sending_blocked(context_tokens, context_limit)

        assert result is True, (
            f"Expected sending blocked when tokens ({context_tokens}) "
            f">= limit ({context_limit}), excess={excess}, but got {result}"
        )

    @given(
        context_limit=_context_limit_st,
        tokens_fraction=st.floats(min_value=0.0, max_value=0.99, allow_nan=False),
    )
    @settings(max_examples=200)
    def test_below_limit_never_blocked(
        self, context_limit: int, tokens_fraction: float
    ):
        """When context_tokens is strictly below context_limit, sending is never blocked.

        **Validates: Requirements 4.1**
        """
        context_tokens = int(context_limit * tokens_fraction)
        # Ensure tokens is strictly below limit
        if context_tokens >= context_limit:
            context_tokens = context_limit - 1

        result = is_sending_blocked(context_tokens, context_limit)

        assert result is False, (
            f"Expected sending allowed when tokens ({context_tokens}) "
            f"< limit ({context_limit}), but got {result}"
        )


# ---------------------------------------------------------------------------
# Pure function reimplementation: filter_larger_context_models
# ---------------------------------------------------------------------------


def filter_larger_context_models(models: dict[str, dict], current_limit: int) -> list[str]:
    """Filter models to only those with a larger context window.

    Mirrors the QML AI_Doctor computed property:
        readonly property var largerContextModels: {
            const currentLimit = root.contextLimit;
            return root.modelList.filter(id => {
                const model = root.models[id];
                return model && model.context_length > currentLimit;
            });
        }

    Args:
        models: Dict mapping model IDs to model config dicts.
            Each model dict has at least a "context_length" int field.
        current_limit: The current model's context_length (the threshold).

    Returns:
        List of model IDs where model["context_length"] > current_limit.
    """
    return [
        model_id
        for model_id, config in models.items()
        if config.get("context_length", 0) > current_limit
    ]


# ---------------------------------------------------------------------------
# Strategies for AI_Doctor model filtering
# ---------------------------------------------------------------------------

# Strategy for a model config dict with a context_length field
_model_config_st = st.fixed_dictionaries({
    "context_length": st.integers(min_value=0, max_value=10_000_000),
})

# Strategy for a model ID (non-empty string)
_model_id_st = st.text(
    alphabet=st.characters(
        whitelist_categories=("L", "N", "Pd"),
        whitelist_characters="-_.",
    ),
    min_size=1,
    max_size=50,
)

# Strategy for a dict of models (1 to 20 models with unique IDs)
_models_dict_st = st.dictionaries(
    keys=_model_id_st,
    values=_model_config_st,
    min_size=0,
    max_size=20,
)

# Strategy for the current context limit
_current_limit_st = st.integers(min_value=0, max_value=10_000_000)


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 14: AI_Doctor suggests only
# models with larger context
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestAIDoctorSuggestsLargerContextModels:
    """Feature: chat-context-management, Property 14: AI_Doctor suggests only models with larger context"""

    @given(
        models=_models_dict_st,
        current_limit=_current_limit_st,
    )
    @settings(max_examples=200)
    def test_all_returned_models_have_strictly_greater_context(
        self, models: dict[str, dict], current_limit: int
    ):
        """Every model in the result has context_length strictly greater than current_limit.

        **Validates: Requirements 4.2**
        """
        result = filter_larger_context_models(models, current_limit)

        for model_id in result:
            ctx_len = models[model_id]["context_length"]
            assert ctx_len > current_limit, (
                f"Model '{model_id}' has context_length={ctx_len} which is not "
                f"strictly greater than current_limit={current_limit}"
            )

    @given(
        models=_models_dict_st,
        current_limit=_current_limit_st,
    )
    @settings(max_examples=200)
    def test_no_models_with_leq_context_in_result(
        self, models: dict[str, dict], current_limit: int
    ):
        """No model with context_length <= current_limit appears in the result.

        **Validates: Requirements 4.2**
        """
        result = filter_larger_context_models(models, current_limit)
        result_set = set(result)

        for model_id, config in models.items():
            if config.get("context_length", 0) <= current_limit:
                assert model_id not in result_set, (
                    f"Model '{model_id}' has context_length={config['context_length']} "
                    f"<= current_limit={current_limit} but was included in result"
                )

    @given(
        models=_models_dict_st,
        current_limit=_current_limit_st,
    )
    @settings(max_examples=200)
    def test_result_is_complete(
        self, models: dict[str, dict], current_limit: int
    ):
        """Every model with context_length > current_limit IS included in the result.

        **Validates: Requirements 4.2**
        """
        result = filter_larger_context_models(models, current_limit)
        result_set = set(result)

        for model_id, config in models.items():
            if config.get("context_length", 0) > current_limit:
                assert model_id in result_set, (
                    f"Model '{model_id}' has context_length={config['context_length']} "
                    f"> current_limit={current_limit} but was NOT included in result"
                )

    @given(
        models=_models_dict_st,
        current_limit=_current_limit_st,
    )
    @settings(max_examples=200)
    def test_result_contains_only_valid_model_ids(
        self, models: dict[str, dict], current_limit: int
    ):
        """All returned IDs are keys in the original models dict.

        **Validates: Requirements 4.2**
        """
        result = filter_larger_context_models(models, current_limit)

        for model_id in result:
            assert model_id in models, (
                f"Result contains '{model_id}' which is not in the models dict"
            )

    @given(
        models=_models_dict_st,
        current_limit=st.just(10_000_000),
    )
    @settings(max_examples=200)
    def test_maximum_limit_returns_empty(
        self, models: dict[str, dict], current_limit: int
    ):
        """When current_limit is at maximum, no model can exceed it (result is empty).

        **Validates: Requirements 4.2**
        """
        result = filter_larger_context_models(models, current_limit)

        assert result == [], (
            f"With maximum limit={current_limit}, expected empty result, "
            f"got {result}"
        )


# ---------------------------------------------------------------------------
# Pure function reimplementation: should_show_notification
# ---------------------------------------------------------------------------


def should_show_notification(
    previous_ratio: float, current_ratio: float, dismissed: bool
) -> bool:
    """Determine whether the auto-compact notification should be shown.

    Mirrors the QML logic in Ai.qml:
        The notification triggers when contextUsageRatio crosses the
        Auto_Compact_Threshold (0.85) from below, AND the notification
        has not been dismissed for this session.

    The crossing condition means:
        - previous_ratio < 0.85 (was below threshold)
        - current_ratio >= 0.85 (now at or above threshold)
        - dismissed is False (user hasn't dismissed it)

    After dismissal, crossing does NOT trigger. After compaction brings
    usage below 0.85 and it re-crosses, the notification triggers again
    (dismissed resets when ratio drops below threshold).

    Args:
        previous_ratio: The context usage ratio before the latest change.
        current_ratio: The context usage ratio after the latest change.
        dismissed: Whether the notification was dismissed for this crossing.

    Returns:
        True if the notification should be displayed.
    """
    return previous_ratio < 0.85 and current_ratio >= 0.85 and not dismissed


# ---------------------------------------------------------------------------
# Strategies for Property 15
# ---------------------------------------------------------------------------

# Ratio values: floats in realistic range [0.0, 2.0] (can exceed 1.0)
_ratio_st = st.floats(
    min_value=0.0, max_value=2.0, allow_nan=False, allow_infinity=False
)

# Ratios strictly below 0.85
_below_threshold_st = st.floats(
    min_value=0.0, max_value=0.8499999999,
    allow_nan=False, allow_infinity=False,
)

# Ratios at or above 0.85
_at_or_above_threshold_st = st.floats(
    min_value=0.85, max_value=2.0,
    allow_nan=False, allow_infinity=False,
)


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 15: Auto-compact notification
# triggers on threshold crossing
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestAutoCompactNotificationThreshold:
    """Feature: chat-context-management, Property 15: Auto-compact notification triggers on threshold crossing"""

    @given(
        previous_ratio=_below_threshold_st,
        current_ratio=_at_or_above_threshold_st,
    )
    @settings(max_examples=200)
    def test_crossing_from_below_triggers_notification(
        self, previous_ratio: float, current_ratio: float
    ):
        """When previous_ratio < 0.85 and current_ratio >= 0.85 and not dismissed,
        the notification SHALL trigger.

        **Validates: Requirements 5.1, 5.5**
        """
        result = should_show_notification(previous_ratio, current_ratio, dismissed=False)

        assert result is True, (
            f"Expected notification to trigger when crossing threshold from below: "
            f"previous={previous_ratio}, current={current_ratio}, dismissed=False"
        )

    @given(
        previous_ratio=_below_threshold_st,
        current_ratio=_at_or_above_threshold_st,
    )
    @settings(max_examples=200)
    def test_crossing_while_dismissed_does_not_trigger(
        self, previous_ratio: float, current_ratio: float
    ):
        """After dismissal, crossing the threshold does NOT trigger the notification.

        **Validates: Requirements 5.1, 5.5**
        """
        result = should_show_notification(previous_ratio, current_ratio, dismissed=True)

        assert result is False, (
            f"Expected notification NOT to trigger when dismissed=True: "
            f"previous={previous_ratio}, current={current_ratio}"
        )

    @given(
        previous_ratio=_at_or_above_threshold_st,
        current_ratio=_ratio_st,
        dismissed=st.booleans(),
    )
    @settings(max_examples=200)
    def test_no_crossing_when_already_above_threshold(
        self, previous_ratio: float, current_ratio: float, dismissed: bool
    ):
        """When previous_ratio was already >= 0.85, no crossing occurs so
        notification does not trigger (regardless of current_ratio or dismissed state).

        **Validates: Requirements 5.1, 5.5**
        """
        result = should_show_notification(previous_ratio, current_ratio, dismissed)

        assert result is False, (
            f"Expected no notification when previous already >= 0.85: "
            f"previous={previous_ratio}, current={current_ratio}, dismissed={dismissed}"
        )

    @given(
        previous_ratio=_below_threshold_st,
        current_ratio=_below_threshold_st,
        dismissed=st.booleans(),
    )
    @settings(max_examples=200)
    def test_no_crossing_when_both_below_threshold(
        self, previous_ratio: float, current_ratio: float, dismissed: bool
    ):
        """When both previous and current are below 0.85, no crossing occurs
        and notification does not trigger.

        **Validates: Requirements 5.1, 5.5**
        """
        result = should_show_notification(previous_ratio, current_ratio, dismissed)

        assert result is False, (
            f"Expected no notification when both below threshold: "
            f"previous={previous_ratio}, current={current_ratio}, dismissed={dismissed}"
        )

    @given(
        drop_ratio=_below_threshold_st,
        re_cross_ratio=_at_or_above_threshold_st,
    )
    @settings(max_examples=200)
    def test_re_crossing_after_drop_triggers_again(
        self, drop_ratio: float, re_cross_ratio: float
    ):
        """After usage drops below 0.85 (reset) and re-crosses the threshold,
        the notification triggers again (dismissed resets on drop below threshold).

        This simulates: user compacts → ratio drops below 0.85 → new messages
        push ratio back above 0.85 → notification fires again.

        **Validates: Requirements 5.1, 5.5**
        """
        # After dropping below threshold, dismissed is reset to False
        # Then re-crossing from the drop_ratio (below) to re_cross_ratio (above)
        result = should_show_notification(drop_ratio, re_cross_ratio, dismissed=False)

        assert result is True, (
            f"Expected notification to trigger again after re-crossing: "
            f"drop_ratio={drop_ratio}, re_cross_ratio={re_cross_ratio}, dismissed=False"
        )

    @given(
        previous_ratio=_ratio_st,
        current_ratio=_ratio_st,
        dismissed=st.booleans(),
    )
    @settings(max_examples=200)
    def test_notification_iff_crossing_from_below_and_not_dismissed(
        self, previous_ratio: float, current_ratio: float, dismissed: bool
    ):
        """Universal property: notification triggers if and only if
        previous < 0.85 AND current >= 0.85 AND not dismissed.

        **Validates: Requirements 5.1, 5.5**
        """
        result = should_show_notification(previous_ratio, current_ratio, dismissed)
        expected = (previous_ratio < 0.85 and current_ratio >= 0.85 and not dismissed)

        assert result == expected, (
            f"Notification mismatch: got {result}, expected {expected}. "
            f"previous={previous_ratio}, current={current_ratio}, dismissed={dismissed}"
        )


# ---------------------------------------------------------------------------
# Pure function reimplementation: can_send_message
# ---------------------------------------------------------------------------


def can_send_message(
    context_tokens: int, context_limit: int, notification_visible: bool
) -> bool:
    """Determine whether the user can send a message.

    Mirrors the QML behavior that the auto-compact notification is non-blocking:
        - The notification appears when contextUsageRatio crosses 0.85
        - WHILE the notification is displayed, the system SHALL continue to
          accept and send user messages without interruption (Requirement 5.4)
        - Sending is only blocked when contextUsageRatio >= 1.0 (contextFull)

    The key invariant: notification_visible has NO effect on whether sending
    is allowed. Only the context_tokens vs context_limit comparison matters.

    Args:
        context_tokens: Current estimated token count.
        context_limit: Model's maximum context window in tokens.
        notification_visible: Whether the auto-compact notification is visible.

    Returns:
        True when context_tokens < context_limit (sending allowed),
        False when context_tokens >= context_limit (sending blocked).
        The notification_visible parameter does NOT affect the result.
    """
    return context_tokens < context_limit


# ---------------------------------------------------------------------------
# Strategies for Property 16 (non-blocking notification)
# ---------------------------------------------------------------------------

# Context limits: positive integers representing model context windows
_p16_context_limit_st = st.integers(min_value=100, max_value=10_000_000)

# Ratios in the notification range (0.85 to just below 1.0)
_notification_ratio_st = st.floats(
    min_value=0.85, max_value=0.9999, allow_nan=False, allow_infinity=False
)


# ---------------------------------------------------------------------------
# Feature: chat-context-management, Property 16: Non-blocking notification
# allows continued message sending
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestNonBlockingNotification:
    """Feature: chat-context-management, Property 16: Non-blocking notification allows continued message sending"""

    @given(
        context_limit=_p16_context_limit_st,
        ratio=_notification_ratio_st,
        notification_visible=st.just(True),
    )
    @settings(max_examples=200)
    def test_notification_visible_still_allows_sending(
        self, context_limit: int, ratio: float, notification_visible: bool
    ):
        """While notification is visible and ratio < 1.0, messages can still be sent.

        For any state where the auto-compact notification is visible and
        contextUsageRatio < 1.0, the system SHALL accept and send user
        messages without interruption.

        **Validates: Requirements 5.4**
        """
        context_tokens = int(context_limit * ratio)
        # Ensure tokens stay strictly below limit
        if context_tokens >= context_limit:
            context_tokens = context_limit - 1

        result = can_send_message(context_tokens, context_limit, notification_visible)

        assert result is True, (
            f"Sending should be allowed when notification is visible and "
            f"ratio ({ratio:.4f}) < 1.0. "
            f"context_tokens={context_tokens}, context_limit={context_limit}, "
            f"notification_visible={notification_visible}"
        )

    @given(
        context_limit=_p16_context_limit_st,
        ratio=_notification_ratio_st,
        notification_visible=st.booleans(),
    )
    @settings(max_examples=200)
    def test_notification_visibility_does_not_affect_sending(
        self, context_limit: int, ratio: float, notification_visible: bool
    ):
        """Notification visibility has NO effect on whether sending is allowed.

        The result of can_send_message is identical regardless of whether
        the notification is visible or not, given the same token counts.

        **Validates: Requirements 5.4**
        """
        context_tokens = int(context_limit * ratio)
        if context_tokens >= context_limit:
            context_tokens = context_limit - 1

        result_with_notification = can_send_message(
            context_tokens, context_limit, True
        )
        result_without_notification = can_send_message(
            context_tokens, context_limit, False
        )

        assert result_with_notification == result_without_notification, (
            f"Notification visibility should not affect sending. "
            f"With notification: {result_with_notification}, "
            f"without: {result_without_notification}. "
            f"context_tokens={context_tokens}, context_limit={context_limit}"
        )

    @given(
        context_tokens=st.integers(min_value=0, max_value=10_000_000),
        context_limit=_p16_context_limit_st,
        notification_visible=st.booleans(),
    )
    @settings(max_examples=200)
    def test_sending_depends_only_on_token_comparison(
        self, context_tokens: int, context_limit: int, notification_visible: bool
    ):
        """can_send_message result depends solely on context_tokens < context_limit.

        For any combination of inputs, the result equals (context_tokens < context_limit)
        regardless of notification_visible.

        **Validates: Requirements 5.4**
        """
        result = can_send_message(context_tokens, context_limit, notification_visible)
        expected = context_tokens < context_limit

        assert result == expected, (
            f"Expected can_send_message to equal (tokens < limit) = {expected}, "
            f"got {result}. "
            f"context_tokens={context_tokens}, context_limit={context_limit}, "
            f"notification_visible={notification_visible}"
        )

    @given(
        context_limit=_p16_context_limit_st,
        ratio=st.floats(
            min_value=0.85, max_value=0.99, allow_nan=False, allow_infinity=False
        ),
    )
    @settings(max_examples=200)
    def test_notification_range_always_allows_sending(
        self, context_limit: int, ratio: float
    ):
        """In the entire notification range (0.85 to <1.0), sending is always allowed
        regardless of notification state.

        **Validates: Requirements 5.4**
        """
        context_tokens = int(context_limit * ratio)
        if context_tokens >= context_limit:
            context_tokens = context_limit - 1

        # With notification visible (the scenario from Requirement 5.4)
        assert can_send_message(context_tokens, context_limit, True) is True, (
            f"Sending should be allowed in notification range. "
            f"ratio={ratio:.4f}, tokens={context_tokens}, limit={context_limit}"
        )
