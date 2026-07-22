# Dictation Pipeline Debugging Bugfix Design

## Overview

The dictation pipeline spans four trust boundaries (keyd → Hyprland → Quickshell → remote STT API) and currently fails silently at every stage. This fix adds structured logging at each pipeline boundary, instruments the keyd→Hyprland signal path with a wrapper script, enriches transcription error reporting with endpoint/status details, and extends the Config schema to support configurable local STT/TTS providers with per-provider defaults.

The second facet — physical key trigger not reaching Quickshell — is addressed by replacing keyd's inline `command(hyprctl ...)` with a logged wrapper script that both executes the dispatch and writes diagnostics, enabling identification of whether the break occurs at keyd execution, Hyprland IPC receipt, or Quickshell signal delivery.

The third facet — flake deployment regression — is addressed by switching the `dots-hyprland` and `dots-hyprland-source` flake inputs from GitHub URLs (`github:celesrenata/end-4-flakes/upstream-sync-2026`) to local path inputs (`path:/home/celes/sources/celesrenata/end-4-flakes`), ensuring `nixos-rebuild` always uses the local repo state rather than stale GitHub content. This prevents the writable-mode staging system from overwriting locally-edited Quickshell configs during home-manager activation.

## Glossary

- **Bug_Condition (C)**: The dictation pipeline fails silently — either the keyd trigger doesn't reach DictationService, or a stage fails without any observable log output
- **Property (P)**: Every pipeline stage SHALL emit structured log entries, the keyd trigger SHALL reliably reach DictationService, and transcription failures SHALL report endpoint details
- **Preservation**: Existing dictation flow (manual `hyprctl dispatch global quickshell:dictationTap`, recording, transcription, intent routing) must remain unchanged
- **DictationService**: The QML singleton (`configs/quickshell/ii/services/DictationService.qml`) managing the full dictation lifecycle
- **keyd**: Kernel-level key remapper configured via NixOS `services.keyd` in `nix-flakes-refactored/configuration.nix`
- **GlobalShortcut**: Quickshell's `GlobalShortcut` component that receives `global` dispatches from Hyprland
- **Pipeline stages**: keyd → Hyprland dispatch → Quickshell GlobalShortcut → DictationService state machine → STT transcription → intent classification → action execution

## Bug Details

### Bug Condition

The bug manifests in two forms: (1) when the physical key trigger fires via keyd's `overload(alt, command(hyprctl dispatch global quickshell:dictationTap))`, the signal is lost somewhere between keyd command execution and Quickshell GlobalShortcut receipt; (2) when any pipeline stage fails, no structured logging exists to identify the failure point.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type PipelineEvent (keyTap, stateTransition, transcriptionAttempt, configAccess, deploymentRebuild)
  OUTPUT: boolean

  RETURN (input.type == "keyTap" AND input.source == "keyd"
          AND NOT dictationServiceActivated(input))
         OR (input.type == "stateTransition"
             AND NOT structuredLogEmitted(input.fromState, input.toState))
         OR (input.type == "transcriptionFailure"
             AND NOT endpointDetailsLogged(input.endpoint, input.statusCode))
         OR (input.type == "configAccess" AND input.providerType IN ["local-stt", "local-tts"]
             AND NOT configSchemaSupports(input.provider))
         OR (input.type == "deploymentRebuild"
             AND input.flakeInputType == "github"
             AND localRepoHasNewerContent(input.localPath, input.githubRef)
             AND activationOverwritesLocalConfigs(input.stagingDir, input.configDir))
