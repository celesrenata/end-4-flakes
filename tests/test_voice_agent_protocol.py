# Feature: streaming-voice-agent, Task 1.2: Protocol event serialization/deserialization
"""Unit tests for the voice agent protocol module.

Tests cover output event constructors, input event parsing,
base64 audio encode/decode helpers, and field validation.

Validates: Requirements 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 12.7
"""

import sys
from pathlib import Path

import pytest

# Add the helper script directory to the path
SCRIPT_DIR = Path(__file__).parent.parent / "configs" / "quickshell" / "ii" / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from voice_agent_backends.protocol import (
    AudioResponseEvent,
    BargeInEvent,
    ErrorEvent,
    FallbackEvent,
    PartialTranscriptEvent,
    ReadyEvent,
    SessionEndEvent,
    StopEvent,
    ToolCallEvent,
    ToolResultEvent,
    TurnCompleteEvent,
    TurnEndEvent,
    decode_audio,
    deserialize_event,
    encode_audio,
    parse_input_event_typed,
    serialize_event,
    validate_input_event,
    validate_output_event,
)


class TestOutputEventConstructors:
    """Test that all 9 output event types serialize correctly."""

    def test_ready_event(self) -> None:
        event = ReadyEvent(backend="nova-sonic", session_id="abc123")
        d = event.to_dict()
        assert d["type"] == "READY"
        assert d["backend"] == "nova-sonic"
        assert d["session_id"] == "abc123"

    def test_ready_event_no_session_id(self) -> None:
        event = ReadyEvent(backend="openai-realtime")
        d = event.to_dict()
        assert d["type"] == "READY"
        assert d["backend"] == "openai-realtime"
        assert "session_id" not in d

    def test_partial_transcript_event(self) -> None:
        event = PartialTranscriptEvent(text="hello world")
        d = event.to_dict()
        assert d["type"] == "PARTIAL_TRANSCRIPT"
        assert d["text"] == "hello world"

    def test_turn_end_event(self) -> None:
        event = TurnEndEvent()
        d = event.to_dict()
        assert d == {"type": "TURN_END"}

    def test_turn_complete_event(self) -> None:
        event = TurnCompleteEvent(text="What's the weather?")
        d = event.to_dict()
        assert d["type"] == "TURN_COMPLETE"
        assert d["text"] == "What's the weather?"

    def test_audio_response_event(self) -> None:
        audio_b64 = encode_audio(b"\x00\x01\x02\x03")
        event = AudioResponseEvent(audio=audio_b64, text="hi there")
        d = event.to_dict()
        assert d["type"] == "AUDIO_RESPONSE"
        assert d["audio"] == audio_b64
        assert d["text"] == "hi there"

    def test_audio_response_event_no_text(self) -> None:
        audio_b64 = encode_audio(b"\x00\x01")
        event = AudioResponseEvent(audio=audio_b64)
        d = event.to_dict()
        assert d["type"] == "AUDIO_RESPONSE"
        assert d["audio"] == audio_b64
        assert "text" not in d

    def test_tool_call_event(self) -> None:
        event = ToolCallEvent(id="tc_1", name="get_time", arguments='{"tz": "UTC"}')
        d = event.to_dict()
        assert d["type"] == "TOOL_CALL"
        assert d["id"] == "tc_1"
        assert d["name"] == "get_time"
        assert d["arguments"] == '{"tz": "UTC"}'

    def test_session_end_event(self) -> None:
        event = SessionEndEvent(reason="timeout")
        d = event.to_dict()
        assert d["type"] == "SESSION_END"
        assert d["reason"] == "timeout"

    def test_session_end_event_default(self) -> None:
        event = SessionEndEvent()
        d = event.to_dict()
        assert d["reason"] == "user_stop"

    def test_error_event(self) -> None:
        event = ErrorEvent(message="Connection lost", fatal=True)
        d = event.to_dict()
        assert d["type"] == "ERROR"
        assert d["message"] == "Connection lost"
        assert d["fatal"] is True

    def test_error_event_non_fatal(self) -> None:
        event = ErrorEvent(message="Retry", fatal=False)
        d = event.to_dict()
        assert d["fatal"] is False

    def test_fallback_event(self) -> None:
        event = FallbackEvent(reason="backend unavailable")
        d = event.to_dict()
        assert d["type"] == "FALLBACK"
        assert d["reason"] == "backend unavailable"


