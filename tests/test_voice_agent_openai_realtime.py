# Feature: streaming-voice-agent, Task 3.2: OpenAI Realtime backend event mapping
"""Unit tests for the OpenAI Realtime backend event handling.

Tests cover:
- response.audio_transcript.delta → PARTIAL_TRANSCRIPT mapping
- response.audio.delta → AUDIO_RESPONSE mapping
- response.function_call_arguments.done → TOOL_CALL mapping
- session.update message formation (VAD, audio format, instructions)
- Audio pause on tool call

Validates: Requirements 6.4, 6.5, 6.6, 6.7, 6.8
"""

import json
import sys
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

# Add the helper script directory to the path
SCRIPT_DIR = Path(__file__).parent.parent / "configs" / "quickshell" / "ii" / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from voice_agent_backends.openai_realtime import (
    OpenAIRealtimeBackend,
    VoiceAgentConfig,
    _emit_event,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_backend(
    api_key: str = "test-key",
    system_prompt: str = "",
    context: str = "",
    tools: str = "",
) -> OpenAIRealtimeBackend:
    """Create a backend instance with a mocked WebSocket."""
    config = VoiceAgentConfig(
        backend="openai-realtime",
        api_key=api_key,
        system_prompt=system_prompt,
        context=context,
        tools=tools,
        sample_rate=24000,
    )
    backend = OpenAIRealtimeBackend(config)
    # Mock the WebSocket so we don't actually connect
    backend._ws = AsyncMock()
    return backend


def _capture_stdout_events(func, *args, **kwargs):
    """Run a function and capture all JSON events emitted to stdout.

    Returns a list of parsed event dicts.
    """
    captured = []
    original_write = sys.stdout.write

    def mock_write(text):
        if text.strip():
            try:
                event = json.loads(text.strip())
                captured.append(event)
            except json.JSONDecodeError:
                pass
        return len(text)

    with patch.object(sys.stdout, "write", side_effect=mock_write):
        with patch.object(sys.stdout, "flush"):
            func(*args, **kwargs)

    return captured


async def _capture_stdout_events_async(coro):
    """Run an async coroutine and capture all JSON events emitted to stdout.

    Returns a list of parsed event dicts.
    """
    captured = []

    def mock_write(text):
        if text.strip():
            try:
                event = json.loads(text.strip())
                captured.append(event)
            except json.JSONDecodeError:
                pass
        return len(text)

    with patch.object(sys.stdout, "write", side_effect=mock_write):
        with patch.object(sys.stdout, "flush"):
            await coro

    return captured


# ---------------------------------------------------------------------------
# Test: response.audio_transcript.delta → PARTIAL_TRANSCRIPT
# Validates: Requirement 6.4
# ---------------------------------------------------------------------------


class TestAudioTranscriptDelta:
    """Test that response.audio_transcript.delta events emit PARTIAL_TRANSCRIPT."""

    @pytest.mark.asyncio
    async def test_delta_emits_partial_transcript(self) -> None:
        """A single delta should emit PARTIAL_TRANSCRIPT with the accumulated text."""
        backend = _make_backend()
        event = {"type": "response.audio_transcript.delta", "delta": "Hello"}

        events = await _capture_stdout_events_async(
            backend._handle_event("response.audio_transcript.delta", event)
        )

        assert len(events) == 1
        assert events[0]["type"] == "PARTIAL_TRANSCRIPT"
        assert events[0]["text"] == "Hello"

    @pytest.mark.asyncio
    async def test_delta_accumulates_text(self) -> None:
        """Multiple deltas should accumulate into the current response text."""
        backend = _make_backend()

        events1 = await _capture_stdout_events_async(
            backend._handle_event(
                "response.audio_transcript.delta",
                {"type": "response.audio_transcript.delta", "delta": "Hello "},
            )
        )
        events2 = await _capture_stdout_events_async(
            backend._handle_event(
                "response.audio_transcript.delta",
                {"type": "response.audio_transcript.delta", "delta": "world"},
            )
        )

        assert events1[0]["text"] == "Hello "
        assert events2[0]["text"] == "Hello world"

    @pytest.mark.asyncio
    async def test_empty_delta_no_emit(self) -> None:
        """An empty delta should not emit an event."""
        backend = _make_backend()
        event = {"type": "response.audio_transcript.delta", "delta": ""}

        events = await _capture_stdout_events_async(
            backend._handle_event("response.audio_transcript.delta", event)
        )

        assert len(events) == 0


# ---------------------------------------------------------------------------
# Test: response.audio.delta → AUDIO_RESPONSE
# Validates: Requirement 6.5
# ---------------------------------------------------------------------------


class TestAudioDelta:
    """Test that response.audio.delta events emit AUDIO_RESPONSE."""

    @pytest.mark.asyncio
    async def test_audio_delta_emits_audio_response(self) -> None:
        """Audio delta should emit AUDIO_RESPONSE with the base64 audio data."""
        backend = _make_backend()
        audio_b64 = "AAECBAUG"  # Some base64 data
        event = {"type": "response.audio.delta", "delta": audio_b64}

        events = await _capture_stdout_events_async(
            backend._handle_event("response.audio.delta", event)
        )

        assert len(events) == 1
        assert events[0]["type"] == "AUDIO_RESPONSE"
        assert events[0]["audio"] == audio_b64

    @pytest.mark.asyncio
    async def test_audio_delta_no_text_field(self) -> None:
        """AUDIO_RESPONSE from audio.delta should not include a text field."""
        backend = _make_backend()
        event = {"type": "response.audio.delta", "delta": "AAAA"}

        events = await _capture_stdout_events_async(
            backend._handle_event("response.audio.delta", event)
        )

        assert "text" not in events[0]

    @pytest.mark.asyncio
    async def test_empty_audio_delta_no_emit(self) -> None:
        """An empty audio delta should not emit an event."""
        backend = _make_backend()
        event = {"type": "response.audio.delta", "delta": ""}

        events = await _capture_stdout_events_async(
            backend._handle_event("response.audio.delta", event)
        )

        assert len(events) == 0


# ---------------------------------------------------------------------------
# Test: response.function_call_arguments.done → TOOL_CALL
# Validates: Requirement 6.6
# ---------------------------------------------------------------------------


class TestFunctionCallDone:
    """Test that response.function_call_arguments.done emits TOOL_CALL."""

    @pytest.mark.asyncio
    async def test_function_call_emits_tool_call(self) -> None:
        """function_call_arguments.done should emit a TOOL_CALL event."""
        backend = _make_backend()
        event = {
            "type": "response.function_call_arguments.done",
            "call_id": "fc_123",
            "name": "get_time",
            "arguments": '{"timezone": "UTC"}',
        }

        events = await _capture_stdout_events_async(
            backend._handle_event("response.function_call_arguments.done", event)
        )

        assert len(events) == 1
        assert events[0]["type"] == "TOOL_CALL"
        assert events[0]["id"] == "fc_123"
        assert events[0]["name"] == "get_time"
        assert events[0]["arguments"] == '{"timezone": "UTC"}'

    @pytest.mark.asyncio
    async def test_function_call_pauses_audio(self) -> None:
        """TOOL_CALL should set _audio_paused to True."""
        backend = _make_backend()
        assert backend._audio_paused is False

        event = {
            "type": "response.function_call_arguments.done",
            "call_id": "fc_1",
            "name": "system_info",
            "arguments": "{}",
        }

        await _capture_stdout_events_async(
            backend._handle_event("response.function_call_arguments.done", event)
        )

        assert backend._audio_paused is True

    @pytest.mark.asyncio
    async def test_function_call_empty_arguments(self) -> None:
        """A function call with empty arguments should still emit correctly."""
        backend = _make_backend()
        event = {
            "type": "response.function_call_arguments.done",
            "call_id": "fc_2",
            "name": "get_status",
            "arguments": "",
        }

        events = await _capture_stdout_events_async(
            backend._handle_event("response.function_call_arguments.done", event)
        )

        assert events[0]["type"] == "TOOL_CALL"
        assert events[0]["arguments"] == ""


# ---------------------------------------------------------------------------
# Test: session.update message formation
# Validates: Requirements 6.7, 6.8
# ---------------------------------------------------------------------------


class TestSessionUpdate:
    """Test that _send_session_update forms the correct JSON structure."""

    @pytest.mark.asyncio
    async def test_session_update_basic_structure(self) -> None:
        """session.update should include modalities, audio formats, and VAD config."""
        backend = _make_backend(system_prompt="You are a helpful assistant.")
        mock_ws = backend._ws

        await backend._send_session_update()

        mock_ws.send.assert_called_once()
        sent_data = json.loads(mock_ws.send.call_args[0][0])

        assert sent_data["type"] == "session.update"
        session = sent_data["session"]
        assert "text" in session["modalities"]
        assert "audio" in session["modalities"]
        assert session["input_audio_format"] == "pcm16"
        assert session["output_audio_format"] == "pcm16"

    @pytest.mark.asyncio
    async def test_session_update_vad_enabled(self) -> None:
        """session.update should have server_vad turn detection enabled."""
        backend = _make_backend()

        await backend._send_session_update()

        sent_data = json.loads(backend._ws.send.call_args[0][0])
        session = sent_data["session"]
        assert session["turn_detection"]["type"] == "server_vad"

    @pytest.mark.asyncio
    async def test_session_update_includes_instructions(self) -> None:
        """session.update should include the system prompt in instructions."""
        backend = _make_backend(system_prompt="Be concise and helpful.")

        await backend._send_session_update()

        sent_data = json.loads(backend._ws.send.call_args[0][0])
        session = sent_data["session"]
        assert "instructions" in session
        assert "Be concise and helpful." in session["instructions"]

    @pytest.mark.asyncio
    async def test_session_update_no_instructions_when_empty(self) -> None:
        """session.update should omit instructions when system prompt is empty."""
        backend = _make_backend(system_prompt="")

        await backend._send_session_update()

        sent_data = json.loads(backend._ws.send.call_args[0][0])
        session = sent_data["session"]
        assert "instructions" not in session

    @pytest.mark.asyncio
    async def test_session_update_with_tools(self, tmp_path) -> None:
        """session.update should include tools when a tools file is provided."""
        tools_file = tmp_path / "tools.json"
        tools_data = [
            {
                "type": "function",
                "function": {
                    "name": "get_time",
                    "description": "Get the current time",
                    "parameters": {"type": "object", "properties": {}},
                },
            }
        ]
        tools_file.write_text(json.dumps(tools_data))

        backend = _make_backend(tools=str(tools_file))

        await backend._send_session_update()

        sent_data = json.loads(backend._ws.send.call_args[0][0])
        session = sent_data["session"]
        assert "tools" in session
        assert len(session["tools"]) == 1
        assert session["tools"][0]["name"] == "get_time"
        assert session["tools"][0]["type"] == "function"

    @pytest.mark.asyncio
    async def test_session_update_with_context(self, tmp_path) -> None:
        """session.update should append context to instructions when context file provided."""
        context_file = tmp_path / "context.json"
        context_data = [
            {"role": "user", "content": "What is Python?"},
            {"role": "assistant", "content": "Python is a programming language."},
        ]
        context_file.write_text(json.dumps(context_data))

        backend = _make_backend(
            system_prompt="You are helpful.",
            context=str(context_file),
        )

        await backend._send_session_update()

        sent_data = json.loads(backend._ws.send.call_args[0][0])
        session = sent_data["session"]
        assert "instructions" in session
        assert "You are helpful." in session["instructions"]
        assert "Session Context" in session["instructions"]
        assert "What is Python?" in session["instructions"]

    @pytest.mark.asyncio
    async def test_session_update_no_ws_does_nothing(self) -> None:
        """_send_session_update should be a no-op when WebSocket is None."""
        backend = _make_backend()
        backend._ws = None

        # Should not raise
        await backend._send_session_update()


# ---------------------------------------------------------------------------
# Test: Audio pausing behavior
# Validates: Related to Requirement 6.6 (tool call pauses audio)
# ---------------------------------------------------------------------------


class TestAudioPausing:
    """Test that audio pausing works correctly around tool calls."""

    @pytest.mark.asyncio
    async def test_send_audio_skipped_when_paused(self) -> None:
        """send_audio should not send when _audio_paused is True."""
        backend = _make_backend()
        backend._audio_paused = True

        await backend.send_audio(b"\x00\x01\x02\x03")

        backend._ws.send.assert_not_called()

    @pytest.mark.asyncio
    async def test_send_audio_works_when_not_paused(self) -> None:
        """send_audio should send audio when not paused."""
        backend = _make_backend()
        backend._audio_paused = False

        await backend.send_audio(b"\x00\x01\x02\x03")

        backend._ws.send.assert_called_once()
        sent_data = json.loads(backend._ws.send.call_args[0][0])
        assert sent_data["type"] == "input_audio_buffer.append"
        assert "audio" in sent_data

    @pytest.mark.asyncio
    async def test_tool_result_resumes_audio(self) -> None:
        """send_tool_result should set _audio_paused back to False."""
        backend = _make_backend()
        backend._audio_paused = True

        await backend.send_tool_result("fc_1", "get_time", "12:00 UTC", is_error=False)

        assert backend._audio_paused is False


# ---------------------------------------------------------------------------
# Test: Additional event types handled by _handle_event
# ---------------------------------------------------------------------------


class TestOtherEventTypes:
    """Test handling of supplementary OpenAI Realtime events."""

    @pytest.mark.asyncio
    async def test_speech_stopped_emits_turn_end(self) -> None:
        """input_audio_buffer.speech_stopped should emit TURN_END."""
        backend = _make_backend()
        event = {"type": "input_audio_buffer.speech_stopped"}

        events = await _capture_stdout_events_async(
            backend._handle_event("input_audio_buffer.speech_stopped", event)
        )

        assert len(events) == 1
        assert events[0]["type"] == "TURN_END"

    @pytest.mark.asyncio
    async def test_transcript_done_emits_turn_complete(self) -> None:
        """response.audio_transcript.done should emit TURN_COMPLETE."""
        backend = _make_backend()
        event = {"type": "response.audio_transcript.done", "transcript": "Hello world"}

        events = await _capture_stdout_events_async(
            backend._handle_event("response.audio_transcript.done", event)
        )

        assert len(events) == 1
        assert events[0]["type"] == "TURN_COMPLETE"
        assert events[0]["text"] == "Hello world"

    @pytest.mark.asyncio
    async def test_transcript_done_resets_current_text(self) -> None:
        """response.audio_transcript.done should reset _current_response_text."""
        backend = _make_backend()
        backend._current_response_text = "accumulated text"

        await _capture_stdout_events_async(
            backend._handle_event(
                "response.audio_transcript.done",
                {"type": "response.audio_transcript.done", "transcript": "final"},
            )
        )

        assert backend._current_response_text == ""

    @pytest.mark.asyncio
    async def test_error_event_emits_error(self) -> None:
        """OpenAI error event should emit an ERROR protocol event."""
        backend = _make_backend()
        event = {
            "type": "error",
            "error": {"type": "rate_limit", "message": "Too many requests"},
        }

        events = await _capture_stdout_events_async(
            backend._handle_event("error", event)
        )

        assert len(events) == 1
        assert events[0]["type"] == "ERROR"
        assert "Too many requests" in events[0]["message"]
        assert events[0]["fatal"] is False

    @pytest.mark.asyncio
    async def test_response_done_resets_text(self) -> None:
        """response.done should reset _current_response_text."""
        backend = _make_backend()
        backend._current_response_text = "some leftover"

        await _capture_stdout_events_async(
            backend._handle_event("response.done", {"type": "response.done"})
        )

        assert backend._current_response_text == ""
