"""Protocol event serialization, deserialization, and validation helpers.

Defines typed constructors for all output/input events in the voice agent
JSON-line protocol, plus base64 encode/decode helpers for PCM audio data
and field validation per event type.

Output Events (helper → QML):
    READY, PARTIAL_TRANSCRIPT, TURN_END, TURN_COMPLETE, AUDIO_RESPONSE,
    TOOL_CALL, SESSION_END, ERROR, FALLBACK

Input Events (QML → helper):
    TOOL_RESULT, STOP, BARGE_IN
"""

from __future__ import annotations

import base64
import json
from dataclasses import dataclass, field
from typing import Any


# ---------------------------------------------------------------------------
# Output event type constants
# ---------------------------------------------------------------------------

OUTPUT_EVENT_TYPES = frozenset({
    "READY",
    "PARTIAL_TRANSCRIPT",
    "TURN_END",
    "TURN_COMPLETE",
    "AUDIO_RESPONSE",
    "TOOL_CALL",
    "SESSION_END",
    "ERROR",
    "FALLBACK",
})

INPUT_EVENT_TYPES = frozenset({
    "TOOL_RESULT",
    "STOP",
    "BARGE_IN",
})


# ---------------------------------------------------------------------------
# Required fields per event type (excludes "type" which is always required)
# ---------------------------------------------------------------------------

_OUTPUT_REQUIRED_FIELDS: dict[str, dict[str, type]] = {
    "READY": {"backend": str},
    "PARTIAL_TRANSCRIPT": {"text": str},
    "TURN_END": {},
    "TURN_COMPLETE": {"text": str},
    "AUDIO_RESPONSE": {"audio": str},
    "TOOL_CALL": {"id": str, "name": str, "arguments": str},
    "SESSION_END": {"reason": str},
    "ERROR": {"message": str, "fatal": bool},
    "FALLBACK": {"reason": str},
}

_INPUT_REQUIRED_FIELDS: dict[str, dict[str, type]] = {
    "TOOL_RESULT": {"id": str, "name": str, "result": str, "is_error": bool},
    "STOP": {},
    "BARGE_IN": {},
}


# ---------------------------------------------------------------------------
# Output event constructors (typed dataclasses)
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class ReadyEvent:
    """READY — Backend connection established."""

    backend: str
    session_id: str = ""

    def to_dict(self) -> dict[str, Any]:
        """Serialize to protocol dict."""
        d: dict[str, Any] = {"type": "READY", "backend": self.backend}
        if self.session_id:
            d["session_id"] = self.session_id
        return d


@dataclass(frozen=True, slots=True)
class PartialTranscriptEvent:
    """PARTIAL_TRANSCRIPT — Intermediate speech recognition text."""

    text: str

    def to_dict(self) -> dict[str, Any]:
        """Serialize to protocol dict."""
        return {"type": "PARTIAL_TRANSCRIPT", "text": self.text}


@dataclass(frozen=True, slots=True)
class TurnEndEvent:
    """TURN_END — Backend detected end of user speech."""

    def to_dict(self) -> dict[str, Any]:
        """Serialize to protocol dict."""
        return {"type": "TURN_END"}


@dataclass(frozen=True, slots=True)
class TurnCompleteEvent:
    """TURN_COMPLETE — Finalized user utterance."""

    text: str

    def to_dict(self) -> dict[str, Any]:
        """Serialize to protocol dict."""
        return {"type": "TURN_COMPLETE", "text": self.text}


@dataclass(frozen=True, slots=True)
class AudioResponseEvent:
    """AUDIO_RESPONSE — Base64-encoded PCM audio from backend."""

    audio: str
    text: str = ""

    def to_dict(self) -> dict[str, Any]:
        """Serialize to protocol dict."""
        d: dict[str, Any] = {"type": "AUDIO_RESPONSE", "audio": self.audio}
        if self.text:
            d["text"] = self.text
        return d


@dataclass(frozen=True, slots=True)
class ToolCallEvent:
    """TOOL_CALL — Backend requests tool execution."""

    id: str
    name: str
    arguments: str

    def to_dict(self) -> dict[str, Any]:
        """Serialize to protocol dict."""
        return {
            "type": "TOOL_CALL",
            "id": self.id,
            "name": self.name,
            "arguments": self.arguments,
        }


@dataclass(frozen=True, slots=True)
class SessionEndEvent:
    """SESSION_END — Session ended normally."""

    reason: str = "user_stop"

    def to_dict(self) -> dict[str, Any]:
        """Serialize to protocol dict."""
        return {"type": "SESSION_END", "reason": self.reason}


@dataclass(frozen=True, slots=True)
class ErrorEvent:
    """ERROR — Error occurred."""

    message: str
    fatal: bool = False

    def to_dict(self) -> dict[str, Any]:
        """Serialize to protocol dict."""
        return {"type": "ERROR", "message": self.message, "fatal": self.fatal}


@dataclass(frozen=True, slots=True)
class FallbackEvent:
    """FALLBACK — Cannot maintain stream, fall back to batch."""

    reason: str

    def to_dict(self) -> dict[str, Any]:
        """Serialize to protocol dict."""
        return {"type": "FALLBACK", "reason": self.reason}


# ---------------------------------------------------------------------------
# Input event dataclasses
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class ToolResultEvent:
    """TOOL_RESULT — Tool execution result from QML."""

    id: str
    name: str
    result: str
    is_error: bool = False

    def to_dict(self) -> dict[str, Any]:
        """Serialize to protocol dict."""
        return {
            "type": "TOOL_RESULT",
            "id": self.id,
            "name": self.name,
            "result": self.result,
            "is_error": self.is_error,
        }


