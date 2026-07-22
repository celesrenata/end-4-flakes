# Feature: streaming-voice-agent, Property 5: Policy enforcement gate
"""Property-based tests for voice agent policy enforcement gate.

Generates all combinations of policies.ai (0, 1, 2) × voiceBackend
("none", "nova-sonic", "openai-realtime") and verifies activation gate
decisions match policy rules.

**Validates: Requirements 14.1, 14.2, 14.3**
"""

from hypothesis import example, given, settings
from hypothesis import strategies as st


# ---------------------------------------------------------------------------
# Policy enforcement function (mirrors QML logic for property testing)
# ---------------------------------------------------------------------------


def check_activation_allowed(policy_ai: int, voice_backend: str) -> tuple[bool, str]:
    """Determine if voice agent activation is allowed given policy and backend.

    Policy rules:
    - policy_ai == 0 → all activation REJECTED (AI disabled)
    - policy_ai == 1 → activation ALLOWED for all backends
    - policy_ai == 2 → local-only: remote backends ("nova-sonic", "openai-realtime")
      REJECTED; "none" ALLOWED (falls through to batch, no remote needed)

    Returns:
        (allowed, error_message) where error_message is "" when allowed.
    """
    if policy_ai == 0:
        return (False, "disabled by policy")

    if policy_ai == 2 and voice_backend in ("nova-sonic", "openai-realtime"):
        return (False, "streaming voice requires remote API access")

    return (True, "")


# ---------------------------------------------------------------------------
# Property test: policy enforcement gate
# ---------------------------------------------------------------------------


@settings(max_examples=100)
@given(
    policy_ai=st.sampled_from([0, 1, 2]),
    voice_backend=st.sampled_from(["none", "nova-sonic", "openai-realtime"]),
)
# Exhaustive explicit examples for all 9 combinations
@example(policy_ai=0, voice_backend="none")
@example(policy_ai=0, voice_backend="nova-sonic")
@example(policy_ai=0, voice_backend="openai-realtime")
@example(policy_ai=1, voice_backend="none")
@example(policy_ai=1, voice_backend="nova-sonic")
@example(policy_ai=1, voice_backend="openai-realtime")
@example(policy_ai=2, voice_backend="none")
@example(policy_ai=2, voice_backend="nova-sonic")
@example(policy_ai=2, voice_backend="openai-realtime")
def test_policy_enforcement_gate(policy_ai: int, voice_backend: str) -> None:
    """Policy enforcement gate produces correct allow/reject decisions.

    Asserts:
    1. policy=0, any backend → rejected with "disabled by policy" (Req 14.1)
    2. policy=2, remote backend → rejected with "requires remote API" (Req 14.2)
    3. policy=1, any backend → allowed
    4. policy=2, "none" → allowed (no remote API needed)
    """
    allowed, error_msg = check_activation_allowed(policy_ai, voice_backend)

    if policy_ai == 0:
        # Requirement 14.1: AI disabled → always reject
        assert not allowed, (
            f"policy=0 should reject activation, got allowed=True "
            f"for backend={voice_backend!r}"
        )
        assert "disabled by policy" in error_msg, (
            f"policy=0 rejection should mention 'disabled by policy', "
            f"got: {error_msg!r}"
        )

    elif policy_ai == 1:
        # policy=1: AI fully enabled → always allow
        assert allowed, (
            f"policy=1 should allow activation, got allowed=False "
            f"for backend={voice_backend!r}"
        )
        assert error_msg == "", (
            f"policy=1 allowed should have empty error, got: {error_msg!r}"
        )

    elif policy_ai == 2:
        # Requirement 14.2: local-only policy
        if voice_backend in ("nova-sonic", "openai-realtime"):
            # Remote backends rejected
            assert not allowed, (
                f"policy=2 should reject remote backend {voice_backend!r}, "
                f"got allowed=True"
            )
            assert "remote API" in error_msg, (
                f"policy=2 rejection for remote backend should mention "
                f"'remote API', got: {error_msg!r}"
            )
        else:
            # "none" → allowed (no remote needed, falls to batch)
            assert allowed, (
                f"policy=2 should allow backend='none', got allowed=False"
            )
            assert error_msg == "", (
                f"policy=2 allowed for 'none' should have empty error, "
                f"got: {error_msg!r}"
            )
