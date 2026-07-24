# Feature: ai-desktop-control, Property 14: Bluetooth response sanitization
"""
Property-based tests for Bluetooth response sanitization.

Property 14: For any bluetoothctl output that contains PIN codes, link keys,
or pairing keys (matching patterns like "Key:", "PIN:", "Passkey:", or hex
key strings of 32+ chars), the sanitized output SHALL NOT contain those
sensitive values. Normal device info (name, address, class) must be preserved.

**Validates: Requirements 9.4**
"""

import re
import string

from hypothesis import given, settings, assume
from hypothesis import strategies as st

from ii_desktop_mcp.tools.bluetooth import _sanitize_output


# --- Strategies ---

# MAC addresses like AA:BB:CC:DD:EE:FF
_mac_address = st.tuples(
    *[st.integers(min_value=0, max_value=255) for _ in range(6)]
).map(lambda octets: ":".join(f"{b:02X}" for b in octets))

# Device names: printable strings without newlines
_device_name = st.text(
    alphabet=st.characters(whitelist_categories=("L", "N", "P", "Z"),
                           blacklist_characters="\n\r"),
    min_size=1,
    max_size=30,
)

# Normal device info lines that should be PRESERVED
_normal_device_lines = st.one_of(
    # "Device AA:BB:CC:DD:EE:FF SomeName"
    st.tuples(_mac_address, _device_name).map(
        lambda t: f"Device {t[0]} {t[1]}"
    ),
    # "Name: SomeDevice"
    _device_name.map(lambda n: f"\tName: {n}"),
    # "Address: AA:BB:CC:DD:EE:FF"
    _mac_address.map(lambda m: f"\tAddress: {m}"),
    # "Class: 0x123456"
    st.integers(min_value=0, max_value=0xFFFFFF).map(
        lambda c: f"\tClass: 0x{c:06x}"
    ),
    # "Powered: yes/no"
    st.sampled_from(["\tPowered: yes", "\tPowered: no"]),
    # "Connected: yes/no"
    st.sampled_from(["\tConnected: yes", "\tConnected: no"]),
    # "Discovering: yes/no"
    st.sampled_from(["\tDiscovering: yes", "\tDiscovering: no"]),
)

# Hex key strings (32+ hex chars) - these simulate crypto key material
_hex_key_string = st.integers(min_value=32, max_value=64).flatmap(
    lambda n: st.text(
        alphabet="0123456789ABCDEFabcdef", min_size=n, max_size=n
    )
)

# Sensitive lines that MUST be stripped
_sensitive_lines = st.one_of(
    # "LinkKey: 0x<hex>"
    _hex_key_string.map(lambda h: f"\tLinkKey: 0x{h}"),
    # "Key: <hex>"
    _hex_key_string.map(lambda h: f"\tKey: {h}"),
    # "PIN: 1234" (4-6 digit PIN)
    st.integers(min_value=0, max_value=999999).map(
        lambda p: f"\tPIN: {p:04d}"
    ),
    # "Passkey: 123456"
    st.integers(min_value=0, max_value=999999).map(
        lambda p: f"\tPasskey: {p:06d}"
    ),
    # "IdentityResolvingKey: <hex>"
    _hex_key_string.map(lambda h: f"\tIdentityResolvingKey: {h}"),
    # "LocalSignatureKey: <hex>"
    _hex_key_string.map(lambda h: f"\tLocalSignatureKey: {h}"),
    # "RemoteSignatureKey: <hex>"
    _hex_key_string.map(lambda h: f"\tRemoteSignatureKey: {h}"),
    # Standalone long hex strings (look like key material)
    _hex_key_string.map(lambda h: f"\t{h}"),
)


# --- Property 14: Bluetooth response sanitization ---


