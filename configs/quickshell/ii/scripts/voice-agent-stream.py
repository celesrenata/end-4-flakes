#!/usr/bin/env python3
"""Streaming voice agent helper process.

Maintains a bidirectional streaming connection to either Amazon Nova Sonic
(HTTP/2 bidirectional) or OpenAI Realtime API (WebSocket). Reads raw PCM
audio from a named FIFO and JSON control messages from stdin. Emits
structured JSON-line events on stdout for the QML VoiceAgentService.

I/O Architecture:
    Audio input:  Named FIFO (--audio-fifo) ← pw-cat --record
    Control input: stdin (JSON lines) ← QML Process.write()
    Event output:  stdout (JSON lines) → QML SplitParser

Output Events (stdout → QML):
    READY              - Backend connection established
    PARTIAL_TRANSCRIPT - Partial speech recognition text
    TURN_END           - Backend detected end of user speech
    TURN_COMPLETE      - Complete user utterance finalized
    AUDIO_RESPONSE     - Base64-encoded PCM audio from backend
    TOOL_CALL          - Backend requests tool execution
    SESSION_END        - Session ended normally
    ERROR              - Error occurred (fatal or non-fatal)
    FALLBACK           - Cannot maintain stream, fall back to batch

Input Events (stdin ← QML):
    TOOL_RESULT        - Tool execution result
    STOP               - User requested session end
    BARGE_IN           - User interrupted playback
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from typing import Any

from voice_agent_backends.base import BaseVoiceBackend, VoiceAgentConfig


# ---------------------------------------------------------------------------
# JSON-line event helpers
# ---------------------------------------------------------------------------


def emit_event(event: dict[str, Any]) -> None:
    """Write a JSON-line event to stdout and flush immediately."""
    _ = sys.stdout.write(json.dumps(event) + "\n")
    sys.stdout.flush()


def emit_ready(backend: str, session_id: str = "") -> None:
    """Emit READY event indicating backend connection established."""
    emit_event({"type": "READY", "backend": backend, "session_id": session_id})


def emit_partial_transcript(text: str) -> None:
    """Emit PARTIAL_TRANSCRIPT with intermediate speech recognition."""
    emit_event({"type": "PARTIAL_TRANSCRIPT", "text": text})


def emit_turn_end() -> None:
    """Emit TURN_END indicating backend detected end of user speech."""
    emit_event({"type": "TURN_END"})


def emit_turn_complete(text: str) -> None:
    """Emit TURN_COMPLETE with finalized user utterance."""
    emit_event({"type": "TURN_COMPLETE", "text": text})


def emit_audio_response(audio_b64: str, text: str = "") -> None:
    """Emit AUDIO_RESPONSE with base64-encoded PCM audio."""
    event: dict[str, Any] = {"type": "AUDIO_RESPONSE", "audio": audio_b64}
    if text:
        event["text"] = text
    emit_event(event)


def emit_tool_call(call_id: str, name: str, arguments: str) -> None:
    """Emit TOOL_CALL requesting tool execution."""
    emit_event({
        "type": "TOOL_CALL",
        "id": call_id,
        "name": name,
        "arguments": arguments,
    })


def emit_session_end(reason: str = "user_stop") -> None:
    """Emit SESSION_END indicating session ended normally."""
    emit_event({"type": "SESSION_END", "reason": reason})


def emit_error(message: str, fatal: bool = False) -> None:
    """Emit ERROR event."""
    emit_event({"type": "ERROR", "message": message, "fatal": fatal})


def emit_fallback(reason: str) -> None:
    """Emit FALLBACK indicating stream cannot be maintained."""
    emit_event({"type": "FALLBACK", "reason": reason})


# ---------------------------------------------------------------------------
# Configuration (imported from voice_agent_backends.base, parse_args defined here)
# ---------------------------------------------------------------------------


def parse_args(argv: list[str] | None = None) -> VoiceAgentConfig:
    """Parse CLI arguments into a VoiceAgentConfig."""
    parser = argparse.ArgumentParser(
        description="Streaming voice agent helper process"
    )
    parser.add_argument(
        "--backend",
        required=True,
        choices=["nova-sonic", "openai-realtime"],
        help="Voice backend: nova-sonic or openai-realtime",
    )
    parser.add_argument(
        "--audio-fifo",
        required=True,
        help="Path to named FIFO for PCM audio input from pw-cat",
    )
    parser.add_argument(
        "--sample-rate",
        type=int,
        default=16000,
        choices=[16000, 24000],
        help="Audio sample rate in Hz (16000 for Nova Sonic, 24000 for OpenAI)",
    )
    parser.add_argument(
        "--region",
        default="",
        help="AWS region for Bedrock (nova-sonic backend)",
    )
    parser.add_argument(
        "--profile",
        default="",
        help="AWS profile for Bedrock (nova-sonic backend)",
    )
    parser.add_argument(
        "--api-key",
        default="",
        help="API key for OpenAI Realtime backend",
    )
    parser.add_argument(
        "--system-prompt",
        default="",
        help="System prompt text for the voice assistant",
    )
    parser.add_argument(
        "--context",
        default="",
        help="Path to session context JSON file",
    )
    parser.add_argument(
        "--tools",
        default="",
        help="Path to available tools definition JSON file",
    )

    args = parser.parse_args(argv)

    return VoiceAgentConfig(
        backend=args.backend,
        audio_fifo=args.audio_fifo,
        sample_rate=args.sample_rate,
        region=args.region,
        profile=args.profile,
        api_key=args.api_key,
        system_prompt=args.system_prompt,
        context=args.context,
        tools=args.tools,
    )


# ---------------------------------------------------------------------------
# Backend abstraction (imported from voice_agent_backends.base)
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Input event parsing
# ---------------------------------------------------------------------------


def parse_input_event(line: str) -> dict[str, Any] | None:
    """Parse a JSON-line input event from stdin.

    Returns the parsed dict if valid, or None if the line is empty or
    cannot be parsed as JSON.
    """
    line = line.strip()
    if not line:
        return None
    try:
        event: Any = json.loads(line)
        if isinstance(event, dict) and "type" in event:
            return event  # type: ignore[no-any-return]
        return None
    except (json.JSONDecodeError, ValueError):
        return None


# ---------------------------------------------------------------------------
# Async main loop
# ---------------------------------------------------------------------------

# Read buffer size — 4096 bytes ≈ 128ms at 16kHz/mono/s16
_AUDIO_READ_CHUNK_SIZE = 4096


async def _read_audio_fifo(fifo_path: str, backend: BaseVoiceBackend, stop_event: asyncio.Event) -> None:
    """Async task: read raw PCM from the named FIFO and forward to backend.

    Opens the FIFO for reading and continuously reads chunks of audio data,
    forwarding each to the backend. Stops when the stop_event is set or the
    FIFO is closed (EOF).
    """
    try:
        # Open FIFO — this will block until the writer (pw-cat) opens it
        fd = os.open(fifo_path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError as exc:
        emit_error(f"Failed to open audio FIFO: {exc}", fatal=True)
        stop_event.set()
        return

    loop = asyncio.get_event_loop()

    try:
        while not stop_event.is_set():
            try:
                data = await loop.run_in_executor(None, os.read, fd, _AUDIO_READ_CHUNK_SIZE)
            except OSError:
                break

            if not data:
                # EOF — writer closed the FIFO
                break

            try:
                await backend.send_audio(data)
            except Exception as exc:
                emit_error(f"Audio send failed: {exc}", fatal=True)
                stop_event.set()
                return
    finally:
        os.close(fd)


async def _read_stdin_events(backend: BaseVoiceBackend, stop_event: asyncio.Event) -> None:
    """Async task: read JSON-line control events from stdin.

    Handles TOOL_RESULT, STOP, and BARGE_IN events from the QML service.
    """
    loop = asyncio.get_event_loop()
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    _ = await loop.connect_read_pipe(lambda: protocol, sys.stdin)

    while not stop_event.is_set():
        try:
            line_bytes = await reader.readline()
        except Exception:
            break

        if not line_bytes:
            # EOF on stdin — QML closed the process
            stop_event.set()
            break

        line = line_bytes.decode("utf-8", errors="replace")
        event = parse_input_event(line)
        if event is None:
            continue

        event_type: str = event.get("type", "")

        if event_type == "STOP":
            stop_event.set()
            break

        elif event_type == "BARGE_IN":
            try:
                await backend.send_barge_in()
            except Exception as exc:
                print(f"[voice-agent] Barge-in send failed: {exc}", file=sys.stderr)

        elif event_type == "TOOL_RESULT":
            call_id: str = event.get("id", "")
            name: str = event.get("name", "")
            result: str = event.get("result", "")
            is_error: bool = event.get("is_error", False)
            try:
                await backend.send_tool_result(call_id, name, result, is_error)
            except Exception as exc:
                emit_error(f"Tool result send failed: {exc}", fatal=False)

        else:
            print(f"[voice-agent] Unknown input event type: {event_type}", file=sys.stderr)


async def run(config: VoiceAgentConfig) -> None:
    """Main async loop: connect backend, start audio/stdin readers, handle shutdown."""
    # Import backend implementations (deferred to avoid import errors when
    # optional dependencies are missing for the other backend)
    backend: BaseVoiceBackend

    if config.backend == "nova-sonic":
        try:
            from voice_agent_backends.nova_sonic import NovaSonicBackend  # type: ignore[import-not-found]
        except ImportError:
            emit_error("Nova Sonic backend not available (missing dependencies)", fatal=True)
            return
        backend = NovaSonicBackend(config)
    elif config.backend == "openai-realtime":
        try:
            from voice_agent_backends.openai_realtime import OpenAIRealtimeBackend  # type: ignore[import-not-found]
        except ImportError:
            emit_error("OpenAI Realtime backend not available (missing dependencies)", fatal=True)
            return
        backend = OpenAIRealtimeBackend(config)
    else:
        emit_error(f"Unknown backend: {config.backend}", fatal=True)
        return

    # Connect to backend
    try:
        await backend.connect()
    except Exception as exc:
        emit_error(f"Backend connection failed: {exc}", fatal=True)
        emit_fallback(f"Connection failed: {exc}")
        return

    # Emit READY — connection established
    emit_ready(config.backend)

    # Coordinate shutdown
    stop_event = asyncio.Event()

    # Launch concurrent tasks
    audio_task = asyncio.create_task(
        _read_audio_fifo(config.audio_fifo, backend, stop_event)
    )
    stdin_task = asyncio.create_task(
        _read_stdin_events(backend, stop_event)
    )

    # Wait for stop signal (from STOP event, EOF, or error)
    _ = await stop_event.wait()

    # Cancel tasks
    _ = audio_task.cancel()
    _ = stdin_task.cancel()
    for task in (audio_task, stdin_task):
        try:
            await task
        except asyncio.CancelledError:
            pass

    # Graceful disconnect
    try:
        await backend.disconnect()
    except Exception as exc:
        print(f"[voice-agent] Disconnect error: {exc}", file=sys.stderr)

    emit_session_end("user_stop")


def main() -> None:
    """Entry point: parse args and run the async main loop."""
    config = parse_args()

    try:
        asyncio.run(run(config))
    except KeyboardInterrupt:
        pass
    except Exception as exc:
        emit_error(f"Unhandled exception: {exc}", fatal=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
