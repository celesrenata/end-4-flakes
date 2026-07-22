"""OpenAI Realtime API backend implementation.

Connects to the OpenAI Realtime WebSocket at
wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview
and translates between the internal voice agent protocol and the
OpenAI Realtime event format.

Audio format: 24kHz, mono, 16-bit signed PCM (pcm16).
"""

from __future__ import annotations

import asyncio
import json
import sys
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import TYPE_CHECKING

import websockets

from voice_agent_backends.protocol import encode_audio

if TYPE_CHECKING:
    from typing import Any

    from websockets.asyncio.client import ClientConnection


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_OPENAI_REALTIME_URL = "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview"
_OPENAI_BETA_HEADER = "realtime=v1"


# ---------------------------------------------------------------------------
# Stdout emit helpers (match voice-agent-stream.py interface)
# ---------------------------------------------------------------------------


def _emit_event(event: "dict[str, Any]") -> None:
    """Write a JSON-line event to stdout and flush."""
    _ = sys.stdout.write(json.dumps(event) + "\n")
    sys.stdout.flush()


def _emit_partial_transcript(text: str) -> None:
    _emit_event({"type": "PARTIAL_TRANSCRIPT", "text": text})


def _emit_turn_end() -> None:
    _emit_event({"type": "TURN_END"})


def _emit_turn_complete(text: str) -> None:
    _emit_event({"type": "TURN_COMPLETE", "text": text})


def _emit_audio_response(audio_b64: str, text: str = "") -> None:
    event: "dict[str, Any]" = {"type": "AUDIO_RESPONSE", "audio": audio_b64}
    if text:
        event["text"] = text
    _emit_event(event)


def _emit_tool_call(call_id: str, name: str, arguments: str) -> None:
    _emit_event({
        "type": "TOOL_CALL",
        "id": call_id,
        "name": name,
        "arguments": arguments,
    })


def _emit_error(message: str, fatal: bool = False) -> None:
    _emit_event({"type": "ERROR", "message": message, "fatal": fatal})


# ---------------------------------------------------------------------------
# Backend base class and config
#
# When imported from voice-agent-stream.py (the normal runtime path), these
# are already defined. We duplicate the minimal definitions here so the module
# is self-contained for testing and type-checking. At runtime, duck typing
# ensures compatibility — the main script's `run()` only calls the methods
# defined on BaseVoiceBackend.
# ---------------------------------------------------------------------------


@dataclass
class VoiceAgentConfig:
    """Configuration for the voice agent helper (mirrors main script)."""

    backend: str = "openai-realtime"
    audio_fifo: str = ""
    sample_rate: int = 24000
    region: str = ""
    profile: str = ""
    api_key: str = ""
    system_prompt: str = ""
    context: str = ""
    tools: str = ""


class BaseVoiceBackend(ABC):
    """Abstract base class for streaming voice backends.

    Mirrors the definition in voice-agent-stream.py. Subclasses implement
    the actual connection to a speech-to-speech API.
    """

    config: VoiceAgentConfig

    def __init__(self, config: VoiceAgentConfig) -> None:
        self.config = config

    @abstractmethod
    async def connect(self) -> None: ...

    @abstractmethod
    async def send_audio(self, chunk: bytes) -> None: ...

    @abstractmethod
    async def send_tool_result(
        self, call_id: str, name: str, result: str, is_error: bool = False
    ) -> None: ...

    @abstractmethod
    async def send_barge_in(self) -> None: ...

    @abstractmethod
    async def disconnect(self) -> None: ...


# ---------------------------------------------------------------------------
# OpenAI Realtime Backend
# ---------------------------------------------------------------------------


