#!/usr/bin/env python3
"""Streaming dictation helper process.

Reads raw PCM audio from stdin (piped from pw-cat --record) and dispatches
to the appropriate transport handler (WebSocket streaming or chunked HTTP).
Emits line-protocol messages on stdout for the QML Process component to parse.

Protocol (stdout → QML):
    READY:<mode>      - Transport established, mode confirmed
    PARTIAL:<text>    - Partial transcription update
    FINAL:<text>      - Final transcription result
    ERROR:<message>   - Error occurred
    FALLBACK:<reason> - Falling back to batch mode
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import os
import sys
import tempfile
import wave
import urllib.parse
from abc import ABC, abstractmethod
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


# ---------------------------------------------------------------------------
# Line protocol helpers
# ---------------------------------------------------------------------------


def emit(tag: str, payload: str) -> None:
    """Write a protocol line to stdout and flush immediately."""
    sys.stdout.write(f"{tag}:{payload}\n")
    sys.stdout.flush()


def emit_ready(mode: str) -> None:
    emit("READY", mode)


def emit_partial(text: str) -> None:
    emit("PARTIAL", text)


def emit_final(text: str) -> None:
    emit("FINAL", text)


def emit_error(message: str) -> None:
    emit("ERROR", message)


def emit_fallback(reason: str) -> None:
    emit("FALLBACK", reason)


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------


@dataclass
class StreamHelperConfig:
    """Configuration parsed from CLI arguments."""

    mode: str  # "streaming" or "chunked"
    endpoint: str  # WebSocket or HTTP URL
    api_key: str  # API key (empty for local)
    provider: str  # Provider name for protocol selection
    chunk_duration: int  # Chunk duration in ms (chunked mode)
    sample_rate: int  # Audio sample rate (16000)
    channels: int  # Audio channels (1)
    sample_format: str  # Sample format ("s16")
    policy_ai: int  # AI policy level (0, 1, or 2)


def parse_args(argv: list[str] | None = None) -> StreamHelperConfig:
    """Parse CLI arguments into a StreamHelperConfig."""
    parser = argparse.ArgumentParser(
        description="Streaming dictation helper process"
    )
    parser.add_argument(
        "--mode",
        required=True,
        choices=["streaming", "chunked"],
        help="Transport mode: streaming (WebSocket) or chunked (HTTP)",
    )
    parser.add_argument(
        "--endpoint",
        required=True,
        help="WebSocket or HTTP endpoint URL",
    )
    parser.add_argument(
        "--api-key",
        default="",
        help="API key for authentication (empty for local providers)",
    )
    parser.add_argument(
        "--provider",
        required=True,
        help="Provider name (e.g. openai, local-whisper, faster-whisper)",
    )
    parser.add_argument(
        "--chunk-duration",
        type=int,
        default=3000,
        help="Chunk duration in milliseconds (chunked mode, default: 3000)",
    )
    parser.add_argument(
        "--sample-rate",
        type=int,
        default=16000,
        help="Audio sample rate in Hz (default: 16000)",
    )
    parser.add_argument(
        "--channels",
        type=int,
        default=1,
        help="Number of audio channels (default: 1)",
    )
    parser.add_argument(
        "--sample-format",
        default="s16",
        help="PCM sample format (default: s16)",
    )
    parser.add_argument(
        "--policy-ai",
        type=int,
        default=1,
        choices=[0, 1, 2],
        help="AI policy level: 0=disabled, 1=allow all, 2=local only",
    )

    args = parser.parse_args(argv)

    return StreamHelperConfig(
        mode=args.mode,
        endpoint=args.endpoint,
        api_key=args.api_key,
        provider=args.provider,
        chunk_duration=args.chunk_duration,
        sample_rate=args.sample_rate,
        channels=args.channels,
        sample_format=args.sample_format,
        policy_ai=args.policy_ai,
    )


# ---------------------------------------------------------------------------
# Policy enforcement
# ---------------------------------------------------------------------------


def is_local_endpoint(endpoint: str) -> bool:
    """Check whether an endpoint URL points to a local address.

    Returns True if the hostname is localhost, 127.0.0.1, ::1, or in the
    127.x.x.x range. Returns False otherwise.
    """
    parsed = urllib.parse.urlparse(endpoint)
    hostname = parsed.hostname or ""
    hostname = hostname.lower()
    if hostname in {"localhost", "127.0.0.1", "::1"}:
        return True
    if hostname.startswith("127."):
        return True
    return False


def check_policy(config: StreamHelperConfig) -> None:
    """Enforce AI policy before establishing any transport.

    Raises SystemExit if policy disallows the configured operation.
    """
    if config.policy_ai == 0:
        emit_error("AI features disabled by policy")
        raise SystemExit(1)

    if config.policy_ai == 2:
        if not is_local_endpoint(config.endpoint):
            emit_error(
                "Online transcription disallowed by policy (local-only mode)"
            )
            raise SystemExit(1)


# ---------------------------------------------------------------------------
# Transport abstraction
# ---------------------------------------------------------------------------


class BaseTransport(ABC):
    """Abstract base class for audio transport handlers.

    Subclasses implement the actual WebSocket streaming or chunked HTTP
    transport logic. See tasks 2.2 and 2.3 for concrete implementations.
    """

    def __init__(self, config: StreamHelperConfig) -> None:
        self.config = config

    @abstractmethod
    async def start(self) -> None:
        """Establish the transport connection.

        Should emit READY on success, or raise on failure.
        """
        ...

    @abstractmethod
    async def feed_audio(self, data: bytes) -> None:
        """Forward a chunk of raw PCM audio data to the backend."""
        ...

    @abstractmethod
    async def finalize(self) -> None:
        """Signal end-of-stream and await the final transcription result.

        Should emit FINAL on success.
        """
        ...


# ---------------------------------------------------------------------------
# WebSocket streaming transport
# ---------------------------------------------------------------------------


class StreamingTransport(BaseTransport):
    """WebSocket-based streaming transport.

    Supports two protocols:
    - OpenAI Realtime API: base64-encoded PCM in JSON frames
    - Local providers (whisper-streaming, etc.): raw binary PCM frames
    """

    _CONNECTION_TIMEOUT = 3.0  # seconds
    _RECONNECT_TIMEOUT = 2.0  # seconds

    def __init__(self, config: StreamHelperConfig) -> None:
        super().__init__(config)
        self._ws: object | None = None  # websockets connection
        self._receive_task: asyncio.Task | None = None
        self._final_event: asyncio.Event = asyncio.Event()
        self._final_text: str = ""
        self._partial_text: str = ""
        self._connected: bool = False

    @property
    def _is_openai(self) -> bool:
        return self.config.provider == "openai"

    def _build_headers(self) -> dict[str, str]:
        """Build connection headers (OpenAI requires auth + beta header)."""
        if self._is_openai and self.config.api_key:
            return {
                "Authorization": f"Bearer {self.config.api_key}",
                "OpenAI-Beta": "realtime=v1",
            }
        return {}

    async def _connect(self) -> None:
        """Open WebSocket connection with timeout."""
        import websockets

        headers = self._build_headers()
        try:
            self._ws = await asyncio.wait_for(
                websockets.connect(
                    self.config.endpoint,
                    additional_headers=headers if headers else None,
                ),
                timeout=self._CONNECTION_TIMEOUT,
            )
            self._connected = True
        except (
            TimeoutError,
            asyncio.TimeoutError,
            ConnectionRefusedError,
            OSError,
        ) as exc:
            self._connected = False
            raise ConnectionError(
                f"WebSocket connection failed: {exc}"
            ) from exc
        except Exception as exc:
            self._connected = False
            raise ConnectionError(
                f"WebSocket connection failed: {exc}"
            ) from exc

    async def _reconnect(self) -> bool:
        """Attempt one reconnection within the reconnect timeout.

        Returns True if reconnection succeeded, False otherwise.
        """
        try:
            await asyncio.wait_for(
                self._connect(), timeout=self._RECONNECT_TIMEOUT
            )
            # Restart the receive task
            self._receive_task = asyncio.create_task(self._receive_loop())
            return True
        except (ConnectionError, TimeoutError, asyncio.TimeoutError):
            return False

    async def start(self) -> None:
        """Establish WebSocket connection and start receiving messages."""
        await self._connect()

        # Start background task to receive messages
        self._receive_task = asyncio.create_task(self._receive_loop())
        emit_ready("streaming")

    async def feed_audio(self, data: bytes) -> None:
        """Forward audio data to the backend."""
        if not self._connected or self._ws is None:
            return

        try:
            if self._is_openai:
                # OpenAI: base64-encode PCM, wrap in JSON
                encoded = base64.b64encode(data).decode("ascii")
                msg = json.dumps(
                    {"type": "input_audio_buffer.append", "audio": encoded}
                )
                await self._ws.send(msg)
            else:
                # Local providers: send raw PCM binary frames
                await self._ws.send(data)
        except Exception:
            # Connection likely dropped — attempt reconnect
            self._connected = False
            if not await self._reconnect():
                emit_fallback("Connection dropped, reconnection failed")
                raise ConnectionError("WebSocket send failed after reconnect")

    async def finalize(self) -> None:
        """Signal end-of-stream and await final transcription result."""
        if not self._connected or self._ws is None:
            return

        try:
            if self._is_openai:
                # Send commit to signal end of audio
                await self._ws.send(
                    json.dumps({"type": "input_audio_buffer.commit"})
                )
                # Request a text response
                await self._ws.send(
                    json.dumps(
                        {
                            "type": "response.create",
                            "response": {"modalities": ["text"]},
                        }
                    )
                )
            else:
                # Local: send empty frame to signal EOF
                await self._ws.send(b"")
        except Exception:
            # If we can't send finalize, emit what we have
            if self._partial_text:
                emit_final(self._partial_text)
            return

        # Wait for the final result from the receive loop
        try:
            await asyncio.wait_for(self._final_event.wait(), timeout=10.0)
            emit_final(self._final_text)
        except asyncio.TimeoutError:
            # If we timeout waiting for final, use accumulated partial
            if self._partial_text:
                emit_final(self._partial_text)
            else:
                emit_error("Timeout waiting for final transcription")
        finally:
            await self._close()

    async def _close(self) -> None:
        """Close the WebSocket connection and cancel receive task."""
        self._connected = False
        if self._receive_task and not self._receive_task.done():
            self._receive_task.cancel()
            try:
                await self._receive_task
            except asyncio.CancelledError:
                pass
        if self._ws is not None:
            try:
                await self._ws.close()
            except Exception:
                pass
            self._ws = None

    async def _receive_loop(self) -> None:
        """Background task: receive messages from the WebSocket."""
        import websockets.exceptions

        try:
            async for message in self._ws:
                if self._is_openai:
                    self._handle_openai_message(message)
                else:
                    self._handle_local_message(message)
        except websockets.exceptions.ConnectionClosed:
            # Connection dropped
            if not self._final_event.is_set():
                # Attempt reconnect
                self._connected = False
                if not await self._reconnect():
                    emit_fallback("Connection closed, reconnection failed")
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            if not self._final_event.is_set():
                emit_error(f"Receive error: {exc}")

    def _handle_openai_message(self, message: str) -> None:
        """Parse OpenAI Realtime API events."""
        try:
            data = json.loads(message)
        except json.JSONDecodeError:
            return

        event_type = data.get("type", "")

        if event_type == "response.audio_transcript.delta":
            # Partial transcription update — accumulate delta
            delta = data.get("delta", "")
            self._partial_text += delta
            emit_partial(self._partial_text)

        elif event_type == "response.audio_transcript.done":
            # Final transcription for this response
            transcript = data.get("transcript", self._partial_text)
            self._final_text = transcript
            self._final_event.set()

        elif event_type == "response.done":
            # Response completed — if we haven't got a transcript.done,
            # use what we have
            if not self._final_event.is_set():
                self._final_text = self._partial_text
                self._final_event.set()

        elif event_type == "error":
            error_msg = data.get("error", {}).get("message", "Unknown error")
            emit_error(f"OpenAI error: {error_msg}")

    def _handle_local_message(self, message: str | bytes) -> None:
        """Parse local whisper-streaming server messages.

        Protocol for local servers:
        - Text frames are partial results (plain text)
        - A frame prefixed with "FINAL:" signals the final result
        """
        if isinstance(message, bytes):
            text = message.decode("utf-8", errors="replace")
        else:
            text = message

        if text.startswith("FINAL:"):
            self._final_text = text[6:]  # strip "FINAL:" prefix
            self._final_event.set()
            emit_final(self._final_text)
        else:
            self._partial_text = text
            emit_partial(text)


# ---------------------------------------------------------------------------
# Chunked HTTP transport
# ---------------------------------------------------------------------------


def _bytes_per_sample(sample_format: str) -> int:
    """Return bytes per sample for the given PCM format string."""
    if sample_format == "s16":
        return 2
    elif sample_format == "s32":
        return 4
    elif sample_format == "f32":
        return 4
    # Default to 2 bytes (16-bit) if unknown
    return 2


def _write_wav(pcm_data: bytes, sample_rate: int, channels: int, sample_width: int) -> str:
    """Write PCM data to a temporary WAV file and return the file path."""
    fd, path = tempfile.mkstemp(suffix=".wav")
    try:
        with wave.open(path, "wb") as wf:
            wf.setnchannels(channels)
            wf.setsampwidth(sample_width)
            wf.setframerate(sample_rate)
            wf.writeframes(pcm_data)
    except Exception:
        os.close(fd)
        raise
    else:
        os.close(fd)
    return path


def _build_multipart(file_path: str, model: str, api_key: str) -> tuple[bytes, str]:
    """Build multipart/form-data body for audio transcription upload.

    Returns (body_bytes, content_type_header).
    """
    boundary = "----DictationChunkBoundary"
    parts: list[bytes] = []

    # File field
    with open(file_path, "rb") as f:
        file_data = f.read()

    parts.append(f"--{boundary}\r\n".encode())
    parts.append(
        b'Content-Disposition: form-data; name="file"; filename="audio.wav"\r\n'
    )
    parts.append(b"Content-Type: audio/wav\r\n\r\n")
    parts.append(file_data)
    parts.append(b"\r\n")

    # Model field (if provided)
    if model:
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(b'Content-Disposition: form-data; name="model"\r\n\r\n')
        parts.append(model.encode())
        parts.append(b"\r\n")

    # Closing boundary
    parts.append(f"--{boundary}--\r\n".encode())

    body = b"".join(parts)
    content_type = f"multipart/form-data; boundary={boundary}"
    return body, content_type


def _submit_chunk(
    file_path: str, endpoint: str, api_key: str, provider: str
) -> str | None:
    """Submit a WAV chunk file via HTTP POST and return transcription text.

    Returns the transcription text on success, or None on failure.
    """
    # Determine model name based on provider
    model = ""
    if provider == "openai":
        model = "whisper-1"
    elif provider in ("faster-whisper", "whisper-cpp", "local-whisper"):
        model = "whisper-1"  # Local endpoints often accept any model name

    body, content_type = _build_multipart(file_path, model, api_key)

    headers = {"Content-Type": content_type}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    req = Request(endpoint, data=body, headers=headers, method="POST")

    try:
        with urlopen(req, timeout=30) as resp:
            resp_data = json.loads(resp.read().decode("utf-8"))
            # OpenAI-compatible response format: {"text": "..."}
            return resp_data.get("text", "")
    except (HTTPError, URLError, json.JSONDecodeError, OSError) as exc:
        print(f"Chunk submission failed: {exc}", file=sys.stderr)
        return None


class ChunkedTransport(BaseTransport):
    """Chunked HTTP transport — buffers audio and POSTs WAV chunks.

    Segments the incoming audio stream into time-bounded chunks, writes each
    to a temporary WAV file, and submits via HTTP POST. Results are accumulated
    and emitted as PARTIAL lines. On finalize, emits FINAL with concatenated
    results or FALLBACK if all chunks failed.
    """

    def __init__(self, config: StreamHelperConfig) -> None:
        super().__init__(config)
        bps = _bytes_per_sample(config.sample_format)
        self._chunk_bytes = int(
            config.sample_rate * config.channels * bps * (config.chunk_duration / 1000)
        )
        self._sample_width = bps
        self._buffer = bytearray()
        self._results: list[str] = []
        self._chunks_submitted = 0
        self._chunks_failed = 0

    async def start(self) -> None:
        """Emit READY for chunked mode. No upfront connection needed."""
        emit_ready("chunked")

    async def feed_audio(self, data: bytes) -> None:
        """Buffer audio data and submit complete chunks."""
        self._buffer.extend(data)

        while len(self._buffer) >= self._chunk_bytes:
            chunk_data = bytes(self._buffer[: self._chunk_bytes])
            del self._buffer[: self._chunk_bytes]
            await self._submit_chunk(chunk_data, is_final=False)

    async def finalize(self) -> None:
        """Submit remaining audio and emit FINAL or FALLBACK."""
        # Submit any remaining buffered audio as the final chunk
        if self._buffer:
            remaining = bytes(self._buffer)
            self._buffer.clear()
            await self._submit_chunk(remaining, is_final=True)

        # Determine final output
        if self._results:
            final_text = " ".join(self._results)
            emit_final(final_text)
        else:
            # All chunks failed — no results at all
            emit_fallback("All chunk transcriptions failed")

    async def _submit_chunk(self, pcm_data: bytes, is_final: bool) -> None:
        """Write a PCM chunk to WAV, POST it, handle the result."""
        wav_path: str | None = None
        try:
            wav_path = _write_wav(
                pcm_data,
                self.config.sample_rate,
                self.config.channels,
                self._sample_width,
            )

            # Run the blocking HTTP request in a thread to avoid blocking the loop
            text = await asyncio.to_thread(
                _submit_chunk,
                wav_path,
                self.config.endpoint,
                self.config.api_key,
                self.config.provider,
            )

            self._chunks_submitted += 1

            if text is not None:
                self._results.append(text)
                # Emit partial with accumulated text so far
                accumulated = " ".join(self._results)
                emit_partial(accumulated)
            else:
                # Chunk failed — skip and continue
                self._chunks_failed += 1
                print(
                    f"Chunk {self._chunks_submitted} failed, skipping",
                    file=sys.stderr,
                )
        finally:
            # Clean up temporary WAV file
            if wav_path and os.path.exists(wav_path):
                try:
                    os.unlink(wav_path)
                except OSError:
                    pass


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

# Read buffer size — 4096 bytes ≈ 128ms of audio at 16kHz/mono/s16
_READ_CHUNK_SIZE = 4096

# Timeout for streaming connection probe (seconds)
_STREAMING_PROBE_TIMEOUT = 3.0


def _create_transport(config: StreamHelperConfig) -> BaseTransport:
    """Create the appropriate transport for the configured mode."""
    if config.mode == "streaming":
        return StreamingTransport(config)
    elif config.mode == "chunked":
        return ChunkedTransport(config)
    else:
        raise ValueError(f"Unknown mode: {config.mode}")


# Exceptions treated as connection failures during probing
_CONNECTION_ERRORS: tuple[type[BaseException], ...] = (
    ConnectionRefusedError,
    TimeoutError,
    OSError,
    ConnectionError,
)

try:
    import websockets.exceptions as _ws_exc

    _WS_ERRORS: tuple[type[BaseException], ...] = (
        _ws_exc.WebSocketException,
    )
except ImportError:
    _WS_ERRORS: tuple[type[BaseException], ...] = ()


async def probe_and_start(config: StreamHelperConfig) -> BaseTransport:
    """Probe transport availability and start with fallback cascade.

    If mode is "streaming":
      1. Try to create and start a StreamingTransport within 3 seconds.
      2. If that fails, try ChunkedTransport as fallback.
      3. If chunked also fails, emit FALLBACK and raise.

    If mode is "chunked":
      1. Try to create and start a ChunkedTransport.
      2. If that fails, emit FALLBACK and raise.

    Returns the successfully started transport. The transport's start() method
    is responsible for emitting READY:<mode>.
    """
    catchable = _CONNECTION_ERRORS + _WS_ERRORS

    if config.mode == "streaming":
        # --- Attempt streaming ---
        try:
            transport = _create_transport(config)
            await asyncio.wait_for(
                transport.start(), timeout=_STREAMING_PROBE_TIMEOUT
            )
            return transport
        except catchable as exc:
            print(
                f"[dictation-stream] Streaming connection failed: {exc}",
                file=sys.stderr,
            )
        except asyncio.TimeoutError:
            print(
                "[dictation-stream] Streaming connection timed out "
                f"({_STREAMING_PROBE_TIMEOUT}s)",
                file=sys.stderr,
            )
        except NotImplementedError as exc:
            print(
                f"[dictation-stream] Streaming not available: {exc}",
                file=sys.stderr,
            )

        # --- Attempt chunked fallback ---
        print(
            "[dictation-stream] Falling back to chunked mode",
            file=sys.stderr,
        )
        chunked_config = StreamHelperConfig(
            mode="chunked",
            endpoint=config.endpoint,
            api_key=config.api_key,
            provider=config.provider,
            chunk_duration=config.chunk_duration,
            sample_rate=config.sample_rate,
            channels=config.channels,
            sample_format=config.sample_format,
            policy_ai=config.policy_ai,
        )
        try:
            transport = _create_transport(chunked_config)
            await transport.start()
            return transport
        except (*catchable, NotImplementedError, asyncio.TimeoutError) as exc:
            reason = (
                f"Neither streaming nor chunked transport available: {exc}"
            )
            print(f"[dictation-stream] {reason}", file=sys.stderr)
            emit_fallback(reason)
            raise RuntimeError(reason) from exc

    elif config.mode == "chunked":
        # --- Attempt chunked directly ---
        try:
            transport = _create_transport(config)
            await transport.start()
            return transport
        except (*catchable, NotImplementedError, asyncio.TimeoutError) as exc:
            reason = f"Chunked transport unavailable: {exc}"
            print(f"[dictation-stream] {reason}", file=sys.stderr)
            emit_fallback(reason)
            raise RuntimeError(reason) from exc

    else:
        raise ValueError(f"Unknown mode: {config.mode}")


async def run(config: StreamHelperConfig) -> None:
    """Main async loop: probe transport, feed audio from stdin, finalize."""
    transport = await probe_and_start(config)

    # Read raw PCM from stdin and feed to transport
    loop = asyncio.get_event_loop()
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin.buffer)

    try:
        while True:
            data = await reader.read(_READ_CHUNK_SIZE)
            if not data:
                break
            await transport.feed_audio(data)
    except ConnectionError:
        # Connection lost and reconnect failed — FALLBACK already emitted
        return

    # Signal end-of-stream
    await transport.finalize()


def main() -> None:
    """Entry point: parse args, enforce policy, run the async main loop."""
    config = parse_args()
    check_policy(config)

    try:
        asyncio.run(run(config))
    except RuntimeError as exc:
        # probe_and_start emits FALLBACK before raising RuntimeError
        print(f"[dictation-stream] Exiting: {exc}", file=sys.stderr)
        sys.exit(1)
    except NotImplementedError as exc:
        emit_error(str(exc))
        sys.exit(1)
    except KeyboardInterrupt:
        pass
    except Exception as exc:
        emit_error(f"Unhandled exception: {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()
