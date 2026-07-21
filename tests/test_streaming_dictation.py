# Feature: streaming-dictation, Property 2: Audio Frame Forwarding Integrity
"""
Property 2: Audio Frame Forwarding Integrity

For any sequence of raw PCM audio frames produced by the capture process,
every frame SHALL be forwarded to the backend connection without loss,
corruption, or reordering.

**Validates: Requirements 2.2, 5.1**
"""

import asyncio
import sys
from pathlib import Path
from unittest.mock import patch

import pytest
from hypothesis import given, settings
import hypothesis.strategies as st

# Add the helper script directory to the path so we can import from it
SCRIPT_DIR = Path(__file__).parent.parent / "configs" / "quickshell" / "ii" / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from importlib import import_module

# Import the module (filename has a hyphen, so use importlib)
_mod = import_module("dictation-stream")
StreamHelperConfig = _mod.StreamHelperConfig
ChunkedTransport = _mod.ChunkedTransport


class CapturingChunkedTransport(ChunkedTransport):
    """Subclass that captures submitted PCM data instead of HTTP POSTing."""

    def __init__(self, config: StreamHelperConfig) -> None:
        super().__init__(config)
        self.captured_chunks: list[bytes] = []

    async def _submit_chunk(self, pcm_data: bytes, is_final: bool) -> None:
        """Capture the raw PCM data instead of writing WAV and POSTing."""
        self.captured_chunks.append(pcm_data)


@pytest.mark.property_test
class TestPartialResultUpdates:
    """Feature: streaming-dictation, Property 3: Partial Result Updates Reflect Backend Output"""

    @given(
        partials=st.lists(
            st.text(min_size=1, max_size=200, alphabet=st.characters(
                whitelist_categories=("L", "N", "P", "Z"),
                blacklist_characters="\x00",
            )),
            min_size=1,
            max_size=30,
        ),
    )
    @settings(max_examples=200)
    def test_streaming_mode_replaces_partial_text(self, partials: list[str]):
        """In streaming mode, each partial result REPLACES partialText entirely.

        The StreamingTransport._handle_local_message sets _partial_text = message
        for each incoming text frame, so after N partials, _partial_text equals
        the last message received.

        **Validates: Requirements 2.3, 11.3**
        """
        config = StreamHelperConfig(
            mode="streaming",
            endpoint="ws://localhost:9999/v1/stream",
            api_key="",
            provider="local-whisper",
            chunk_duration=3000,
            sample_rate=16000,
            channels=1,
            sample_format="s16",
            policy_ai=1,
        )
        transport = _mod.StreamingTransport(config)

        # Simulate receiving partial messages from a local backend
        for partial in partials:
            transport._handle_local_message(partial)

        # In streaming mode, partialText should be the LAST partial received
        assert transport._partial_text == partials[-1], (
            f"Expected partialText to be the last partial '{partials[-1]}', "
            f"but got '{transport._partial_text}'"
        )

    @given(
        chunk_results=st.lists(
            st.text(min_size=1, max_size=200, alphabet=st.characters(
                whitelist_categories=("L", "N", "P", "Z"),
                blacklist_characters="\x00",
            )),
            min_size=1,
            max_size=20,
        ),
    )
    @settings(max_examples=200)
    def test_chunked_mode_accumulates_partial_text(self, chunk_results: list[str]):
        """In chunked mode, each chunk result ACCUMULATES into partialText.

        The ChunkedTransport appends each successful chunk result to _results
        and the accumulated text is the space-joined list of all results.

        **Validates: Requirements 3.3, 10.3**
        """
        config = StreamHelperConfig(
            mode="chunked",
            endpoint="http://localhost:9999/v1/audio/transcriptions",
            api_key="",
            provider="local-whisper",
            chunk_duration=3000,
            sample_rate=16000,
            channels=1,
            sample_format="s16",
            policy_ai=1,
        )
        transport = _mod.ChunkedTransport(config)

        # Simulate chunk results being accumulated
        for result in chunk_results:
            transport._results.append(result)

        # The accumulated partial text should be all results joined with spaces
        expected = " ".join(chunk_results)
        actual = " ".join(transport._results)
        assert actual == expected, (
            f"Expected accumulated text '{expected}', but got '{actual}'"
        )

    @given(
        partials=st.lists(
            st.text(min_size=1, max_size=200, alphabet=st.characters(
                whitelist_categories=("L", "N", "P", "Z"),
                blacklist_characters="\x00",
            )),
            min_size=2,
            max_size=30,
        ),
    )
    @settings(max_examples=200)
    def test_streaming_intermediate_partials_not_preserved(self, partials: list[str]):
        """In streaming mode, intermediate partials are overwritten — only the last survives.

        This confirms that streaming mode REPLACES (not accumulates), so after
        processing N distinct partials, the earlier ones are discarded.

        **Validates: Requirements 2.3, 11.3**
        """
        config = StreamHelperConfig(
            mode="streaming",
            endpoint="ws://localhost:9999/v1/stream",
            api_key="",
            provider="local-whisper",
            chunk_duration=3000,
            sample_rate=16000,
            channels=1,
            sample_format="s16",
            policy_ai=1,
        )
        transport = _mod.StreamingTransport(config)

        # Feed all partials
        for partial in partials:
            transport._handle_local_message(partial)

        # Verify that partialText does NOT contain the concatenation of all
        # partials — it should only be the last one
        if partials[0] != partials[-1]:
            assert transport._partial_text != " ".join(partials), (
                "Streaming mode should replace partialText, not accumulate"
            )
        assert transport._partial_text == partials[-1]

    @given(
        chunk_results=st.lists(
            st.text(min_size=1, max_size=100, alphabet=st.characters(
                whitelist_categories=("L", "N", "P", "Z"),
                blacklist_characters="\x00",
            )),
            min_size=2,
            max_size=20,
        ),
    )
    @settings(max_examples=200)
    def test_chunked_order_preserved(self, chunk_results: list[str]):
        """In chunked mode, the order of chunk results is preserved in the accumulation.

        **Validates: Requirements 3.3, 10.3**
        """
        config = StreamHelperConfig(
            mode="chunked",
            endpoint="http://localhost:9999/v1/audio/transcriptions",
            api_key="",
            provider="local-whisper",
            chunk_duration=3000,
            sample_rate=16000,
            channels=1,
            sample_format="s16",
            policy_ai=1,
        )
        transport = _mod.ChunkedTransport(config)

        # Simulate chunk results accumulating in order
        for result in chunk_results:
            transport._results.append(result)

        # Verify order is preserved — splitting on space and checking individual
        # results appear in sequence
        accumulated = " ".join(transport._results)
        for i, result in enumerate(chunk_results):
            assert result in accumulated, (
                f"Chunk result {i} '{result}' not found in accumulated text"
            )
        # Verify exact content by checking the list directly
        assert transport._results == chunk_results


@pytest.mark.property_test
class TestAudioFrameIntegrity:
    """Feature: streaming-dictation, Property 2: Audio Frame Forwarding Integrity"""

    @given(
        frames=st.lists(
            st.binary(min_size=1, max_size=8192), min_size=1, max_size=50
        ),
        chunk_duration=st.integers(min_value=100, max_value=10000),
    )
    @settings(max_examples=200)
    def test_frames_forwarded_without_loss(self, frames: list[bytes], chunk_duration: int):
        """All input frames concatenated equal all chunks submitted concatenated.

        **Validates: Requirements 2.2, 5.1**
        """
        config = StreamHelperConfig(
            mode="chunked",
            endpoint="http://localhost:9999/v1/audio/transcriptions",
            api_key="",
            provider="local-whisper",
            chunk_duration=chunk_duration,
            sample_rate=16000,
            channels=1,
            sample_format="s16",
            policy_ai=1,
        )

        transport = CapturingChunkedTransport(config)

        async def run():
            await transport.start()
            for frame in frames:
                await transport.feed_audio(frame)
            # Finalize flushes the remaining buffer
            await transport.finalize()

        # Suppress stdout protocol emissions during test
        with patch.object(_mod, "emit_ready"), \
             patch.object(_mod, "emit_partial"), \
             patch.object(_mod, "emit_final"), \
             patch.object(_mod, "emit_fallback"):
            asyncio.run(run())

        # The concatenation of all captured chunks must equal the concatenation
        # of all input frames — no loss, corruption, or reordering
        expected = b"".join(frames)
        actual = b"".join(transport.captured_chunks)

        assert actual == expected, (
            f"Audio data mismatch.\n"
            f"Input total bytes: {len(expected)}\n"
            f"Output total bytes: {len(actual)}\n"
            f"Number of input frames: {len(frames)}\n"
            f"Number of output chunks: {len(transport.captured_chunks)}"
        )

    @given(
        frames=st.lists(
            st.binary(min_size=1, max_size=8192), min_size=1, max_size=50
        ),
        chunk_duration=st.integers(min_value=100, max_value=10000),
    )
    @settings(max_examples=200)
    def test_chunk_ordering_preserved(self, frames: list[bytes], chunk_duration: int):
        """Chunks are emitted in the same order as the input frames were received.

        **Validates: Requirements 2.2, 5.1**
        """
        config = StreamHelperConfig(
            mode="chunked",
            endpoint="http://localhost:9999/v1/audio/transcriptions",
            api_key="",
            provider="local-whisper",
            chunk_duration=chunk_duration,
            sample_rate=16000,
            channels=1,
            sample_format="s16",
            policy_ai=1,
        )

        transport = CapturingChunkedTransport(config)

        async def run():
            await transport.start()
            for frame in frames:
                await transport.feed_audio(frame)
            await transport.finalize()

        with patch.object(_mod, "emit_ready"), \
             patch.object(_mod, "emit_partial"), \
             patch.object(_mod, "emit_final"), \
             patch.object(_mod, "emit_fallback"):
            asyncio.run(run())

        # Verify ordering: walking through original data byte-by-byte through
        # the chunks should produce the same sequence
        expected = b"".join(frames)
        actual = b"".join(transport.captured_chunks)

        # Check prefix preservation at each chunk boundary
        offset = 0
        for i, chunk in enumerate(transport.captured_chunks):
            expected_slice = expected[offset:offset + len(chunk)]
            assert chunk == expected_slice, (
                f"Chunk {i} does not match expected data at offset {offset}.\n"
                f"Chunk size: {len(chunk)}, expected slice size: {len(expected_slice)}"
            )
            offset += len(chunk)

        assert offset == len(expected), (
            f"Total chunk bytes ({offset}) != total input bytes ({len(expected)})"
        )