class OpenAIRealtimeBackend(BaseVoiceBackend):
    """WebSocket-based backend connecting to OpenAI Realtime API.

    Implements the BaseVoiceBackend interface for the OpenAI Realtime
    speech-to-speech API. Audio is sent as base64-encoded PCM in
    `input_audio_buffer.append` events and received as base64 PCM in
    `response.audio.delta` events.

    Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8, 13.2
    """

    def __init__(self, config: VoiceAgentConfig) -> None:
        super().__init__(config)
        self._ws: "ClientConnection | None" = None
        self._receive_task: "asyncio.Task[None] | None" = None
        self._audio_paused: bool = False
        self._current_response_text: str = ""

    async def connect(self) -> None:
        """Establish WebSocket connection and send session.update.

        Connects to wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview
        with the API key and OpenAI-Beta header. Sends a session.update event
        to configure VAD, audio formats, system prompt, and tools.

        Requirements: 6.1, 6.2, 6.7, 6.8
        """
        api_key = self.config.api_key
        if not api_key:
            msg = "OpenAI API key is required for openai-realtime backend"
            raise ValueError(msg)

        headers = {
            "Authorization": f"Bearer {api_key}",
            "OpenAI-Beta": _OPENAI_BETA_HEADER,
        }

        self._ws = await websockets.connect(
            _OPENAI_REALTIME_URL,
            additional_headers=headers,
        )

        # Send session.update to configure the session
        await self._send_session_update()

        # Start background receive loop
        self._receive_task = asyncio.create_task(self._receive_loop())

    async def send_audio(self, chunk: bytes) -> None:
        """Send a PCM audio chunk as input_audio_buffer.append.

        Encodes the raw PCM bytes as base64 and sends them to the
        OpenAI Realtime API. Skipped if audio is paused (during tool calls).

        Args:
            chunk: Raw PCM audio bytes (s16, mono, 24kHz).

        Requirement: 6.3
        """
        if self._audio_paused:
            return
        if self._ws is None:
            return

        audio_b64 = encode_audio(chunk)
        event = {
            "type": "input_audio_buffer.append",
            "audio": audio_b64,
        }
        await self._ws.send(json.dumps(event))

    async def send_tool_result(
        self, call_id: str, name: str, result: str, is_error: bool = False
    ) -> None:
        """Send tool execution result and trigger a new response.

        Creates a conversation.item.create event with the function_call_output,
        then sends response.create to prompt the model to continue.

        Args:
            call_id: The unique tool call ID from the TOOL_CALL event.
            name: The tool name.
            result: Serialized result string (or error message).
            is_error: Whether the tool execution failed.

        Requirement: 8.4
        """
        if self._ws is None:
            return

        # Send the tool output as a conversation item
        item_event = {
            "type": "conversation.item.create",
            "item": {
                "type": "function_call_output",
                "call_id": call_id,
                "output": result,
            },
        }
        await self._ws.send(json.dumps(item_event))

        # Trigger a new response from the model
        response_event = {"type": "response.create"}
        await self._ws.send(json.dumps(response_event))

        # Resume audio forwarding
        self._audio_paused = False

    async def send_barge_in(self) -> None:
        """Cancel current response and clear audio buffer for barge-in.

        Sends response.cancel to stop the current response generation,
        then input_audio_buffer.clear to reset the audio buffer.

        Requirement: 4.5
        """
        if self._ws is None:
            return

        # Cancel current response
        cancel_event = {"type": "response.cancel"}
        await self._ws.send(json.dumps(cancel_event))

        # Clear audio buffer
        clear_event = {"type": "input_audio_buffer.clear"}
        await self._ws.send(json.dumps(clear_event))

    async def disconnect(self) -> None:
        """Gracefully close the WebSocket connection.

        Cancels the background receive task and closes the WebSocket.
        """
        if self._receive_task is not None:
            self._receive_task.cancel()
            try:
                await self._receive_task
            except asyncio.CancelledError:
                pass
            self._receive_task = None

        if self._ws is not None:
            await self._ws.close()
            self._ws = None

    # -----------------------------------------------------------------------
    # Internal helpers
    # -----------------------------------------------------------------------

    async def _send_session_update(self) -> None:
        """Send session.update event to configure the OpenAI Realtime session.

        Configures:
        - Input/output audio format: pcm16
        - Server-side VAD (turn detection)
        - System prompt with context
        - Available tools

        Requirements: 6.7, 6.8
        """
        if self._ws is None:
            return

        # Build instructions from system prompt + context
        instructions = self.config.system_prompt or ""
        context_content = self._load_context()
        if context_content:
            if instructions:
                instructions += "\n\n"
            instructions += f"## Session Context\n\n{context_content}"

        # Build tools list
        tools = self._load_tools()

        session_config: "dict[str, Any]" = {
            "modalities": ["text", "audio"],
            "input_audio_format": "pcm16",
            "output_audio_format": "pcm16",
            "turn_detection": {
                "type": "server_vad",
            },
        }

        if instructions:
            session_config["instructions"] = instructions

        if tools:
            session_config["tools"] = tools

        event = {
            "type": "session.update",
            "session": session_config,
        }
        await self._ws.send(json.dumps(event))

    def _load_context(self) -> str:
        """Load session context from the context file path.

        Returns:
            Formatted context string, or empty string if unavailable.
        """
        context_path = self.config.context
        if not context_path:
            return ""

        try:
            with open(context_path) as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            print(f"[openai-realtime] Failed to load context: {exc}", file=sys.stderr)
            return ""

        # Format messages as a readable context block
        if isinstance(data, list):
            lines: "list[str]" = []
            for msg in data:
                role = msg.get("role", "unknown")
                content = msg.get("content", "")
                lines.append(f"{role}: {content}")
            return "\n".join(lines)

        # If it's a dict or other format, serialize it
        return json.dumps(data, indent=2)

    def _load_tools(self) -> "list[dict[str, Any]]":
        """Load tools definition from the tools file path.

        Returns:
            List of tool definitions in OpenAI function format, or empty list.
        """
        tools_path = self.config.tools
        if not tools_path:
            return []

        try:
            with open(tools_path) as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            print(f"[openai-realtime] Failed to load tools: {exc}", file=sys.stderr)
            return []

        if isinstance(data, list):
            # Ensure tools are in OpenAI Realtime format
            formatted: "list[dict[str, Any]]" = []
            for tool in data:
                if isinstance(tool, dict):
                    # If already in {type: "function", function: {...}} format, extract
                    if "type" in tool and tool["type"] == "function" and "function" in tool:
                        func_def = tool["function"]
                    else:
                        func_def = tool

                    formatted.append({
                        "type": "function",
                        "name": func_def.get("name", ""),
                        "description": func_def.get("description", ""),
                        "parameters": func_def.get("parameters", {}),
                    })
            return formatted

        return []

    async def _receive_loop(self) -> None:
        """Background task: receive and dispatch OpenAI Realtime events.

        Continuously reads messages from the WebSocket and dispatches
        them to the appropriate handler based on event type.
        """
        if self._ws is None:
            return

        try:
            async for message in self._ws:
                if isinstance(message, bytes):
                    # Binary frames not expected from OpenAI Realtime
                    continue

                try:
                    event = json.loads(message)
                except json.JSONDecodeError:
                    continue

                event_type = event.get("type", "")
                await self._handle_event(event_type, event)

        except websockets.ConnectionClosed as exc:
            _emit_error(f"WebSocket connection closed: {exc}", fatal=True)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            _emit_error(f"Receive loop error: {exc}", fatal=True)

    async def _handle_event(self, event_type: str, event: "dict[str, Any]") -> None:
        """Dispatch a received OpenAI Realtime event.

        Maps OpenAI event types to protocol output events:
        - response.audio_transcript.delta → PARTIAL_TRANSCRIPT
        - response.audio.delta → AUDIO_RESPONSE
        - response.audio_transcript.done → TURN_COMPLETE
        - response.function_call_arguments.done → TOOL_CALL
        - input_audio_buffer.speech_started → (logged)
        - input_audio_buffer.speech_stopped → TURN_END
        - response.done → (response complete)
        - error → ERROR

        Requirements: 6.4, 6.5, 6.6
        """
        if event_type == "response.audio_transcript.delta":
            # Partial transcription of the AI's spoken response
            delta = event.get("delta", "")
            if delta:
                self._current_response_text += delta
                _emit_partial_transcript(self._current_response_text)

        elif event_type == "response.audio.delta":
            # Audio chunk from the AI's response (base64 PCM)
            audio_b64 = event.get("delta", "")
            if audio_b64:
                _emit_audio_response(audio_b64)

        elif event_type == "response.audio_transcript.done":
            # Final transcript of the AI's complete response
            transcript = event.get("transcript", "")
            if transcript:
                _emit_turn_complete(transcript)
            self._current_response_text = ""

        elif event_type == "response.function_call_arguments.done":
            # Tool call complete — emit TOOL_CALL and pause audio
            call_id = event.get("call_id", "")
            name = event.get("name", "")
            arguments = event.get("arguments", "")
            self._audio_paused = True
            _emit_tool_call(call_id, name, arguments)

        elif event_type == "input_audio_buffer.speech_started":
            # User started speaking — log for debugging
            print("[openai-realtime] Speech started", file=sys.stderr)

        elif event_type == "input_audio_buffer.speech_stopped":
            # User stopped speaking — emit TURN_END
            _emit_turn_end()

        elif event_type == "response.done":
            # Response generation complete
            self._current_response_text = ""

        elif event_type == "error":
            # API error
            error_data = event.get("error", {})
            message = error_data.get("message", "Unknown OpenAI Realtime error")
            error_type = error_data.get("type", "")
            _emit_error(f"[{error_type}] {message}", fatal=False)

        elif event_type == "session.created":
            # Session established — informational
            print("[openai-realtime] Session created", file=sys.stderr)

        elif event_type == "session.updated":
            # Session config confirmed
            print("[openai-realtime] Session updated", file=sys.stderr)