@dataclass(frozen=True, slots=True)
class StopEvent:
    """STOP — User requested session end."""

    def to_dict(self) -> dict[str, Any]:
        """Serialize to protocol dict."""
        return {"type": "STOP"}


@dataclass(frozen=True, slots=True)
class BargeInEvent:
    """BARGE_IN — User interrupted playback."""

    def to_dict(self) -> dict[str, Any]:
        """Serialize to protocol dict."""
        return {"type": "BARGE_IN"}


# ---------------------------------------------------------------------------
# Factory: create output event from dict
# ---------------------------------------------------------------------------

_OUTPUT_EVENT_CLASSES: dict[str, type] = {
    "READY": ReadyEvent,
    "PARTIAL_TRANSCRIPT": PartialTranscriptEvent,
    "TURN_END": TurnEndEvent,
    "TURN_COMPLETE": TurnCompleteEvent,
    "AUDIO_RESPONSE": AudioResponseEvent,
    "TOOL_CALL": ToolCallEvent,
    "SESSION_END": SessionEndEvent,
    "ERROR": ErrorEvent,
    "FALLBACK": FallbackEvent,
}

_INPUT_EVENT_CLASSES: dict[str, type] = {
    "TOOL_RESULT": ToolResultEvent,
    "STOP": StopEvent,
    "BARGE_IN": BargeInEvent,
}


# ---------------------------------------------------------------------------
# Base64 audio encode/decode helpers
# ---------------------------------------------------------------------------


def encode_audio(pcm_bytes: bytes) -> str:
    """Base64-encode raw PCM audio bytes for AUDIO_RESPONSE events.

    Args:
        pcm_bytes: Raw PCM audio (16-bit signed, mono).

    Returns:
        Base64-encoded string suitable for the "audio" field.
    """
    return base64.b64encode(pcm_bytes).decode("ascii")


def decode_audio(b64_str: str) -> bytes:
    """Decode base64-encoded PCM audio back to raw bytes.

    Args:
        b64_str: Base64-encoded audio string from an AUDIO_RESPONSE event.

    Returns:
        Raw PCM bytes.
    """
    return base64.b64decode(b64_str)


# ---------------------------------------------------------------------------
# Event validation
# ---------------------------------------------------------------------------


def validate_output_event(event: dict[str, Any]) -> bool:
    """Validate that an output event dict has all required fields with correct types.

    Args:
        event: A dict representing a serialized output event.

    Returns:
        True if the event is valid (has "type" in OUTPUT_EVENT_TYPES and all
        required fields with correct types), False otherwise.
    """
    if not isinstance(event, dict):
        return False

    event_type = event.get("type")
    if event_type not in OUTPUT_EVENT_TYPES:
        return False

    required = _OUTPUT_REQUIRED_FIELDS[event_type]
    for field_name, field_type in required.items():
        if field_name not in event:
            return False
        if not isinstance(event[field_name], field_type):
            return False

    return True


def validate_input_event(event: dict[str, Any]) -> bool:
    """Validate that an input event dict has all required fields with correct types.

    Args:
        event: A dict representing a serialized input event.

    Returns:
        True if the event is valid (has "type" in INPUT_EVENT_TYPES and all
        required fields with correct types), False otherwise.
    """
    if not isinstance(event, dict):
        return False

    event_type = event.get("type")
    if event_type not in INPUT_EVENT_TYPES:
        return False

    required = _INPUT_REQUIRED_FIELDS[event_type]
    for field_name, field_type in required.items():
        if field_name not in event:
            return False
        if not isinstance(event[field_name], field_type):
            return False

    return True


# ---------------------------------------------------------------------------
# Serialization / deserialization helpers
# ---------------------------------------------------------------------------


def serialize_event(event: dict[str, Any]) -> str:
    """Serialize an event dict to a JSON line (with trailing newline).

    Args:
        event: A protocol event dict (must have "type" field).

    Returns:
        JSON string terminated by newline.
    """
    return json.dumps(event, separators=(",", ":")) + "\n"


def deserialize_event(line: str) -> dict[str, Any] | None:
    """Deserialize a JSON line into an event dict.

    Args:
        line: A single line of text (may include trailing newline).

    Returns:
        Parsed dict if valid JSON with a "type" field, None otherwise.
    """
    line = line.strip()
    if not line:
        return None
    try:
        data = json.loads(line)
        if isinstance(data, dict) and "type" in data:
            return data  # type: ignore[return-value]
        return None
    except (json.JSONDecodeError, ValueError):
        return None


def parse_input_event_typed(line: str) -> ToolResultEvent | StopEvent | BargeInEvent | None:
    """Parse a JSON line into a typed input event dataclass.

    Args:
        line: A single JSON line from stdin.

    Returns:
        A typed input event instance, or None if invalid.
    """
    data = deserialize_event(line)
    if data is None:
        return None

    if not validate_input_event(data):
        return None

    event_type = data["type"]

    if event_type == "TOOL_RESULT":
        return ToolResultEvent(
            id=data["id"],
            name=data["name"],
            result=data["result"],
            is_error=data.get("is_error", False),
        )
    elif event_type == "STOP":
        return StopEvent()
    elif event_type == "BARGE_IN":
        return BargeInEvent()

    return None