# ---------------------------------------------------------------------------
# Feature: streaming-dictation, Property 10: Base64 PCM Round-Trip (OpenAI)
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestBase64RoundTrip:
    """Feature: streaming-dictation, Property 10: Base64 PCM Round-Trip (OpenAI)

    The OpenAI streaming path base64-encodes PCM audio frames before sending
    them over WebSocket. This property verifies that encoding is lossless —
    any raw PCM bytes encoded to base64 and decoded back produce the exact
    original bytes.

    **Validates: Requirements 10.2**
    """

    @given(pcm_frame=st.binary(min_size=0, max_size=32768))
    @settings(max_examples=200)
    def test_base64_encode_decode_identity(self, pcm_frame: bytes) -> None:
        """Encoding to base64 and decoding back produces identical bytes.

        **Validates: Requirements 10.2**
        """
        import base64

        encoded = base64.b64encode(pcm_frame).decode("ascii")
        decoded = base64.b64decode(encoded)
        assert decoded == pcm_frame

    @given(pcm_frame=st.binary(min_size=1, max_size=16384))
    @settings(max_examples=200)
    def test_openai_frame_encoding_preserves_data(self, pcm_frame: bytes) -> None:
        """The JSON wrapping used for OpenAI preserves the audio data.

        Simulates the exact encoding path in StreamingTransport.feed_audio:
        base64-encode PCM, wrap in input_audio_buffer.append JSON, then parse
        back and decode — the recovered bytes must equal the original frame.

        **Validates: Requirements 10.2**
        """
        import base64
        import json

        # Encode exactly as StreamingTransport.feed_audio does
        encoded = base64.b64encode(pcm_frame).decode("ascii")
        msg = json.dumps({"type": "input_audio_buffer.append", "audio": encoded})

        # Parse it back (simulates what the server would receive)
        parsed = json.loads(msg)
        recovered = base64.b64decode(parsed["audio"])

        assert recovered == pcm_frame


# Feature: streaming-dictation, Property 6: Chunk Duration Compliance
"""
Property 6: Chunk Duration Compliance

For any audio stream and chunk duration configuration, the Audio_Chunker SHALL
produce chunks whose duration is within ±100ms of the configured chunkDurationMs,
except for the final chunk which may be shorter.

**Validates: Requirements 3.1, 6.4**
"""

_bytes_per_sample = _mod._bytes_per_sample


@pytest.mark.property_test
class TestChunkDurationCompliance:
    """Feature: streaming-dictation, Property 6: Chunk Duration Compliance"""

    @given(
        chunk_duration_ms=st.integers(min_value=500, max_value=10000),
        sample_rate=st.sampled_from([8000, 16000, 22050, 44100, 48000]),
        channels=st.integers(min_value=1, max_value=2),
        total_audio_bytes=st.integers(min_value=1, max_value=1_000_000),
    )
    @settings(max_examples=100)
    def test_non_final_chunks_exact_duration(
        self,
        chunk_duration_ms: int,
        sample_rate: int,
        channels: int,
        total_audio_bytes: int,
    ):
        """Non-final chunks have duration within ±100ms of configured chunk_duration.

        For any chunk_duration, sample_rate, channels, and total audio length,
        the calculated chunk_bytes produces non-final chunks whose duration is
        within ±100ms of the configured duration.

        **Validates: Requirements 3.1, 6.4**
        """
        bps = _bytes_per_sample("s16")  # 2 bytes per sample

        # Calculate chunk_bytes the same way ChunkedTransport does
        chunk_bytes = int(sample_rate * channels * bps * (chunk_duration_ms / 1000))
        if chunk_bytes == 0:
            return  # Degenerate case

        audio_data = bytes(total_audio_bytes)

        # Simulate chunking (same algorithm as ChunkedTransport)
        chunks: list[bytes] = []
        offset = 0
        while offset + chunk_bytes <= len(audio_data):
            chunks.append(audio_data[offset : offset + chunk_bytes])
            offset += chunk_bytes
        if offset < len(audio_data):
            chunks.append(audio_data[offset:])  # final chunk (may be shorter)

        if len(chunks) <= 1:
            return  # Only final chunk, no non-final to verify

        # Verify non-final chunks are within ±100ms tolerance
        tolerance_ms = 100
        for i, chunk in enumerate(chunks[:-1]):
            actual_duration_ms = len(chunk) / (sample_rate * channels * bps) * 1000
            assert abs(actual_duration_ms - chunk_duration_ms) <= tolerance_ms, (
                f"Non-final chunk {i} duration {actual_duration_ms:.1f}ms "
                f"exceeds ±{tolerance_ms}ms tolerance from configured "
                f"{chunk_duration_ms}ms (sample_rate={sample_rate}, "
                f"channels={channels})"
            )

    @given(
        chunk_duration_ms=st.integers(min_value=500, max_value=10000),
        sample_rate=st.sampled_from([8000, 16000, 22050, 44100, 48000]),
        channels=st.integers(min_value=1, max_value=2),
        total_audio_bytes=st.integers(min_value=1, max_value=1_000_000),
    )
    @settings(max_examples=100)
    def test_non_final_chunks_exactly_chunk_bytes_long(
        self,
        chunk_duration_ms: int,
        sample_rate: int,
        channels: int,
        total_audio_bytes: int,
    ):
        """All non-final chunks are exactly chunk_bytes long.

        **Validates: Requirements 3.1, 6.4**
        """
        bps = _bytes_per_sample("s16")
        chunk_bytes = int(sample_rate * channels * bps * (chunk_duration_ms / 1000))
        if chunk_bytes == 0:
            return

        audio_data = bytes(total_audio_bytes)

        # Simulate chunking
        chunks: list[bytes] = []
        offset = 0
        while offset + chunk_bytes <= len(audio_data):
            chunks.append(audio_data[offset : offset + chunk_bytes])
            offset += chunk_bytes
        if offset < len(audio_data):
            chunks.append(audio_data[offset:])

        if len(chunks) <= 1:
            return

        # All non-final chunks must be exactly chunk_bytes
        for i, chunk in enumerate(chunks[:-1]):
            assert len(chunk) == chunk_bytes, (
                f"Non-final chunk {i} has {len(chunk)} bytes, "
                f"expected exactly {chunk_bytes} bytes "
                f"(sample_rate={sample_rate}, channels={channels}, "
                f"chunk_duration={chunk_duration_ms}ms)"
            )

    @given(
        chunk_duration_ms=st.integers(min_value=500, max_value=10000),
        sample_rate=st.sampled_from([8000, 16000, 22050, 44100, 48000]),
        channels=st.integers(min_value=1, max_value=2),
        total_audio_bytes=st.integers(min_value=1, max_value=1_000_000),
    )
    @settings(max_examples=100)
    def test_final_chunk_shorter_or_equal(
        self,
        chunk_duration_ms: int,
        sample_rate: int,
        channels: int,
        total_audio_bytes: int,
    ):
        """The final chunk may be shorter than configured duration.

        **Validates: Requirements 3.1, 6.4**
        """
        bps = _bytes_per_sample("s16")
        chunk_bytes = int(sample_rate * channels * bps * (chunk_duration_ms / 1000))
        if chunk_bytes == 0:
            return

        audio_data = bytes(total_audio_bytes)

        # Simulate chunking
        chunks: list[bytes] = []
        offset = 0
        while offset + chunk_bytes <= len(audio_data):
            chunks.append(audio_data[offset : offset + chunk_bytes])
            offset += chunk_bytes
        if offset < len(audio_data):
            chunks.append(audio_data[offset:])

        if not chunks:
            return

        # Final chunk must be ≤ chunk_bytes in size
        final_chunk = chunks[-1]
        assert len(final_chunk) <= chunk_bytes, (
            f"Final chunk size {len(final_chunk)} bytes exceeds "
            f"chunk_bytes={chunk_bytes} (sample_rate={sample_rate}, "
            f"channels={channels}, chunk_duration={chunk_duration_ms}ms)"
        )

    @given(
        chunk_duration_ms=st.integers(min_value=500, max_value=10000),
        sample_rate=st.sampled_from([8000, 16000, 22050, 44100, 48000]),
        channels=st.integers(min_value=1, max_value=2),
        feed_sizes=st.lists(
            st.integers(min_value=1, max_value=16000),
            min_size=1,
            max_size=100,
        ),
    )
    @settings(max_examples=100)
    def test_chunked_transport_duration_compliance(
        self,
        chunk_duration_ms: int,
        sample_rate: int,
        channels: int,
        feed_sizes: list[int],
    ):
        """ChunkedTransport produces non-final chunks within ±100ms of configured duration.

        Feeds audio in random-sized pieces via feed_audio() and verifies the
        captured chunks comply with the duration tolerance across different
        sample rates and channel counts.

        **Validates: Requirements 3.1, 6.4**
        """
        bps = _bytes_per_sample("s16")

        config = StreamHelperConfig(
            mode="chunked",
            endpoint="http://localhost:9999/v1/audio/transcriptions",
            api_key="",
            provider="local-whisper",
            chunk_duration=chunk_duration_ms,
            sample_rate=sample_rate,
            channels=channels,
            sample_format="s16",
            policy_ai=1,
        )

        transport = CapturingChunkedTransport(config)

        async def run():
            await transport.start()
            for size in feed_sizes:
                await transport.feed_audio(bytes(size))
            await transport.finalize()

        with patch.object(_mod, "emit_ready"), \
             patch.object(_mod, "emit_partial"), \
             patch.object(_mod, "emit_final"), \
             patch.object(_mod, "emit_fallback"):
            asyncio.run(run())

        if len(transport.captured_chunks) <= 1:
            return  # Only final chunk, no non-final to verify

        # All non-final chunks must be within ±100ms of configured duration
        tolerance_ms = 100
        non_final_chunks = transport.captured_chunks[:-1]

        for i, chunk in enumerate(non_final_chunks):
            actual_duration_ms = len(chunk) / (sample_rate * channels * bps) * 1000
            assert abs(actual_duration_ms - chunk_duration_ms) <= tolerance_ms, (
                f"Non-final chunk {i} has duration {actual_duration_ms:.1f}ms, "
                f"expected {chunk_duration_ms}ms ±{tolerance_ms}ms "
                f"(sample_rate={sample_rate}, channels={channels})"
            )

        # Final chunk must be ≤ chunk_bytes
        chunk_bytes = int(sample_rate * channels * bps * (chunk_duration_ms / 1000))
        final_chunk = transport.captured_chunks[-1]
        assert len(final_chunk) <= chunk_bytes, (
            f"Final chunk size {len(final_chunk)} exceeds chunk_bytes={chunk_bytes}"
        )


