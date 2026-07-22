"""Tool call pairing logic and session context management.

Provides ToolCallManager for tracking pending tool calls (enforcing the
single-pending-call invariant) and load_session_context() for reading and
validating session context JSON files.

Used by voice-agent-stream.py's main loop to coordinate tool call/result
pairing across backends and pause/resume audio forwarding during tool
execution.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Errors
# ---------------------------------------------------------------------------


class ToolCallError(Exception):
    """Raised when a tool call invariant is violated."""


class ConcurrentToolCallError(ToolCallError):
    """Raised when a new TOOL_CALL arrives while one is already pending."""


class ToolResultMismatchError(ToolCallError):
    """Raised when a TOOL_RESULT ID does not match the pending call."""


class NoToolCallPendingError(ToolCallError):
    """Raised when a TOOL_RESULT arrives with no pending tool call."""


# ---------------------------------------------------------------------------
# ToolCallManager
# ---------------------------------------------------------------------------


class ToolCallManager:
    """Tracks pending tool calls and enforces the single-pending-call invariant.

    The streaming voice protocol requires that at most one tool call is
    pending at any time. When a TOOL_CALL event is emitted by the backend:
      1. The pending call ID is recorded
      2. Audio forwarding should be paused (signalled via `audio_paused`)
      3. No new TOOL_CALL may be accepted until a matching TOOL_RESULT arrives

    When a TOOL_RESULT with a matching ID arrives:
      1. The pending state is cleared
      2. Audio forwarding can resume

    Requirements: 8.3, 8.4, 12.3, 12.4
    """

    def __init__(self) -> None:
        self._pending_tool_call_id: str | None = None
        self._pending_tool_name: str | None = None
        self._audio_paused: bool = False

    @property
    def audio_paused(self) -> bool:
        """Whether audio forwarding should be paused (tool call in progress)."""
        return self._audio_paused

    @property
    def pending_call_id(self) -> str | None:
        """The ID of the currently pending tool call, or None."""
        return self._pending_tool_call_id

    @property
    def pending_tool_name(self) -> str | None:
        """The name of the currently pending tool, or None."""
        return self._pending_tool_name

    @property
    def has_pending_call(self) -> bool:
        """Whether there is a tool call currently awaiting a result."""
        return self._pending_tool_call_id is not None

    def on_tool_call(self, call_id: str, name: str) -> None:
        """Record a new pending tool call. Pauses audio forwarding.

        Args:
            call_id: Unique tool call ID from the backend.
            name: Tool name being invoked.

        Raises:
            ConcurrentToolCallError: If a tool call is already pending.
        """
        if self._pending_tool_call_id is not None:
            raise ConcurrentToolCallError(
                f"New TOOL_CALL '{call_id}' ({name}) received while "
                f"'{self._pending_tool_call_id}' ({self._pending_tool_name}) "
                f"is still pending"
            )

        self._pending_tool_call_id = call_id
        self._pending_tool_name = name
        self._audio_paused = True

    def on_tool_result(self, call_id: str) -> None:
        """Process a tool result, clearing the pending state and resuming audio.

        Args:
            call_id: Tool call ID from the TOOL_RESULT event.

        Raises:
            NoToolCallPendingError: If no tool call is currently pending.
            ToolResultMismatchError: If the result ID doesn't match the pending call.
        """
        if self._pending_tool_call_id is None:
            raise NoToolCallPendingError(
                f"TOOL_RESULT '{call_id}' received but no tool call is pending"
            )

        if call_id != self._pending_tool_call_id:
            raise ToolResultMismatchError(
                f"TOOL_RESULT ID '{call_id}' does not match pending "
                f"call ID '{self._pending_tool_call_id}'"
            )

        self._pending_tool_call_id = None
        self._pending_tool_name = None
        self._audio_paused = False

    def reset(self) -> None:
        """Reset all state (used during shutdown or error recovery)."""
        self._pending_tool_call_id = None
        self._pending_tool_name = None
        self._audio_paused = False


# ---------------------------------------------------------------------------
# Session context loading
# ---------------------------------------------------------------------------


def load_session_context(path: str) -> list[dict[str, Any]]:
    """Load and validate session context from a JSON file.

    The context file should contain a JSON array of message objects, each
    with at minimum "role" and "content" string fields. Additional fields
    are preserved but not required.

    Args:
        path: File system path to the session context JSON file.

    Returns:
        List of message dicts with "role" and "content" fields.

    Raises:
        FileNotFoundError: If the file does not exist.
        ValueError: If the file is not valid JSON or has incorrect structure.

    Requirements: 9.2, 9.3
    """
    context_path = Path(path)

    if not context_path.exists():
        raise FileNotFoundError(f"Session context file not found: {path}")

    try:
        content = context_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise FileNotFoundError(f"Cannot read session context file: {exc}") from exc

    try:
        data = json.loads(content)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Session context file is not valid JSON: {exc}") from exc

    if not isinstance(data, list):
        raise ValueError(
            f"Session context must be a JSON array, got {type(data).__name__}"
        )

    # Validate each message has role and content
    messages: list[dict[str, Any]] = []
    for i, item in enumerate(data):
        if not isinstance(item, dict):
            raise ValueError(
                f"Session context message at index {i} must be an object, "
                f"got {type(item).__name__}"
            )
        if "role" not in item:
            raise ValueError(
                f"Session context message at index {i} missing 'role' field"
            )
        if "content" not in item:
            raise ValueError(
                f"Session context message at index {i} missing 'content' field"
            )
        messages.append(item)

    return messages


def format_context_for_prompt(messages: list[dict[str, Any]]) -> str:
    """Format loaded session context messages for system prompt injection.

    Produces a human-readable block suitable for appending to the system
    prompt text for both Nova Sonic and OpenAI Realtime backends.

    Args:
        messages: List of message dicts (as returned by load_session_context).

    Returns:
        Formatted string, or empty string if messages is empty.
    """
    if not messages:
        return ""

    lines: list[str] = []
    for msg in messages:
        role = msg.get("role", "unknown")
        content = msg.get("content", "")
        lines.append(f"{role}: {content}")

    return "\n".join(lines)


def load_and_format_context(path: str) -> str:
    """Load context from file and format for prompt injection.

    Convenience function combining load_session_context and
    format_context_for_prompt. Returns empty string on any error
    (logs warning to stderr).

    Args:
        path: File system path to the session context JSON file.

    Returns:
        Formatted context string, or empty string on error.
    """
    if not path:
        return ""

    try:
        messages = load_session_context(path)
        return format_context_for_prompt(messages)
    except (FileNotFoundError, ValueError) as exc:
        print(f"[tool-manager] Context load failed: {exc}", file=sys.stderr)
        return ""
