# Design: Voice Dictation + Sidebar Popout

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│  Dictation Service (singleton in main shell)                   │
│                                                                │
│  ┌──────────────────┐  ┌──────────────────┐                   │
│  │ DoubleTapDetector│  │ AudioRecorder    │                   │
│  │ (Control_R state)│→ │ (pw-record proc) │                   │
│  └──────────────────┘  └────────┬─────────┘                   │
│                                  │ stop (tap/silence/timeout)  │
│                        ┌─────────▼──────────┐                  │
│                        │ Transcriber        │                  │
│                        │ (curl → whisper)   │                  │
│                        └─────────┬──────────┘                  │
│                                  │ text result                  │
│                        ┌─────────▼──────────┐                  │
│                        │ Router             │                  │
│                        │ sidebar open?      │                  │
│                        │ → AI chat / Action │                  │
│                        └────────────────────┘                  │
└───────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│  SidebarLeft.qml (modified)                                    │
│                                                                │
│  ┌──────────────────────┐                                      │
│  │ Popout Toggle        │                                      │
│  │ • exclusiveZone = w  │ (claims left-edge space)             │
│  │ • no focus grab      │ (windows tile around it)             │
│  │ • still resizable    │ (drag right edge)                    │
│  │ • persisted state    │                                      │
│  └──────────────────────┘                                      │
└───────────────────────────────────────────────────────────────┘
```

## Component Design

### DictationService.qml (singleton)

State machine:
```
Idle → Listening (double-tap detected)
Listening → Processing (stop triggered)
Processing → Idle (transcription complete or error)
```

**Double-tap detection:**
- Track `Control_R` key-up events via a Hyprland global shortcut or raw key monitoring
- On first tap: start a timer (400ms)
- On second tap within the timer window: activate dictation
- If timer expires without second tap: do nothing (normal key behavior)
- Key detection uses `bindrit` (release-only, input-transparent) in Hyprland keybinds

**Audio recording:**
- Process component runs: `pw-record --target=@DEFAULT_SOURCE@ /tmp/quickshell-dictation/<timestamp>.wav`
- SilenceTimer (3000ms): reset on any audio activity, fire on silence
- MaxTimer (60000ms): hard stop after 1 minute
- On stop: kill pw-record process, proceed to transcription

**Silence detection:**
- Option A: Monitor `pw-record` output for silence (if it reports levels)
- Option B: After recording, use a small script to check if the last 3s of audio is silence (simpler but less responsive)
- Option C: Use `pw-cat --monitor` alongside recording to detect audio levels in real-time
- Recommended: Option A with pw-record's `--rate` and a small level-monitor sidecar

**Transcription:**
- Read config to determine provider (local or remote)
- For OpenAI-compatible API: `curl -F file=@audio.wav -F model=whisper-1 <endpoint>`
- For local whisper: `whisper-cpp -f audio.wav` or equivalent
- Parse result text from JSON response

**Routing:**
```javascript
if (GlobalStates.sidebarLeftOpen) {
    // Send to sidebar AI chat
    Ai.sendUserMessage(transcribedText);
} else {
    // Send to AI Action Palette via overview
    GlobalStates.overviewOpen = true;
    SearchWidget.setSearchingText("? " + transcribedText);
}
```

### DictationIndicator.qml (floating overlay)

- Small PanelWindow (WlrLayer.Overlay, no keyboard focus)
- Anchored to top-right or bottom-center
- Shows: pulsing mic icon + duration counter while recording
- Shows: "Transcribing..." with spinner while processing
- Auto-dismisses after completion or error

### Sidebar Popout (SidebarLeft.qml modifications)

**Current behavior (overlay):**
- `exclusiveZone: 0` — sidebar floats over content
- `HyprlandFocusGrab` — click outside closes it
- Visibility toggled by keybind/IPC

**Popout behavior:**
- `exclusiveZone: sidebarWidth` — claims left-edge space, Hyprland tiles around it
- No `HyprlandFocusGrab` — stays open regardless of clicks elsewhere
- `visible: true` always (when popped out)
- Resize handle still works — on resize, update `exclusiveZone` to match new width

**State management:**
```
Persistent.states.sidebar.poppedOut: bool (default: false)
```

**Toggle flow:**
1. User presses `Ctrl+P` or clicks popout button
2. `poppedOut = true`
3. Set `exclusiveZone = sidebarWidth`
4. Disable `HyprlandFocusGrab`
5. Set `visible = true` (pinned)
6. Hyprland auto-shunts tiled windows right

**Un-toggle:**
1. User presses `Ctrl+P` again or clicks button
2. `poppedOut = false`
3. Set `exclusiveZone = 0`
4. Re-enable `HyprlandFocusGrab`
5. Sidebar reverts to toggle behavior
6. Hyprland reclaims the space for windows

## Data Flow

### Dictation
```
Control_R double-tap
  → activate recording (pw-record starts)
  → show indicator
  → wait for stop (tap / silence / timeout)
  → kill pw-record
  → transcribe audio (curl or local tool)
  → route text (sidebar chat or action palette)
  → clean up temp file
  → dismiss indicator
```

### Sidebar Popout
```
Ctrl+P (or button click)
  → toggle poppedOut state
  → update exclusiveZone
  → toggle focusGrab
  → persist state
  → Hyprland handles window layout
```

## Testing Strategy

**Property tests:**
1. Double-tap timing: events within threshold activate, events outside threshold don't
2. Routing logic: sidebar open → chat, sidebar closed → action palette
3. Silence timeout: fires after configured duration of no audio
4. Exclusive zone: matches sidebar width at all times when popped out

**Integration tests:**
1. Full dictation flow with mocked pw-record and transcription endpoint
2. Popout toggle correctly changes exclusiveZone between 0 and sidebarWidth
3. Policy enforcement blocks remote transcription in local-only mode
4. Configuration changes apply immediately (double-tap speed, silence timeout)
