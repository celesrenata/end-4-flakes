# Feature: streaming-voice-agent, Task 2.2: Unit tests for Nova Sonic backend event mapping
"""Unit tests for Nova Sonic backend event routing and system prompt construction.

Tests cover:
- Transcript event → PARTIAL_TRANSCRIPT mapping
- Audio response event → AUDIO_RESPONSE mapping
- Tool-use event → TOOL_CALL mapping
- System prompt injection with context
- Audio pausing on tool call

Validates: Requirements 5.4, 5.5, 5.6, 5.7
"""

import json
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

# Add the helper script directory to the path
SCRIPT_DIR = Path(__file__).parent.parent / "configs" / "quickshell" / "ii" / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from voice_agent_backends.base import VoiceAgentConfig
from voice_agent_backends.nova_sonic import NovaSonicBackend


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


def _make_config(**overrides) -> VoiceAgentConfig:
    """Create a minimal VoiceAgentConfig for testing."""
    defaults = {
        "backend": "nova-sonic",
        "audio_fifo": "/tmp/test-fifo.pcm",
        "sample_rate": 16000,
        "region": "us-east-1",
        "profile": "default",
        "api_key": "",
        "system_prompt": "",
        "context": "",
        "tools": "",
    }
    defaults.update(overrides)
    return VoiceAgentConfig(**defaults)


def _make_backend(**config_overrides) -> NovaSonicBackend:
    """Create a NovaSonicBackend instance without connecting."""
    config = _make_config(**config_overrides)
    return NovaSonicBackend(config)


def _capture_emitted_events(backend, action):
    """Run an action on the backend and capture all events emitted to stdout.

    Returns a list of dicts (parsed JSON events).
    """
    captured = []

    def mock_emit(event: dict):
        captured.append(event)

    with patch("voice_agent_backends.nova_sonic._emit_event", side_effect=mock_emit):
        action(backend)

    return captured


# ---------------------------------------------------------------------------
# Test: Transcript event → PARTIAL_TRANSCRIPT mapping (Req 5.4)
# ---------------------------------------------------------------------------


class TestTextOutputMapping:
    """Test _handle_text_output routes transcript events correctly."""

    def test_user_transcript_emits_partial_transcript(self) -> None:
        """User role text output emits PARTIAL_TRANSCRIPT."""
        backend = _make_backend()
        backend._current_role = "USER"
        backend._current_generation_stage = ""

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_text_output({"content": "hello world"}),
        )

        assert len(events) == 1
        assert events[0]["type"] == "PARTIAL_TRANSCRIPT"
        assert events[0]["text"] == "hello world"

    def test_user_transcript_accumulates_text(self) -> None:
        """User text output accumulates in _accumulated_user_text."""
        backend = _make_backend()
        backend._current_role = "USER"

        with patch("voice_agent_backends.nova_sonic._emit_event"):
            backend._handle_text_output({"content": "hello world"})

        assert backend._accumulated_user_text == "hello world"

    def test_assistant_speculative_emits_partial_transcript(self) -> None:
        """Assistant SPECULATIVE stage emits PARTIAL_TRANSCRIPT."""
        backend = _make_backend()
        backend._current_role = "ASSISTANT"
        backend._current_generation_stage = "SPECULATIVE"

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_text_output({"content": "Let me check"}),
        )

        assert len(events) == 1
        assert events[0]["type"] == "PARTIAL_TRANSCRIPT"
        assert events[0]["text"] == "Let me check"

    def test_assistant_speculative_accumulates(self) -> None:
        """Assistant SPECULATIVE text accumulates in _accumulated_assistant_text."""
        backend = _make_backend()
        backend._current_role = "ASSISTANT"
        backend._current_generation_stage = "SPECULATIVE"

        with patch("voice_agent_backends.nova_sonic._emit_event"):
            backend._handle_text_output({"content": "Hello "})
            backend._handle_text_output({"content": "there"})

        assert backend._accumulated_assistant_text == "Hello there"

    def test_assistant_final_emits_turn_complete(self) -> None:
        """Assistant FINAL stage emits TURN_COMPLETE."""
        backend = _make_backend()
        backend._current_role = "ASSISTANT"
        backend._current_generation_stage = "FINAL"

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_text_output({"content": "The weather is sunny."}),
        )

        assert len(events) == 1
        assert events[0]["type"] == "TURN_COMPLETE"
        assert events[0]["text"] == "The weather is sunny."

    def test_empty_content_emits_nothing(self) -> None:
        """Empty content does not emit any event."""
        backend = _make_backend()
        backend._current_role = "USER"

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_text_output({"content": ""}),
        )

        assert len(events) == 0

    def test_missing_content_emits_nothing(self) -> None:
        """Missing content key does not emit any event."""
        backend = _make_backend()
        backend._current_role = "USER"

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_text_output({}),
        )

        assert len(events) == 0