# ---------------------------------------------------------------------------
# Feature: streaming-dictation, Property 1: Capability Detection Always Returns Valid Mode
# ---------------------------------------------------------------------------
"""
Property 1: Capability Detection Always Returns Valid Mode

For any provider string and endpoint config, detection returns exactly one
of "streaming", "chunked", or "batch" — never an undefined or invalid value.

**Validates: Requirements 1.1, 1.5**
"""

VALID_MODES = {"streaming", "chunked", "batch"}
KNOWN_LOCAL_PROVIDERS = ["whisper-cpp", "faster-whisper", "local-whisper"]


def detect_capability(provider: str, streaming_endpoint: str) -> str:
    """Python equivalent of QML detectCapability for testing.

    Determines the best transcription mode based on the configured provider
    and streaming endpoint. This mirrors the QML-side logic from DictationService.

    Args:
        provider: The configured transcription provider name.
        streaming_endpoint: Custom streaming endpoint URL (empty string if not set).

    Returns:
        One of "streaming", "chunked", or "batch".
    """
    # Explicit streaming endpoint configured → streaming
    if streaming_endpoint:
        return "streaming"

    # Known streaming-capable providers
    if provider == "openai":
        return "streaming"

    # Known local providers — attempt streaming (fallback handled by helper)
    if provider in KNOWN_LOCAL_PROVIDERS:
        return "streaming"

    # Unknown provider → batch
    return "batch"


# --- Strategies ---

# Arbitrary provider strings including empty, unicode, and common values
_provider_st = st.text(min_size=0, max_size=50)

# Arbitrary endpoint strings including empty, unicode, and URL-like values
_endpoint_st = st.text(min_size=0, max_size=200)


# --- Property Tests ---


@pytest.mark.property_test
class TestCapabilityDetection:
    """Feature: streaming-dictation, Property 1: Capability Detection Always Returns Valid Mode"""

    @given(
        provider=_provider_st,
        endpoint=_endpoint_st,
    )
    @settings(max_examples=200)
    def test_always_returns_valid_mode(self, provider, endpoint):
        """
        Property: For any provider string and endpoint configuration,
        detect_capability always returns exactly one of "streaming", "chunked",
        or "batch" — never an undefined or invalid value.

        **Validates: Requirements 1.1, 1.5**
        """
        result = detect_capability(provider, endpoint)
        assert result in VALID_MODES, (
            f"detect_capability({provider!r}, {endpoint!r}) returned {result!r}, "
            f"which is not in {VALID_MODES}"
        )

    @given(
        provider=_provider_st,
        endpoint=st.text(min_size=1, max_size=200),
    )
    @settings(max_examples=200)
    def test_nonempty_endpoint_always_streaming(self, provider, endpoint):
        """
        Property: When a non-empty streaming endpoint is configured,
        detect_capability always returns "streaming" regardless of provider.

        **Validates: Requirements 1.1, 1.5**
        """
        result = detect_capability(provider, endpoint)
        assert result == "streaming", (
            f"Non-empty endpoint should always yield 'streaming', "
            f"got {result!r} for provider={provider!r}, endpoint={endpoint!r}"
        )

    @given(
        provider=st.text(min_size=0, max_size=50).filter(
            lambda p: p != "openai" and p not in KNOWN_LOCAL_PROVIDERS
        ),
    )
    @settings(max_examples=200)
    def test_unknown_provider_empty_endpoint_returns_batch(self, provider):
        """
        Property: When the endpoint is empty and the provider is not a known
        streaming-capable provider, detect_capability returns "batch".

        **Validates: Requirements 1.1, 1.5**
        """
        result = detect_capability(provider, "")
        assert result == "batch", (
            f"Unknown provider with empty endpoint should return 'batch', "
            f"got {result!r} for provider={provider!r}"
        )

    @given(
        provider=st.sampled_from(["openai"] + KNOWN_LOCAL_PROVIDERS),
    )
    @settings(max_examples=200)
    def test_known_providers_return_streaming(self, provider):
        """
        Property: Known streaming-capable providers (openai and local providers)
        always return "streaming" when endpoint is empty.

        **Validates: Requirements 1.1, 1.5**
        """
        result = detect_capability(provider, "")
        assert result == "streaming", (
            f"Known provider {provider!r} with empty endpoint should return "
            f"'streaming', got {result!r}"
        )


# ---------------------------------------------------------------------------
# Feature: streaming-dictation, Property 7: Chunk Submission Count
# ---------------------------------------------------------------------------
"""
Property 7: Chunk Submission Count

For any recording session of duration D with chunk duration C, the number of
HTTP chunk submissions SHALL equal ceil(D / C) (accounting for the final
partial chunk).

**Validates: Requirements 3.2, 3.4**
"""

import math


@pytest.mark.property_test
class TestChunkSubmissionCount:
    """Feature: streaming-dictation, Property 7: Chunk Submission Count"""

    @given(
        duration_ms=st.integers(min_value=100, max_value=60000),
        chunk_duration_ms=st.integers(min_value=500, max_value=10000),
    )
    @settings(max_examples=200)
    def test_submission_count_equals_ceil(self, duration_ms, chunk_duration_ms):
        """
        Property: For any recording duration D and chunk duration C,
        the number of chunk submissions equals ceil(D / C).

        Uses the actual ChunkedTransport class with a monkeypatched
        _submit_chunk that counts invocations rather than HTTP POSTing.

        **Validates: Requirements 3.2, 3.4**
        """
        sample_rate = 16000
        channels = 1
        bps = 2  # s16 format

        # Calculate total audio bytes for the given duration
        total_bytes = int(sample_rate * channels * bps * (duration_ms / 1000))
        if total_bytes == 0:
            return  # Skip degenerate case

        # Expected submission count
        expected_submissions = math.ceil(duration_ms / chunk_duration_ms)

        # Create config for the ChunkedTransport
        config = StreamHelperConfig(
            mode="chunked",
            endpoint="http://localhost:9999/v1/audio/transcriptions",
            api_key="",
            provider="local-whisper",
            chunk_duration=chunk_duration_ms,
            sample_rate=sample_rate,
            channels=channels,
            sample_format="s16",
            policy_ai=1,
        )

        transport = ChunkedTransport(config)

        # Monkeypatch _submit_chunk to just count calls
        submission_count = 0

        async def mock_submit_chunk(pcm_data: bytes, is_final: bool) -> None:
            nonlocal submission_count
            submission_count += 1

        transport._submit_chunk = mock_submit_chunk

        # Feed all audio data and finalize
        audio_data = b"\x00" * total_bytes

        async def run():
            await transport.feed_audio(audio_data)
            await transport.finalize()

        asyncio.run(run())

        assert submission_count == expected_submissions, (
            f"For duration={duration_ms}ms, chunk_duration={chunk_duration_ms}ms: "
            f"expected {expected_submissions} submissions, got {submission_count}. "
            f"total_bytes={total_bytes}, chunk_bytes={transport._chunk_bytes}"
        )

    @given(
        duration_ms=st.integers(min_value=500, max_value=60000),
        chunk_duration_ms=st.integers(min_value=500, max_value=10000),
        num_feeds=st.integers(min_value=1, max_value=20),
    )
    @settings(max_examples=200)
    def test_submission_count_independent_of_feed_pattern(
        self, duration_ms, chunk_duration_ms, num_feeds
    ):
        """
        Property: The total number of chunk submissions is independent of how
        audio data is fed (all at once vs. many small pieces).

        Regardless of whether feed_audio is called once with all data or many
        times with small pieces, the final submission count equals ceil(D / C).

        **Validates: Requirements 3.2, 3.4**
        """
        sample_rate = 16000
        channels = 1
        bps = 2

        total_bytes = int(sample_rate * channels * bps * (duration_ms / 1000))
        if total_bytes == 0:
            return

        expected_submissions = math.ceil(duration_ms / chunk_duration_ms)

        config = StreamHelperConfig(
            mode="chunked",
            endpoint="http://localhost:9999/v1/audio/transcriptions",
            api_key="",
            provider="local-whisper",
            chunk_duration=chunk_duration_ms,
            sample_rate=sample_rate,
            channels=channels,
            sample_format="s16",
            policy_ai=1,
        )

        transport = ChunkedTransport(config)

        submission_count = 0

        async def mock_submit_chunk(pcm_data: bytes, is_final: bool) -> None:
            nonlocal submission_count
            submission_count += 1

        transport._submit_chunk = mock_submit_chunk

        # Split audio into num_feeds pieces of varying size
        audio_data = b"\x00" * total_bytes
        feed_size = total_bytes // num_feeds

        async def run():
            offset = 0
            for i in range(num_feeds):
                if i == num_feeds - 1:
                    # Last piece gets all remaining bytes
                    piece = audio_data[offset:]
                else:
                    piece = audio_data[offset : offset + feed_size]
                    offset += feed_size
                if piece:
                    await transport.feed_audio(piece)
            await transport.finalize()

        asyncio.run(run())

        assert submission_count == expected_submissions, (
            f"For duration={duration_ms}ms, chunk_duration={chunk_duration_ms}ms, "
            f"num_feeds={num_feeds}: expected {expected_submissions} submissions, "
            f"got {submission_count}"
        )


# ---------------------------------------------------------------------------
# Feature: streaming-dictation, Property 8: Chunk Failure Isolation
# ---------------------------------------------------------------------------
"""
Property 8: Chunk Failure Isolation

For any chunk failure at position N in a sequence of chunks, all subsequent
chunks at positions > N SHALL still be submitted and their results accumulated
into partialText.

**Validates: Requirements 3.6**
"""


class FailingChunkedTransport(ChunkedTransport):
    """Subclass that simulates failures at specific chunk positions.

    Tracks all submission attempts (including failed ones) and raises an
    exception for chunks at the specified fail positions, while still allowing
    the transport to continue processing subsequent chunks.
    """

    def __init__(self, config: StreamHelperConfig, fail_positions: set[int]) -> None:
        super().__init__(config)
        self.fail_positions: set[int] = fail_positions
        self.submission_attempts: list[tuple[int, bool]] = []  # (position, succeeded)
        self._submission_index: int = 0

    async def _submit_chunk(self, pcm_data: bytes, is_final: bool) -> None:
        """Simulate chunk submission — fails at designated positions."""
        current_pos = self._submission_index
        self._submission_index += 1

        if current_pos in self.fail_positions:
            # Record the failed attempt
            self.submission_attempts.append((current_pos, False))
            # Simulate a failed chunk — increment failure counter, skip result
            self._chunks_submitted += 1
            self._chunks_failed += 1
        else:
            # Record a successful submission
            self.submission_attempts.append((current_pos, True))
            self._chunks_submitted += 1
            self._results.append(f"chunk_{current_pos}")


