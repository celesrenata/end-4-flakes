# Feature: dictation-debugging, Property 1: Bug Condition
"""
Bug Condition Exploration Test — Silent Pipeline Failure

This test surfaces counterexamples demonstrating that the dictation pipeline
fails silently at multiple stages:
- keyd trigger doesn't reach DictationService (missing Hyprland socket env)
- No structured state transition logging exists
- Transcription failures lack endpoint details
- Flake input points to GitHub (causing deployment regression)

**Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.7**

EXPECTED: All tests FAIL on unfixed code — failure confirms the bugs exist.
"""

import subprocess
import time

import pytest


class TestBugConditionExploration:
    """Surface counterexamples proving the dictation pipeline fails silently."""

    def test_1a_keyd_dispatch_without_env_not_logged(self):
        """
        Test 1a: Run hyprctl dispatch from sudo (simulating keyd's root context)
        without HYPRLAND_INSTANCE_SIGNATURE, then assert the failure is logged
        to journal with tag 'keyd-dictation'.

        EXPECTED TO FAIL: No wrapper script exists yet, so no logging occurs.
        The dispatch may succeed (since we're in a user session) or fail,
        but either way there's no keyd-dictation journal entry.
        """
        # Simulate what keyd does: dispatch from a context that may lack env vars.
        # We use env -i to strip environment, simulating keyd's root execution context.
        # The key assertion is that the FAILURE is LOGGED — not just that it fails.
        result = subprocess.run(
            ["env", "-i", "hyprctl", "dispatch", "global", "quickshell:dictationTap"],
            capture_output=True,
            text=True,
            timeout=5,
        )

        # Now check if the failure was logged to journal with the keyd-dictation tag
        # (This is what the wrapper script SHOULD do but doesn't exist yet)
        journal_result = subprocess.run(
            ["journalctl", "-t", "keyd-dictation", "--since", "10 sec ago", "--no-pager", "-q"],
            capture_output=True,
            text=True,
            timeout=5,
        )

        # ASSERTION: The failure should be logged with tag keyd-dictation
        # This WILL FAIL because no wrapper script exists — keyd just runs
        # hyprctl directly with no logging wrapper
        assert "keyd-dictation" in journal_result.stdout or journal_result.stdout.strip() != "", (
            f"COUNTEREXAMPLE: hyprctl dispatch from stripped env "
            f"(exit={result.returncode}, stderr='{result.stderr.strip()}') "
            f"produced NO keyd-dictation journal entry. "
            f"The pipeline fails silently with no diagnostic trace."
        )

    def test_1b_no_structured_state_transition_logs(self):
        """
        Test 1b: Trigger dictation via terminal, then grep quickshell journal
        for structured STATE transition log entries.

        EXPECTED TO FAIL: No _logTransition helper exists in DictationService,
        so no 'STATE:.*→' pattern will appear in journal.
        """
        # Trigger dictation — this should cause state transitions in DictationService
        subprocess.run(
            ["hyprctl", "dispatch", "global", "quickshell:dictationTap"],
            capture_output=True,
            text=True,
            timeout=5,
        )

        # Give Quickshell a moment to process
        time.sleep(2)

        # Check journal for structured state transition logs
        journal_result = subprocess.run(
            ["journalctl", "--user", "-u", "quickshell", "--since", "5 sec ago",
             "--no-pager", "-q", "--output=cat"],
            capture_output=True,
            text=True,
            timeout=5,
        )

        # Look for the structured state transition pattern: STATE: X → Y
        # The → character (or ->) should appear in state transition logs
        has_state_log = "STATE:" in journal_result.stdout and "→" in journal_result.stdout

        # ASSERTION: Structured state transition logs should exist
        # This WILL FAIL because DictationService has no _logTransition helper
        assert has_state_log, (
            f"COUNTEREXAMPLE: After triggering dictation via terminal dispatch, "
            f"quickshell journal contains NO structured state transition entries "
            f"(pattern 'STATE:.*→' not found). "
            f"Journal output (last 5s): '{journal_result.stdout[:500]}'"
        )

    def test_1c_transcription_failure_lacks_endpoint_details(self):
        """
        Test 1c: Configure an invalid transcription endpoint, trigger dictation,
        then grep journal for TRANSCRIPTION_FAIL with endpoint details.

        EXPECTED TO FAIL: DictationService has no TRANSCRIPTION_FAIL logging
        with endpoint URL — failures are reported with generic messages only.
        """
        # Trigger dictation (the test relies on the current provider config
        # potentially failing against an unreachable endpoint, OR we check
        # that even after a transcription attempt, the journal doesn't have
        # the expected structured failure log format)
        subprocess.run(
            ["hyprctl", "dispatch", "global", "quickshell:dictationTap"],
            capture_output=True,
            text=True,
            timeout=5,
        )

        # Wait for the full recording→transcription cycle to potentially fail
        # (short recording will auto-stop via silence detection or we trigger stop)
        time.sleep(3)

        # Stop recording if still active
        subprocess.run(
            ["hyprctl", "dispatch", "global", "quickshell:dictationTap"],
            capture_output=True,
            text=True,
            timeout=5,
        )

        # Wait for transcription attempt
        time.sleep(3)

        # Check journal for structured transcription failure logs
        journal_result = subprocess.run(
            ["journalctl", "--user", "-u", "quickshell", "--since", "15 sec ago",
             "--no-pager", "-q", "--output=cat"],
            capture_output=True,
            text=True,
            timeout=5,
        )

        # Look for the expected structured failure pattern
        has_transcription_fail_log = "TRANSCRIPTION_FAIL" in journal_result.stdout and "endpoint=" in journal_result.stdout

        # ASSERTION: Transcription failure should log endpoint details
        # This WILL FAIL because DictationService doesn't have this logging yet
        assert has_transcription_fail_log, (
            f"COUNTEREXAMPLE: After triggering dictation (which may fail against "
            f"an unreachable/invalid transcription endpoint), quickshell journal "
            f"contains NO 'TRANSCRIPTION_FAIL | endpoint=' entry. "
            f"Failures are reported without endpoint URL or HTTP status context. "
            f"Journal output (last 15s): '{journal_result.stdout[:500]}'"
        )

    def test_1d_flake_input_points_to_github(self):
        """
        Test 1d: Verify nix flake metadata for nix-flakes-refactored shows
        dots-hyprland resolves to a GitHub URL (confirming deployment regression).

        EXPECTED TO FAIL (from the test's perspective): We ASSERT that the input
        resolves to a LOCAL path. Since it currently points to GitHub, this
        assertion fails — confirming the deployment regression bug exists.
        """
        # Check flake metadata to see where dots-hyprland resolves
        result = subprocess.run(
            ["nix", "flake", "metadata", "/home/celes/sources/celesrenata/nix-flakes-refactored",
             "--json"],
            capture_output=True,
            text=True,
            timeout=30,
        )

        if result.returncode != 0:
            pytest.fail(
                f"COUNTEREXAMPLE: Could not read flake metadata "
                f"(exit={result.returncode}, stderr='{result.stderr.strip()[:200]}'). "
                f"Cannot verify flake input resolution."
            )

        import json
        try:
            metadata = json.loads(result.stdout)
        except json.JSONDecodeError as e:
            pytest.fail(f"COUNTEREXAMPLE: Failed to parse flake metadata JSON: {e}")

        # Navigate to the dots-hyprland input's locked URL/type
        locks = metadata.get("locks", {}).get("nodes", {})
        dots_hyprland = locks.get("dots-hyprland", {})
        locked = dots_hyprland.get("locked", {})
        original = dots_hyprland.get("original", {})

        # The input type tells us whether it's "github" or "path"
        input_type = original.get("type", locked.get("type", "unknown"))
        input_url = original.get("url", "")

        # ASSERTION: dots-hyprland should resolve to a LOCAL path (not GitHub)
        # This WILL FAIL because the current flake.nix has:
        #   dots-hyprland.url = "github:celesrenata/end-4-flakes/upstream-sync-2026"
        is_local = input_type == "path" or input_url.startswith("path:")

        assert is_local, (
            f"COUNTEREXAMPLE: dots-hyprland flake input resolves to "
            f"type='{input_type}' (url='{input_url}'). "
            f"Expected local path input but found GitHub reference. "
            f"This confirms the deployment regression: nixos-rebuild will fetch "
            f"stale GitHub content instead of using the local working copy, "
            f"overwriting locally-edited Quickshell configs."
        )
