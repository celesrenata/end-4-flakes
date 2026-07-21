"""Integration tests for the streaming dictation helper process.

Tests the full flow including:
- WebSocket streaming with a mock server
- Chunked HTTP with a mock endpoint
- Fallback behavior on connection failure
- Policy enforcement
- Helper protocol output (READY/PARTIAL/FINAL/ERROR/FALLBACK)

Validates: Requirements 2.1–2.6, 3.1–3.6, 9.1–9.4
"""

import asyncio
import json
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

SCRIPT_DIR = Path(__file__).parent.parent / "configs" / "quickshell" / "ii" / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))
from importlib import import_module

_mod = import_module("dictation-stream")
StreamHelperConfig = _mod.StreamHelperConfig
StreamingTransport = _mod.StreamingTransport
ChunkedTransport = _mod.ChunkedTransport
check_policy = _mod.check_policy
probe_and_start = _mod.probe_and_start


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_config(
    mode: str = "streaming",
    endpoint: str = "ws://localhost:8765",
    provider: str = "local-whisper",
    api_key: str = "",
    chunk_duration: int = 3000,
    policy_ai: int = 1,
) -> StreamHelperConfig:
    return StreamHelperConfig(
        mode=mode,
        endpoint=endpoint,
        api_key=api_key,
        provider=provider,
        chunk_duration=chunk_duration,
        sample_rate=16000,
        channels=1,
        sample_format="s16",
        policy_ai=policy_ai,
    )


# ---------------------------------------------------------------------------
# Test: Full WebSocket streaming flow
# ---------------------------------------------------------------------------


class TestStreamingFlowConnectSendReceiveFinalize:
    """Test complete WebSocket streaming flow: connect → send frames → receive partials → finalize."""

    def test_local_provider_full_flow(self):
        """Connect to a mock local WS server, send audio, receive PARTIAL/FINAL."""

        async def _run():
            import websockets

            received_frames: list[bytes] = []

            async def ws_handler(ws):
                frame_count = 0
                async for message in ws:
                    if isinstance(message, bytes):
                        received_frames.append(message)
                        frame_count += 1
                        if len(message) == 0:
                            # EOF signal — send final
                            await ws.send("FINAL:hello world")
                            break
                        else:
                            await ws.send(f"partial {frame_count}")

            server = await websockets.serve(ws_handler, "127.0.0.1", 0)
            port = server.sockets[0].getsockname()[1]

            try:
                config = _make_config(
                    mode="streaming",
                    endpoint=f"ws://127.0.0.1:{port}",
                    provider="local-whisper",
                )
                transport = StreamingTransport(config)

                with patch.object(_mod, "emit_ready") as mock_ready, \
                     patch.object(_mod, "emit_partial") as mock_partial, \
                     patch.object(_mod, "emit_final") as mock_final:

                    await transport.start()
                    mock_ready.assert_called_once_with("streaming")

                    # Send some audio frames
                    for i in range(3):
                        await transport.feed_audio(b"\x00\x01" * 100)
                        await asyncio.sleep(0.05)

                    # Finalize — sends empty frame to signal EOF
                    await transport.finalize()

                    # Verify partials were emitted
                    assert mock_partial.call_count >= 1
                    # Verify final was emitted (may be called from both
                    # _handle_local_message and finalize method)
                    assert mock_final.call_count >= 1
                    assert mock_final.call_args[0][0] == "hello world"

                # Verify server received frames
                assert len(received_frames) >= 3
            finally:
                server.close()
                await server.wait_closed()

        asyncio.run(_run())

    def test_openai_provider_base64_encoding(self):
        """OpenAI mode sends base64-encoded JSON frames."""

        async def _run():
            import websockets
            import base64

            received_messages: list[str] = []

            async def ws_handler(ws):
                async for message in ws:
                    received_messages.append(message)
                    data = json.loads(message)
                    if data.get("type") == "input_audio_buffer.append":
                        await ws.send(json.dumps({
                            "type": "response.audio_transcript.delta",
                            "delta": "hi "
                        }))
                    elif data.get("type") == "response.create":
                        await ws.send(json.dumps({
                            "type": "response.audio_transcript.done",
                            "transcript": "hi there"
                        }))
                        break

            server = await websockets.serve(ws_handler, "127.0.0.1", 0)
            port = server.sockets[0].getsockname()[1]

            try:
                config = _make_config(
                    mode="streaming",
                    endpoint=f"ws://127.0.0.1:{port}",
                    provider="openai",
                    api_key="test-key",
                )
                transport = StreamingTransport(config)

                with patch.object(_mod, "emit_ready"), \
                     patch.object(_mod, "emit_partial") as mock_partial, \
                     patch.object(_mod, "emit_final") as mock_final:

                    await transport.start()

                    # Send audio
                    audio_frame = b"\x00\x01\x02\x03" * 50
                    await transport.feed_audio(audio_frame)
                    await asyncio.sleep(0.1)

                    await transport.finalize()

                    # Verify the frame was base64 encoded in JSON
                    assert len(received_messages) >= 1
                    first_msg = json.loads(received_messages[0])
                    assert first_msg["type"] == "input_audio_buffer.append"
                    decoded = base64.b64decode(first_msg["audio"])
                    assert decoded == audio_frame

                    # Verify final emitted
                    mock_final.assert_called_once_with("hi there")
            finally:
                server.close()
                await server.wait_closed()

        asyncio.run(_run())