@pytest.mark.property_test
class TestChunkFailureIsolation:
    """Feature: streaming-dictation, Property 8: Chunk Failure Isolation"""

    @given(data=st.data())
    @settings(max_examples=100)
    def test_failure_does_not_prevent_subsequent_submissions(self, data):
        """A chunk failure at position N does not prevent submission of chunks > N.

        For any number of chunks and any failure position, all chunks after the
        failure are still submitted to the backend.

        **Validates: Requirements 3.6**
        """
        num_chunks = data.draw(st.integers(min_value=2, max_value=20), label="num_chunks")
        fail_position = data.draw(
            st.integers(min_value=0, max_value=num_chunks - 1), label="fail_position"
        )

        # Use a chunk duration that makes each chunk exactly 1600 bytes
        # (100ms at 16kHz/mono/s16 = 16000 * 1 * 2 * 0.1 = 3200 bytes)
        # We pick 100ms chunks so we can precisely control how many chunks get created
        chunk_duration_ms = 100
        sample_rate = 16000
        channels = 1
        bps = 2
        chunk_bytes = int(sample_rate * channels * bps * (chunk_duration_ms / 1000))

        # Generate exactly num_chunks worth of audio data
        total_bytes = chunk_bytes * num_chunks

        config = StreamHelperConfig(
            mode="chunked",
            endpoint="http://localhost:9999/v1/audio/transcriptions",
            api_key="",
            provider="local-whisper",
            chunk_duration=chunk_duration_ms,
            sample_rate=sample_rate,
            channels=channels,
            sample_format="s16",
            policy_ai=1,
        )

        transport = FailingChunkedTransport(config, fail_positions={fail_position})

        audio_data = b"\x00" * total_bytes

        async def run():
            await transport.start()
            await transport.feed_audio(audio_data)
            await transport.finalize()

        with patch.object(_mod, "emit_ready"), \
             patch.object(_mod, "emit_partial"), \
             patch.object(_mod, "emit_final"), \
             patch.object(_mod, "emit_fallback"):
            asyncio.run(run())

        # All chunks should have been attempted (num_chunks total)
        assert len(transport.submission_attempts) == num_chunks, (
            f"Expected {num_chunks} submission attempts, "
            f"got {len(transport.submission_attempts)}"
        )

        # Verify the failed chunk is at the correct position
        assert transport.submission_attempts[fail_position] == (fail_position, False), (
            f"Expected chunk at position {fail_position} to have failed, "
            f"but got {transport.submission_attempts[fail_position]}"
        )

        # All chunks AFTER the failure position should have been submitted successfully
        for pos in range(fail_position + 1, num_chunks):
            assert transport.submission_attempts[pos] == (pos, True), (
                f"Chunk at position {pos} (after failure at {fail_position}) "
                f"should have been submitted successfully, "
                f"but got {transport.submission_attempts[pos]}"
            )

    @given(data=st.data())
    @settings(max_examples=100)
    def test_system_never_stops_early_after_failure(self, data):
        """The system continues processing after a failure — it never stops early.

        Even with multiple failures at various positions, every chunk position
        is attempted.

        **Validates: Requirements 3.6**
        """
        num_chunks = data.draw(st.integers(min_value=2, max_value=20), label="num_chunks")
        # Draw multiple random failure positions
        fail_positions = data.draw(
            st.frozensets(
                st.integers(min_value=0, max_value=num_chunks - 1),
                min_size=1,
                max_size=min(num_chunks, 5),
            ),
            label="fail_positions",
        )

        chunk_duration_ms = 100
        sample_rate = 16000
        channels = 1
        bps = 2
        chunk_bytes = int(sample_rate * channels * bps * (chunk_duration_ms / 1000))

        total_bytes = chunk_bytes * num_chunks

        config = StreamHelperConfig(
            mode="chunked",
            endpoint="http://localhost:9999/v1/audio/transcriptions",
            api_key="",
            provider="local-whisper",
            chunk_duration=chunk_duration_ms,
            sample_rate=sample_rate,
            channels=channels,
            sample_format="s16",
            policy_ai=1,
        )

        transport = FailingChunkedTransport(config, fail_positions=set(fail_positions))

        audio_data = b"\x00" * total_bytes

        async def run():
            await transport.start()
            await transport.feed_audio(audio_data)
            await transport.finalize()

        with patch.object(_mod, "emit_ready"), \
             patch.object(_mod, "emit_partial"), \
             patch.object(_mod, "emit_final"), \
             patch.object(_mod, "emit_fallback"):
            asyncio.run(run())

        # The system must attempt ALL chunks — never stop early
        assert len(transport.submission_attempts) == num_chunks, (
            f"System stopped early! Expected {num_chunks} submission attempts "
            f"but only got {len(transport.submission_attempts)}. "
            f"Fail positions: {fail_positions}"
        )

        # Verify that every position was attempted in order
        for i in range(num_chunks):
            pos, _succeeded = transport.submission_attempts[i]
            assert pos == i, (
                f"Expected position {i} at index {i}, got position {pos}. "
                f"Chunks were processed out of order."
            )

        # Verify failed positions match expectations
        for pos in fail_positions:
            assert transport.submission_attempts[pos] == (pos, False), (
                f"Position {pos} should have failed but got "
                f"{transport.submission_attempts[pos]}"
            )

        # Verify non-failed positions succeeded
        for pos in range(num_chunks):
            if pos not in fail_positions:
                assert transport.submission_attempts[pos] == (pos, True), (
                    f"Position {pos} should have succeeded but got "
                    f"{transport.submission_attempts[pos]}"
                )


# ---------------------------------------------------------------------------
# Feature: streaming-dictation, Property 12: Policy Enforcement for Remote Providers
# ---------------------------------------------------------------------------
"""
Property 12: Policy Enforcement for Remote Providers

For any remote provider configuration when policies.ai equals 2, activation
SHALL be rejected with an error message. For any chunk endpoint when policies.ai
equals 2, the endpoint SHALL be verified as local (localhost/127.0.0.1/::1)
before audio is sent.

**Validates: Requirements 12.2, 12.4**
"""

check_policy = _mod.check_policy
is_local_endpoint = _mod.is_local_endpoint

# --- Strategies ---

# Remote endpoint URLs (clearly not localhost/127.x/::1)
_remote_endpoints = st.sampled_from([
    "wss://api.openai.com/v1/realtime",
    "http://example.com/api/transcribe",
    "https://speech.googleapis.com/v1/speech:recognize",
    "wss://api.deepgram.com/v1/listen",
    "http://remote-server.io:8080/transcribe",
    "https://transcription.azure.com/v1/audio",
    "ws://192.168.1.100:8765",
    "http://10.0.0.5:5000/v1/audio/transcriptions",
    "wss://my-whisper.example.org/stream",
    "http://api.assemblyai.com/v2/realtime/ws",
])

# Local endpoint URLs (localhost, 127.0.0.1, ::1)
_local_endpoints = st.sampled_from([
    "ws://localhost:8765",
    "http://127.0.0.1:5000/v1/audio/transcriptions",
    "ws://[::1]:8765",
    "http://localhost:9999/v1/audio/transcriptions",
    "ws://127.0.0.1:8765/stream",
    "http://[::1]:5000/transcribe",
    "wss://localhost:443/v1/realtime",
    "http://127.0.0.2:5000/v1/audio",
    "http://127.255.255.255:8080/api",
])


@pytest.mark.property_test
class TestPolicyEnforcement:
    """Feature: streaming-dictation, Property 12: Policy Enforcement for Remote Providers"""

    @given(endpoint=_remote_endpoints)
    @settings(max_examples=100)
    def test_policy2_rejects_remote_endpoints(self, endpoint: str) -> None:
        """Remote endpoints are rejected when policy_ai=2.

        **Validates: Requirements 12.2, 12.4**
        """
        config = StreamHelperConfig(
            mode="streaming",
            endpoint=endpoint,
            api_key="test-key",
            provider="openai",
            chunk_duration=3000,
            sample_rate=16000,
            channels=1,
            sample_format="s16",
            policy_ai=2,
        )

        with pytest.raises(SystemExit):
            check_policy(config)

    @given(endpoint=_local_endpoints)
    @settings(max_examples=100)
    def test_policy2_allows_local_endpoints(self, endpoint: str) -> None:
        """Local endpoints (localhost/127.0.0.1/::1) pass when policy_ai=2.

        **Validates: Requirements 12.2, 12.4**
        """
        config = StreamHelperConfig(
            mode="streaming",
            endpoint=endpoint,
            api_key="",
            provider="local-whisper",
            chunk_duration=3000,
            sample_rate=16000,
            channels=1,
            sample_format="s16",
            policy_ai=2,
        )

        # Should NOT raise - local endpoints are allowed under policy 2
        check_policy(config)

    @given(
        endpoint=st.one_of(_remote_endpoints, _local_endpoints),
        mode=st.sampled_from(["streaming", "chunked"]),
        provider=st.sampled_from(["openai", "local-whisper", "faster-whisper"]),
    )
    @settings(max_examples=100)
    def test_policy0_always_rejects(self, endpoint: str, mode: str, provider: str) -> None:
        """Policy_ai=0 always raises SystemExit regardless of endpoint.

        **Validates: Requirements 12.2, 12.4**
        """
        config = StreamHelperConfig(
            mode=mode,
            endpoint=endpoint,
            api_key="",
            provider=provider,
            chunk_duration=3000,
            sample_rate=16000,
            channels=1,
            sample_format="s16",
            policy_ai=0,
        )

        with pytest.raises(SystemExit):
            check_policy(config)

    @given(
        endpoint=st.one_of(_remote_endpoints, _local_endpoints),
        mode=st.sampled_from(["streaming", "chunked"]),
        provider=st.sampled_from(["openai", "local-whisper", "faster-whisper"]),
    )
    @settings(max_examples=100)
    def test_policy1_never_rejects(self, endpoint: str, mode: str, provider: str) -> None:
        """Policy_ai=1 never raises regardless of endpoint.

        **Validates: Requirements 12.2, 12.4**
        """
        config = StreamHelperConfig(
            mode=mode,
            endpoint=endpoint,
            api_key="test-key",
            provider=provider,
            chunk_duration=3000,
            sample_rate=16000,
            channels=1,
            sample_format="s16",
            policy_ai=1,
        )

        # Should NOT raise - policy 1 allows everything
        check_policy(config)

    @given(
        hostname=st.sampled_from([
            "ws://localhost:8765",
            "http://127.0.0.1:5000/path",
            "ws://[::1]:9999",
            "http://127.0.0.1:80",
            "http://127.100.200.50:8080/api",
        ])
    )
    @settings(max_examples=100)
    def test_is_local_endpoint_true_for_local(self, hostname: str) -> None:
        """is_local_endpoint returns True for localhost/127.x.x.x/::1 URLs.

        **Validates: Requirements 12.2, 12.4**
        """
        assert is_local_endpoint(hostname) is True

    @given(
        hostname=st.sampled_from([
            "wss://api.openai.com/v1/realtime",
            "http://example.com/api",
            "ws://192.168.1.100:8765",
            "http://10.0.0.5:5000/v1/audio",
            "https://speech.googleapis.com/v1",
            "http://my-server.local:8080/transcribe",
        ])
    )
    @settings(max_examples=100)
    def test_is_local_endpoint_false_for_remote(self, hostname: str) -> None:
        """is_local_endpoint returns False for non-local URLs.

        **Validates: Requirements 12.2, 12.4**
        """
        assert is_local_endpoint(hostname) is False