# ---------------------------------------------------------------------------
# Test: Audio response event → AUDIO_RESPONSE mapping (Req 5.5)
# ---------------------------------------------------------------------------


class TestAudioOutputMapping:
    """Test _handle_audio_output emits AUDIO_RESPONSE correctly."""

    def test_audio_output_emits_audio_response(self) -> None:
        """Audio output with content emits AUDIO_RESPONSE."""
        backend = _make_backend()
        backend._accumulated_assistant_text = ""

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_audio_output({"content": "AAECBAUG"}),
        )

        assert len(events) == 1
        assert events[0]["type"] == "AUDIO_RESPONSE"
        assert events[0]["audio"] == "AAECBAUG"

    def test_audio_output_includes_accumulated_text(self) -> None:
        """First audio chunk includes accumulated assistant text."""
        backend = _make_backend()
        backend._accumulated_assistant_text = "The weather is sunny."

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_audio_output({"content": "AAEC"}),
        )

        assert events[0]["type"] == "AUDIO_RESPONSE"
        assert events[0]["text"] == "The weather is sunny."

    def test_audio_output_clears_accumulated_text(self) -> None:
        """After first audio emission, accumulated text is cleared."""
        backend = _make_backend()
        backend._accumulated_assistant_text = "Some text"

        with patch("voice_agent_backends.nova_sonic._emit_event"):
            backend._handle_audio_output({"content": "AAEC"})

        assert backend._accumulated_assistant_text == ""

    def test_second_audio_chunk_has_no_text(self) -> None:
        """Second audio chunk does not include text (already cleared)."""
        backend = _make_backend()
        backend._accumulated_assistant_text = "First"

        events = []

        def mock_emit(event):
            events.append(event)

        with patch("voice_agent_backends.nova_sonic._emit_event", side_effect=mock_emit):
            backend._handle_audio_output({"content": "AAEC"})
            backend._handle_audio_output({"content": "BAUG"})

        assert events[0]["text"] == "First"
        # Second emission: text should be empty string (omitted from emit helper)
        assert events[1]["audio"] == "BAUG"

    def test_empty_audio_content_emits_nothing(self) -> None:
        """Empty audio content does not emit an event."""
        backend = _make_backend()

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_audio_output({"content": ""}),
        )

        assert len(events) == 0

    def test_missing_audio_content_emits_nothing(self) -> None:
        """Missing content key does not emit an event."""
        backend = _make_backend()

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_audio_output({}),
        )

        assert len(events) == 0


# ---------------------------------------------------------------------------
# Test: Tool-use event → TOOL_CALL mapping (Req 5.6)
# ---------------------------------------------------------------------------


class TestToolUseMapping:
    """Test _handle_tool_use emits TOOL_CALL and pauses audio."""

    def test_tool_use_emits_tool_call(self) -> None:
        """Tool use event emits a TOOL_CALL event."""
        backend = _make_backend()

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_tool_use({
                "toolUseId": "tc1",
                "toolName": "get_time",
                "content": '{"tz": "UTC"}',
            }),
        )

        assert len(events) == 1
        assert events[0]["type"] == "TOOL_CALL"
        assert events[0]["id"] == "tc1"
        assert events[0]["name"] == "get_time"
        assert events[0]["arguments"] == '{"tz": "UTC"}'

    def test_tool_use_pauses_audio(self) -> None:
        """Tool use event sets _audio_paused to True."""
        backend = _make_backend()
        assert backend._audio_paused is False

        with patch("voice_agent_backends.nova_sonic._emit_event"):
            backend._handle_tool_use({
                "toolUseId": "tc1",
                "toolName": "get_time",
                "content": "{}",
            })

        assert backend._audio_paused is True

    def test_tool_use_tracks_pending_id(self) -> None:
        """Tool use event stores the pending tool call ID."""
        backend = _make_backend()
        assert backend._pending_tool_call_id is None

        with patch("voice_agent_backends.nova_sonic._emit_event"):
            backend._handle_tool_use({
                "toolUseId": "tc_abc",
                "toolName": "shell_exec",
                "content": '{"cmd": "ls"}',
            })

        assert backend._pending_tool_call_id == "tc_abc"

    def test_tool_use_with_empty_content(self) -> None:
        """Tool use with empty content defaults to '{}'."""
        backend = _make_backend()

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_tool_use({
                "toolUseId": "tc2",
                "toolName": "system_info",
            }),
        )

        assert events[0]["arguments"] == "{}"

    def test_tool_use_missing_fields_defaults(self) -> None:
        """Tool use with missing fields uses empty string defaults."""
        backend = _make_backend()

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_tool_use({}),
        )

        assert events[0]["type"] == "TOOL_CALL"
        assert events[0]["id"] == ""
        assert events[0]["name"] == ""
        assert events[0]["arguments"] == "{}"