@settings(max_examples=100)
@given(
    normal_lines=st.lists(_normal_device_lines, min_size=1, max_size=5),
    sensitive_lines=st.lists(_sensitive_lines, min_size=1, max_size=5),
    insertion_indices=st.lists(st.integers(min_value=0, max_value=100), min_size=1, max_size=5),
)
def test_sensitive_patterns_removed_from_output(
    normal_lines: list[str],
    sensitive_lines: list[str],
    insertion_indices: list[int],
):
    """
    Property 14: For any bluetoothctl output containing sensitive patterns
    (Key:, PIN:, Passkey:, long hex strings), _sanitize_output must remove
    all sensitive content while leaving normal device info intact.

    **Validates: Requirements 9.4**
    """
    # Build output by interleaving normal and sensitive lines
    combined = list(normal_lines)
    for i, sensitive_line in enumerate(sensitive_lines):
        idx = insertion_indices[i % len(insertion_indices)] % (len(combined) + 1)
        combined.insert(idx, sensitive_line)

    raw_output = "\n".join(combined)
    sanitized = _sanitize_output(raw_output)

    # Assert: no sensitive keywords remain in sanitized output
    # Check for Key/PIN/Passkey words in context of sensitive lines
    for line in sanitized.splitlines():
        assert not re.search(r"\bLinkKey\b", line), (
            f"Sanitized output still contains 'LinkKey': {line!r}"
        )
        assert not re.search(r"\bIdentityResolvingKey\b", line), (
            f"Sanitized output still contains 'IdentityResolvingKey': {line!r}"
        )
        assert not re.search(r"\bLocalSignatureKey\b", line), (
            f"Sanitized output still contains 'LocalSignatureKey': {line!r}"
        )
        assert not re.search(r"\bRemoteSignatureKey\b", line), (
            f"Sanitized output still contains 'RemoteSignatureKey': {line!r}"
        )

    # Check no long hex strings (32+ chars) remain
    assert not re.search(r"\b[0-9A-Fa-f]{32,}\b", sanitized), (
        f"Sanitized output still contains a 32+ char hex string"
    )

    # Check lines with PIN: and Passkey: are removed
    for line in sanitized.splitlines():
        assert not re.search(r"\bPIN\b", line), (
            f"Sanitized output still contains 'PIN': {line!r}"
        )
        assert not re.search(r"\bPasskey\b", line), (
            f"Sanitized output still contains 'Passkey': {line!r}"
        )


@settings(max_examples=100)
@given(
    normal_lines=st.lists(_normal_device_lines, min_size=1, max_size=8),
)
def test_normal_device_info_preserved(normal_lines: list[str]):
    """
    Property 14 (preservation): For any bluetoothctl output containing only
    normal device information (names, addresses, class), _sanitize_output
    must preserve all content content (the meaningful payload of each line)
    without stripping it away. The function may strip leading/trailing
    whitespace from the overall output.

    **Validates: Requirements 9.4**
    """
    raw_output = "\n".join(normal_lines)
    sanitized = _sanitize_output(raw_output)

    # Each normal line's content (stripped) should appear in the sanitized output
    for line in normal_lines:
        line_content = line.strip()
        assert line_content in sanitized, (
            f"Normal device line content was incorrectly removed: {line_content!r}\n"
            f"Sanitized output: {sanitized!r}"
        )


@settings(max_examples=100)
@given(
    sensitive_line=_sensitive_lines,
)
def test_individual_sensitive_line_removed(sensitive_line: str):
    """
    Property 14 (individual): Each sensitive line type, when embedded in
    bluetoothctl output, must be fully removed by _sanitize_output.

    **Validates: Requirements 9.4**
    """
    # Wrap the sensitive line in some context (like bluetoothctl info output)
    raw_output = (
        f"Device AA:BB:CC:DD:EE:FF TestDevice\n"
        f"\tName: TestDevice\n"
        f"{sensitive_line}\n"
        f"\tConnected: yes\n"
    )
    sanitized = _sanitize_output(raw_output)

    # The sensitive line should not appear
    # Extract the actual sensitive content (strip leading whitespace for matching)
    stripped_sensitive = sensitive_line.strip()

    # Check that the key/PIN/passkey patterns are gone
    assert not re.search(r"\bLinkKey\b", sanitized), (
        f"'LinkKey' leaked in sanitized output"
    )
    assert not re.search(r"\bPIN\b", sanitized), (
        f"'PIN' leaked in sanitized output"
    )
    assert not re.search(r"\bPasskey\b", sanitized), (
        f"'Passkey' leaked in sanitized output"
    )
    assert not re.search(r"\bIdentityResolvingKey\b", sanitized), (
        f"'IdentityResolvingKey' leaked in sanitized output"
    )
    assert not re.search(r"\bLocalSignatureKey\b", sanitized), (
        f"'LocalSignatureKey' leaked in sanitized output"
    )
    assert not re.search(r"\bRemoteSignatureKey\b", sanitized), (
        f"'RemoteSignatureKey' leaked in sanitized output"
    )
    assert not re.search(r"\b[0-9A-Fa-f]{32,}\b", sanitized), (
        f"Long hex key string leaked in sanitized output"
    )

    # But the non-sensitive lines should be preserved
    assert "TestDevice" in sanitized, (
        f"Normal device name was incorrectly removed"
    )
    assert "Connected: yes" in sanitized, (
        f"Normal 'Connected' info was incorrectly removed"
    )
