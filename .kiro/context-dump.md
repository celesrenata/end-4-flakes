# Context Dump for New Chat (2026-07-22)

## Current State

### What's Working
- Model discovery on startup (with timeout + curl connect-timeout)
- Voice agent tools (shell_exec, system_info, weather, config_get, config_set, hyprland_dispatch, app_launch)
- `voiceSystemPrompt` in Config with {DATETIME} resolution
- Default provider dropdown in ProviderPanel
- Nix-managed quickshell config via `xdg.configFile` symlinks (declarative, atomic)
- `voice-agent-stream` nix wrapper with python deps (websockets, boto3)
- Missing context/tools files are non-fatal in the Python helper
- `hyprctl dispatch global quickshell:dictationTap` works manually

### What's Broken
- **keyd `command()` action stopped working after rebuild/restart**. The dispatch script at `/etc/keyd/dictation-dispatch.sh` is NOT being invoked when the physical dictation button (Logitech micmute) is pressed. No `keyd-dictation` journal entries appear.
- keyd starts clean (no group warning now), matches the Logitech Consumer Control device, but `micmute=command(...)` doesn't fire.
- The physical key sends bare `Control_L` press/release to Hyprland (wev shows key 37 only, no key 43/h). This means keyd is NOT intercepting the key — it's passing it through as raw Control_L.
- Model name `gpt-4o-mini-realtime-preview` doesn't exist on the user's OpenAI account. Needs to use `gpt-realtime-mini` (committed in end-4-flakes but not yet in the deployed nix store since the dots-hyprland-source flake lock wasn't updated for this specific change).

### The keyd Problem (Root Cause Unknown)
- Before this session, keyd was running since boot and working fine
- keyd was restarted during this session (to try to pick up the new dispatch script)
- After restart, `command()` actions stopped firing
- The dispatch script itself is correct (no flock, original format restored)
- keyd logs show it matching `Logitech USB Receiver Consumer Control` (046d:c548:a8528a18)
- The `[ids] *` should match all devices
- No group permission warning in latest restart
- Hypothesis: keyd lost its grab on the specific device that emits micmute, OR the Consumer Control device doesn't emit standard keycodes that keyd maps to `micmute`

### Key Files
- `/etc/keyd/mac.conf` — keyd config with ctrl↔meta swap + micmute→command
- `/etc/keyd/dictation-dispatch.sh` — dispatch script (finds hyprland socket, runs hyprctl)
- `~/.config/hypr/custom.conf` — user Hyprland overrides (currently empty of dictation binds)
- `/home/celes/sources/celesrenata/nix-flakes-refactored/configuration.nix` — keyd nix config
- `/home/celes/sources/celesrenata/nix-flakes-refactored/esnixi/hyprland.nix` — Hyprland overrides

### Repos
- **end-4-flakes** (`/home/celes/sources/celesrenata/end-4-flakes`) — flake module + quickshell configs, branch `upstream-sync-2026`
- **dots-hyprland** (`/home/celes/sources/celesrenata/dots-hyprland`) — config source for nix deployment, branch `upstream-sync-2026`
- **nix-flakes-refactored** (`/home/celes/sources/celesrenata/nix-flakes-refactored`) — NixOS system config
- **hyprmcp** (`/home/celes/sources/celesrenata/hyprmcp`) — ii-desktop-mcp tools

### Pending Commits (not yet in deployed nix store)
- `gpt-realtime-mini` model name in openai_realtime.py
- `tools: str = ""` field added to openai_realtime.py VoiceAgentConfig
- Non-fatal missing context file in voice-agent-stream.py
- printf-based file writes in VoiceAgentService.qml

### What Needs to Happen
1. Fix keyd `command()` — figure out why micmute isn't being intercepted after restart
2. Update dots-hyprland-source flake lock for the model name fix
3. Once keyd works, verify the full pipeline: button → keyd dispatch → quickshell dictationTap → voice agent connects to gpt-realtime-mini → tools work
