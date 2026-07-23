# Realtime Dictation Service — gpt-realtime-whisper

## Model
`gpt-realtime-whisper` — OpenAI's purpose-built streaming dictation model.
Do NOT substitute gpt-4o-transcribe, gpt-4o-mini-transcribe, whisper-1, gpt-realtime-2.1, or any other model.

## Architecture
Persistent user service (systemd), not a per-invocation script.

```
Global push-to-talk key
        │
        ▼
PipeWire microphone capture
        │
        ▼
24 kHz mono signed PCM16
        │
        ▼
Persistent WebSocket connection gpt-realtime-whisper
        │
        ├── transcript delta events ──► Quickshell overlay
        │
        └── completed transcript ─────► focused application (wtype)
```

## Connection
```
wss://api.openai.com/v1/realtime?model=gpt-realtime-whisper
Authorization: Bearer $OPENAI_API_KEY
```

## Session Configuration
```json
{
  "type": "session.update",
  "session": {
    "type": "transcription",
    "audio": {
      "input": {
        "format": {
          "type": "audio/pcm",
          "rate": 24000
        },
        "transcription": {
          "model": "gpt-realtime-whisper",
          "language": "en",
          "delay": "low"
        },
        "turn_detection": null
      }
    }
  }
}
```

## Audio Protocol
- While recording: send base64-encoded PCM16 chunks via `input_audio_buffer.append`
- On stop: send `input_audio_buffer.commit`
- Manual commits only (no server VAD — `turn_detection: null`)

## Events
- `conversation.item.input_audio_transcription.delta` → partial text in `event.delta`
- `conversation.item.input_audio_transcription.completed` → final text in `event.transcript`

## UX Rules
- Do NOT type deltas directly into the focused application (text may be revised)
- Show deltas in a Quickshell floating overlay, replace as hypothesis develops
- On `completed` event: inject ONLY the finalized transcript via wtype
- Preserve clipboard contents around clipboard-based insertion

## Text Injection
1. Prefer `wtype` (Wayland virtual-keyboard protocol)
2. Fallback: `wl-copy` + simulated Ctrl+V
3. Last resort: `ydotool`
4. Preserve and restore clipboard around insertion

## Service Commands (Unix socket IPC)
- `start` / `stop` / `toggle` / `cancel` / `status`

## Quickshell IPC
Subscribe to socket for:
```json
{"state": "listening", "partial": "the current transcription...", "level": 0.72}
```

## NixOS Module Config
```nix
services.realtime-dictation = {
  enable = true;
  model = "gpt-realtime-whisper";
  language = "en";
  delay = "low";
  audio = { sampleRate = 24000; channels = 1; device = null; };
  injection = { method = "wtype"; preserveClipboard = true; };
  socketPath = "%t/realtime-dictation.sock";
  apiKeyFile = config.sops.secrets.openai-api-key.path;
};
```

## Implementation
- Python with asyncio + websockets + pw-cat subprocess
- Hardened systemd user service
- Exponential backoff reconnection
- Track `item_id` for transcript ordering
- Unit tests for event parsing, transcript reconciliation, IPC, injection escaping
