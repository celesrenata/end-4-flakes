# Bugfix Requirements Document

## Introduction

The dictation pipeline is a multi-stage chain: Physical key (Logitech Dictation / Left Alt tap) → keyd (kernel remapper) → Hyprland global shortcut → Quickshell DictationService → OpenAI Whisper transcription → Intent classification → Action execution. The pipeline fails silently — when a stage fails, there is no logging or feedback indicating where the signal was lost. Additionally, the physical key trigger (keyd dispatching `hyprctl dispatch global quickshell:dictationTap`) does not reach Quickshell, while the same command works when run manually from a terminal. A further regression occurs because the `nix-flakes-refactored` flake pins `dots-hyprland` to a GitHub branch rather than the local working copy, causing `nixos-rebuild` to overwrite locally-edited Quickshell configs with stale flake content.

This bug has three facets:
1. **Silent failures** — no instrumentation exists to trace signal flow through the pipeline stages
2. **Physical key trigger broken** — keyd's `overload(alt, command(...))` invocation of `hyprctl dispatch global` does not trigger the Quickshell GlobalShortcut, even though the identical command works from a terminal
3. **Flake deployment regression** — the `dots-hyprland` flake input fetches from GitHub (`github:celesrenata/end-4-flakes/upstream-sync-2026`) instead of the local repo, so `nixos-rebuild` deploys stale Quickshell configs and the activation script overwrites local edits

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the physical key trigger fires (Left Alt tap → keyd → `hyprctl dispatch global quickshell:dictationTap`) THEN the system fails silently and DictationService never receives the activation signal

1.2 WHEN any stage in the dictation pipeline fails (keyd → Hyprland → Quickshell → Whisper → intent → action) THEN the system produces no observable log output, notification, or indicator to identify which stage failed

1.3 WHEN keyd executes `command(hyprctl dispatch global quickshell:dictationTap)` THEN the system does not log whether the command was executed, whether Hyprland received it, or whether Quickshell processed it

1.4 WHEN DictationService transitions between states (Idle → Listening → Processing → Idle/Error) THEN the system does not emit structured log entries that could be used to trace the pipeline progression

1.5 WHEN the transcription request fails or returns empty text THEN the system transitions to Error state but provides insufficient context about which endpoint was attempted or what the failure response contained

1.6 WHEN a user wants to configure local STT providers (whisper.cpp, faster-whisper, Vosk, WhisperLive) or local TTS providers (Piper, Coqui TTS, Mimic 3) THEN the system has no configuration options for local provider endpoints, model paths, or connection settings — forcing reliance on remote OpenAI or hardcoded localhost:8080 defaults with no way to specify the correct port or protocol for each provider

1.7 WHEN the user edits Quickshell configs locally in `end-4-flakes/configs/quickshell/ii/` and then runs `nixos-rebuild` (or `home-manager switch`) without first pushing to GitHub THEN the system fetches the stale GitHub-pinned `dots-hyprland` input (`github:celesrenata/end-4-flakes/upstream-sync-2026`), and the `programs.dots-hyprland` activation script (mode = "hybrid", writable-mode staging) copies the outdated flake config to `~/.config/quickshell/ii/`, overwriting the user's local edits

### Expected Behavior (Correct)

2.1 WHEN the physical key trigger fires (Left Alt tap → keyd → `hyprctl dispatch global quickshell:dictationTap`) THEN the system SHALL successfully deliver the signal to DictationService and begin activation, OR log a clear error at the specific stage that failed

2.2 WHEN any stage in the dictation pipeline fails THEN the system SHALL emit a structured log entry identifying the failed stage, the input it received, and the error condition, viewable via `journalctl --user -u quickshell`

2.3 WHEN keyd executes the dictation command THEN the system SHALL log at minimum: (a) keyd command execution, (b) Hyprland dispatch receipt, and (c) Quickshell GlobalShortcut signal receipt — enabling identification of the break point

2.4 WHEN DictationService transitions between states THEN the system SHALL emit structured log entries in the format `[DictationService] STATE: <from> → <to> | <context>` for each transition, including timestamp information

2.5 WHEN the transcription request fails THEN the system SHALL log the endpoint URL attempted, the HTTP status code or error message received, the fallback index, and whether a fallback was attempted

2.6 WHEN a user wants to use local STT providers (whisper.cpp on :8080, faster-whisper on :8000, Vosk on :2700, WhisperLive on :9090) or local TTS providers (Piper via Wyoming on :10200, Coqui TTS on :5002, Mimic 3 on :59125) THEN the system SHALL provide configuration options in the Config schema for: provider name, endpoint URL (host:port), protocol type (REST/WebSocket/Wyoming), model identifier or path, and optional parameters (language, temperature) — with sensible defaults per provider

2.7 WHEN the user runs `nixos-rebuild` (or `home-manager switch`) THEN the system SHALL use the local `end-4-flakes` repository (at `/home/celes/sources/celesrenata/end-4-flakes`) as the source for Quickshell configs rather than the GitHub-pinned branch, OR SHALL prevent the activation script from overwriting `~/.config/quickshell/ii/` when the local repo contains newer content — ensuring local edits survive rebuilds without requiring a manual `rsync` workaround

### Unchanged Behavior (Regression Prevention)

3.1 WHEN `hyprctl dispatch global quickshell:dictationTap` is run manually from a terminal THEN the system SHALL CONTINUE TO activate DictationService normally

3.2 WHEN DictationService is in Idle state and `activate()` is called THEN the system SHALL CONTINUE TO begin recording via pw-record (batch mode) or streaming pipeline

3.3 WHEN transcription succeeds and the sidebar is closed THEN the system SHALL CONTINUE TO route text through the voice assistant pipeline (intent classification → ActionPalette)

3.4 WHEN transcription succeeds and the sidebar is open THEN the system SHALL CONTINUE TO emit the `transcriptionComplete` signal with the transcribed text

3.5 WHEN the recording duration reaches `maxDurationMs` THEN the system SHALL CONTINUE TO automatically stop recording

3.6 WHEN the configured provider is "openai" and a valid API key exists THEN the system SHALL CONTINUE TO successfully transcribe audio via the OpenAI Whisper API

3.7 WHEN `nixos-rebuild` is run for changes unrelated to Quickshell configs (e.g., adding a package, updating keybinds, changing system services) THEN the system SHALL CONTINUE TO complete the rebuild without reverting or modifying the user's current `~/.config/quickshell/ii/` content
