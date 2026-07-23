# end-4-flakes — NixOS Flakes for dots-hyprland with AI & Theming Extensions

NixOS flake packaging for [end-4's dots-hyprland](https://github.com/end-4/dots-hyprland), with heavy modifications to theming and the addition of a full AI/voice assistant layer. This wraps the upstream "illogical-impulse" Quickshell desktop into declarative Nix modules and extends it with streaming voice dictation, an AI action palette, vision analysis, multi-provider model discovery, an MCP server for desktop control, and deep Material You theming integration.

**Target platform:** Baremetal NixOS (x86_64-linux, aarch64-linux). No VM, container, or T2/Mac support.

## What this provides

End-4's dots-hyprland gives you a gorgeous Material You shell on Hyprland. This flake packages it for NixOS, adds rich Home Manager module options for configuration, and extends it significantly:

1. **Theming** — Deep Material You integration that goes beyond upstream. Wallpaper colors propagate to foot terminal, fuzzel launcher, Qt apps, Hyprland borders, and RGB hardware. Dark/light mode with automatic wallpaper variant switching. Multiple bar styles. Anti-flashbang overlays. All driven from a single wallpaper image through matugen and kde-material-you-colors (patched for non-Plasma).

2. **AI & Voice** — A complete voice assistant and AI integration layer built into the Quickshell sidebar and launcher. Multi-provider LLM support (7 providers + custom endpoints), streaming dictation, bidirectional voice conversations, vision analysis, structured action execution, and a full MCP server for programmatic desktop access.

3. **NixOS-native packaging** — Everything is declared in Nix. Template system with `@VARIABLE@` placeholders processed at build time. Binary paths resolve to Nix store paths. Systemd services managed by Home Manager. No imperative setup scripts in production.

## Features

### Theming & Appearance

- **Material You color pipeline** — Wallpaper → matugen generates a full Material Design 3 palette → applied to foot terminal, fuzzel launcher, Hyprland borders, hyprbars plugin, slurp selection, Qt apps. Multiple palette schemes: auto, scheme-content, scheme-expressive, scheme-fidelity, scheme-monochrome, scheme-neutral, scheme-rainbow, scheme-tonal-spot.
- **kde-material-you-colors** — Patched to work without Plasma. Propagates wallpaper palette to Qt/KDE apps. Konsole `exist_ok` fix, KWin reload skip, stub `plasma-apply-colorscheme`.
- **Dark/Light mode** — `Ctrl+Super+Shift+D` toggles instantly. Wallpaper variant auto-detection: place `forest-dark.jpg` and `forest-light.jpg` side by side, the system picks the right one.
- **Terminal theming** — foot.ini generated from wallpaper colors via matugen templates. 16-color palette + background/foreground + cursor all auto-derived. Configurable opacity (10–100%).
- **Launcher theming** — fuzzel theme colors from wallpaper palette, applied via matugen template.
- **RGB lighting sync** — Colors extracted from wallpaper pushed to RGB hardware.
- **Anti-flashbang** — Configurable overlay during workspace transitions (off/weak/strong).
- **Bar styles** — Top or bottom placement, three corner styles (hug/float/rectangle), borderless mode. Background optional. Verbose/compact mode for different screen sizes.
- **Screen corners** — Per-monitor decorative rounded corners respecting individual scale values.
- **Wallpaper parallax** — Workspace-linked parallax scrolling with configurable zoom. Sidebar parallax offset.

### Bar

The bar is a full-featured status strip with three sections:

- **Left** — Sidebar toggle button (distro or spark icon), active window title. Scroll to adjust brightness.
- **Center** — Resource monitors (CPU, RAM, swap), media now-playing, workspace indicators (default or hefty with app icons), clock/date, utility buttons (screenshot, color picker, mic toggle, keyboard, dark mode, night light, performance profile), battery indicator.
- **Right** — System tray, network/bluetooth/keyboard layout/mute indicators, weather widget. Scroll to adjust volume.

### Sidebars

**Left sidebar** (swipeable tabs):
- Intelligence — Full AI chat with streaming responses, context window tracking, `/compact` and `/summarize` commands, multiple named sessions, search/filter/archive/group
- Providers — API key management for OpenAI, Anthropic, Gemini, Mistral, OpenRouter, AWS Bedrock, Ollama + custom endpoints. Auto-validation with debounce, model discovery, balance display, voice provider configuration
- Translator — Bidirectional translation via translate-shell (Google/Bing/DeepL/Yandex engines)
- Anime — Booru image browser (Yandere, Konachan, Waifu.im, Zerochan) with tag search, NSFW policy controls

**Right sidebar**:
- Quick toggles: Network, Bluetooth, Night Light, Game Mode, Idle Inhibitor, EasyEffects, Cloudflare WARP
- Notifications + Volume mixer (tabbed)
- Calendar, Pomodoro timer, Todo list
- Uptime display, Hyprland/Quickshell reload, Settings, Session (power) menu

Both sidebars support keyboard navigation, focus grab, and layer shell blur.

### Overview / Launcher

Full-screen workspace overview triggered by Super tap, with a multi-mode search bar:

- **Apps** — Fuzzy search of desktop entries via AppSearch service
- **Math** — Calculator via qalc (expression → result, click to copy)
- **Commands** — Type any command to run it in bash (or in terminal if `sudo`)
- **Web search** — Google (with configurable excluded sites like quora.com)
- **Clipboard** (`;` prefix) — fuzzy search clipboard history via cliphist
- **Emoji** (`:` prefix) — Unicode 17.0 emoji search
- **AI Actions** (`?` prefix) — Natural language → LLM generates structured action plan (config.set, shell.exec, hyprland.dispatch, app.launch) with Apply/Preview/Revert
- **Launcher actions** (`/` prefix) — `/dark`, `/light`, `/wall`, `/konachanwall`, `/accentcolor`, `/todo`

### AI & Voice

- **Voice Assistant** — Tap activation key, speak naturally. Intent classification (heuristic or AI-powered) separates commands from dictation. Commands execute directly without opening UI. Concise spoken-style responses. Configurable verbosity.
- **Streaming Dictation** — Real-time transcription via WebSocket (OpenAI Realtime, local whisper servers) or chunked HTTP. Words appear in a floating indicator as spoken. Graceful fallback cascade: streaming → chunked → batch.
- **Bidirectional Voice Agent** — Full duplex conversations via Amazon Nova Sonic (HTTP/2 bidirectional) or OpenAI Realtime API (WebSocket). Tool calling mid-conversation. Barge-in (interrupt AI). RMS waveform amplitude indicator. Session context injection from sidebar chat.
- **Text-to-Speech** — Piper (local neural), espeak-ng, Coqui, Mimic3 (local), or OpenAI TTS (cloud). Played through PipeWire. Interrupts on new dictation.
- **Multi-Provider Model Discovery** — API keys stored via libsecret/secret-tool. Models discovered dynamically from provider APIs. Balance/credits display. Supports: OpenAI, Anthropic, Gemini, Mistral, OpenRouter, AWS Bedrock (SigV4 via `aws` CLI), Ollama, any OpenAI-compatible endpoint.
- **AI Action Palette** — Type `?` in the launcher. LLM returns structured actions with desktop context (open windows, workspace, config state). Per-action execution with approval gate for shell commands. Preview mode for config changes (apply visually → commit or revert).
- **Context Lens** — `Super+Shift+A` captures a screen region. Pick an action (Explain, Extract Text, Translate, Summarize, Identify Error, Generate Command). Results in floating overlay. Send to sidebar chat for follow-up. Supports OpenAI/Gemini/Bedrock vision APIs.
- **Context Window Management** — Token estimation per model, visual context meter with color thresholds (70% warn, 90% critical), `/compact` summarization, `/summarize` to fork into new session, proactive 85% warning with model upgrade suggestions.
- **Multiple Chat Sessions** — Named conversations with create/switch/rename/purge/archive/group. Session drawer with search (keyword, date, subject, group). Persisted as JSON files. Auto-save on message. Active session survives restarts.
- **Free Dictation Session** — Protected persistent session that logs all voice interactions. Auto-submits dictated text. Cannot be deleted or renamed.
- **HyprMCP Tool Integration** — AI can read/write Quickshell config, dispatch Hyprland commands, query audio/network/system state. Read-back verification after writes.

### Desktop Intelligence (ii-desktop-mcp)

A [Model Context Protocol](https://modelcontextprotocol.io/) server exposing structured desktop state to AI clients (Quickshell sidebar, Action Palette, external MCP clients like Kiro). Runs as systemd user service over stdio transport.

- Config read/write (with sensitive value redaction)
- Audio state + volume/mute control (PipeWire/WirePlumber)
- Network status + WiFi AP scanning (NetworkManager)
- Systemd service status + journal logs
- Clipboard history search/copy (cliphist)
- Application search + launch (XDG desktop entries)
- Screenshots (monitor/window/region via grim)
- System info (CPU, GPU, memory, disk, kernel — no hardware identifiers)
- Shell logs with level filtering
- Diagnostic bundle (concurrent all-system snapshot)

### Desktop Demo Driver

Automated demonstration system using ydotool for input emulation. 30+ scenes across 6 categories (shell, workspace, window, utility, app-launch, mcp). Configurable pacing (0.5x–3.0x speed), pause/resume, state guards (verify preconditions), automatic desktop state capture/restore. Triggerable via keybind (`Super+Alt+F10`), IPC, or CLI.

### Hyprland Configuration

Full Hyprland config via `.conf.template` files with NixOS template substitution:

- **Window management** — Dwindle tiling, gaps (in/out/workspace), borders, rounding, blur (xray, popups), shadows, dim inactive
- **Animations** — Material Design bezier curves (emphasizedDecel, emphasizedAccel, standardDecel), window in/out/move, layer animations, workspace slide/slidevert
- **Input** — Keyboard layout (templated), numlock default, touchpad (natural scroll, disable while typing, clickfinger), repeat rate 35/250ms
- **Window rules** — Float rules for dialogs/PiP/pavucontrol/nm-editor, gaming tearing (*.exe, minecraft, steam_app), no shadow for tiled
- **Layer rules** — Per-layer blur, animations (slide left/right for sidebars, fade for notifications, noanim for overview/screenshot)
- **Plugins** — hyprbars (Material You colored title buttons), hyprexpo (workspace overview grid)
- **Idle/Power** — hypridle with 5-stage cascade: 150s dim → 300s lock → 330s DPMS off → 1800s suspend
- **Gestures** — 3-finger horizontal workspace swipe (Hyprland native)
- **Touchegg** — Optional: 3-finger pinch close, 3-finger swipe up (overview), 4-finger swipe move window, browser pinch-zoom
- **VM passthrough** — `Super+Alt+F1` enters a submap that passes all keys to the VM

### Shell & Desktop (from upstream, with NixOS adaptations)

- **Quickshell bar** — Full status bar (see Bar section above)
- **Overview/Launcher** — Multi-mode search (see Overview section above)
- **Notifications** — Qt 6.11 compatible, grouped by app, force-to-monitor option, persistent storage, action buttons, urgency-based styling
- **Cheatsheet** — `Super+/` shows all keybinds parsed from config, organized by section headers
- **Emoji picker** — Unicode 17.0 data, searchable via `Super+.`
- **On-screen keyboard** — QWERTY full layout, pinnable
- **Session menu** — Shutdown, reboot, suspend, lock (hyprlock)
- **Dock** — Auto-hide dock with pinned apps, hover-to-reveal, monochrome icons
- **Idle/Power panel** — Configure hypridle timeouts and DPMS
- **Night light** — Hyprsunset with configurable temperature (default 4500K), automatic scheduling
- **Media controls** — MPRIS integration with playerctl
- **Background widgets** — Optional clock overlay on wallpaper
- **Zoom** — `Super+=/Super+-` adjustable cursor zoom
- **Screenshot tool** — Full-screen, region, or window capture with content region detection
- **Recording** — Region or fullscreen, with or without sound
- **OCR** — `Super+Shift+X` captures region → tesseract → clipboard
- **Color picker** — `Super+Shift+C` via hyprpicker → clipboard
- **nwg-displays** — Optional graphical monitor layout management

### NixOS Integration

- **Three deployment modes** — `hybrid` (recommended: Hyprland declarative + Quickshell copied), `declarative` (all read-only), `writable` (staged for manual editing)
- **Home Manager modules** — Rich typed options for: appearance (transparency, rounding, anti-flashbang, palette), bar (position, style, workspaces, weather, utility buttons), battery, apps, time format, Hyprland (gaps, borders, rounding, blur, monitors, gestures, tearing, night light, keybinds), terminal (scrollback, cursor, opacity), notifications (force monitor), dock, search prefixes
- **Config override system** — Complete file-level or directory-level overrides for hyprland.conf, Config.qml, foot.ini, touchegg.conf
- **Template system** — `.conf.template` files with `@VARIABLE@` placeholders resolved at build time to Nix store paths
- **Quickshell systemd service** — Managed by Home Manager. QML cache cleared on restart. Full `PATH` and `XDG_DATA_DIRS` for app launching. Security sandboxing (ProtectSystem=strict). Memory limit 2G.
- **Python virtual environment** — Managed venv at `~/.local/state/quickshell/.venv` with materialyoucolor, pywayland, pillow, numpy, boto3, websockets. Auto-setup on first rebuild.
- **Overlay** — Patches quickshell (qt5compat + qtpositioning QML imports) and kde-material-you-colors (non-Plasma fixes)
- **Package sets** — `minimal`, `essential`, `all`. Includes: quickshell, Qt6 modules, KDE components (Bluetooth/NetworkManager with QML path wrappers), hyprland tools, audio (PipeWire/playerctl), fonts (Nerd Fonts, Noto), matugen
- **VM integration test** — Full NixOS VM test that verifies config generation, placeholder resolution, service creation, session variables
- **Custom config persistence** — `~/.config/hypr/custom/` files survive rebuilds via graceful `source` directives
- **App launcher PATH resolution** — Wrapper ensures quickshell-spawned apps can find Nix store binaries

### Upstream Sync (Aug 2025 → Jul 2026)

Cherry-picked and adapted for the NixOS template system:
- Qt 6.11 notification fix, XDG_DATA_DIRS fix, DPMS syntax fix, monitor scale type fix
- Multi-monitor screen corners, clipboard escaped text, Super key hold state
- Konachan/waifu.im User-Agent and tag fixes, HOME env for Lua configs
- Keybind syntax (raw keycodes, fullscreen dispatcher, movetoworkspacesilent)
- Removed: JetBrains windowrule, unlock refocus hack, redundant sleep delays, deprecated scripts
- Added: hefty workspaces, light/dark wallpaper variants, anti-flashbang weak, notification force monitor, dark/light toggle, Emoji 17.0, cheatsheet improvements, nwg-displays, custom config auto-creation, hyprsunset default temp fix
- Lua keybinds adapted to `.conf.template` format with equivalence verification

## Architecture

```
end-4-flakes/                       # This repo
├── configs/
│   ├── hypr/                       # Hyprland .conf.template files
│   │   ├── hyprland.conf.template  #   Entry point (sources all others)
│   │   ├── general.conf.template   #   Layout, decoration, animations, input
│   │   ├── keybinds.conf.template  #   ~300 keybinds with @BIN@ paths
│   │   ├── rules.conf.template     #   Window/layer rules
│   │   ├── colors.conf.template    #   Material You border/plugin colors
│   │   ├── env.conf.template       #   Environment variables
│   │   ├── execs.conf.template     #   Autostart programs
│   │   ├── hypridle.conf.template  #   Idle/power cascade
│   │   └── scripts/                #   workspace_action.sh, launch_first_available.sh
│   ├── quickshell/ii/
│   │   ├── services/               #   41 singleton services (AI, voice, audio, etc.)
│   │   ├── modules/
│   │   │   ├── bar/                #     Status bar (resources, media, workspaces, etc.)
│   │   │   ├── sidebarLeft/        #     AI chat, providers, translator, anime
│   │   │   ├── sidebarRight/       #     Toggles, notifications, volume, calendar, todo
│   │   │   ├── overview/           #     Launcher + search (apps, math, AI, clipboard, emoji)
│   │   │   ├── common/             #     Config.qml, Persistent.qml, Appearance, widgets
│   │   │   ├── notifications/      #     Notification popups + history
│   │   │   └── ...                 #     cheatsheet, dock, osk, session, screenCorners, etc.
│   │   └── scripts/
│   │       ├── voice-agent-stream.py   # Bidirectional voice (Nova Sonic / OpenAI Realtime)
│   │       ├── dictation-stream.py     # Streaming/chunked STT helper
│   │       ├── colors/                 # switchwall, generate_colors_material.py
│   │       └── voice_agent_backends/   # Backend implementations + tool manager
│   ├── applications/               # foot.ini.template (Material You colors)
│   ├── matugen/templates/          # Color templates: foot, fuzzel, gtk, hyprland, kde, kitty
│   └── scripts/                    # generate-colors.sh, record.sh, zoom.sh
├── modules/
│   ├── home-manager.nix            # Main HM module (mode, packages, activation)
│   ├── configuration.nix           # File copying + custom config placeholders
│   ├── python-environment.nix      # Python venv (materialyoucolor, pywayland, boto3)
│   ├── writable-mode.nix           # Staging + setup script for editable mode
│   └── components/
│       ├── quickshell-config.nix   # Generates Config.qml from Nix options
│       ├── quickshell-service.nix  # systemd service + voice-agent wrapper + PATH setup
│       ├── hyprland-config.nix     # Generates general.conf from Nix options
│       ├── terminal-config.nix     # foot terminal options
│       ├── touchegg.nix            # Touchpad gesture definitions
│       ├── config-override.nix     # Escape hatch: complete file/directory overrides
│       └── system-services.nix     # NixOS-level: UPower for battery
├── packages/
│   ├── default.nix                 # Utility scripts (update-flake, generate-qmldir, etc.)
│   └── dots-hyprland-packages.nix  # Package sets (basic/widgets/hyprland/python/audio/fonts)
├── tests/
│   ├── vm-test.nix                 # NixOS VM integration test
│   └── *.py                        # 34 Python test files (Hypothesis property-based)
└── flake.nix                       # Overlays, HM modules, NixOS modules, dev shells, checks
```

### Deployment chain

```
end-4-flakes → pushed to GitHub
  → nix flake update dots-hyprland (pins commit in system flake's flake.lock)
  → overlay patches quickshell + kde-material-you-colors
  → programs.dots-hyprland module processes templates, generates configs
  → nixos-rebuild switch deploys everything atomically
  → systemd user service starts quickshell with full PATH/env
  → ~/.config/quickshell/ii/ is the live runtime config
  → ~/.config/hypr/ contains resolved Hyprland configs
```

## Quick Start

### Prerequisites
- NixOS (baremetal) with flakes enabled
- Home Manager integrated into system flake (not standalone)
- Hyprland compositor
- PipeWire audio

### As a flake input in your system flake

```nix
# flake.nix inputs:
dots-hyprland.url = "github:celesrenata/end-4-flakes/upstream-sync-2026";
dots-hyprland.inputs.nixpkgs.follows = "nixpkgs";

# home-manager module:
{
  programs.dots-hyprland = {
    enable = true;
    source = inputs.dots-hyprland + "/configs";
    packageSet = "essential";  # minimal | essential | all
    mode = "hybrid";           # hybrid | declarative | writable

    quickshell = {
      appearance.transparency = true;
      appearance.antiFlashbang = "weak";
      bar.workspaces.shown = 10;
      bar.workspaces.variant = "hefty";
      bar.bottom = false;
      bar.cornerStyle = 1;  # Float
      notifications.forceMonitor = "DP-1";
    };

    hyprland = {
      general.gapsIn = 4;
      general.gapsOut = 7;
      decoration.rounding = 16;
      decoration.blurEnabled = true;
      night.colorTemperature = 4500;
      keybinds.darkLightToggle = true;
    };

    packages.includeNwgDisplays = true;
  };
}
```

### Development

```bash
git clone git@github.com:celesrenata/end-4-flakes.git
cd end-4-flakes
nix develop

# Test locally (temporary, wiped on rebuild):
rsync -av configs/quickshell/ii/ ~/.config/quickshell/ii/
systemctl --user restart quickshell

# Run tests:
cd tests && python -m pytest
```

## Configuration

See [NIXOS_CONFIGURATION_GUIDE.md](NIXOS_CONFIGURATION_GUIDE.md) for the full Nix module option reference and [CONFIGURATION_GUIDE.md](CONFIGURATION_GUIDE.md) for editing static config files directly.

### Key config paths

| What | Where |
|------|-------|
| Quickshell runtime config | `~/.config/quickshell/ii/modules/common/Config.qml` |
| Persistent state (model, session) | `~/.local/state/quickshell/states.json` |
| Chat sessions | `~/.local/share/quickshell/aiChats/` |
| Hyprland main config | `~/.config/hypr/hyprland.conf` |
| Hyprland custom overrides | `~/.config/hypr/custom/*.conf` |
| Monitor layout (nwg-displays) | `~/.config/hypr/monitors.conf` |
| AI provider keys | Secret storage via libsecret/secret-tool |
| Python venv | `~/.local/state/quickshell/.venv` |

## Keybinds (highlights)

| Key | Action |
|-----|--------|
| `Super` (tap) | Overview / launcher |
| `Super+Return` | Terminal |
| `Super+Space` | App launcher (fallback to fuzzel) |
| `Super+A` | Left sidebar (AI chat) |
| `Super+N` | Right sidebar (toggles, notifications) |
| `Super+/` | Cheatsheet |
| `Super+.` | Emoji picker |
| `Super+V` | Clipboard history |
| `Super+Shift+A` | Context Lens (AI vision) |
| `?` in launcher | AI Action Palette |
| `Super+Shift+S` | Screen snip |
| `Super+Shift+C` | Color picker |
| `Super+Shift+X` | OCR → clipboard |
| `Ctrl+H` / dictation key | Voice dictation toggle |
| `Ctrl+Super+Shift+D` | Dark / Light toggle |
| `Ctrl+Super+T` | Change wallpaper |
| `Super+Alt+F10` | Desktop Demo Driver |
| `Super+Alt+F1` | VM passthrough mode |
| `Super+L` | Lock screen |
| Scroll on left bar | Brightness |
| Scroll on right bar | Volume |

## Testing

- **Python (Hypothesis)** — 34 test files covering: template placeholder integrity, wallpaper variant selection, keybind injection, voice assistant intent classification, streaming protocol, capability detection, tool call pairing, demo driver orchestration, audio pipeline, credential handling, policy enforcement
- **NixOS VM test** — Full integration test verifying config generation, placeholder resolution, systemd service, session variables, package availability

## Credits

- [end-4](https://github.com/end-4) — Original dots-hyprland and the illogical-impulse aesthetic
- [outfoxxed](https://github.com/outfoxxed) — Quickshell framework
- [Hyprland team](https://hyprland.org/) — The compositor
- NixOS community — The ecosystem

## License

GPL-3.0 — See [LICENSE](LICENSE) for details.
