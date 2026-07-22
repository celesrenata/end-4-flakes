# Implementation Plan: dictation-debugging

## Overview

Fix the dictation pipeline's silent failure modes by adding structured logging at every pipeline stage (keyd → Hyprland → Quickshell → STT), replacing keyd's broken inline command with a logged wrapper script that resolves the Hyprland socket from root context, extending Config.qml with local STT/TTS provider configuration, and switching flake inputs from GitHub to local path to prevent deployment regressions. Implementation follows the bugfix workflow: exploration test (confirm bug) → preservation test (capture baseline) → fix implementation → verification.

## Tasks

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Silent Pipeline Failure (keyd trigger + missing diagnostics)
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the pipeline fails silently
  - **Scoped PBT Approach**: Scope property to concrete failing cases:
    - keyd `command(hyprctl dispatch global quickshell:dictationTap)` from root context fails silently (no HYPRLAND_INSTANCE_SIGNATURE)
    - DictationService state transitions produce no structured `[DictationService] STATE:` log entries
    - Transcription failures lack endpoint URL and HTTP status in log output
  - Test 1a: Run `sudo hyprctl dispatch global quickshell:dictationTap` without setting HYPRLAND_INSTANCE_SIGNATURE — assert it fails AND that the failure is logged to journal with tag `keyd-dictation` (will fail: no wrapper script exists yet)
  - Test 1b: Trigger dictation via terminal, grep `journalctl --user -u quickshell --since "5 sec ago"` for `STATE:.*→` pattern — assert structured state transition logs exist (will fail: no _logTransition helper exists)
  - Test 1c: Configure invalid transcription endpoint, trigger dictation, grep journal for `TRANSCRIPTION_FAIL | endpoint=` — assert endpoint URL is logged on failure (will fail: no stderr capture or endpoint logging exists)
  - Test 1d: Verify `nix flake metadata` for nix-flakes-refactored shows `dots-hyprland` resolves to GitHub URL (confirms deployment regression exists)
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: All tests FAIL (this is correct - proves the bugs exist)
  - Document counterexamples: keyd dispatch returns error in root context, journal shows no STATE transition entries, transcription error has no endpoint details, flake input points to GitHub
  - Mark task complete when tests are written, run, and failures are documented
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.7_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Existing Dictation Flow Unchanged
  - **IMPORTANT**: Follow observation-first methodology
  - Observe on UNFIXED code: `hyprctl dispatch global quickshell:dictationTap` from terminal activates DictationService (state transitions to Listening)
  - Observe on UNFIXED code: recording via pw-record starts/stops correctly in batch mode
  - Observe on UNFIXED code: successful transcription routes text through voice assistant pipeline
  - Observe on UNFIXED code: Config.qml loads without `sttProviders`/`ttsProviders` sections (backward compat baseline)
  - Write property-based tests:
    - For all manual terminal dispatches, DictationService transitions Idle→Listening (or Idle→StreamingActive for streaming providers)
    - For all successful transcriptions with sidebar closed, text routes to `_processVoiceAssistant`
    - For all config loads without new provider sections, Config.qml initializes without error (JsonObject defaults)
    - For all `nixos-rebuild` runs unrelated to Quickshell, `~/.config/quickshell/ii/` is not modified
  - Verify tests PASS on UNFIXED code (these capture existing correct behavior)
  - **EXPECTED OUTCOME**: Tests PASS (confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [ ] 3. Fix: Dictation pipeline debugging instrumentation and deployment regression

  - [x] 3.1 Replace keyd inline command with wrapper script reference
    - **Repo**: `nix-flakes-refactored`
    - **File**: `configuration.nix` (line ~239)
    - Replace: `leftalt = "overload(alt, command(hyprctl dispatch global quickshell:dictationTap))";`
    - With: `leftalt = "overload(alt, command(/etc/keyd/dictation-dispatch.sh))";`
    - _Bug_Condition: isBugCondition(input) where input.type == "keyTap" AND input.source == "keyd" AND NOT dictationServiceActivated_
    - _Expected_Behavior: keyd executes wrapper script which resolves Hyprland socket from root context and dispatches with proper env_
    - _Preservation: Manual `hyprctl dispatch global quickshell:dictationTap` from terminal remains unchanged_
    - _Requirements: 1.1, 2.1, 2.3_

  - [x] 3.2 Create keyd wrapper script deployed via NixOS environment.etc
    - **Repo**: `nix-flakes-refactored`
    - **File**: `configuration.nix` (add `environment.etc."keyd/dictation-dispatch.sh"` block)
    - Deploy `/etc/keyd/dictation-dispatch.sh` with mode 0755
    - Script must: resolve HYPRLAND_INSTANCE_SIGNATURE from `/run/user/*/hypr`, set XDG_RUNTIME_DIR, use full path to `hyprctl`, log DISPATCH/OK/FAIL to syslog via `logger -t keyd-dictation`
    - Use `${pkgs.hyprland}/bin/hyprctl` for Nix store path resolution
    - _Bug_Condition: keyd runs as root without Hyprland env vars → dispatch silently fails_
    - _Expected_Behavior: Wrapper resolves socket, dispatches, logs outcome to journal_
    - _Preservation: The dispatch command itself is identical; wrapper only adds env resolution + logging_
    - _Requirements: 1.1, 1.3, 2.1, 2.3_

  - [x] 3.3 Add structured state transition logging to DictationService.qml
    - **Repo**: `end-4-flakes`
    - **File**: `configs/quickshell/ii/services/DictationService.qml`
    - Add `_logTransition(from, to, context)` helper that emits `[DictationService] STATE: <fromName> → <toName> | <context>`
    - Add `_setState(newState, context)` helper that captures old state, assigns new, calls _logTransition
    - Replace all bare `root.state = X` assignments with `root._setState(X, "context description")`
    - State name mapping: [Idle, Listening, StreamingActive, Processing, Error]
    - _Bug_Condition: State transitions produce no structured log → pipeline failures are opaque_
    - _Expected_Behavior: Every state transition emits structured log with from/to/context_
    - _Preservation: State machine behavior unchanged; logging is additive console.log only_
    - _Requirements: 1.2, 1.4, 2.2, 2.4_

  - [x] 3.4 Add GlobalShortcut receipt logging
    - **Repo**: `end-4-flakes`
    - **File**: `configs/quickshell/ii/services/DictationService.qml`
    - In `GlobalShortcut { name: "dictationTap" }` `onPressed` handler, replace existing log with:
      `console.log("[DictationService] GlobalShortcut dictationTap RECEIVED | state=" + root.state + " enabled=" + root.enabled + " provider=" + root.provider)`
    - _Bug_Condition: No log proving GlobalShortcut received the signal from Hyprland_
    - _Expected_Behavior: Journal shows RECEIVED entry with current state context when signal arrives_
    - _Preservation: onKeyTap() still called identically after logging_
    - _Requirements: 1.3, 2.3_

  - [x] 3.5 Add transcription failure logging with endpoint details and stderr capture
    - **Repo**: `end-4-flakes`
    - **File**: `configs/quickshell/ii/services/DictationService.qml`
    - In `transcribeProcess.onExited`, before fallback logic, add:
      `console.warn("[DictationService] TRANSCRIPTION_FAIL | endpoint=" + endpoint + " exit=" + exitCode + " fallbackIndex=" + root._fallbackIndex)`
    - Add `stderr: SplitParser { splitMarker: ""; onRead: data => { console.warn("[DictationService] TRANSCRIPTION_STDERR | " + data.trim()) } }` to transcribeProcess
    - Extract endpoint from `transcribeProcess.command` array for logging
    - _Bug_Condition: Transcription fails with generic "Transcription failed" → no endpoint/status context_
    - _Expected_Behavior: Failure logs include endpoint URL, exit code, fallback index, and stderr output_
    - _Preservation: Fallback chain logic and error state transitions unchanged_
    - _Requirements: 1.5, 2.5_

  - [x] 3.6 Add activation gate logging
    - **Repo**: `end-4-flakes`
    - **File**: `configs/quickshell/ii/services/DictationService.qml`
    - At top of `activate()`, add:
      `console.log("[DictationService] activate() called | state=" + root.state + " enabled=" + root.enabled + " provider=" + root.provider + " policy=" + Config.options.policies.ai)`
    - At each gate rejection (ai disabled, not enabled, no provider, local-only policy), add:
      `console.warn("[DictationService] GATE_REJECT | reason=<specific_reason>")`
    - _Bug_Condition: Activation fails silently when gates reject → user sees nothing_
    - _Expected_Behavior: Each gate check logs its decision; rejections are visible in journal_
    - _Preservation: Gate logic and state transitions unchanged; logging is additive_
    - _Requirements: 1.2, 2.2_

  - [x] 3.7 Extend Config.qml schema with local STT/TTS provider configuration
    - **Repo**: `end-4-flakes`
    - **File**: `configs/quickshell/ii/modules/common/Config.qml`
    - Inside the `dictation` JsonObject, add `sttProviders` JsonObject with nested per-provider configs:
      - `whisperCpp`: endpoint "http://localhost:8080", protocol "rest", model "base.en", language "en", temperature 0.0
      - `fasterWhisper`: endpoint "http://localhost:8000", protocol "rest", model "base", language "en", temperature 0.0
      - `vosk`: endpoint "ws://localhost:2700", protocol "websocket", model "vosk-model-en-us-0.22", language "en"
      - `whisperLive`: endpoint "ws://localhost:9090", protocol "websocket", model "base.en", language "en"
    - Add `ttsProviders` JsonObject with:
      - `piper`: endpoint "tcp://localhost:10200", protocol "wyoming", voice "en_US-lessac-medium", model ""
      - `coqui`: endpoint "http://localhost:5002", protocol "rest", voice "tts_models/en/ljspeech/tacotron2-DDC", language "en"
      - `mimic3`: endpoint "http://localhost:59125", protocol "rest", voice "en_US/ljspeech_low", language "en"
      - `espeakNg`: voice "en", speed 175, pitch 50
    - All new properties have sensible defaults — existing configs without these sections load without error
    - _Bug_Condition: No config options for local STT/TTS providers → forced to use hardcoded defaults_
    - _Expected_Behavior: Config schema supports per-provider endpoint/protocol/model/voice configuration_
    - _Preservation: Existing config files without new sections use JsonObject defaults (backward compatible)_
    - _Requirements: 1.6, 2.6_

  - [x] 3.8 Switch flake inputs from GitHub to local path
    - **Repo**: `nix-flakes-refactored`
    - **File**: `flake.nix`
    - Replace: `dots-hyprland.url = "github:celesrenata/end-4-flakes/upstream-sync-2026";`
    - With: `dots-hyprland.url = "path:/home/celes/sources/celesrenata/end-4-flakes";`
    - Replace: `dots-hyprland-source.url = "github:celesrenata/dots-hyprland/upstream-sync-2026";`
    - With: `dots-hyprland-source.url = "path:/home/celes/sources/celesrenata/dots-hyprland";`
    - Keep `dots-hyprland.inputs.nixpkgs.follows = "nixpkgs";` and `dots-hyprland-source.flake = false;` unchanged
    - _Bug_Condition: GitHub-pinned input causes nixos-rebuild to overwrite local Quickshell edits with stale content_
    - _Expected_Behavior: Local path input ensures rebuild uses current local repo state_
    - _Preservation: Module behavior, staging system, and quickshell-service.nix logic are unchanged — only the source resolution changes_
    - _Requirements: 1.7, 2.7, 3.7_

  - [x] 3.9 Deploy changes and sync configs
    - **Repo**: `end-4-flakes` (Quickshell configs) + `nix-flakes-refactored` (NixOS config)
    - Sync DictationService.qml and Config.qml to deployed location: `rsync -av configs/quickshell/ii/ ~/.config/quickshell/ii/`
    - Restart Quickshell: `systemctl --user restart quickshell`
    - Run `sudo nixos-rebuild switch --flake /home/celes/sources/celesrenata/nix-flakes-refactored` to deploy keyd wrapper + flake input changes
    - Verify Quickshell starts without errors: `journalctl --user -u quickshell --since "10 sec ago" --no-pager`
    - Verify keyd wrapper deployed: `ls -la /etc/keyd/dictation-dispatch.sh`
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_

  - [x] 3.10 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Pipeline Stages Emit Structured Diagnostics
    - **IMPORTANT**: Re-run the SAME tests from task 1 - do NOT write new tests
    - The test from task 1 encodes the expected behavior
    - When these tests pass, it confirms: keyd wrapper logs to journal, state transitions emit structured entries, transcription failures include endpoint details, flake input resolves locally
    - Run bug condition exploration tests from step 1
    - **EXPECTED OUTCOME**: Tests PASS (confirms bugs are fixed)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.7_

  - [x] 3.11 Verify preservation tests still pass
    - **Property 2: Preservation** - Existing Dictation Flow Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm: manual dispatch still works, recording lifecycle unchanged, transcription success path intact, config backward compatible, non-Quickshell rebuilds don't touch deployed configs
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [x] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.
  - Verify end-to-end: tap physical key → check `journalctl -t keyd-dictation` for DISPATCH/OK → check quickshell journal for GlobalShortcut RECEIVED → check STATE transition logs
  - Verify full transcription cycle: activate → record → stop → transcribe → journal contains complete STATE trace (Idle→Listening→Processing→Idle)
  - Verify failure path: configure invalid endpoint → activate → journal contains TRANSCRIPTION_FAIL with endpoint URL
  - Verify deployment: `nix flake metadata /home/celes/sources/celesrenata/nix-flakes-refactored` shows `dots-hyprland` resolved from local path

## Notes

- Changes span two repositories: `end-4-flakes` (Quickshell configs, Config.qml) and `nix-flakes-refactored` (NixOS system config, keyd, flake.nix)
- The keyd wrapper script runs as root — it must resolve the user's Hyprland socket path dynamically from `/run/user/*/hypr`
- Local path flake inputs make the flake non-reproducible on other machines — acceptable for single-user workstation (esnixi)
- After implementing Changes 3-7, deploy to runtime with `rsync -av configs/quickshell/ii/ ~/.config/quickshell/ii/ && systemctl --user restart quickshell`
- After implementing Changes 1, 2, 8, 9: run `sudo nixos-rebuild switch --flake /home/celes/sources/celesrenata/nix-flakes-refactored`

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1"] },
    { "id": 1, "tasks": ["2"] },
    { "id": 2, "tasks": ["3.1", "3.2", "3.3", "3.4", "3.5", "3.6", "3.7", "3.8"] },
    { "id": 3, "tasks": ["3.9"] },
    { "id": 4, "tasks": ["3.10", "3.11"] },
    { "id": 5, "tasks": ["4"] }
  ]
}
```