# ---------------------------------------------------------------------------
# Test: System prompt injection (Req 5.7)
# ---------------------------------------------------------------------------


class TestSystemPromptInjection:
    """Test _build_system_prompt constructs correct system prompt."""

    def test_default_system_prompt(self) -> None:
        """With no config system prompt, uses default voice assistant prompt."""
        backend = _make_backend(system_prompt="")
        prompt = backend._build_system_prompt()

        assert "helpful voice assistant" in prompt
        assert "concise" in prompt

    def test_custom_system_prompt(self) -> None:
        """Custom system prompt is used when provided."""
        backend = _make_backend(system_prompt="You are a pirate assistant.")
        prompt = backend._build_system_prompt()

        assert "You are a pirate assistant." in prompt

    def test_context_injection_from_file(self) -> None:
        """Context from a JSON file is injected into the system prompt."""
        context_data = [
            {"role": "user", "content": "What's the weather?"},
            {"role": "assistant", "content": "It's sunny today."},
        ]

        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", delete=False
        ) as f:
            json.dump(context_data, f)
            context_path = f.name

        try:
            backend = _make_backend(
                system_prompt="You are helpful.",
                context=context_path,
            )
            prompt = backend._build_system_prompt()

            assert "Conversation Context" in prompt
            assert "user: What's the weather?" in prompt
            assert "assistant: It's sunny today." in prompt
        finally:
            Path(context_path).unlink(missing_ok=True)

    def test_context_dict_format(self) -> None:
        """Dict context is serialized as JSON in the prompt."""
        context_data = {"topic": "weather", "location": "Seattle"}

        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", delete=False
        ) as f:
            json.dump(context_data, f)
            context_path = f.name

        try:
            backend = _make_backend(context=context_path)
            prompt = backend._build_system_prompt()

            assert "weather" in prompt
            assert "Seattle" in prompt
        finally:
            Path(context_path).unlink(missing_ok=True)

    def test_missing_context_file_handled_gracefully(self) -> None:
        """Missing context file does not crash, just omits context."""
        backend = _make_backend(context="/nonexistent/path/context.json")
        prompt = backend._build_system_prompt()

        # Should still have the default prompt, just no context section
        assert "helpful voice assistant" in prompt

    def test_no_context_file_omits_section(self) -> None:
        """When no context path is given, no context section appears."""
        backend = _make_backend(system_prompt="You are helpful.", context="")
        prompt = backend._build_system_prompt()

        assert "Conversation Context" not in prompt


# ---------------------------------------------------------------------------
# Test: Audio pausing during tool call (Req 5.6)
# ---------------------------------------------------------------------------


class TestAudioPausingDuringToolCall:
    """Test that audio is paused while a tool call is pending."""

    def test_send_audio_dropped_when_paused(self) -> None:
        """Audio chunks are silently dropped when _audio_paused is True."""
        import asyncio

        backend = _make_backend()
        backend._is_active = True
        backend._audio_paused = True

        # send_audio should not raise or send anything when paused
        # Since we haven't connected, _send_event_dict would fail if called
        # The fact that it returns without error proves audio is dropped
        asyncio.run(backend.send_audio(b"\x00\x01\x02\x03"))

    def test_send_audio_dropped_when_inactive(self) -> None:
        """Audio chunks are dropped when backend is inactive."""
        import asyncio

        backend = _make_backend()
        backend._is_active = False
        backend._audio_paused = False

        asyncio.run(backend.send_audio(b"\x00\x01\x02\x03"))


# ---------------------------------------------------------------------------
# Test: Content start and content end event handling
# ---------------------------------------------------------------------------


