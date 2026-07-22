# Feature: streaming-voice-agent, Task 4.1: Tool call pairing logic and session context loading
"""Unit tests for the ToolCallManager and session context loading.

Tests cover:
- Single pending call invariant enforcement
- Audio pause/resume on TOOL_CALL/TOOL_RESULT transitions
- Tool result ID validation
- Session context file loading and validation
- Context formatting for system prompt injection
- Graceful reset behavior

Validates: Requirements 8.3, 8.4, 9.2, 9.3, 12.3, 12.4
"""

import json
import sys
import tempfile
from pathlib import Path

import pytest

# Add the helper script directory to the path
SCRIPT_DIR = Path(__file__).parent.parent / "configs" / "quickshell" / "ii" / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from voice_agent_backends.tool_manager import (
    ConcurrentToolCallError,
    NoToolCallPendingError,
    ToolCallManager,
    ToolResultMismatchError,
    format_context_for_prompt,
    load_and_format_context,
    load_session_context,
)


# ---------------------------------------------------------------------------
# ToolCallManager tests
# ---------------------------------------------------------------------------


class TestToolCallManagerInitialState:
    """Tests for ToolCallManager initial state."""

    def test_initial_state_no_pending_call(self) -> None:
        mgr = ToolCallManager()
        assert mgr.has_pending_call is False
        assert mgr.pending_call_id is None
        assert mgr.pending_tool_name is None

    def test_initial_state_audio_not_paused(self) -> None:
        mgr = ToolCallManager()
        assert mgr.audio_paused is False


class TestToolCallManagerOnToolCall:
    """Tests for on_tool_call behavior."""

    def test_tool_call_sets_pending(self) -> None:
        mgr = ToolCallManager()
        mgr.on_tool_call("call_1", "system_info")
        assert mgr.has_pending_call is True
        assert mgr.pending_call_id == "call_1"
        assert mgr.pending_tool_name == "system_info"

    def test_tool_call_pauses_audio(self) -> None:
        mgr = ToolCallManager()
        mgr.on_tool_call("call_1", "system_info")
        assert mgr.audio_paused is True

    def test_concurrent_tool_call_raises(self) -> None:
        mgr = ToolCallManager()
        mgr.on_tool_call("call_1", "system_info")
        with pytest.raises(ConcurrentToolCallError):
            mgr.on_tool_call("call_2", "shell_exec")

    def test_concurrent_error_message_includes_ids(self) -> None:
        mgr = ToolCallManager()
        mgr.on_tool_call("call_1", "system_info")
        with pytest.raises(ConcurrentToolCallError, match="call_1"):
            mgr.on_tool_call("call_2", "shell_exec")


class TestToolCallManagerOnToolResult:
    """Tests for on_tool_result behavior."""

    def test_matching_result_clears_pending(self) -> None:
        mgr = ToolCallManager()
        mgr.on_tool_call("call_1", "system_info")
        mgr.on_tool_result("call_1")
        assert mgr.has_pending_call is False
        assert mgr.pending_call_id is None
        assert mgr.pending_tool_name is None

    def test_matching_result_resumes_audio(self) -> None:
        mgr = ToolCallManager()
        mgr.on_tool_call("call_1", "system_info")
        assert mgr.audio_paused is True
        mgr.on_tool_result("call_1")
        assert mgr.audio_paused is False

    def test_result_without_pending_raises(self) -> None:
        mgr = ToolCallManager()
        with pytest.raises(NoToolCallPendingError):
            mgr.on_tool_result("call_1")

    def test_mismatched_result_id_raises(self) -> None:
        mgr = ToolCallManager()
        mgr.on_tool_call("call_1", "system_info")
        with pytest.raises(ToolResultMismatchError, match="call_2"):
            mgr.on_tool_result("call_2")

    def test_after_result_new_call_allowed(self) -> None:
        mgr = ToolCallManager()
        mgr.on_tool_call("call_1", "system_info")
        mgr.on_tool_result("call_1")
        # Should not raise
        mgr.on_tool_call("call_2", "shell_exec")
        assert mgr.pending_call_id == "call_2"


class TestToolCallManagerReset:
    """Tests for reset behavior."""

    def test_reset_clears_pending(self) -> None:
        mgr = ToolCallManager()
        mgr.on_tool_call("call_1", "system_info")
        mgr.reset()
        assert mgr.has_pending_call is False
        assert mgr.audio_paused is False

    def test_reset_allows_new_calls(self) -> None:
        mgr = ToolCallManager()
        mgr.on_tool_call("call_1", "system_info")
        mgr.reset()
        # Should not raise
        mgr.on_tool_call("call_2", "shell_exec")
        assert mgr.pending_call_id == "call_2"