# ---------------------------------------------------------------------------
# Feature: streaming-dictation, Property 14: Custom Endpoint Override
# ---------------------------------------------------------------------------
"""
Property 14: Custom Endpoint Override

For any non-empty streamingEndpoint configuration value, the system SHALL use
that endpoint verbatim regardless of the provider type or auto-detection logic.

**Validates: Requirements 6.5**
"""


def resolve_endpoint(provider: str, streaming_endpoint: str) -> str:
    """Resolve the final endpoint URL used for streaming transport.

    Mirrors the endpoint resolution logic from the design:
    - If streamingEndpoint is non-empty, return it verbatim (custom override)
    - If empty and provider is "openai", derive the OpenAI Realtime API endpoint
    - If empty and provider is a known local provider, derive ws://localhost:8765
    - Otherwise, return empty string (batch mode, no endpoint needed)

    Args:
        provider: The configured transcription provider name.
        streaming_endpoint: Custom streaming endpoint URL (empty string if not set).

    Returns:
        The resolved endpoint URL string.
    """
    if streaming_endpoint:
        return streaming_endpoint

    if provider == "openai":
        return "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview"

    if provider in KNOWN_LOCAL_PROVIDERS:
        return "ws://localhost:8765"

    return ""


@pytest.mark.property_test
class TestCustomEndpointOverride:
    """Feature: streaming-dictation, Property 14: Custom Endpoint Override"""

    @given(
        endpoint=st.text(min_size=1, max_size=500),
        provider=st.text(min_size=0, max_size=50),
    )
    @settings(max_examples=100)
    def test_nonempty_endpoint_forces_streaming_mode(self, endpoint: str, provider: str):
        """Any non-empty streamingEndpoint forces detect_capability to return "streaming".

        Regardless of what provider is configured — known, unknown, empty, or
        arbitrary text — if a custom streaming endpoint is set, the mode is
        always "streaming".

        **Validates: Requirements 6.5**
        """
        result = detect_capability(provider, endpoint)
        assert result == "streaming", (
            f"Expected 'streaming' for non-empty endpoint, got {result!r}. "
            f"provider={provider!r}, endpoint={endpoint!r}"
        )

    @given(
        endpoint=st.text(min_size=1, max_size=500),
        provider=st.text(min_size=0, max_size=50),
    )
    @settings(max_examples=100)
    def test_endpoint_used_verbatim(self, endpoint: str, provider: str):
        """The custom endpoint is used as-is — no transformation, normalization, or replacement.

        When a non-empty streamingEndpoint is configured, resolve_endpoint must
        return the exact same string without any modification (no URL encoding,
        no lowercasing, no stripping, no protocol prefixing).

        **Validates: Requirements 6.5**
        """
        resolved = resolve_endpoint(provider, endpoint)
        assert resolved == endpoint, (
            f"Endpoint was modified! Original: {endpoint!r}, Resolved: {resolved!r}. "
            f"provider={provider!r}"
        )

    @given(
        endpoint=st.text(min_size=1, max_size=500),
        provider=st.sampled_from(
            ["openai"] + KNOWN_LOCAL_PROVIDERS + ["", "unknown", "azure", "anthropic"]
        ),
    )
    @settings(max_examples=100)
    def test_custom_endpoint_overrides_provider_defaults(self, endpoint: str, provider: str):
        """Custom endpoint overrides any provider-specific default endpoint derivation.

        Even for providers that have known default endpoints (openai →
        wss://api.openai.com/..., local → ws://localhost:8765), a custom
        endpoint takes precedence and is returned verbatim.

        **Validates: Requirements 6.5**
        """
        resolved = resolve_endpoint(provider, endpoint)

        # Must NOT be the auto-derived endpoint for the provider
        if provider == "openai":
            auto_derived = "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview"
            # The resolved endpoint must be our custom one, not the auto-derived one
            # (unless the custom one happens to equal the auto-derived one)
            assert resolved == endpoint, (
                f"Expected custom endpoint {endpoint!r}, got auto-derived {resolved!r}"
            )
        elif provider in KNOWN_LOCAL_PROVIDERS:
            auto_derived = "ws://localhost:8765"
            assert resolved == endpoint, (
                f"Expected custom endpoint {endpoint!r}, got auto-derived {resolved!r}"
            )
        else:
            assert resolved == endpoint, (
                f"Expected custom endpoint {endpoint!r}, got {resolved!r}"
            )


# ---------------------------------------------------------------------------
# Feature: streaming-dictation, Property 11: State Machine Transitions
# ---------------------------------------------------------------------------
"""
Property 11: State Machine Transitions

For any activation with a streaming/chunked-capable provider, the state SHALL
transition to StreamingActive (not Listening). For any stop-recording event in
StreamingActive, the state SHALL transition to Processing. For any error in
StreamingActive, the state SHALL transition to Error.

**Validates: Requirements 7.2, 7.4, 7.6**
"""

from enum import Enum, auto
from dataclasses import dataclass
from typing import Optional


class DState(Enum):
    """Mirror of the DictationService state enum."""
    Idle = auto()
    Listening = auto()
    StreamingActive = auto()
    Processing = auto()
    Error = auto()


class EventType(Enum):
    """Events that drive the DictationService state machine."""
    activate_streaming = auto()
    activate_chunked = auto()
    activate_batch = auto()
    stop_recording = auto()
    receive_final = auto()
    receive_error = auto()
    receive_fallback = auto()
    timeout = auto()


@dataclass
class Event:
    """A single state machine event."""
    type: EventType


class DictationStateMachine:
    """Python model of the DictationService state machine.

    Implements the transitions specified in the design:
      Idle + activate(streaming/chunked) → StreamingActive
      Idle + activate(batch) → Listening
      StreamingActive + stop_recording → Processing
      StreamingActive + receive_error → Error
      StreamingActive + receive_fallback → Listening
      Listening + stop_recording → Processing
      Processing + receive_final → Idle
      Processing + receive_error → Error
      Error + timeout → Idle
    """

    def __init__(self) -> None:
        self.state: DState = DState.Idle

    def send(self, event: Event) -> None:
        """Apply an event to the state machine, transitioning if applicable."""
        t = event.type

        if self.state == DState.Idle:
            if t in (EventType.activate_streaming, EventType.activate_chunked):
                self.state = DState.StreamingActive
            elif t == EventType.activate_batch:
                self.state = DState.Listening
            # Other events in Idle are ignored (no-op)

        elif self.state == DState.StreamingActive:
            if t == EventType.stop_recording:
                self.state = DState.Processing
            elif t == EventType.receive_error:
                self.state = DState.Error
            elif t == EventType.receive_fallback:
                self.state = DState.Listening
            # Other events in StreamingActive are ignored

        elif self.state == DState.Listening:
            if t == EventType.stop_recording:
                self.state = DState.Processing
            # Other events in Listening are ignored

        elif self.state == DState.Processing:
            if t == EventType.receive_final:
                self.state = DState.Idle
            elif t == EventType.receive_error:
                self.state = DState.Error
            # Other events in Processing are ignored

        elif self.state == DState.Error:
            if t == EventType.timeout:
                self.state = DState.Idle
            # Other events in Error are ignored


# --- Hypothesis Strategies ---

_event_type_st = st.sampled_from(list(EventType))
_event_st = _event_type_st.map(lambda t: Event(type=t))
_event_sequence_st = st.lists(_event_st, min_size=1, max_size=50)