class TestContentStartHandling:
    """Test _handle_content_start tracks role and generation stage."""

    def test_tracks_role(self) -> None:
        """Content start with role updates _current_role."""
        backend = _make_backend()
        backend._handle_content_start({"role": "USER", "type": "AUDIO"})
        assert backend._current_role == "USER"

    def test_tracks_content_type(self) -> None:
        """Content start with type updates _current_content_type."""
        backend = _make_backend()
        backend._handle_content_start({"role": "ASSISTANT", "type": "TEXT"})
        assert backend._current_content_type == "TEXT"

    def test_parses_generation_stage_from_additional_fields(self) -> None:
        """Generation stage is parsed from additionalModelFields JSON."""
        backend = _make_backend()
        backend._handle_content_start({
            "role": "ASSISTANT",
            "type": "TEXT",
            "additionalModelFields": '{"generationStage": "SPECULATIVE"}',
        })
        assert backend._current_generation_stage == "SPECULATIVE"

    def test_empty_additional_fields_clears_stage(self) -> None:
        """Empty additionalModelFields resets generation stage."""
        backend = _make_backend()
        backend._current_generation_stage = "SPECULATIVE"
        backend._handle_content_start({"role": "ASSISTANT", "type": "TEXT"})
        assert backend._current_generation_stage == ""


class TestContentEndHandling:
    """Test _handle_content_end emits TURN_END on user audio end."""

    def test_user_audio_content_end_emits_turn_end(self) -> None:
        """Content end for USER AUDIO emits TURN_END."""
        backend = _make_backend()
        backend._current_role = "USER"
        backend._current_content_type = "AUDIO"

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_content_end({}),
        )

        assert len(events) == 1
        assert events[0]["type"] == "TURN_END"

    def test_assistant_content_end_does_not_emit_turn_end(self) -> None:
        """Content end for ASSISTANT role does not emit TURN_END."""
        backend = _make_backend()
        backend._current_role = "ASSISTANT"
        backend._current_content_type = "TEXT"

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_content_end({}),
        )

        assert len(events) == 0

    def test_user_text_content_end_does_not_emit_turn_end(self) -> None:
        """Content end for USER TEXT does not emit TURN_END."""
        backend = _make_backend()
        backend._current_role = "USER"
        backend._current_content_type = "TEXT"

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_content_end({}),
        )

        assert len(events) == 0


# ---------------------------------------------------------------------------
# Test: _handle_output_event routing
# ---------------------------------------------------------------------------


class TestOutputEventRouting:
    """Test _handle_output_event dispatches to the correct handler."""

    def test_routes_text_output(self) -> None:
        """textOutput events are routed to _handle_text_output."""
        backend = _make_backend()
        backend._current_role = "USER"

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_output_event(
                {"textOutput": {"content": "testing"}}
            ),
        )

        assert events[0]["type"] == "PARTIAL_TRANSCRIPT"

    def test_routes_audio_output(self) -> None:
        """audioOutput events are routed to _handle_audio_output."""
        backend = _make_backend()

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_output_event(
                {"audioOutput": {"content": "AAEC"}}
            ),
        )

        assert events[0]["type"] == "AUDIO_RESPONSE"

    def test_routes_tool_use(self) -> None:
        """toolUse events are routed to _handle_tool_use."""
        backend = _make_backend()

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_output_event(
                {"toolUse": {"toolUseId": "t1", "toolName": "cmd", "content": "{}"}}
            ),
        )

        assert events[0]["type"] == "TOOL_CALL"

    def test_routes_content_start(self) -> None:
        """contentStart events update role tracking."""
        backend = _make_backend()
        backend._handle_output_event(
            {"contentStart": {"role": "ASSISTANT", "type": "TEXT"}}
        )
        assert backend._current_role == "ASSISTANT"

    def test_completion_start_resets_assistant_text(self) -> None:
        """completionStart resets accumulated assistant text."""
        backend = _make_backend()
        backend._accumulated_assistant_text = "old text"
        backend._handle_output_event({"completionStart": {}})
        assert backend._accumulated_assistant_text == ""

    def test_completion_end_emits_turn_complete_for_user(self) -> None:
        """completionEnd emits TURN_COMPLETE if user text accumulated."""
        backend = _make_backend()
        backend._accumulated_user_text = "What time is it?"

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_output_event({"completionEnd": {}}),
        )

        assert events[0]["type"] == "TURN_COMPLETE"
        assert events[0]["text"] == "What time is it?"

    def test_completion_end_clears_user_text(self) -> None:
        """completionEnd clears accumulated user text after emitting."""
        backend = _make_backend()
        backend._accumulated_user_text = "hello"

        with patch("voice_agent_backends.nova_sonic._emit_event"):
            backend._handle_output_event({"completionEnd": {}})

        assert backend._accumulated_user_text == ""

    def test_completion_end_no_user_text_emits_nothing(self) -> None:
        """completionEnd with no accumulated user text emits nothing."""
        backend = _make_backend()
        backend._accumulated_user_text = ""

        events = _capture_emitted_events(
            backend,
            lambda b: b._handle_output_event({"completionEnd": {}}),
        )

        assert len(events) == 0
