# Python Environment & Voice Assistant Setup

This document describes the Python virtual environment management and voice assistant architecture in the end-4-flakes NixOS desktop.

## Python Virtual Environment

### Location & Purpose

The Python venv is stored at:
```
~/.local/state/quickshell/.venv/
```

**Purpose:** Provides isolated Python dependencies for Material You color generation, AI voice processing, and image analysis — without polluting the system Python or requiring `pip install --system`.

### Managed Dependencies

The venv is managed declaratively via [`modules/python-environment.nix`](../modules/python-environment.nix):

| Package | Version | Purpose |
|---------|---------|---------|
| `materialyoucolor` | Latest | Google's Material You algorithm — extracts color palette from wallpaper images |
| `pywayland` | Latest | Wayland protocol client for Hyprland IPC communication |
| `pillow` (PIL) | Latest | Image processing: resize, crop, color extraction, region detection |
| `numpy` | Latest | Array operations for image analysis and color space conversions |
| `boto3` | Latest | AWS SDK for Bedrock API access (multi-provider AI) |
| `websockets` | Latest | WebSocket client for streaming voice (OpenAI Realtime API, local whisper servers) |

### Auto-Setup on First Rebuild

The Home Manager activation script (`modules/python-environment.nix`) runs:

```bash
# Create venv if it doesn't exist
if [[ ! -d "$HOME/.local/state/quickshell/.venv" ]]; then
    python3 -m venv "$HOME/.local/state/quickshell/.venv"
fi

# Install dependencies from requirements.txt
"$HOME/.local/state/quickshell/.venv/bin/pip install" \
    materialyoucolor pywayland pillow numpy boto3 websockets
```

This runs **once** on first `home-manager switch`. Subsequent rebuilds skip if the venv already exists.

### Manual Setup / Repair

If the venv gets corrupted or dependencies are missing:

```bash
# 1. Remove broken venv
rm -rf ~/.local/state/quickshell/.venv

# 2. Recreate via home-manager (preferred)
home-manager switch

# OR manually:
python3 -m venv ~/.local/state/quickshell/.venv
~/.local/state/quickshell/.venv/bin/pip install \
    materialyoucolor pywayland pillow numpy boto3 websockets

# 3. Verify installation
~/.local/state/quickshell/.venv/bin/python3 -c "import materialyoucolor; print(materialyoucolor.__version__)"
```

### Testing the Environment

Use the provided test script:

```bash
# From the flake root:
nix run .#test-python-env

# Or manually:
~/.local/state/quickshell/.venv/bin/python3 -c "
import materialyoucolor
import pywayland
import PIL
import numpy
import boto3
import websockets
print('All dependencies OK')
"
```

## Voice Assistant Architecture

### Overview

The voice assistant provides **three interaction modes**:

1. **Streaming Dictation** — Real-time speech-to-text (words appear as you speak)
2. **Intent Classification** — Separate commands from dictation (e.g., "open terminal" vs transcribing text)
3. **Bidirectional Voice Agent** — Full duplex conversations with AI models (like a phone call)

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    User Speaks into Mic                      │
└────────────────────────┬────────────────────────────────────┘
                         │ Audio Stream
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Streaming Dictation (STT)                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ OpenAI Realtime│  │ Local Whisper│  │ Chunked HTTP STT │  │
│  │ (WebSocket)   │  │ (via ydotool)│  │ (fallback)       │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
└────────────────────────┬────────────────────────────────────┘
                         │ Transcribed Text
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Intent Classifier (Heuristic or AI)             │
│  - Commands: "open terminal", "take screenshot" → execute   │
│  - Dictation: transcribe to text → insert into focused app  │
└────────────────────────┬────────────────────────────────────┘
                         │ Action
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Bidirectional Voice Agent (Optional)            │
│  ┌──────────────────┐  ┌──────────────────┐                 │
│  │ Amazon Nova Sonic │  │ OpenAI Realtime  │                 │
│  │ (HTTP/2 bidir)   │  │ (WebSocket)      │                 │
│  └──────────────────┘  └──────────────────┘                 │
│  - Tool calling mid-conversation                            │
│  - Barge-in (interrupt AI while speaking)                   │
│  - RMS waveform amplitude indicator                         │
└─────────────────────────────────────────────────────────────┘
```

### Scripts & Files

| File | Purpose |
|------|---------|
| [`configs/quickshell/scripts/dictation-stream.py`](../configs/quickshell/scripts/dictation-stream.py) | Streaming dictation helper — connects to STT backend, streams words to Quickshell UI |
| [`configs/quickshell/services/Ai.qml`](../configs/quickshell/services/Ai.qml) | AI chat session management (multi-provider, context window tracking) |
| [`configs/quickshell/services/ai/*.qml`](../configs/quickshell/services/ai/) | API strategy implementations for each provider |

### Provider Configuration

AI providers are configured in the Quickshell sidebar → **Providers** tab. Each provider stores:

- **API Key** — via `libsecret` (system keyring), not in config files
- **Base URL** — for custom endpoints (OpenAI-compatible APIs)
- **Model Name** — e.g., `gpt-4o`, `claude-3-5-sonnet`, `llama-3.1-70b`

Supported providers:

| Provider | API Type | Auth Method | Voice Support |
|----------|----------|-------------|---------------|
| OpenAI | REST + WebSocket | Bearer token | Realtime API (WebSocket) |
| Anthropic | REST | Bearer token | Text only |
| Gemini | REST | Bearer token | Text + Vision |
| Mistral | REST | Bearer token | Text only |
| OpenRouter | REST | Bearer token | Text + some voice |
| AWS Bedrock | SigV4 (via `aws` CLI) | IAM credentials | Text + some voice |
| Ollama | Local REST | None (localhost) | Text + local STT |
| Custom | OpenAI-compatible | Bearer token | Depends on backend |

### Voice Agent Backends

The [`configs/quickshell/scripts/voice_agent_backends/`](../configs/quickshell/scripts/voice_agent_backends/) directory contains:

| Backend | Protocol | Use Case |
|---------|----------|----------|
| `openai_realtime.py` | WebSocket (OpenAI Realtime API) | Low-latency conversations with GPT-4o |
| `nova_sonic.py` | HTTP/2 bidirectional (Amazon Nova Sonic) | Full-duplex voice with tool calling |
| `bedrock_converse.py` | REST (AWS Bedrock) | Enterprise-grade AI with SageMaker |

### TTS (Text-to-Speech) Options

The voice agent can respond verbally via TTS:

| Engine | Type | Latency | Quality |
|--------|------|---------|---------|
| **Piper** | Local neural | ~100ms | High (runs on CPU) |
| **espeak-ng** | Local synthesis | ~50ms | Robotic but fast |
| **Coqui** | Local neural | ~200ms | Very high quality |
| **Mimic3** | Local neural | ~150ms | High quality (Mycroft) |
| **OpenAI TTS** | Cloud | ~500ms | Highest quality |

TTS output plays through PipeWire. New dictation interrupts ongoing speech.

### Context Window Management

The AI chat tracks token usage per session:

```qml
// In Ai.qml service
property int contextWindow: 128000        // Max tokens for current model
property int usedTokens: 45000            // Tokens consumed this session
property real contextPercent: usedTokens / contextWindow  // 0.35 = 35%

// Visual indicator in sidebar:
// Green (<70%) → Yellow (70-90%) → Red (>90%, critical)
```

Commands available in chat:
- `/compact` — Summarize conversation to reduce token count
- `/summarize` — Fork current context into a new session
- `/new` — Start fresh session
- `/sessions` — List all named sessions

### Multi-Session Management

Chat sessions are persisted as JSON files in:
```
~/.local/share/quickshell/aiChats/<session-name>.json
```

Each session stores:
- System prompt
- Message history (role, content, tokens)
- Model metadata (provider, name, context window size)
- Creation timestamp
- Last activity timestamp

Sessions can be:
- **Named** — User-defined names for organization
- **Archived** — Hidden from main list but still accessible
- **Grouped** — Organized into folders (e.g., "Work", "Personal")
- **Free dictation** — Protected persistent session that logs all voice interactions

## Audio Pipeline

### Input (Microphone)

```
Mic → PipeWire → Python venv (voice_agent_stream.py) → STT backend
```

1. PipeWire captures audio from the active input device
2. `wayland-idle-inhibitor.py` prevents screen dimming during voice interaction
3. Audio is chunked and sent to the STT backend via WebSocket or HTTP

### Output (Speaker/TTS)

```
TTS engine → PipeWire → Speaker/Headphones
```

1. TTS engine generates audio waveform
2. PipeWire plays through the active output device
3. Barge-in detection: if new mic input detected during TTS playback, interrupt and restart STT

### Volume & Mute Controls

| Control | Method | Keybind |
|---------|--------|---------|
| Master volume | `wpctl set-volume @DEFAULT_SINK@ N%` | `XF86AudioRaiseVolume` / `XF86AudioLowerVolume` |
| Mic mute | `wpctl set-mute @DEFAULT_SOURCE@ toggle` | `XF86AudioMicMute` / `Super+Alt+M` |
| App-specific volume | PipeWire node selection in Volume Mixer sidebar | N/A (GUI only) |

## Debugging Voice Assistant

### Check STT Connection

```bash
# Test OpenAI Realtime WebSocket connection:
OPENAI_API_KEY=sk-xxx ~/.local/state/quickshell/.venv/bin/python3 \
  -c "import websockets; print('websockets OK')"

# Test Ollama local server:
curl http://localhost:11434/api/tags | python3 -m json.tool
```

### Check TTS Engine

```bash
# Test Piper TTS (if installed):
piper --model en_US-amy-medium.onnx --output_audio device

# Test espeak-ng:
espeak-ng "Hello, this is a test." --stdout | paplay
```

### View Voice Agent Logs

```bash
# Follow Quickshell logs for voice activity:
journalctl --user -u quickshell.service -f | grep -i voice

# Or check the dictation script directly:
~/.local/state/quickshell/.venv/bin/python3 \
  ~/.config/quickshell/ii/scripts/dictation-stream.py --debug
```

### Common Voice Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| No audio input detected | PipeWire not running or mic muted | `pw-cli list-objects type/Source`; unmute in pavucontrol |
| STT returns empty text | Backend unreachable (Ollama down, API key invalid) | Check backend logs; verify API key in Providers tab |
| TTS doesn't play | PipeWire sink not set or audio disabled | `wpctl set-default <sink>`; check system sound settings |
| Barge-in not working | RMS threshold too high or latency too low | Adjust `voice_agent_backends/config.py` thresholds |
| Context window full | Session exceeded token limit | Use `/compact` to summarize, or `/new` for fresh session |

## Security Considerations

1. **API keys stored in keyring** — Never in config files or logs
2. **Local TTS (Piper/espeak)** — No network calls; audio stays on device
3. **Cloud STT/TTS** — Audio sent to provider; check provider privacy policies
4. **Voice agent tool calling** — Commands executed with user approval gate for shell commands
5. **No persistent voice recording** — Audio is streamed in chunks; not stored on disk

## Performance Notes

| Component | Latency | CPU Usage | Memory |
|-----------|---------|-----------|--------|
| OpenAI Realtime STT | ~200ms | Low (network-bound) | ~50MB |
| Local Whisper STT | ~1-3s | High (CPU/GPU) | ~2GB |
| Piper TTS | ~100ms | Medium | ~200MB |
| espeak-ng TTS | ~50ms | Very low | ~10MB |
| Context window tracking | Negligible | None | ~5MB per session |
