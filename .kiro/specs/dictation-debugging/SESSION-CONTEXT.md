# Next Session Context

## Workspace
- `/home/celes/sources/celesrenata/end-4-flakes` — Quickshell configs, dots-hyprland flake
- `/home/celes/sources/celesrenata/nix-flakes-refactored` — NixOS system config flake

## Current State (2026-07-22 ~05:00 PDT)

### What's Working
- Dictation pipeline: Logi button → Ctrl+H → Hyprland bind → Quickshell dictationTap → recording → OpenAI transcription → ActionPalette
- Structured logging in DictationService (STATE transitions, GATE_REJECT, TRANSCRIPTION_FAIL)
- Foot terminal on Ctrl+Super+G
- Model name reactive binding in sidebar
- AwsCredentialReader registered in qmldir
- Chat ListView BottomToTop layout
- Mic at 25% volume

### Open Items (Priority Order)

#### 1. Voice Providers Not Showing in Sidepanel
The user says voice providers (STT/TTS like whisper.cpp, Vosk, Piper, etc.) should appear in the providers sidepanel but don't.

Investigate:
- `configs/quickshell/ii/modules/sidebarLeft/ProviderPanel.qml` — what providers does it render?
- `configs/quickshell/ii/services/ModelDiscoveryService.qml` — has `providerConfigs` — does it include voice/STT providers?
- `configs/quickshell/ii/modules/common/Config.qml` — has `sttProviders` and `ttsProviders` JsonObjects (added during dictation-debugging spec)
- The question is: should the ProviderPanel show STT/TTS providers alongside AI model providers (OpenAI, Gemini, etc.)? Or is there a separate voice provider UI that was never built?

#### 2. Debounce Implementation
Spec ready at `.kiro/specs/dictation-debounce-indicator/tasks.md`. Can be run via task orchestrator.
Fixes the Logi button triple-fire problem (Ctrl+H fires 3x in 300ms).

#### 3. Chat Switching Garbled Display
When switching between chat sessions, the UI becomes garbled instead of cleanly replacing content.
Likely related to the `verticalLayoutDirection: ListView.BottomToTop` change or the session loading in Ai.qml.

#### 4. ListView BottomToTop May Have Reversed Message Order
Need to verify that `verticalLayoutDirection: ListView.BottomToTop` doesn't visually flip messages (newest at top). If it does, need to reverse the model array instead.

### Deploy Workflow (IMPORTANT)
1. Edit files in `end-4-flakes` repo
2. `git add && git commit && git push` in end-4-flakes
3. `rsync -av configs/quickshell/ii/ ~/.config/quickshell/ii/` to deploy immediately
4. `systemctl --user restart quickshell` to apply
5. For NixOS-level changes: edit nix-flakes-refactored, commit, push
6. `nix flake update dots-hyprland --flake /home/celes/sources/celesrenata/nix-flakes-refactored`
7. Commit flake.lock update
8. `sudo nixos-rebuild switch --flake /home/celes/sources/celesrenata/nix-flakes-refactored`
9. After rebuild: `hyprctl reload` (Hyprland doesn't auto-reload on config write)

### Key Files
- `configs/quickshell/ii/services/DictationService.qml` — dictation state machine
- `configs/quickshell/ii/services/Ai.qml` — AI service, model management
- `configs/quickshell/ii/services/ModelDiscoveryService.qml` — provider discovery
- `configs/quickshell/ii/modules/sidebarLeft/ProviderPanel.qml` — provider UI
- `configs/quickshell/ii/modules/sidebarLeft/AiChat.qml` — chat UI
- `configs/quickshell/ii/modules/common/Config.qml` — config schema (has sttProviders/ttsProviders)
- `configs/quickshell/ii/services/qmldir` — singleton registrations (must include all services)
- `nix-flakes-refactored/home/desktop/hyprland.nix` — deployed hyprland.conf content
- `nix-flakes-refactored/configuration.nix` — keyd config, dictation wrapper script

### Git Branches
- end-4-flakes: `upstream-sync-2026`
- nix-flakes-refactored: `refactored`