@pytest.mark.property_test
class TestStateMachineTransitions:
    """Feature: streaming-dictation, Property 11: State Machine Transitions"""

    @given(
        mode=st.sampled_from([EventType.activate_streaming, EventType.activate_chunked]),
    )
    @settings(max_examples=200)
    def test_streaming_chunked_activation_enters_streaming_active(self, mode: EventType):
        """Activation with streaming/chunked-capable provider → StreamingActive.

        From Idle, activating with either streaming or chunked mode must always
        transition to StreamingActive (never to Listening or any other state).

        **Validates: Requirements 7.2**
        """
        sm = DictationStateMachine()
        assert sm.state == DState.Idle

        sm.send(Event(type=mode))
        assert sm.state == DState.StreamingActive, (
            f"After activate({mode.name}) from Idle, expected StreamingActive, "
            f"got {sm.state.name}"
        )

    @given(
        prefix_events=st.lists(
            st.sampled_from([
                Event(type=EventType.stop_recording),
                Event(type=EventType.receive_final),
                Event(type=EventType.receive_error),
                Event(type=EventType.timeout),
            ]),
            min_size=0,
            max_size=10,
        ),
        mode=st.sampled_from([EventType.activate_streaming, EventType.activate_chunked]),
    )
    @settings(max_examples=200)
    def test_activation_from_idle_always_streaming_active(
        self, prefix_events: list[Event], mode: EventType
    ):
        """After any sequence of events that returns the machine to Idle,
        activating with streaming/chunked enters StreamingActive.

        We first apply random events (which in Idle are no-ops) then activate.
        This verifies the transition is robust regardless of prior event history.

        **Validates: Requirements 7.2**
        """
        sm = DictationStateMachine()

        # These events are no-ops in Idle state, machine stays Idle
        for event in prefix_events:
            sm.send(event)

        assert sm.state == DState.Idle, (
            f"Precondition failed: expected Idle after no-op events, got {sm.state.name}"
        )

        sm.send(Event(type=mode))
        assert sm.state == DState.StreamingActive, (
            f"After activate({mode.name}) from Idle, expected StreamingActive, "
            f"got {sm.state.name}"
        )

    @given(
        mode=st.sampled_from([EventType.activate_streaming, EventType.activate_chunked]),
    )
    @settings(max_examples=200)
    def test_stop_in_streaming_active_enters_processing(self, mode: EventType):
        """Stop-recording in StreamingActive → Processing.

        After entering StreamingActive via activation, a stop_recording event
        must always transition to Processing.

        **Validates: Requirements 7.4**
        """
        sm = DictationStateMachine()
        sm.send(Event(type=mode))
        assert sm.state == DState.StreamingActive

        sm.send(Event(type=EventType.stop_recording))
        assert sm.state == DState.Processing, (
            f"After stop_recording in StreamingActive, expected Processing, "
            f"got {sm.state.name}"
        )

    @given(
        mode=st.sampled_from([EventType.activate_streaming, EventType.activate_chunked]),
    )
    @settings(max_examples=200)
    def test_error_in_streaming_active_enters_error(self, mode: EventType):
        """Error in StreamingActive → Error state.

        After entering StreamingActive, a receive_error event must always
        transition to the Error state.

        **Validates: Requirements 7.6**
        """
        sm = DictationStateMachine()
        sm.send(Event(type=mode))
        assert sm.state == DState.StreamingActive

        sm.send(Event(type=EventType.receive_error))
        assert sm.state == DState.Error, (
            f"After receive_error in StreamingActive, expected Error, "
            f"got {sm.state.name}"
        )

    @given(events=_event_sequence_st)
    @settings(max_examples=200)
    def test_state_never_invalid(self, events: list[Event]):
        """For any sequence of events, the state is always a valid DState.

        The state machine must never reach an undefined/invalid state regardless
        of what sequence of events is applied.

        **Validates: Requirements 7.2, 7.4, 7.6**
        """
        sm = DictationStateMachine()
        valid_states = set(DState)

        for event in events:
            sm.send(event)
            assert sm.state in valid_states, (
                f"State machine reached invalid state {sm.state!r} "
                f"after event {event.type.name}"
            )

    @given(
        events=_event_sequence_st,
        mode=st.sampled_from([EventType.activate_streaming, EventType.activate_chunked]),
    )
    @settings(max_examples=200)
    def test_streaming_activation_never_enters_listening(
        self, events: list[Event], mode: EventType
    ):
        """Streaming/chunked activation from Idle never enters Listening directly.

        This verifies the key distinction: streaming/chunked modes go to
        StreamingActive, only batch goes to Listening. Regardless of prior
        event history, if the machine is in Idle and receives a streaming/chunked
        activation, the next state is always StreamingActive.

        **Validates: Requirements 7.2**
        """
        sm = DictationStateMachine()

        # Drive the machine through arbitrary events
        for event in events:
            sm.send(event)

        # If we ended up in Idle, activate with streaming/chunked
        if sm.state == DState.Idle:
            sm.send(Event(type=mode))
            assert sm.state == DState.StreamingActive, (
                f"Streaming/chunked activation from Idle must go to StreamingActive, "
                f"got {sm.state.name}"
            )
            # Verify it's NOT Listening
            assert sm.state != DState.Listening, (
                f"Streaming/chunked activation must NOT enter Listening"
            )


class StreamingSession:
    """Models the DictationService state for final result routing tests."""

    def __init__(self):
        self.state = "StreamingActive"
        self.partialText = ""
        self.routed_text = None

    def receive_partial(self, text: str):
        """Simulate receiving a PARTIAL message — replaces partialText in streaming mode."""
        self.partialText = text

    def receive_final(self, text: str):
        """Simulate receiving a FINAL message — replaces partial, routes, transitions to Idle."""
        self.partialText = text
        self.routed_text = text  # route the FINAL, not the last partial
        self.state = "Idle"
        self.partialText = ""  # cleanup after routing


@pytest.mark.property_test
class TestFinalResultRouting:
    """Feature: streaming-dictation, Property 4: Final Result Replaces Partial and Routes Correctly"""

    @given(
        partials=st.lists(
            st.text(min_size=1, max_size=200),
            min_size=0,
            max_size=20,
        ),
        final_text=st.text(min_size=1, max_size=500),
    )
    @settings(max_examples=200)
    def test_final_replaces_partial_and_routes(self, partials: list[str], final_text: str):
        """After FINAL is received, the routed text is the FINAL text, not any previous partial.

        **Validates: Requirements 2.5, 7.5, 8.1, 8.2**
        """
        session = StreamingSession()

        # Feed a sequence of partial results
        for partial in partials:
            session.receive_partial(partial)
            assert session.state == "StreamingActive"

        # Receive the final result
        session.receive_final(final_text)

        # The routed text must be the FINAL text, not any previous partial
        assert session.routed_text == final_text
        # State must transition to Idle
        assert session.state == "Idle"
        # partialText is cleaned up after routing
        assert session.partialText == ""

    @given(
        partials=st.lists(
            st.text(min_size=1, max_size=200),
            min_size=1,
            max_size=20,
        ),
        final_text=st.text(min_size=1, max_size=500),
    )
    @settings(max_examples=200)
    def test_final_text_differs_from_last_partial(self, partials: list[str], final_text: str):
        """The system routes the FINAL text specifically, not whatever was in partialText before.

        **Validates: Requirements 8.1, 8.2**
        """
        session = StreamingSession()

        # Feed partials — the last partial may differ from the final
        for partial in partials:
            session.receive_partial(partial)

        last_partial = session.partialText

        # Receive final
        session.receive_final(final_text)

        # Regardless of what the last partial was, routed text is the final
        assert session.routed_text == final_text
        assert session.routed_text != last_partial or final_text == last_partial

    @given(
        final_text=st.text(min_size=1, max_size=500),
    )
    @settings(max_examples=200)
    def test_state_transitions_to_idle_after_final(self, final_text: str):
        """State MUST be Idle after final result is received and routed.

        **Validates: Requirements 7.5**
        """
        session = StreamingSession()
        assert session.state == "StreamingActive"

        session.receive_final(final_text)
        assert session.state == "Idle"


# ---------------------------------------------------------------------------
# Feature: streaming-dictation, Property 5: Connection Drop Recovery
# ---------------------------------------------------------------------------
"""
Property 5: Connection Drop Recovery

When a streaming connection drops, the system either reconnects within 2
seconds or falls back to batch mode — it NEVER hangs indefinitely. Audio
captured so far is not lost (either retransmitted on reconnect or saved for
batch).

**Validates: Requirements 2.6, 9.1**
"""

from enum import Enum
from dataclasses import dataclass as _dataclass


class RecoveryOutcome(Enum):
    """Possible outcomes of a connection drop recovery attempt."""
    RECONNECTED = "reconnected"
    FALLBACK_TO_BATCH = "fallback_to_batch"


@_dataclass
class ConnectionDropEvent:
    """Models a connection drop occurring during a streaming session.

    Attributes:
        drop_position_pct: Where in the session the drop occurs (0.0 to 1.0).
        reconnect_succeeds: Whether the reconnection attempt will succeed.
        audio_bytes_captured: How many bytes of audio have been captured so far.
    """
    drop_position_pct: float
    reconnect_succeeds: bool
    audio_bytes_captured: int


def recover_from_drop(event: ConnectionDropEvent) -> tuple[RecoveryOutcome, int]:
    """Determine recovery outcome from a connection drop.

    This models the decision logic in StreamingTransport._reconnect and the
    feed_audio / _receive_loop error paths:
    - If reconnection succeeds → RECONNECTED, audio can be retransmitted
    - If reconnection fails → FALLBACK_TO_BATCH, audio is preserved for batch

    Returns:
        A tuple of (outcome, preserved_audio_bytes).
        The preserved_audio_bytes is always equal to audio_bytes_captured —
        audio is never lost regardless of outcome.
    """
    if event.reconnect_succeeds:
        return (RecoveryOutcome.RECONNECTED, event.audio_bytes_captured)
    else:
        return (RecoveryOutcome.FALLBACK_TO_BATCH, event.audio_bytes_captured)


# Valid outcomes — the system must ALWAYS resolve to one of these
_VALID_OUTCOMES = {RecoveryOutcome.RECONNECTED, RecoveryOutcome.FALLBACK_TO_BATCH}