END FUNCTION
```

### Examples

- Left Alt tap → keyd fires `hyprctl dispatch global quickshell:dictationTap` → nothing happens, no log anywhere → user has no way to know if keyd ran the command, if Hyprland received it, or if Quickshell processed it
- DictationService transitions from Listening → Processing → Error, but journalctl shows only `[DictationService] onKeyTap` with no state flow context
- Transcription fails against `http://localhost:8080/v1/audio/transcriptions` → error message says "Transcription failed" with no mention of endpoint URL, HTTP status, or response body
- User wants to configure faster-whisper on port 8000 with a specific model → config only has `provider: "openai"` and `streamingEndpoint: ""` with no per-provider endpoint/port/protocol options
- User edits `configs/quickshell/ii/services/DictationService.qml` locally, adds structured logging, then runs `nixos-rebuild switch` → the `dots-hyprland` flake input fetches from GitHub (`upstream-sync-2026` branch), the writable-mode staging copies the stale GitHub version to `~/.config/quickshell/ii/`, overwriting the local edits — user must manually `rsync` from repo to deployed dir after every rebuild

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- `hyprctl dispatch global quickshell:dictationTap` from terminal must continue to activate DictationService
- Recording via pw-record (batch mode) and streaming pipeline must continue to work identically
- Voice assistant pipeline (intent classification → ActionPalette) must remain unchanged
- Sidebar-open behavior (transcriptionComplete signal) must remain unchanged
- Max duration auto-stop, silence detection, and double-tap timer must continue working
- OpenAI Whisper API transcription with valid key must continue to succeed
- Fallback chain (configured → localhost → OpenAI) must continue to function

**Scope:**
All existing DictationService behavior is preserved. New logging is additive (console.log calls). The keyd wrapper script replaces the inline command but produces the same `hyprctl dispatch global` call. Config schema additions are new optional properties with defaults matching current hardcoded values. The local path input change only affects where Nix resolves the `dots-hyprland` flake source — the actual module behavior, staging system, and quickshell-service.nix logic remain identical.

## Hypothesized Root Cause

Based on the bug description, the most likely issues are:

1. **keyd `command()` execution environment**: keyd runs as root (systemd service). The `hyprctl` command requires `HYPRLAND_INSTANCE_SIGNATURE` and access to the Hyprland socket (under the user's XDG_RUNTIME_DIR). When keyd executes `command(hyprctl dispatch global quickshell:dictationTap)`, it likely fails because:
   - No `HYPRLAND_INSTANCE_SIGNATURE` in keyd's environment
   - The socket path `/run/user/1000/hypr/$SIGNATURE/.socket.sock` is inaccessible from root context
   - `hyprctl` is not in root's PATH

2. **Missing structured logging**: DictationService has only two `console.log` calls in `onKeyTap()` — no state transition logging, no transcription attempt logging, no error context beyond a generic message string.

3. **Insufficient error context**: `_attemptFallbackTranscription` and `transcribeProcess.onExited` report failure with generic messages but don't log the endpoint URL, HTTP status code, or curl stderr output.

4. **Hardcoded provider defaults**: The config schema has a single `provider` string and optional `streamingEndpoint` — no way to specify per-provider endpoints, ports, protocols, or model paths for the various local STT/TTS engines (whisper.cpp :8080, faster-whisper :8000, Vosk :2700, WhisperLive :9090, Piper :10200, Coqui :5002, Mimic 3 :59125).

5. **GitHub-pinned flake input overwrites local edits**: The `nix-flakes-refactored/flake.nix` declares `dots-hyprland.url = "github:celesrenata/end-4-flakes/upstream-sync-2026"` and `dots-hyprland-source.url = "github:celesrenata/dots-hyprland/upstream-sync-2026"`. When the user edits Quickshell configs locally in the `end-4-flakes` repo and then runs `nixos-rebuild switch`, Nix fetches the GitHub-pinned version (which is stale relative to the local working copy). The `programs.dots-hyprland` home-manager module with `mode = "hybrid"` uses writable-mode staging, and the `quickshell-service.nix` startup script checks a `SETUP_MARKER` — but `home-manager switch` regenerates the staging directory from the flake input each time. The result: local edits in `configs/quickshell/ii/` are overwritten by the GitHub content on every rebuild, requiring a manual `rsync` from repo to `~/.config/quickshell/ii/` after each `nixos-rebuild`.

## Correctness Properties

Property 1: Bug Condition - Pipeline stages emit structured diagnostics

_For any_ pipeline event where a stage transition occurs (keyd command execution, Hyprland dispatch receipt, Quickshell GlobalShortcut signal, DictationService state change, transcription attempt, transcription failure), the instrumented system SHALL emit a structured log entry to journalctl containing: stage identifier, timestamp context, input received, and outcome (success/failure with details).

**Validates: Requirements 2.2, 2.3, 2.4, 2.5**

Property 2: Preservation - Existing dictation functionality unchanged

_For any_ input that exercises the existing dictation flow (manual terminal dispatch, recording lifecycle, transcription success path, intent routing, sidebar behavior), the fixed system SHALL produce exactly the same functional behavior as the original system, preserving all state transitions, signal emissions, and API interactions.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**

Property 3: Bug Condition - Local flake source prevents deployment regression

_For any_ `nixos-rebuild` or `home-manager switch` invocation where the user has locally edited Quickshell configs in the `end-4-flakes` repository, the fixed flake SHALL resolve `dots-hyprland` from the local path (`/home/celes/sources/celesrenata/end-4-flakes`) rather than a GitHub URL, ensuring the writable-mode staging system deploys the current local content and does NOT overwrite `~/.config/quickshell/ii/` with stale GitHub-pinned content.

**Validates: Requirements 1.7, 2.7, 3.7**

## Fix Implementation

### Changes Required

**File**: `nix-flakes-refactored/configuration.nix` (keyd config)

**Change 1: Replace inline command with wrapper script**

Replace:
```nix
leftalt = "overload(alt, command(hyprctl dispatch global quickshell:dictationTap))";
```
With:
```nix
leftalt = "overload(alt, command(/etc/keyd/dictation-dispatch.sh))";
```

**File**: New script `/etc/keyd/dictation-dispatch.sh` (deployed via NixOS `environment.etc`)

**Change 2: Create keyd wrapper script with logging**

```bash
#!/bin/bash
# Logged wrapper for keyd → Hyprland dictation dispatch
LOG_TAG="keyd-dictation"
TIMESTAMP=$(date +%s.%N)

# Resolve Hyprland socket for the active user session
HYPR_SIG=$(find /run/user/*/hypr -maxdepth 1 -name ".socket.sock" 2>/dev/null | head -1 | xargs dirname | xargs basename)
RUNTIME_DIR=$(find /run/user -maxdepth 1 -type d -name "[0-9]*" 2>/dev/null | head -1)

if [ -z "$HYPR_SIG" ] || [ -z "$RUNTIME_DIR" ]; then
    logger -t "$LOG_TAG" "FAIL ts=$TIMESTAMP reason=no_hyprland_socket"
    exit 1
fi

export HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"

logger -t "$LOG_TAG" "DISPATCH ts=$TIMESTAMP sig=$HYPR_SIG"

RESULT=$(hyprctl dispatch global quickshell:dictationTap 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    logger -t "$LOG_TAG" "OK ts=$TIMESTAMP result=$RESULT"
else
    logger -t "$LOG_TAG" "FAIL ts=$TIMESTAMP exit=$EXIT_CODE result=$RESULT"
fi
```

**File**: `configs/quickshell/ii/services/DictationService.qml`

**Change 3: Add structured state transition logging**

Add a helper function and instrument all state changes:

```qml
// Structured logging helper
function _logTransition(from, to, context) {
    var stateNames = ["Idle", "Listening", "StreamingActive", "Processing", "Error"]
    var fromName = stateNames[from] || String(from)
    var toName = stateNames[to] || String(to)
    console.log("[DictationService] STATE: " + fromName + " → " + toName + " | " + (context || ""))
}
```

Replace all bare `root.state = X` assignments with calls through a setter that logs transitions. Every assignment like:
```qml
root.state = DictationService.State.Listening
```
becomes:
```qml
root._setState(DictationService.State.Listening, "activate() batch mode")
```

Where `_setState` is:
```qml
function _setState(newState, context) {
    var oldState = root.state
    root.state = newState
    _logTransition(oldState, newState, context)
}
```

**Change 4: Add GlobalShortcut receipt logging**

In the `GlobalShortcut` `onPressed` handler, add environment/context logging:

```qml
onPressed: {
    console.log("[DictationService] GlobalShortcut dictationTap RECEIVED | state=" + root.state + " enabled=" + root.enabled + " provider=" + root.provider)
    root.onKeyTap()
}
```

**Change 5: Add transcription failure logging with endpoint details**

In `transcribeProcess.onExited`, before fallback:
```qml
onExited: (exitCode, exitStatus) => {
    if (exitCode !== 0) {
        var endpoint = transcribeProcess.command[transcribeProcess.command.length - 1] || "unknown"
        console.warn("[DictationService] TRANSCRIPTION_FAIL | endpoint=" + endpoint + " exit=" + exitCode + " fallbackIndex=" + root._fallbackIndex)
        // ... existing fallback logic
    }
}
```

Add stderr capture to the transcribeProcess:
```qml
stderr: SplitParser {
    splitMarker: ""
    onRead: data => {
        console.warn("[DictationService] TRANSCRIPTION_STDERR | " + data.trim())
    }
}
```

**Change 6: Add activation gate logging**

In `activate()`, log each gate check:
```qml
function activate() {
    console.log("[DictationService] activate() called | state=" + root.state + " enabled=" + root.enabled + " provider=" + root.provider + " policy=" + Config.options.policies.ai)
    // ... existing gate checks, with added logging on rejection:
    if (Config.options.policies.ai === 0) {
        console.warn("[DictationService] GATE_REJECT | reason=ai_disabled")
        // ...
    }
}
```

**File**: `configs/quickshell/ii/modules/common/Config.qml`

**Change 7: Extend Config schema with local provider configuration**

Add structured provider configuration objects inside the `dictation` JsonObject:

```qml
property JsonObject dictation: JsonObject {
    // ... existing properties unchanged ...

    // Local STT provider configurations
    property JsonObject sttProviders: JsonObject {
        property JsonObject whisperCpp: JsonObject {
            property string endpoint: "http://localhost:8080"
            property string protocol: "rest"  // rest | websocket
            property string model: "base.en"
            property string language: "en"
            property real temperature: 0.0
        }
        property JsonObject fasterWhisper: JsonObject {
            property string endpoint: "http://localhost:8000"
            property string protocol: "rest"
            property string model: "base"
            property string language: "en"
            property real temperature: 0.0
        }
        property JsonObject vosk: JsonObject {
            property string endpoint: "ws://localhost:2700"
            property string protocol: "websocket"
            property string model: "vosk-model-en-us-0.22"
            property string language: "en"
        }
        property JsonObject whisperLive: JsonObject {
            property string endpoint: "ws://localhost:9090"
            property string protocol: "websocket"
            property string model: "base.en"
            property string language: "en"
        }
    }

    // Local TTS provider configurations
    property JsonObject ttsProviders: JsonObject {
        property JsonObject piper: JsonObject {
            property string endpoint: "tcp://localhost:10200"
            property string protocol: "wyoming"  // wyoming | rest
            property string voice: "en_US-lessac-medium"
            property string model: ""  // Path to .onnx model (optional, uses voice name if empty)
        }
        property JsonObject coqui: JsonObject {
            property string endpoint: "http://localhost:5002"
            property string protocol: "rest"
            property string voice: "tts_models/en/ljspeech/tacotron2-DDC"
            property string language: "en"
        }
        property JsonObject mimic3: JsonObject {
            property string endpoint: "http://localhost:59125"
            property string protocol: "rest"
            property string voice: "en_US/ljspeech_low"
            property string language: "en"
        }
        property JsonObject espeakNg: JsonObject {
            property string voice: "en"
            property int speed: 175
            property int pitch: 50
        }
    }
}
```

**File**: `nix-flakes-refactored/configuration.nix` (or appropriate NixOS module)

**Change 8: Deploy wrapper script via NixOS environment.etc**

```nix
environment.etc."keyd/dictation-dispatch.sh" = {
  mode = "0755";
  text = ''
    #!/bin/bash
    LOG_TAG="keyd-dictation"
    TIMESTAMP=$(date +%s.%N)
    HYPR_SIG=$(find /run/user/*/hypr -maxdepth 1 -name ".socket.sock" 2>/dev/null | head -1 | xargs dirname | xargs basename)
    RUNTIME_DIR=$(find /run/user -maxdepth 1 -type d -name "[0-9]*" 2>/dev/null | head -1)
    if [ -z "$HYPR_SIG" ] || [ -z "$RUNTIME_DIR" ]; then
      logger -t "$LOG_TAG" "FAIL ts=$TIMESTAMP reason=no_hyprland_socket"
      exit 1
    fi
    export HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG"
    export XDG_RUNTIME_DIR="$RUNTIME_DIR"
    logger -t "$LOG_TAG" "DISPATCH ts=$TIMESTAMP sig=$HYPR_SIG"
    RESULT=$("${pkgs.hyprland}/bin/hyprctl" dispatch global quickshell:dictationTap 2>&1)
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 0 ]; then
      logger -t "$LOG_TAG" "OK ts=$TIMESTAMP result=$RESULT"
    else
      logger -t "$LOG_TAG" "FAIL ts=$TIMESTAMP exit=$EXIT_CODE result=$RESULT"
    fi
  '';
};
```

**File**: `nix-flakes-refactored/flake.nix`

**Change 9: Switch flake inputs from GitHub to local path**

Replace the GitHub-pinned `dots-hyprland` inputs with local path inputs so `nixos-rebuild` always uses the current local repository state:

**Before:**
```nix
dots-hyprland.url = "github:celesrenata/end-4-flakes/upstream-sync-2026";
dots-hyprland.inputs.nixpkgs.follows = "nixpkgs";
dots-hyprland-source.url = "github:celesrenata/dots-hyprland/upstream-sync-2026";
dots-hyprland-source.flake = false;
```

**After:**
```nix
dots-hyprland.url = "path:/home/celes/sources/celesrenata/end-4-flakes";
dots-hyprland.inputs.nixpkgs.follows = "nixpkgs";
dots-hyprland-source.url = "path:/home/celes/sources/celesrenata/dots-hyprland";
dots-hyprland-source.flake = false;
```

**Rationale:**
- Local path inputs mean `nix flake lock --update-input dots-hyprland` (or any `nixos-rebuild`) resolves the input from the local filesystem, using whatever is committed (or dirty, depending on Nix version) in the repo at that path.
- The writable-mode staging in `programs.dots-hyprland` will now stage content from the LOCAL repo, not stale GitHub content.
- This eliminates the "edit locally → rebuild → configs overwritten by GitHub version" regression loop.

**Tradeoff:** Local path inputs make the flake non-reproducible on other machines (the path must exist at build time). This is acceptable because:
- This is a single-user workstation config (esnixi) — not a shared/CI build
- The user actively develops against the local repos
- For CI or remote builds, the GitHub URLs can be restored via `nix flake lock --override-input dots-hyprland github:celesrenata/end-4-flakes/upstream-sync-2026`

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the silent failure on unfixed code, then verify the fix produces structured log output and the keyd trigger reaches DictationService.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate the silent failure BEFORE implementing the fix. Confirm or refute the root cause analysis regarding keyd's execution environment.

**Test Plan**: Manually trace the pipeline on the unfixed system to observe where signals are lost. Check keyd's systemd journal for command execution evidence. Verify Hyprland socket accessibility from root context.

**Test Cases**:
1. **keyd Environment Test**: Run `sudo -u root hyprctl dispatch global quickshell:dictationTap` — confirm it fails without HYPRLAND_INSTANCE_SIGNATURE (will fail on unfixed code)
2. **Journal Silence Test**: Tap Left Alt, then check `journalctl --user -u quickshell --since "5 sec ago"` — confirm no log output (will fail on unfixed code)
3. **State Transition Opacity Test**: Trigger dictation via terminal, check logs during Listening→Processing→Error flow — confirm minimal context (will fail on unfixed code)
4. **Transcription Error Test**: Configure invalid endpoint, trigger dictation — confirm error lacks endpoint/status details (will fail on unfixed code)
5. **Deployment Regression Test**: Edit a Quickshell config in the repo, run `nixos-rebuild switch`, then diff `~/.config/quickshell/ii/` against the repo — confirm the deployed version matches GitHub (stale) rather than local (current) (will fail on unfixed code)

**Expected Counterexamples**:
- keyd's `command()` runs in root context without Hyprland socket access → dispatch silently fails
- No journal entries between GlobalShortcut press and state transitions → impossible to diagnose
- Transcription errors report "failed" without endpoint URL or HTTP status
- After `nixos-rebuild switch`, locally-edited Quickshell configs are replaced with stale GitHub content from `upstream-sync-2026` branch

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed system produces structured diagnostic output.

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := instrumentedPipeline(input)
  ASSERT structuredLogEmitted(result.stage, result.outcome)
  IF input.type == "keyTap" THEN
    ASSERT journalContains("keyd-dictation", "DISPATCH") OR journalContains("keyd-dictation", "FAIL")
  END IF
  IF input.type == "stateTransition" THEN
    ASSERT journalContains("[DictationService] STATE:", input.from + " → " + input.to)
  END IF
  IF input.type == "transcriptionFailure" THEN
    ASSERT journalContains("TRANSCRIPTION_FAIL", "endpoint=")
  END IF
  IF input.type == "deploymentRebuild" THEN
    ASSERT flakeInputResolvesTo("dots-hyprland", "path:/home/celes/sources/celesrenata/end-4-flakes")
    ASSERT deployedConfig("~/.config/quickshell/ii/") == localRepo("configs/quickshell/ii/")
  END IF
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed system produces the same functional result as the original.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT originalBehavior(input) = fixedBehavior(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the state machine input domain
- It catches edge cases in state transition paths that manual tests might miss
- It provides strong guarantees that the additive logging doesn't break functional behavior

**Test Plan**: Observe behavior on UNFIXED code first for manual dispatch activation, successful transcription, intent routing, and sidebar interactions, then write tests confirming these continue after fix.

**Test Cases**:
1. **Manual Dispatch Preservation**: Verify `hyprctl dispatch global quickshell:dictationTap` from terminal still activates DictationService after adding the wrapper script
2. **Recording Lifecycle Preservation**: Verify batch recording (pw-record start/stop) and streaming pipeline continue to work with added logging
3. **Transcription Success Preservation**: Verify successful OpenAI API transcription still returns text and routes to voice assistant
4. **Config Backward Compatibility**: Verify existing config files without `sttProviders`/`ttsProviders` objects load without error (JsonObject defaults apply)
5. **Non-Quickshell Rebuild Preservation**: Verify that `nixos-rebuild switch` for changes unrelated to Quickshell (e.g., adding a package) does not modify `~/.config/quickshell/ii/` content — the local path input still resolves but the staging system only applies when relevant files change

### Unit Tests

- Test `_logTransition()` produces correct format string for all state enum values
- Test `_setState()` updates state property AND emits log
- Test keyd wrapper script resolves Hyprland socket correctly given various `/run/user/*/hypr` layouts
- Test Config schema loads with and without new provider sections (backward compatibility)
- Test transcription error log includes endpoint URL extracted from process command array
- Test `nix flake metadata` resolves `dots-hyprland` input to local path (not GitHub URL) after Change 9

### Property-Based Tests

- Generate random sequences of state transitions and verify each produces a structured log entry with valid from/to state names
- Generate random DictationService inputs (activate, stopRecording, keyTap) and verify the state machine + logging doesn't introduce new error paths
- Generate random config payloads with/without sttProviders/ttsProviders and verify Config.qml loads without crash
- Generate random flake input URL variations and verify local path inputs resolve to the expected store path containing current repo content

### Integration Tests

- End-to-end: tap physical key → check `journalctl -t keyd-dictation` for DISPATCH/OK entry → check quickshell journal for GlobalShortcut RECEIVED → check state transition logs
- Full transcription cycle with logging: activate → record → stop → transcribe → verify journal contains complete STATE trace (Idle→Listening→Processing→Idle)
- Failure path: configure invalid endpoint → activate → verify journal contains TRANSCRIPTION_FAIL with endpoint URL and exit code
- Config reload: add sttProviders section to live config → verify Quickshell picks up new values without restart crash
- Deployment regression: edit `configs/quickshell/ii/services/DictationService.qml` in repo → run `nixos-rebuild switch` → verify `~/.config/quickshell/ii/services/DictationService.qml` contains the local edit (not the old GitHub version) → confirm `nix flake metadata` shows `dots-hyprland` resolved from local path