class TestInputEventConstructors:
    """Test input event dataclasses serialize correctly."""

    def test_tool_result_event(self) -> None:
        event = ToolResultEvent(id="tc_1", name="get_time", result="12:00 UTC", is_error=False)
        d = event.to_dict()
        assert d["type"] == "TOOL_RESULT"
        assert d["id"] == "tc_1"
        assert d["name"] == "get_time"
        assert d["result"] == "12:00 UTC"
        assert d["is_error"] is False

    def test_stop_event(self) -> None:
        event = StopEvent()
        d = event.to_dict()
        assert d == {"type": "STOP"}

    def test_barge_in_event(self) -> None:
        event = BargeInEvent()
        d = event.to_dict()
        assert d == {"type": "BARGE_IN"}


class TestBase64AudioHelpers:
    """Test encode/decode round-trip for PCM audio data."""

    def test_round_trip_basic(self) -> None:
        pcm = b"\x00\x01\x02\x03\x04\x05"
        encoded = encode_audio(pcm)
        decoded = decode_audio(encoded)
        assert decoded == pcm

    def test_round_trip_empty(self) -> None:
        pcm = b""
        encoded = encode_audio(pcm)
        decoded = decode_audio(encoded)
        assert decoded == pcm

    def test_round_trip_large(self) -> None:
        # Simulate a chunk of 16kHz mono s16 audio (~128ms)
        pcm = bytes(range(256)) * 16  # 4096 bytes
        encoded = encode_audio(pcm)
        decoded = decode_audio(encoded)
        assert decoded == pcm
        assert len(decoded) == 4096

    def test_encode_produces_ascii(self) -> None:
        pcm = b"\xff\xfe\xfd\xfc"
        encoded = encode_audio(pcm)
        assert encoded.isascii()


class TestOutputEventValidation:
    """Test validate_output_event for each event type."""

    def test_valid_ready(self) -> None:
        assert validate_output_event({"type": "READY", "backend": "nova-sonic"}) is True

    def test_ready_missing_backend(self) -> None:
        assert validate_output_event({"type": "READY"}) is False

    def test_ready_wrong_type(self) -> None:
        assert validate_output_event({"type": "READY", "backend": 123}) is False

    def test_valid_partial_transcript(self) -> None:
        assert validate_output_event({"type": "PARTIAL_TRANSCRIPT", "text": "hi"}) is True

    def test_partial_transcript_missing_text(self) -> None:
        assert validate_output_event({"type": "PARTIAL_TRANSCRIPT"}) is False

    def test_valid_turn_end(self) -> None:
        assert validate_output_event({"type": "TURN_END"}) is True

    def test_valid_turn_complete(self) -> None:
        assert validate_output_event({"type": "TURN_COMPLETE", "text": "done"}) is True

    def test_valid_audio_response(self) -> None:
        assert validate_output_event({"type": "AUDIO_RESPONSE", "audio": "AAEC"}) is True

    def test_audio_response_missing_audio(self) -> None:
        assert validate_output_event({"type": "AUDIO_RESPONSE"}) is False

    def test_valid_tool_call(self) -> None:
        assert validate_output_event({
            "type": "TOOL_CALL", "id": "1", "name": "f", "arguments": "{}"
        }) is True

    def test_tool_call_missing_id(self) -> None:
        assert validate_output_event({
            "type": "TOOL_CALL", "name": "f", "arguments": "{}"
        }) is False

    def test_tool_call_missing_name(self) -> None:
        assert validate_output_event({
            "type": "TOOL_CALL", "id": "1", "arguments": "{}"
        }) is False

    def test_tool_call_missing_arguments(self) -> None:
        assert validate_output_event({
            "type": "TOOL_CALL", "id": "1", "name": "f"
        }) is False

    def test_valid_session_end(self) -> None:
        assert validate_output_event({"type": "SESSION_END", "reason": "done"}) is True

    def test_session_end_missing_reason(self) -> None:
        assert validate_output_event({"type": "SESSION_END"}) is False

    def test_valid_error(self) -> None:
        assert validate_output_event({"type": "ERROR", "message": "oops", "fatal": True}) is True

    def test_error_missing_message(self) -> None:
        assert validate_output_event({"type": "ERROR", "fatal": True}) is False

    def test_error_missing_fatal(self) -> None:
        assert validate_output_event({"type": "ERROR", "message": "oops"}) is False

    def test_error_fatal_wrong_type(self) -> None:
        assert validate_output_event({"type": "ERROR", "message": "oops", "fatal": "yes"}) is False

    def test_valid_fallback(self) -> None:
        assert validate_output_event({"type": "FALLBACK", "reason": "timeout"}) is True

    def test_fallback_missing_reason(self) -> None:
        assert validate_output_event({"type": "FALLBACK"}) is False

    def test_unknown_event_type(self) -> None:
        assert validate_output_event({"type": "UNKNOWN", "data": "x"}) is False

    def test_not_a_dict(self) -> None:
        assert validate_output_event("not a dict") is False  # type: ignore[arg-type]

    def test_missing_type_field(self) -> None:
        assert validate_output_event({"backend": "nova-sonic"}) is False


