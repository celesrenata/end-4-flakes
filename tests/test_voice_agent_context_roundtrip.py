# Feature: streaming-voice-agent, Property 8: Session context serialization round-trip
"""Property-based tests for session context serialization round-trip.

Generates random message histories (role + content), serializes to JSON,
parses back via load_session_context, and verifies that message order and
field equality are preserved.

**Validates: Requirements 9.1, 9.2, 9.3**
"""

import json
import sys
from pathlib import Path

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

# Add the helper script directory to the path
SCRIPT_DIR = Path(__file__).parent.parent / "configs" / "quickshell" / "ii" / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from voice_agent_backends.tool_manager import load_session_context


# ---------------------------------------------------------------------------
# Strategies for generating random session context messages
# ---------------------------------------------------------------------------

# Roles that appear in typical chat sessions
_roles_st = st.sampled_from(["user", "assistant", "system"])

# Content text: printable strings, avoiding surrogates (break JSON round-trip)
_content_st = st.text(
    min_size=0,
    max_size=500,
    alphabet=st.characters(blacklist_categories=("Cs",)),
)

# A single message with role and content
_message_st = st.fixed_dictionaries({
    "role": _roles_st,
    "content": _content_st,
})

# A message with optional extra fields (timestamps, IDs, metadata)
_message_with_extras_st = st.fixed_dictionaries(
    {"role": _roles_st, "content": _content_st},
    optional={
        "timestamp": st.integers(min_value=0, max_value=2**53),
        "id": st.text(min_size=1, max_size=50, alphabet=st.characters(
            whitelist_categories=("L", "N"),
        )),
    },
)

# A message history: list of 0-20 messages
_message_history_st = st.lists(_message_st, min_size=0, max_size=20)

# A message history with extra fields
_message_history_with_extras_st = st.lists(
    _message_with_extras_st, min_size=0, max_size=20
)


# ---------------------------------------------------------------------------
# Property test: session context serialization round-trip
# ---------------------------------------------------------------------------


@pytest.mark.property_test
@settings(max_examples=100)
@given(messages=_message_history_st)
def test_session_context_roundtrip_preserves_order_and_fields(
    messages: list[dict], tmp_path_factory
) -> None:
    """Message histories survive serialize-to-JSON → load_session_context round-trip.

    **Validates: Requirements 9.1, 9.2, 9.3**

    Asserts:
    1. Serializing messages to JSON and loading them back produces identical output
    2. Message order is preserved exactly
    3. All role and content fields match
    """
    # Use a unique temp file per hypothesis example
    tmp_dir = tmp_path_factory.mktemp("ctx")
    context_file = tmp_dir / "session_context.json"

    # Serialize: write message history as JSON array
    serialized = json.dumps(messages, ensure_ascii=False)
    context_file.write_text(serialized, encoding="utf-8")

    # Deserialize: load back via load_session_context
    loaded = load_session_context(str(context_file))

    # Verify count matches
    assert len(loaded) == len(messages), (
        f"Expected {len(messages)} messages, got {len(loaded)}"
    )

    # Verify order and field equality
    for i, (original, recovered) in enumerate(zip(messages, loaded)):
        assert recovered["role"] == original["role"], (
            f"Message {i}: role mismatch: "
            f"{recovered['role']!r} != {original['role']!r}"
        )
        assert recovered["content"] == original["content"], (
            f"Message {i}: content mismatch: "
            f"{recovered['content']!r} != {original['content']!r}"
        )


@pytest.mark.property_test
@settings(max_examples=100)
@given(messages=_message_history_with_extras_st)
def test_session_context_roundtrip_preserves_extra_fields(
    messages: list[dict], tmp_path_factory
) -> None:
    """Extra fields (timestamp, id) survive the serialization round-trip.

    **Validates: Requirements 9.1, 9.2, 9.3**

    Asserts:
    1. Additional fields beyond role/content are preserved through round-trip
    2. The complete dict equality holds for each message
    """
    tmp_dir = tmp_path_factory.mktemp("ctx")
    context_file = tmp_dir / "session_context.json"

    serialized = json.dumps(messages, ensure_ascii=False)
    context_file.write_text(serialized, encoding="utf-8")

    loaded = load_session_context(str(context_file))

    assert len(loaded) == len(messages)

    for i, (original, recovered) in enumerate(zip(messages, loaded)):
        assert recovered == original, (
            f"Message {i} mismatch:\n"
            f"  original:  {original!r}\n"
            f"  recovered: {recovered!r}"
        )
