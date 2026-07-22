# Feature: streaming-voice-agent, Property 6: Credential validation before connection
"""Property-based tests for voice agent credential validation.

Generates activation attempts with varying credential states (backend type,
AWS credential availability, OpenAI key presence) and verifies rejection
with descriptive errors when credentials are missing.

**Validates: Requirements 1.3, 1.4, 1.5**
"""

from hypothesis import example, given, settings
from hypothesis import strategies as st


# ---------------------------------------------------------------------------
# Credential validation function (mirrors VoiceAgentService.validateCredentials)
# ---------------------------------------------------------------------------


def check_credentials(
    voice_backend: str, aws_creds_detected: bool, openai_key: str
) -> tuple[bool, str]:
    """Validate credentials for the configured voice backend.

    Logic mirrors VoiceAgentService.qml validateCredentials():
    - "nova-sonic": requires aws_creds_detected == True
    - "openai-realtime": requires non-empty openai_key
    - "none": always valid (no streaming backend, no creds needed)

    Returns:
        (valid, error_message) where error_message is "" when valid.
    """
    if voice_backend == "nova-sonic":
        if not aws_creds_detected:
            return (False, "AWS credentials missing: add a [bedrock] profile to ~/.aws/credentials")
        return (True, "")

    if voice_backend == "openai-realtime":
        if not openai_key:
            return (False, "OpenAI API key missing: add your key in Provider Settings")
        return (True, "")

    # backend == "none" → no credentials needed
    return (True, "")


# ---------------------------------------------------------------------------
# Property test: credential validation before connection
# ---------------------------------------------------------------------------


@settings(max_examples=100)
@given(
    voice_backend=st.sampled_from(["none", "nova-sonic", "openai-realtime"]),
    aws_creds_detected=st.booleans(),
    openai_key=st.text(min_size=0, max_size=50),
)
# Key edge cases as explicit examples
@example(voice_backend="nova-sonic", aws_creds_detected=False, openai_key="")
@example(voice_backend="nova-sonic", aws_creds_detected=True, openai_key="")
@example(voice_backend="openai-realtime", aws_creds_detected=False, openai_key="")
@example(voice_backend="openai-realtime", aws_creds_detected=True, openai_key="sk-abc123")
@example(voice_backend="none", aws_creds_detected=False, openai_key="")
@example(voice_backend="none", aws_creds_detected=True, openai_key="sk-xyz")
def test_credential_validation_before_connection(
    voice_backend: str, aws_creds_detected: bool, openai_key: str
) -> None:
    """Credential validation produces correct accept/reject with descriptive errors.

    Asserts:
    1. backend="nova-sonic" + aws_creds=False → rejected with "AWS" in error (Req 1.3)
    2. backend="nova-sonic" + aws_creds=True → valid
    3. backend="openai-realtime" + empty key → rejected with "OpenAI" in error (Req 1.4)
    4. backend="openai-realtime" + non-empty key → valid
    5. backend="none" → always valid regardless of credential state
    6. On any rejection: error message is descriptive (non-empty) (Req 1.5)
    """
    valid, error_msg = check_credentials(voice_backend, aws_creds_detected, openai_key)

    if voice_backend == "nova-sonic":
        if not aws_creds_detected:
            # Requirement 1.3: AWS creds missing → reject
            assert not valid, (
                f"nova-sonic with aws_creds=False should reject, got valid=True"
            )
            assert "AWS" in error_msg, (
                f"nova-sonic rejection should mention 'AWS', got: {error_msg!r}"
            )
            # Requirement 1.5: descriptive error
            assert len(error_msg) > 0, "rejection error must be non-empty"
        else:
            # AWS creds present → valid
            assert valid, (
                f"nova-sonic with aws_creds=True should be valid, got valid=False"
            )
            assert error_msg == "", (
                f"valid credential check should have empty error, got: {error_msg!r}"
            )

    elif voice_backend == "openai-realtime":
        if not openai_key:
            # Requirement 1.4: OpenAI key missing → reject
            assert not valid, (
                f"openai-realtime with empty key should reject, got valid=True"
            )
            assert "OpenAI" in error_msg, (
                f"openai-realtime rejection should mention 'OpenAI', got: {error_msg!r}"
            )
            # Requirement 1.5: descriptive error
            assert len(error_msg) > 0, "rejection error must be non-empty"
        else:
            # OpenAI key present → valid
            assert valid, (
                f"openai-realtime with non-empty key should be valid, got valid=False"
            )
            assert error_msg == "", (
                f"valid credential check should have empty error, got: {error_msg!r}"
            )

    else:
        # backend="none" → always valid, no credentials needed
        assert valid, (
            f"backend='none' should always be valid regardless of creds, "
            f"got valid=False (aws_creds={aws_creds_detected}, key={openai_key!r})"
        )
        assert error_msg == "", (
            f"backend='none' valid should have empty error, got: {error_msg!r}"
        )