class TestInputEventValidation:
    """Test validate_input_event for each input event type."""

    def test_valid_tool_result(self) -> None:
        assert validate_input_event({
            "type": "TOOL_RESULT", "id": "1", "name": "f", "result": "ok", "is_error": False
        }) is True

    def test_tool_result_missing_id(self) -> None:
        assert validate_input_event({
            "type": "TOOL_RESULT", "name": "f", "result": "ok", "is_error": False
        }) is False

    def test_tool_result_missing_name(self) -> None:
        assert validate_input_event({
            "type": "TOOL_RESULT", "id": "1", "result": "ok", "is_error": False
        }) is False

    def test_tool_result_missing_result(self) -> None:
        assert validate_input_event({
            "type": "TOOL_RESULT", "id": "1", "name": "f", "is_error": False
        }) is False

    def test_tool_result_missing_is_error(self) -> None:
        assert validate_input_event({
            "type": "TOOL_RESULT", "id": "1", "name": "f", "result": "ok"
        }) is False

    def test_tool_result_wrong_is_error_type(self) -> None:
        assert validate_input_event({
            "type": "TOOL_RESULT", "id": "1", "name": "f", "result": "ok", "is_error": "no"
        }) is False

    def test_valid_stop(self) -> None:
        assert validate_input_event({"type": "STOP"}) is True

    def test_valid_barge_in(self) -> None:
        assert validate_input_event({"type": "BARGE_IN"}) is True

    def test_unknown_input_type(self) -> None:
        assert validate_input_event({"type": "READY"}) is False

    def test_not_a_dict(self) -> None:
        assert validate_input_event([1, 2, 3]) is False  # type: ignore[arg-type]


class TestSerializationDeserialization:
    """Test serialize_event and deserialize_event."""

    def test_serialize_adds_newline(self) -> None:
        line = serialize_event({"type": "TURN_END"})
        assert line.endswith("\n")

    def test_round_trip(self) -> None:
        event = {"type": "READY", "backend": "nova-sonic"}
        line = serialize_event(event)
        parsed = deserialize_event(line)
        assert parsed == event

    def test_deserialize_empty_line(self) -> None:
        assert deserialize_event("") is None
        assert deserialize_event("   \n") is None

    def test_deserialize_invalid_json(self) -> None:
        assert deserialize_event("{not json}") is None

    def test_deserialize_no_type_field(self) -> None:
        assert deserialize_event('{"foo": "bar"}\n') is None


class TestParseInputEventTyped:
    """Test parse_input_event_typed for typed input event parsing."""

    def test_parse_tool_result(self) -> None:
        line = '{"type":"TOOL_RESULT","id":"t1","name":"get_time","result":"12:00","is_error":false}\n'
        event = parse_input_event_typed(line)
        assert isinstance(event, ToolResultEvent)
        assert event.id == "t1"
        assert event.name == "get_time"
        assert event.result == "12:00"
        assert event.is_error is False

    def test_parse_stop(self) -> None:
        line = '{"type":"STOP"}\n'
        event = parse_input_event_typed(line)
        assert isinstance(event, StopEvent)

    def test_parse_barge_in(self) -> None:
        line = '{"type":"BARGE_IN"}\n'
        event = parse_input_event_typed(line)
        assert isinstance(event, BargeInEvent)

    def test_parse_invalid_returns_none(self) -> None:
        assert parse_input_event_typed("") is None
        assert parse_input_event_typed("not json") is None

    def test_parse_output_event_returns_none(self) -> None:
        # Output events should not parse as input events
        line = '{"type":"READY","backend":"nova-sonic"}\n'
        assert parse_input_event_typed(line) is None