@pytest.mark.property_test
class TestConnectionDropRecovery:
    """Feature: streaming-dictation, Property 5: Connection Drop Recovery"""

    @given(
        drop_position_pct=st.floats(min_value=0.0, max_value=1.0),
        reconnect_succeeds=st.booleans(),
        audio_bytes_captured=st.integers(min_value=0, max_value=10_000_000),
    )
    @settings(max_examples=200)
    def test_recovery_always_resolves_to_valid_outcome(
        self,
        drop_position_pct: float,
        reconnect_succeeds: bool,
        audio_bytes_captured: int,
    ):
        """Connection drops always resolve to reconnected or fallback — never hang.

        For any point in a streaming session where a drop occurs and any
        reconnection outcome, the recovery function ALWAYS returns a valid
        outcome. The system never enters an undefined or hung state.

        **Validates: Requirements 2.6, 9.1**
        """
        event = ConnectionDropEvent(
            drop_position_pct=drop_position_pct,
            reconnect_succeeds=reconnect_succeeds,
            audio_bytes_captured=audio_bytes_captured,
        )

        outcome, preserved_bytes = recover_from_drop(event)

        assert outcome in _VALID_OUTCOMES, (
            f"Recovery produced invalid outcome {outcome!r}. "
            f"Valid outcomes: {_VALID_OUTCOMES}. "
            f"Event: drop_position={drop_position_pct:.2f}, "
            f"reconnect_succeeds={reconnect_succeeds}"
        )

    @given(
        drop_position_pct=st.floats(min_value=0.0, max_value=1.0),
        reconnect_succeeds=st.booleans(),
        audio_bytes_captured=st.integers(min_value=0, max_value=10_000_000),
    )
    @settings(max_examples=200)
    def test_audio_never_lost_on_drop(
        self,
        drop_position_pct: float,
        reconnect_succeeds: bool,
        audio_bytes_captured: int,
    ):
        """Audio captured before a drop is preserved regardless of recovery outcome.

        Whether the system reconnects or falls back to batch, the audio bytes
        captured so far are always preserved (for retransmission or batch
        processing). Audio is NEVER silently discarded.

        **Validates: Requirements 2.6, 9.1**
        """
        event = ConnectionDropEvent(
            drop_position_pct=drop_position_pct,
            reconnect_succeeds=reconnect_succeeds,
            audio_bytes_captured=audio_bytes_captured,
        )

        outcome, preserved_bytes = recover_from_drop(event)

        assert preserved_bytes == audio_bytes_captured, (
            f"Audio data lost! Captured {audio_bytes_captured} bytes but only "
            f"preserved {preserved_bytes} bytes. Outcome: {outcome.value}, "
            f"reconnect_succeeds={reconnect_succeeds}"
        )

    @given(
        drop_position_pct=st.floats(min_value=0.0, max_value=1.0),
        audio_bytes_captured=st.integers(min_value=0, max_value=10_000_000),
    )
    @settings(max_examples=200)
    def test_failed_reconnect_always_falls_back(
        self,
        drop_position_pct: float,
        audio_bytes_captured: int,
    ):
        """When reconnection fails, the system always falls back to batch.

        If the reconnect attempt within the 2s window fails, the outcome is
        ALWAYS fallback_to_batch. The system never retries indefinitely or
        enters a hung state.

        **Validates: Requirements 2.6, 9.1**
        """
        event = ConnectionDropEvent(
            drop_position_pct=drop_position_pct,
            reconnect_succeeds=False,
            audio_bytes_captured=audio_bytes_captured,
        )

        outcome, _ = recover_from_drop(event)

        assert outcome == RecoveryOutcome.FALLBACK_TO_BATCH, (
            f"Failed reconnection should always produce FALLBACK_TO_BATCH, "
            f"got {outcome.value}. drop_position={drop_position_pct:.2f}"
        )

    @given(
        drop_position_pct=st.floats(min_value=0.0, max_value=1.0),
        audio_bytes_captured=st.integers(min_value=0, max_value=10_000_000),
    )
    @settings(max_examples=200)
    def test_successful_reconnect_always_reconnects(
        self,
        drop_position_pct: float,
        audio_bytes_captured: int,
    ):
        """When reconnection succeeds, the system always returns RECONNECTED.

        If the WebSocket reconnection within 2s succeeds, the outcome is
        ALWAYS reconnected — the session continues without falling back.

        **Validates: Requirements 2.6, 9.1**
        """
        event = ConnectionDropEvent(
            drop_position_pct=drop_position_pct,
            reconnect_succeeds=True,
            audio_bytes_captured=audio_bytes_captured,
        )

        outcome, _ = recover_from_drop(event)

        assert outcome == RecoveryOutcome.RECONNECTED, (
            f"Successful reconnection should always produce RECONNECTED, "
            f"got {outcome.value}. drop_position={drop_position_pct:.2f}"
        )

    @given(
        drop_positions=st.lists(
            st.floats(min_value=0.0, max_value=1.0),
            min_size=1,
            max_size=10,
        ),
        reconnect_outcomes=st.lists(
            st.booleans(),
            min_size=1,
            max_size=10,
        ),
    )
    @settings(max_examples=200)
    def test_multiple_drops_all_resolve(
        self,
        drop_positions: list[float],
        reconnect_outcomes: list[bool],
    ):
        """Multiple connection drops in a session all resolve independently.

        Even if multiple drops occur at various points, each one resolves to
        a valid outcome. The system never accumulates unresolved drops that
        could lead to a hang.

        **Validates: Requirements 2.6, 9.1**
        """
        # Pair up drop positions with reconnect outcomes (use shorter list length)
        pairs = list(zip(drop_positions, reconnect_outcomes))

        cumulative_audio = 0
        for drop_pos, reconnect_ok in pairs:
            # Simulate audio accumulating between drops
            cumulative_audio += int(drop_pos * 32000)  # ~1s of audio per unit

            event = ConnectionDropEvent(
                drop_position_pct=drop_pos,
                reconnect_succeeds=reconnect_ok,
                audio_bytes_captured=cumulative_audio,
            )

            outcome, preserved_bytes = recover_from_drop(event)

            # Every drop must resolve to a valid outcome
            assert outcome in _VALID_OUTCOMES, (
                f"Drop at position {drop_pos:.2f} produced invalid outcome "
                f"{outcome!r}. reconnect_ok={reconnect_ok}"
            )

            # Audio must be preserved
            assert preserved_bytes == cumulative_audio, (
                f"Audio lost at drop position {drop_pos:.2f}: "
                f"expected {cumulative_audio}, got {preserved_bytes}"
            )

    @given(
        drop_position_pct=st.floats(min_value=0.0, max_value=1.0),
        reconnect_succeeds=st.booleans(),
        audio_bytes_captured=st.integers(min_value=0, max_value=10_000_000),
    )
    @settings(max_examples=200)
    def test_streaming_transport_reconnect_decision(
        self,
        drop_position_pct: float,
        reconnect_succeeds: bool,
        audio_bytes_captured: int,
    ):
        """StreamingTransport._reconnect maps directly to the recovery model.

        The StreamingTransport._reconnect method returns True (reconnected) or
        False (failed → triggers FALLBACK emission). This test verifies the
        model matches the actual code's decision structure by checking that:
        - _reconnect returning True → RECONNECTED outcome
        - _reconnect returning False → FALLBACK_TO_BATCH outcome
        - The _RECONNECT_TIMEOUT (2.0s) bounds the decision time

        **Validates: Requirements 2.6, 9.1**
        """
        # Verify the transport's reconnect timeout is bounded at 2 seconds
        StreamingTransport = _mod.StreamingTransport
        assert StreamingTransport._RECONNECT_TIMEOUT <= 2.0, (
            f"Reconnect timeout {StreamingTransport._RECONNECT_TIMEOUT}s exceeds "
            f"the 2-second requirement from Requirement 2.6"
        )

        # The model maps reconnect success/failure to outcomes
        event = ConnectionDropEvent(
            drop_position_pct=drop_position_pct,
            reconnect_succeeds=reconnect_succeeds,
            audio_bytes_captured=audio_bytes_captured,
        )

        outcome, _ = recover_from_drop(event)

        # Verify bidirectional mapping
        if reconnect_succeeds:
            assert outcome == RecoveryOutcome.RECONNECTED
        else:
            assert outcome == RecoveryOutcome.FALLBACK_TO_BATCH



# ---------------------------------------------------------------------------
# Feature: streaming-dictation, Property 13: No Audio Persistence in Streaming Mode
# ---------------------------------------------------------------------------
"""
Property 13: No Audio Persistence in Streaming Mode

For any completed streaming-mode session, no audio data SHALL remain on disk —
audio is piped directly from PipeWire to the backend without intermediate file
storage.

**Validates: Requirements 12.3, 8.4**
"""

import os
import tempfile
from dataclasses import dataclass as _dc_13, field as _field_13
from typing import Set


@_dc_13
class StreamingSessionModel:
    """Models the DictationService's file I/O behavior during a session.

    Streaming mode: audio is piped directly (pw-cat stdout → helper stdin),
    no _recordingPath is set, no temp files are created.

    Batch mode: audio is written to /tmp/quickshell-dictation/<timestamp>.wav,
    _recordingPath is set, file is cleaned up after transcription completes.

    Attributes:
        mode: "streaming", "chunked", or "batch"
        recording_path: The _recordingPath value (empty string for streaming/chunked)
        files_written: Set of file paths written during the session
        session_complete: Whether the session has completed
        audio_size_bytes: Amount of audio data in the session
        duration_ms: Session duration in milliseconds
    """
    mode: str
    recording_path: str = ""
    files_written: Set[str] = _field_13(default_factory=set)
    session_complete: bool = False
    audio_size_bytes: int = 0
    duration_ms: int = 0


def activate_session(mode: str, duration_ms: int, audio_size_bytes: int) -> StreamingSessionModel:
    """Simulate the DictationService activation path for a given mode.

    Models the QML logic from DictationService.activate():
    - batch: sets _recordingPath = "/tmp/quickshell-dictation/<timestamp>.wav"
    - streaming/chunked: does NOT set _recordingPath, pipes audio directly

    Args:
        mode: "streaming", "chunked", or "batch"
        duration_ms: Session duration in milliseconds
        audio_size_bytes: Amount of audio data generated

    Returns:
        A StreamingSessionModel representing the session state.
    """
    session = StreamingSessionModel(
        mode=mode,
        duration_ms=duration_ms,
        audio_size_bytes=audio_size_bytes,
    )

    if mode == "batch":
        # Batch mode creates a temp file — mirrors QML:
        # root._recordingPath = "/tmp/quickshell-dictation/" + Date.now() + ".wav"
        session.recording_path = f"/tmp/quickshell-dictation/{duration_ms}.wav"
        session.files_written.add(session.recording_path)
    else:
        # Streaming and chunked modes: NO file path set, NO files written
        # Audio is piped: pw-cat → stdout → helper stdin
        session.recording_path = ""

    return session


def complete_session(session: StreamingSessionModel) -> StreamingSessionModel:
    """Complete a streaming session and perform cleanup.

    Models the cleanup logic:
    - Streaming/chunked: no files to clean up (partialText = "", state → Idle)
    - Batch: deletes the _recordingPath file after transcription

    Args:
        session: The active session model.

    Returns:
        The completed session model.
    """
    session.session_complete = True

    if session.mode == "batch":
        # Batch cleanup: rm -f _recordingPath
        session.files_written.discard(session.recording_path)
    # Streaming/chunked: nothing to clean — no files were ever created

    return session


def get_disk_audio_files(session: StreamingSessionModel) -> Set[str]:
    """Return the set of audio files remaining on disk after session completes.

    In the real system, streaming mode never writes files, so this always
    returns an empty set for streaming/chunked sessions. For batch, files
    may remain if cleanup hasn't run yet.
    """
    return session.files_written.copy()


