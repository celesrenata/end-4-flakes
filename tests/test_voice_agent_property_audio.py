# Feature: streaming-voice-agent, Property 2: Audio format preservation
"""
Property 2: Audio format preservation

For any AUDIO_RESPONSE event emitted by the helper, decoding the `audio` field
from base64 SHALL produce a byte sequence whose length is a multiple of 2
(16-bit samples), and the decoded PCM data SHALL be playable at the backend's
configured sample rate (16kHz for Nova Sonic, 24kHz for OpenAI Realtime).

**Validates: Requirements 12.5, 13.1, 13.2, 13.3**
"""

import sys
from pathlib import Path

from hypothesis import given, settings
import hypothesis.strategies as st

# Add the helper script directory to the path
SCRIPT_DIR = Path(__file__).parent.parent / "configs" / "quickshell" / "ii" / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from voice_agent_backends.protocol import decode_audio, encode_audio


# Strategy: generate random byte sequences where length is a multiple of 2
# (16-bit PCM samples = 2 bytes each)
pcm_data_strategy = st.binary(min_size=0, max_size=8192).filter(
    lambda b: len(b) % 2 == 0
)


@settings(max_examples=200)
@given(pcm_data=pcm_data_strategy)
def test_audio_encode_decode_preserves_length(pcm_data: bytes) -> None:
    """Encoding then decoding PCM data preserves the byte length."""
    encoded = encode_audio(pcm_data)
    decoded = decode_audio(encoded)
    assert len(decoded) == len(pcm_data)


@settings(max_examples=200)
@given(pcm_data=pcm_data_strategy)
def test_audio_encode_decode_preserves_content(pcm_data: bytes) -> None:
    """Encoding then decoding PCM data produces identical bytes."""
    encoded = encode_audio(pcm_data)
    decoded = decode_audio(encoded)
    assert decoded == pcm_data


@settings(max_examples=200)
@given(pcm_data=pcm_data_strategy)
def test_encoded_audio_is_valid_base64_ascii(pcm_data: bytes) -> None:
    """Encoded audio string contains only valid ASCII characters (base64 charset)."""
    encoded = encode_audio(pcm_data)
    assert encoded.isascii()
    # Verify all characters are in the base64 alphabet (A-Z, a-z, 0-9, +, /, =)
    valid_chars = set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
    )
    assert all(c in valid_chars for c in encoded)


@settings(max_examples=200)
@given(pcm_data=pcm_data_strategy)
def test_pcm_chunk_alignment_16bit_mono(pcm_data: bytes) -> None:
    """For 16kHz mono s16 audio, one frame = 2 bytes. Decoded length is always
    frame-aligned (multiple of 2)."""
    encoded = encode_audio(pcm_data)
    decoded = decode_audio(encoded)
    # 16-bit mono: each sample is 2 bytes
    assert len(decoded) % 2 == 0
