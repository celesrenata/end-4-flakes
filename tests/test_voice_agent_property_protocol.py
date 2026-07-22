# Feature: streaming-voice-agent, Property 1: Protocol round-trip integrity
"""Property-based tests for voice agent protocol round-trip integrity.

Generates random valid events across all 9 output event types, serializes
to JSON line via serialize_event, deserializes back via deserialize_event,
and verifies that the parsed result has a valid type and passes field validation.

**Validates: Requirements 12.1, 12.2, 12.5, 12.6, 12.7**
"""

import sys
from pathlib import Path

from hypothesis import given, settings
from hypothesis import strategies as st

# Add the helper script directory to the path
SCRIPT_DIR = Path(__file__).parent.parent / "configs" / "quickshell" / "ii" / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from voice_agent_backends.protocol import (
    AudioResponseEvent,
    ErrorEvent,
    FallbackEvent,
    OUTPUT_EVENT_TYPES,
    PartialTranscriptEvent,
    ReadyEvent,
    SessionEndEvent,
    ToolCallEvent,
    TurnCompleteEvent,
    TurnEndEvent,
    decode_audio,
    deserialize_event,
    encode_audio,
    serialize_event,
    validate_output_event,
)


# ---------------------------------------------------------------------------
# Strategies for generating random valid output events
# ---------------------------------------------------------------------------

# Text strategy: printable strings (avoid null bytes which break JSON)
_text_st = st.text(min_size=0, max_size=200, alphabet=st.characters(
    blacklist_categories=("Cs",),  # exclude surrogates
))

# Non-empty text for required fields
_nonempty_text_st = st.text(min_size=1, max_size=200, alphabet=st.characters(
    blacklist_categories=("Cs",),
))

# Binary data for audio (even length for 16-bit PCM alignment)
_pcm_bytes_st = st.binary(min_size=0, max_size=512).map(
    lambda b: b if len(b) % 2 == 0 else b[:-1]
)


@st.composite
def ready_events(draw: st.DrawFn) -> ReadyEvent:
    """Generate a random ReadyEvent."""
    backend = draw(_nonempty_text_st)
    session_id = draw(_text_st)
    return ReadyEvent(backend=backend, session_id=session_id)


@st.composite
def partial_transcript_events(draw: st.DrawFn) -> PartialTranscriptEvent:
    """Generate a random PartialTranscriptEvent."""
    text = draw(_nonempty_text_st)
    return PartialTranscriptEvent(text=text)


def turn_end_events() -> st.SearchStrategy[TurnEndEvent]:
    """Generate a TurnEndEvent (no fields)."""
    return st.just(TurnEndEvent())


@st.composite
def turn_complete_events(draw: st.DrawFn) -> TurnCompleteEvent:
    """Generate a random TurnCompleteEvent."""
    text = draw(_nonempty_text_st)
    return TurnCompleteEvent(text=text)


@st.composite
def audio_response_events(draw: st.DrawFn) -> AudioResponseEvent:
    """Generate a random AudioResponseEvent with valid base64 audio."""
    pcm = draw(_pcm_bytes_st)
    audio_b64 = encode_audio(pcm)
    text = draw(_text_st)
    return AudioResponseEvent(audio=audio_b64, text=text)


@st.composite
def tool_call_events(draw: st.DrawFn) -> ToolCallEvent:
    """Generate a random ToolCallEvent."""
    call_id = draw(_nonempty_text_st)
    name = draw(_nonempty_text_st)
    arguments = draw(_nonempty_text_st)
    return ToolCallEvent(id=call_id, name=name, arguments=arguments)


@st.composite
def session_end_events(draw: st.DrawFn) -> SessionEndEvent:
    """Generate a random SessionEndEvent."""
    reason = draw(_nonempty_text_st)
    return SessionEndEvent(reason=reason)


@st.composite
def error_events(draw: st.DrawFn) -> ErrorEvent:
    """Generate a random ErrorEvent."""
    message = draw(_nonempty_text_st)
    fatal = draw(st.booleans())
    return ErrorEvent(message=message, fatal=fatal)


@st.composite
def fallback_events(draw: st.DrawFn) -> FallbackEvent:
    """Generate a random FallbackEvent."""
    reason = draw(_nonempty_text_st)
    return FallbackEvent(reason=reason)


# Combined strategy for any valid output event
any_output_event = st.one_of(
    ready_events(),
    partial_transcript_events(),
    turn_end_events(),
    turn_complete_events(),
    audio_response_events(),
    tool_call_events(),
    session_end_events(),
    error_events(),
    fallback_events(),
)


# ---------------------------------------------------------------------------
# Property test: round-trip integrity
# ---------------------------------------------------------------------------


@settings(max_examples=100)
@given(event=any_output_event)
def test_protocol_round_trip_integrity(event) -> None:
    """Any valid output event survives serialize → deserialize round-trip.

    Asserts:
    1. serialize_event produces a newline-terminated JSON string
    2. deserialize_event recovers a dict with a valid "type" field
    3. The deserialized event passes validate_output_event
    4. For AUDIO_RESPONSE events, decode_audio produces valid bytes
    """
    # Serialize via to_dict → serialize_event
    event_dict = event.to_dict()
    line = serialize_event(event_dict)

    # Line must end with newline (Requirement 12.1)
    assert line.endswith("\n"), "Serialized event must end with newline"

    # Deserialize back
    parsed = deserialize_event(line)
    assert parsed is not None, f"deserialize_event returned None for: {line!r}"

    # Type must be a valid output event type (Requirement 12.2)
    assert parsed["type"] in OUTPUT_EVENT_TYPES, (
        f"Parsed type {parsed['type']!r} not in OUTPUT_EVENT_TYPES"
    )

    # Must pass field validation (Requirements 12.5, 12.6, 12.7)
    assert validate_output_event(parsed), (
        f"validate_output_event failed for: {parsed}"
    )

    # For AUDIO_RESPONSE: verify decode_audio produces valid bytes (Req 12.5)
    if parsed["type"] == "AUDIO_RESPONSE":
        audio_bytes = decode_audio(parsed["audio"])
        assert isinstance(audio_bytes, bytes), "decode_audio must return bytes"