# ---------------------------------------------------------------------------
# Test: Chunked HTTP flow
# ---------------------------------------------------------------------------


class TestChunkedFlowSubmitChunksAccumulate:
    """Test chunked transport with mocked HTTP submissions."""

    def test_chunks_submitted_at_interval(self):
        """Verify chunks are submitted when buffer fills, and partials are emitted."""

        async def _run():
            config = _make_config(
                mode="chunked",
                endpoint="http://localhost:9999/v1/audio/transcriptions",
                provider="openai",
                api_key="test-key",
                chunk_duration=500,  # 500ms chunks
            )
            transport = ChunkedTransport(config)

            chunk_count = 0

            async def mock_submit(pcm_data: bytes, is_final: bool) -> None:
                nonlocal chunk_count
                chunk_count += 1
                transport._results.append(f"chunk{chunk_count}")
                _mod.emit_partial(" ".join(transport._results))

            with patch.object(transport, "_submit_chunk", side_effect=mock_submit), \
                 patch.object(_mod, "emit_ready") as mock_ready, \
                 patch.object(_mod, "emit_partial") as mock_partial, \
                 patch.object(_mod, "emit_final") as mock_final:

                await transport.start()
                mock_ready.assert_called_once_with("chunked")

                # 500ms at 16kHz mono s16 = 16000 bytes per chunk
                chunk_bytes = 16000
                audio_block = b"\x00\x01" * (chunk_bytes // 2)

                # Feed 2.5 chunks worth
                await transport.feed_audio(audio_block)
                await transport.feed_audio(audio_block)
                await transport.feed_audio(b"\x00" * (chunk_bytes // 2))

                # At this point 2 full chunks should have been submitted
                assert chunk_count == 2

                # Finalize submits the remaining buffer
                await transport.finalize()
                assert chunk_count == 3

                # Final should have been emitted with concatenated text
                mock_final.assert_called_once_with("chunk1 chunk2 chunk3")

        asyncio.run(_run())

    def test_final_concatenation(self):
        """Verify final result is concatenation of all chunk results."""

        async def _run():
            config = _make_config(
                mode="chunked",
                endpoint="http://localhost:9999/v1/audio/transcriptions",
                provider="local-whisper",
                chunk_duration=1000,
            )
            transport = ChunkedTransport(config)

            call_idx = 0
            results = ["Hello", "world", "foo"]

            async def mock_submit(pcm_data: bytes, is_final: bool) -> None:
                nonlocal call_idx
                if call_idx < len(results):
                    transport._results.append(results[call_idx])
                    call_idx += 1

            with patch.object(transport, "_submit_chunk", side_effect=mock_submit), \
                 patch.object(_mod, "emit_ready"), \
                 patch.object(_mod, "emit_final") as mock_final:

                await transport.start()

                # Feed 3 full chunks (1000ms at 16kHz s16 mono = 32000 bytes)
                chunk_bytes = 32000
                for _ in range(3):
                    await transport.feed_audio(b"\x00" * chunk_bytes)

                await transport.finalize()
                mock_final.assert_called_once_with("Hello world foo")

        asyncio.run(_run())


# ---------------------------------------------------------------------------
# Test: Fallback on connection failure
# ---------------------------------------------------------------------------


class TestFallbackOnConnectionFailure:
    """Test that streaming transport emits FALLBACK on connection failure."""

    def test_unreachable_endpoint_triggers_connection_error(self):
        """StreamingTransport connecting to non-existent endpoint raises ConnectionError."""

        async def _run():
            config = _make_config(
                mode="streaming",
                endpoint="ws://127.0.0.1:1",  # Port 1 — nothing listening
                provider="local-whisper",
            )
            transport = StreamingTransport(config)

            with pytest.raises(ConnectionError):
                await transport.start()

        asyncio.run(_run())

    def test_probe_and_start_fallback_to_chunked(self):
        """probe_and_start falls back to chunked when streaming fails."""

        async def _run():
            config = _make_config(
                mode="streaming",
                endpoint="ws://127.0.0.1:1",
                provider="local-whisper",
            )

            with patch.object(_mod, "emit_fallback") as mock_fallback, \
                 patch.object(_mod, "emit_ready") as mock_ready:
                transport = await probe_and_start(config)
                # Should have fallen back to chunked successfully
                mock_ready.assert_called_with("chunked")
                # FALLBACK should NOT be emitted since chunked worked
                mock_fallback.assert_not_called()

        asyncio.run(_run())

    def test_streaming_connection_timeout_within_bounds(self):
        """Verify that connection timeout is enforced (< 5 seconds total)."""

        async def _run():
            import time

            config = _make_config(
                mode="streaming",
                # Use a non-routable address to trigger timeout
                endpoint="ws://192.0.2.1:9999",
                provider="local-whisper",
            )
            transport = StreamingTransport(config)

            start = time.monotonic()
            with pytest.raises(ConnectionError):
                await transport.start()
            elapsed = time.monotonic() - start

            # Should timeout within the configured 3 second window (+ small overhead)
            assert elapsed < 5.0

        asyncio.run(_run())


# ---------------------------------------------------------------------------
# Test: Policy enforcement
# ---------------------------------------------------------------------------


class TestPolicyBlocksRemoteStreaming:
    """Test that check_policy raises SystemExit when policy_ai=2 and endpoint is remote."""

    def test_policy_2_blocks_remote_endpoint(self):
        """Remote endpoint with policy_ai=2 should raise SystemExit."""
        config = _make_config(
            endpoint="wss://api.openai.com/v1/realtime",
            policy_ai=2,
            provider="openai",
        )

        with patch.object(_mod, "emit_error") as mock_error:
            with pytest.raises(SystemExit) as exc_info:
                check_policy(config)
            assert exc_info.value.code == 1
            mock_error.assert_called_once()
            assert "disallowed" in mock_error.call_args[0][0].lower() or \
                   "policy" in mock_error.call_args[0][0].lower()

    def test_policy_2_allows_local_endpoint(self):
        """Local endpoint with policy_ai=2 should pass without error."""
        config = _make_config(
            endpoint="ws://localhost:8765",
            policy_ai=2,
            provider="local-whisper",
        )
        # Should not raise
        check_policy(config)

    def test_policy_2_allows_127_endpoint(self):
        """127.0.0.1 endpoint with policy_ai=2 should pass."""
        config = _make_config(
            endpoint="ws://127.0.0.1:8765",
            policy_ai=2,
            provider="faster-whisper",
        )
        check_policy(config)

    def test_policy_0_blocks_all(self):
        """policy_ai=0 blocks activation regardless of endpoint."""
        config = _make_config(
            endpoint="ws://localhost:8765",
            policy_ai=0,
            provider="local-whisper",
        )

        with patch.object(_mod, "emit_error"):
            with pytest.raises(SystemExit) as exc_info:
                check_policy(config)
            assert exc_info.value.code == 1

    def test_policy_1_allows_remote(self):
        """policy_ai=1 allows remote endpoints."""
        config = _make_config(
            endpoint="wss://api.openai.com/v1/realtime",
            policy_ai=1,
            provider="openai",
        )
        # Should not raise
        check_policy(config)


# ---------------------------------------------------------------------------
# Test: Protocol output — READY
# ---------------------------------------------------------------------------


class TestProtocolOutputReady:
    """Verify READY:<mode> is emitted on transport start."""

    def test_streaming_ready(self):
        """StreamingTransport emits READY:streaming on successful start."""

        async def _run():
            import websockets

            async def ws_handler(ws):
                async for msg in ws:
                    pass

            server = await websockets.serve(ws_handler, "127.0.0.1", 0)
            port = server.sockets[0].getsockname()[1]

            try:
                config = _make_config(
                    mode="streaming",
                    endpoint=f"ws://127.0.0.1:{port}",
                )
                transport = StreamingTransport(config)

                with patch.object(_mod, "emit_ready") as mock_ready:
                    await transport.start()
                    mock_ready.assert_called_once_with("streaming")

                await transport._close()
            finally:
                server.close()
                await server.wait_closed()

        asyncio.run(_run())

    def test_chunked_ready(self):
        """ChunkedTransport emits READY:chunked on start."""

        async def _run():
            config = _make_config(mode="chunked")
            transport = ChunkedTransport(config)

            with patch.object(_mod, "emit_ready") as mock_ready:
                await transport.start()
                mock_ready.assert_called_once_with("chunked")

        asyncio.run(_run())


# ---------------------------------------------------------------------------
# Test: Protocol output — PARTIAL
# ---------------------------------------------------------------------------


class TestProtocolOutputPartial:
    """Verify PARTIAL:<text> emissions during audio processing."""

    def test_chunked_emits_partial_on_chunk_result(self):
        """ChunkedTransport emits PARTIAL with accumulated text after each chunk."""

        async def _run():
            config = _make_config(
                mode="chunked",
                endpoint="http://localhost:9999/v1/audio/transcriptions",
                provider="openai",
                api_key="key",
                chunk_duration=500,
            )
            transport = ChunkedTransport(config)

            call_idx = 0
            texts = ["Hello", "world"]

            async def mock_submit(pcm_data: bytes, is_final: bool) -> None:
                nonlocal call_idx
                if call_idx < len(texts):
                    transport._results.append(texts[call_idx])
                    _mod.emit_partial(" ".join(transport._results))
                    call_idx += 1

            with patch.object(transport, "_submit_chunk", side_effect=mock_submit), \
                 patch.object(_mod, "emit_ready"), \
                 patch.object(_mod, "emit_partial") as mock_partial, \
                 patch.object(_mod, "emit_final"):

                await transport.start()

                # Feed 2 full chunks (500ms at 16kHz s16 mono = 16000 bytes)
                chunk_bytes = 16000
                await transport.feed_audio(b"\x00" * chunk_bytes)
                await transport.feed_audio(b"\x00" * chunk_bytes)

                await transport.finalize()

                # Should have emitted partials
                calls = mock_partial.call_args_list
                assert len(calls) >= 2
                assert calls[0][0][0] == "Hello"
                assert calls[1][0][0] == "Hello world"

        asyncio.run(_run())


# ---------------------------------------------------------------------------
# Test: Protocol output — FINAL
# ---------------------------------------------------------------------------


class TestProtocolOutputFinal:
    """Verify FINAL:<text> is emitted on session completion."""

    def test_chunked_final_on_complete(self):
        """ChunkedTransport emits FINAL with full concatenated text."""

        async def _run():
            config = _make_config(
                mode="chunked",
                endpoint="http://localhost:9999/v1/audio/transcriptions",
                chunk_duration=1000,
            )
            transport = ChunkedTransport(config)

            async def mock_submit(pcm_data: bytes, is_final: bool) -> None:
                transport._results.append("word")

            with patch.object(transport, "_submit_chunk", side_effect=mock_submit), \
                 patch.object(_mod, "emit_ready"), \
                 patch.object(_mod, "emit_partial"), \
                 patch.object(_mod, "emit_final") as mock_final:

                await transport.start()

                # Feed 2 full chunks + partial remainder
                # (1000ms at 16kHz s16 mono = 32000 bytes per chunk)
                chunk_bytes = 32000
                await transport.feed_audio(b"\x00" * chunk_bytes)
                await transport.feed_audio(b"\x00" * chunk_bytes)
                # Add a partial chunk so finalize has something to submit
                await transport.feed_audio(b"\x00" * 8000)

                await transport.finalize()
                mock_final.assert_called_once_with("word word word")

        asyncio.run(_run())

    def test_streaming_final_from_ws(self):
        """StreamingTransport emits FINAL from WebSocket server response."""

        async def _run():
            import websockets

            async def ws_handler(ws):
                async for msg in ws:
                    if isinstance(msg, bytes) and len(msg) == 0:
                        await ws.send("FINAL:test transcription result")
                        break

            server = await websockets.serve(ws_handler, "127.0.0.1", 0)
            port = server.sockets[0].getsockname()[1]

            try:
                config = _make_config(
                    mode="streaming",
                    endpoint=f"ws://127.0.0.1:{port}",
                    provider="local-whisper",
                )
                transport = StreamingTransport(config)

                with patch.object(_mod, "emit_ready"), \
                     patch.object(_mod, "emit_final") as mock_final:
                    await transport.start()
                    await transport.feed_audio(b"\x01\x02" * 50)
                    await asyncio.sleep(0.05)
                    await transport.finalize()

                    # emit_final may be called from both _handle_local_message
                    # and finalize() — verify it was called with correct text
                    assert mock_final.call_count >= 1
                    assert mock_final.call_args[0][0] == "test transcription result"
            finally:
                server.close()
                await server.wait_closed()

        asyncio.run(_run())


# ---------------------------------------------------------------------------
# Test: Protocol output — ERROR
# ---------------------------------------------------------------------------


class TestProtocolOutputError:
    """Verify ERROR:<message> is emitted on error conditions."""

    def test_policy_violation_emits_error(self):
        """Policy violation emits ERROR before raising SystemExit."""
        config = _make_config(
            endpoint="wss://api.openai.com/v1/realtime",
            policy_ai=2,
            provider="openai",
        )

        with patch.object(_mod, "emit_error") as mock_error:
            with pytest.raises(SystemExit):
                check_policy(config)
            mock_error.assert_called_once()
            msg = mock_error.call_args[0][0]
            assert "disallowed" in msg.lower() or "policy" in msg.lower()

    def test_openai_error_event_emits_error(self):
        """OpenAI error event from WebSocket triggers ERROR emission."""

        async def _run():
            import websockets

            async def ws_handler(ws):
                await ws.send(json.dumps({
                    "type": "error",
                    "error": {"message": "Rate limit exceeded"}
                }))
                # Keep connection open briefly for receive loop
                await asyncio.sleep(0.5)

            server = await websockets.serve(ws_handler, "127.0.0.1", 0)
            port = server.sockets[0].getsockname()[1]

            try:
                config = _make_config(
                    mode="streaming",
                    endpoint=f"ws://127.0.0.1:{port}",
                    provider="openai",
                    api_key="test-key",
                )
                transport = StreamingTransport(config)

                with patch.object(_mod, "emit_ready"), \
                     patch.object(_mod, "emit_error") as mock_error:
                    await transport.start()
                    # Wait for the receive loop to process the error
                    await asyncio.sleep(0.2)

                    mock_error.assert_called_once()
                    assert "Rate limit exceeded" in mock_error.call_args[0][0]

                await transport._close()
            finally:
                server.close()
                await server.wait_closed()

        asyncio.run(_run())


# ---------------------------------------------------------------------------
# Test: Protocol output — FALLBACK
# ---------------------------------------------------------------------------


class TestProtocolOutputFallback:
    """Verify FALLBACK:<reason> is emitted on connection failure."""

    def test_all_chunks_fail_emits_fallback(self):
        """When all chunk submissions fail, FALLBACK is emitted."""

        async def _run():
            config = _make_config(
                mode="chunked",
                endpoint="http://localhost:9999/v1/audio/transcriptions",
                chunk_duration=500,
            )
            transport = ChunkedTransport(config)

            async def mock_submit_fail(pcm_data: bytes, is_final: bool) -> None:
                # Simulate failure by not appending to results
                transport._chunks_submitted += 1
                transport._chunks_failed += 1

            with patch.object(transport, "_submit_chunk", side_effect=mock_submit_fail), \
                 patch.object(_mod, "emit_ready"), \
                 patch.object(_mod, "emit_partial"), \
                 patch.object(_mod, "emit_fallback") as mock_fallback:

                await transport.start()

                # Feed some audio (one full chunk)
                chunk_bytes = 16000  # 500ms
                await transport.feed_audio(b"\x00" * chunk_bytes)
                await transport.finalize()

                # Since no results accumulated, finalize should emit fallback
                mock_fallback.assert_called_once()
                assert "failed" in mock_fallback.call_args[0][0].lower()

        asyncio.run(_run())

    def test_streaming_connection_refused_falls_back_to_chunked(self):
        """probe_and_start with unreachable streaming falls back to chunked (no FALLBACK emitted)."""

        async def _run():
            config = _make_config(
                mode="streaming",
                endpoint="ws://127.0.0.1:1",  # Nothing listening
                provider="local-whisper",
            )

            with patch.object(_mod, "emit_ready") as mock_ready, \
                 patch.object(_mod, "emit_fallback") as mock_fallback:
                transport = await probe_and_start(config)

                # Should have started chunked successfully
                mock_ready.assert_called_with("chunked")
                # FALLBACK should NOT be emitted since chunked worked
                mock_fallback.assert_not_called()

        asyncio.run(_run())