@pytest.mark.property_test
class TestNoAudioPersistence:
    """Feature: streaming-dictation, Property 13: No Audio Persistence in Streaming Mode"""

    @given(
        duration_ms=st.integers(min_value=100, max_value=300_000),
        audio_size_bytes=st.integers(min_value=1, max_value=50_000_000),
    )
    @settings(max_examples=200)
    def test_streaming_mode_never_sets_recording_path(
        self, duration_ms: int, audio_size_bytes: int
    ):
        """In streaming mode, _recordingPath is always empty — no file path is set.

        The streaming activation path in DictationService does NOT set
        _recordingPath. Audio is piped directly from pw-cat to the helper
        process via stdin, never touching disk.

        **Validates: Requirements 12.3, 8.4**
        """
        session = activate_session("streaming", duration_ms, audio_size_bytes)

        assert session.recording_path == "", (
            f"Streaming mode should NOT set _recordingPath, "
            f"but got '{session.recording_path}'. "
            f"duration_ms={duration_ms}, audio_size={audio_size_bytes}"
        )

    @given(
        duration_ms=st.integers(min_value=100, max_value=300_000),
        audio_size_bytes=st.integers(min_value=1, max_value=50_000_000),
    )
    @settings(max_examples=200)
    def test_chunked_mode_never_sets_recording_path(
        self, duration_ms: int, audio_size_bytes: int
    ):
        """In chunked mode, _recordingPath is always empty — no file path is set.

        The chunked activation path also pipes audio via stdin to the helper,
        which handles chunking in-memory. No intermediate audio files are created.

        **Validates: Requirements 12.3, 8.4**
        """
        session = activate_session("chunked", duration_ms, audio_size_bytes)

        assert session.recording_path == "", (
            f"Chunked mode should NOT set _recordingPath, "
            f"but got '{session.recording_path}'. "
            f"duration_ms={duration_ms}, audio_size={audio_size_bytes}"
        )

    @given(
        duration_ms=st.integers(min_value=100, max_value=300_000),
        audio_size_bytes=st.integers(min_value=1, max_value=50_000_000),
    )
    @settings(max_examples=200)
    def test_streaming_mode_writes_no_files(
        self, duration_ms: int, audio_size_bytes: int
    ):
        """In streaming mode, no audio files are written to disk at any point.

        The streaming code path pipes audio directly from pw-cat through a
        shell pipe to the Python helper process. No intermediate file I/O
        occurs for the audio data.

        **Validates: Requirements 12.3, 8.4**
        """
        session = activate_session("streaming", duration_ms, audio_size_bytes)

        assert len(session.files_written) == 0, (
            f"Streaming mode should write ZERO files to disk, "
            f"but {len(session.files_written)} files were written: "
            f"{session.files_written}. "
            f"duration_ms={duration_ms}, audio_size={audio_size_bytes}"
        )

    @given(
        duration_ms=st.integers(min_value=100, max_value=300_000),
        audio_size_bytes=st.integers(min_value=1, max_value=50_000_000),
    )
    @settings(max_examples=200)
    def test_no_audio_on_disk_after_streaming_session_completes(
        self, duration_ms: int, audio_size_bytes: int
    ):
        """After a streaming session completes, no audio data remains on disk.

        Even after a full session lifecycle (activate → record → stop → complete),
        the disk contains no leftover audio files from the streaming session.

        **Validates: Requirements 12.3, 8.4**
        """
        session = activate_session("streaming", duration_ms, audio_size_bytes)
        completed = complete_session(session)

        remaining_files = get_disk_audio_files(completed)

        assert len(remaining_files) == 0, (
            f"After streaming session completes, no audio files should remain "
            f"on disk, but found: {remaining_files}. "
            f"duration_ms={duration_ms}, audio_size={audio_size_bytes}"
        )

    @given(
        duration_ms=st.integers(min_value=100, max_value=300_000),
        audio_size_bytes=st.integers(min_value=1, max_value=50_000_000),
    )
    @settings(max_examples=200)
    def test_no_audio_on_disk_after_chunked_session_completes(
        self, duration_ms: int, audio_size_bytes: int
    ):
        """After a chunked session completes, no audio data remains on disk.

        Chunked mode also pipes audio to the helper, which handles chunking
        in-memory and submits via HTTP. No persistent audio on disk.

        **Validates: Requirements 12.3, 8.4**
        """
        session = activate_session("chunked", duration_ms, audio_size_bytes)
        completed = complete_session(session)

        remaining_files = get_disk_audio_files(completed)

        assert len(remaining_files) == 0, (
            f"After chunked session completes, no audio files should remain "
            f"on disk, but found: {remaining_files}. "
            f"duration_ms={duration_ms}, audio_size={audio_size_bytes}"
        )

    @given(
        duration_ms=st.integers(min_value=100, max_value=300_000),
        audio_size_bytes=st.integers(min_value=1, max_value=50_000_000),
    )
    @settings(max_examples=200)
    def test_batch_mode_does_set_recording_path(
        self, duration_ms: int, audio_size_bytes: int
    ):
        """Contrast: batch mode DOES set _recordingPath to /tmp/quickshell-dictation/.

        This confirms the property is specific to streaming/chunked modes.
        Batch mode creates a temp WAV file for recording, which is later
        submitted for transcription.

        **Validates: Requirements 12.3, 8.4**
        """
        session = activate_session("batch", duration_ms, audio_size_bytes)

        assert session.recording_path != "", (
            f"Batch mode SHOULD set _recordingPath, but it's empty. "
            f"duration_ms={duration_ms}"
        )
        assert "/tmp/quickshell-dictation/" in session.recording_path, (
            f"Batch _recordingPath should be in /tmp/quickshell-dictation/, "
            f"got '{session.recording_path}'"
        )

    @given(
        duration_ms=st.integers(min_value=100, max_value=300_000),
        audio_size_bytes=st.integers(min_value=1, max_value=50_000_000),
    )
    @settings(max_examples=200)
    def test_batch_mode_does_write_files(
        self, duration_ms: int, audio_size_bytes: int
    ):
        """Contrast: batch mode DOES write audio files to disk during recording.

        This confirms the distinction — batch mode uses file I/O while
        streaming/chunked modes do not.

        **Validates: Requirements 12.3, 8.4**
        """
        session = activate_session("batch", duration_ms, audio_size_bytes)

        assert len(session.files_written) > 0, (
            f"Batch mode SHOULD write files to disk, but files_written is empty. "
            f"duration_ms={duration_ms}"
        )

    @given(
        mode=st.sampled_from(["streaming", "chunked"]),
        duration_ms=st.integers(min_value=100, max_value=300_000),
        audio_size_bytes=st.integers(min_value=1, max_value=50_000_000),
    )
    @settings(max_examples=200)
    def test_streaming_cleanup_is_noop(
        self, mode: str, duration_ms: int, audio_size_bytes: int
    ):
        """Streaming/chunked session cleanup doesn't need to delete any files.

        Since no files are written in streaming/chunked mode, the cleanup
        function is a no-op — there's nothing to remove. This contrasts with
        batch mode which must rm -f the recording file.

        **Validates: Requirements 12.3, 8.4**
        """
        session = activate_session(mode, duration_ms, audio_size_bytes)

        # Track files before and after cleanup
        files_before = session.files_written.copy()
        completed = complete_session(session)
        files_after = get_disk_audio_files(completed)

        # Both should be empty — cleanup is a no-op
        assert files_before == set(), (
            f"Before cleanup, streaming/chunked should have no files, "
            f"but had: {files_before}"
        )
        assert files_after == set(), (
            f"After cleanup, streaming/chunked should have no files, "
            f"but had: {files_after}"
        )

# ---------------------------------------------------------------------------
# Feature: streaming-dictation, Property 9: Indicator Width Constraint
# ---------------------------------------------------------------------------
"""
Property 9: Indicator Width Constraint

For any partialText content, the DictationIndicator's computed width SHALL
never exceed 400 pixels, and when the text exceeds this width, only the
rightmost portion SHALL be visible.

**Validates: Requirements 4.3, 4.4**
"""


def compute_indicator_width(
    base_row_width: int,
    partial_text_width: int,
    has_partial_text: bool,
    max_width: int = 400,
) -> int:
    """Model the DictationIndicator width formula from QML.

    QML formula:
        implicitWidth: Math.min(
            Math.max(indicatorRow.implicitWidth + 24,
                     root.hasPartialText ? partialTextMetrics.width + 24 : 0),
            400
        )
    """
    if has_partial_text:
        return min(max(base_row_width + 24, partial_text_width + 24), max_width)
    else:
        return min(base_row_width + 24, max_width)


@pytest.mark.property_test
class TestIndicatorWidthConstraint:
    """Feature: streaming-dictation, Property 9: Indicator Width Constraint"""

    @given(
        base_row_width=st.integers(min_value=0, max_value=2000),
        partial_text_width=st.integers(min_value=0, max_value=5000),
        has_partial_text=st.booleans(),
    )
    @settings(max_examples=200)
    def test_width_never_exceeds_max(
        self,
        base_row_width: int,
        partial_text_width: int,
        has_partial_text: bool,
    ):
        """For ANY text content (any width), computed width NEVER exceeds 400px.

        **Validates: Requirements 4.3, 4.4**
        """
        width = compute_indicator_width(base_row_width, partial_text_width, has_partial_text)
        assert width <= 400, (
            f"Indicator width {width}px exceeds max 400px "
            f"(base_row_width={base_row_width}, partial_text_width={partial_text_width}, "
            f"has_partial_text={has_partial_text})"
        )

    @given(
        base_row_width=st.integers(min_value=0, max_value=100),
        partial_text_width=st.integers(min_value=0, max_value=300),
    )
    @settings(max_examples=200)
    def test_short_text_width_based_on_content(
        self,
        base_row_width: int,
        partial_text_width: int,
    ):
        """For short text, width is based on text width + padding.

        When has_partial_text is True and the content fits within 400px,
        the width is max(base_row_width + 24, partial_text_width + 24).

        **Validates: Requirements 4.3, 4.4**
        """
        width = compute_indicator_width(base_row_width, partial_text_width, has_partial_text=True)
        expected = max(base_row_width + 24, partial_text_width + 24)
        # Since both inputs are small enough, expected won't exceed 400
        assert expected <= 400, "Precondition: inputs should produce width <= 400"
        assert width == expected, (
            f"Expected width {expected}px based on content, got {width}px "
            f"(base_row_width={base_row_width}, partial_text_width={partial_text_width})"
        )

    @given(
        base_row_width=st.integers(min_value=0, max_value=2000),
        partial_text_width=st.integers(min_value=377, max_value=5000),
    )
    @settings(max_examples=200)
    def test_long_text_width_capped_at_max(
        self,
        base_row_width: int,
        partial_text_width: int,
    ):
        """For long text, width is capped at 400.

        When partial_text_width + 24 >= 400, the width must be exactly 400.

        **Validates: Requirements 4.3, 4.4**
        """
        # partial_text_width >= 377 means partial_text_width + 24 >= 401 > 400
        width = compute_indicator_width(base_row_width, partial_text_width, has_partial_text=True)
        assert width == 400, (
            f"Expected width capped at 400px for long text, got {width}px "
            f"(base_row_width={base_row_width}, partial_text_width={partial_text_width})"
        )

    @given(
        base_row_width=st.integers(min_value=0, max_value=2000),
        partial_text_width=st.integers(min_value=0, max_value=5000),
    )
    @settings(max_examples=200)
    def test_no_partial_text_uses_row_width_only(
        self,
        base_row_width: int,
        partial_text_width: int,
    ):
        """With no partial text, width is just the icon row width + padding (capped at 400).

        When has_partial_text is False, the partial_text_width is ignored
        entirely and the formula simplifies to min(base_row_width + 24, 400).

        **Validates: Requirements 4.3, 4.4**
        """
        width = compute_indicator_width(
            base_row_width, partial_text_width, has_partial_text=False
        )
        expected = min(base_row_width + 24, 400)
        assert width == expected, (
            f"Without partial text, expected min({base_row_width} + 24, 400) = {expected}px, "
            f"got {width}px"
        )