# ---------------------------------------------------------------------------
# Session context loading tests
# ---------------------------------------------------------------------------


class TestLoadSessionContext:
    """Tests for load_session_context."""

    def test_valid_context_file(self, tmp_path: Path) -> None:
        context = [
            {"role": "user", "content": "Hello"},
            {"role": "assistant", "content": "Hi there!"},
        ]
        f = tmp_path / "context.json"
        f.write_text(json.dumps(context))

        result = load_session_context(str(f))
        assert result == context

    def test_file_not_found(self) -> None:
        with pytest.raises(FileNotFoundError):
            load_session_context("/nonexistent/path.json")

    def test_invalid_json(self, tmp_path: Path) -> None:
        f = tmp_path / "bad.json"
        f.write_text("not json at all {{{")
        with pytest.raises(ValueError, match="not valid JSON"):
            load_session_context(str(f))

    def test_not_array(self, tmp_path: Path) -> None:
        f = tmp_path / "obj.json"
        f.write_text(json.dumps({"messages": []}))
        with pytest.raises(ValueError, match="must be a JSON array"):
            load_session_context(str(f))

    def test_message_missing_role(self, tmp_path: Path) -> None:
        f = tmp_path / "no_role.json"
        f.write_text(json.dumps([{"content": "hello"}]))
        with pytest.raises(ValueError, match="missing 'role'"):
            load_session_context(str(f))

    def test_message_missing_content(self, tmp_path: Path) -> None:
        f = tmp_path / "no_content.json"
        f.write_text(json.dumps([{"role": "user"}]))
        with pytest.raises(ValueError, match="missing 'content'"):
            load_session_context(str(f))

    def test_message_not_object(self, tmp_path: Path) -> None:
        f = tmp_path / "bad_item.json"
        f.write_text(json.dumps(["just a string"]))
        with pytest.raises(ValueError, match="must be an object"):
            load_session_context(str(f))

    def test_preserves_extra_fields(self, tmp_path: Path) -> None:
        context = [
            {"role": "user", "content": "Hi", "timestamp": 12345, "id": "msg_1"},
        ]
        f = tmp_path / "extra.json"
        f.write_text(json.dumps(context))

        result = load_session_context(str(f))
        assert result[0]["timestamp"] == 12345
        assert result[0]["id"] == "msg_1"

    def test_empty_array(self, tmp_path: Path) -> None:
        f = tmp_path / "empty.json"
        f.write_text(json.dumps([]))
        result = load_session_context(str(f))
        assert result == []


class TestFormatContextForPrompt:
    """Tests for format_context_for_prompt."""

    def test_formats_messages(self) -> None:
        messages = [
            {"role": "user", "content": "What time is it?"},
            {"role": "assistant", "content": "It's 3pm."},
        ]
        result = format_context_for_prompt(messages)
        assert "user: What time is it?" in result
        assert "assistant: It's 3pm." in result

    def test_empty_messages(self) -> None:
        assert format_context_for_prompt([]) == ""

    def test_preserves_order(self) -> None:
        messages = [
            {"role": "user", "content": "First"},
            {"role": "assistant", "content": "Second"},
            {"role": "user", "content": "Third"},
        ]
        result = format_context_for_prompt(messages)
        lines = result.split("\n")
        assert lines[0] == "user: First"
        assert lines[1] == "assistant: Second"
        assert lines[2] == "user: Third"


class TestLoadAndFormatContext:
    """Tests for load_and_format_context convenience function."""

    def test_valid_file(self, tmp_path: Path) -> None:
        context = [{"role": "user", "content": "Hello"}]
        f = tmp_path / "ctx.json"
        f.write_text(json.dumps(context))
        result = load_and_format_context(str(f))
        assert "user: Hello" in result

    def test_empty_path(self) -> None:
        assert load_and_format_context("") == ""

    def test_nonexistent_file_returns_empty(self) -> None:
        result = load_and_format_context("/does/not/exist.json")
        assert result == ""

    def test_invalid_json_returns_empty(self, tmp_path: Path) -> None:
        f = tmp_path / "bad.json"
        f.write_text("{invalid")
        result = load_and_format_context(str(f))
        assert result == ""
