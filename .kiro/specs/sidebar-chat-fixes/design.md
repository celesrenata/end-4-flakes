# Design: Sidebar Chat Fixes

## Overview

Six bugs in the Quickshell sidebar AI chat panel require targeted fixes across rendering, session persistence, input handling, dictation routing, voice assistant context, and deploy workflow. Each fix is isolated and independently verifiable.

## Fix 1: Chat Invisible Until Interaction (Req 2.1)

**Root Cause:** The SwipeView in `SidebarLeftContent.qml` previously used `layer.enabled: true` + `OpacityMask` which cached content into an FBO. This has already been removed (commented out) in the repo but the **QML compilation cache** at `~/.cache/quickshell/qmlcache` was preventing the change from taking effect.

**Fix:** The code change is already done (OpacityMask removed, `clip: true` retained). The actual fix is ensuring the cache is cleared on deploys (see Fix 6). Verify after cache clear that the sidebar renders immediately.

**Verification:** After deploy + cache clear + restart, open sidebar → messages visible immediately without clicking.

## Fix 2: Session Switching Shows Same Messages (Req 2.2)

**Root Cause:** Two issues compound:
1. `loadSession()` sets `chatSaveFile.chatName` then calls `chatSaveFile.reload()`. The `path` property is a binding (`${Directories.aiChats}/${chatName}.json`) which should re-evaluate immediately in QML. However, the QML cache was the actual blocker — the `switching` guard and explicit path set were added but never took effect.
2. The `onMessageIDsChanged` handler calls `saveCurrentSession()` which could overwrite the wrong file during transition. The `!root.switching` guard was already added.

**Fix:** Already implemented in code — verify after cache clear. The `loadSession` function explicitly sets `chatSaveFile.path` before reload, and `onMessageIDsChanged` is guarded by `!root.switching`.

**Verification:** After cache clear + restart, open session drawer → click "Chat 2" → messages change to Chat 2 content. Switch back → original session restored.

## Fix 3: Select All + Delete Broken (Req 2.3)

**Root Cause:** The `Keys.onPressed` handler on the root Item (line ~110 of AiChat.qml) does `messageInputField.forceActiveFocus()` on EVERY key press. This steals focus back to the input field, but the handler also calls `event.accepted = true` only for PageUp/PageDown. The actual problem is that the **root-level** handler forces focus, and the messageInputField's own handler doesn't explicitly handle Delete/Backspace — which is correct (they should fall through to native TextArea). The issue is likely that the root handler's `messageInputField.forceActiveFocus()` call on every key event disrupts the TextArea's internal selection state.

**Fix:** In `AiChat.qml`, modify the root-level `Keys.onPressed` to NOT call `forceActiveFocus()` when the messageInputField already has focus, and to not interfere with Delete/Backspace events:

```qml
Keys.onPressed: (event) => {
    if (!messageInputField.activeFocus) {
        messageInputField.forceActiveFocus()
    }
    if (event.modifiers === Qt.NoModifier) {
        if (event.key === Qt.Key_PageUp) {
            messageListView.contentY = Math.max(0, messageListView.contentY - messageListView.height / 2)
            event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
            messageListView.contentY = Math.min(messageListView.contentHeight - messageListView.height / 2, messageListView.contentY + messageListView.height / 2)
            event.accepted = true
        }
    }
}
```

**File:** `configs/quickshell/ii/modules/sidebarLeft/AiChat.qml` line ~110

**Verification:** Type text → Ctrl+A → Delete → text is cleared. Also: Ctrl+A → Backspace → text is cleared.

## Fix 4: Dictation Types Into Sidebar Instead of System Cursor (Req 2.4)

**Root Cause:** `AiChat.qml`'s `onTranscriptionComplete` handler (line ~316) always targets the sidebar input or auto-submits to AI. When the user dictates with the sidebar closed, `_processVoiceAssistant` routes to ActionPalette (correct for voice assistant). But when the sidebar is OPEN and the active session is NOT "Free Dictation", it inserts at `messageInputField` cursor — which the user doesn't want.

The user wants:
- **Sidebar closed:** Voice assistant behavior (speak to AI) → route to ActionPalette internally, log to Free Dictation (current behavior, keep)
- **Sidebar open + Free Dictation:** Send dictation to AI as a message internally (keep, but don't visibly spam the input)
- **Sidebar open + other session OR sidebar closed + double-tap mode:** Type at the system cursor using `wtype`

**Fix:** Modify the `onTranscriptionComplete` handler in AiChat.qml:
1. If sidebar is open AND active session is "Free Dictation": call `Ai.sendUserMessage(text)` directly (no intermediate input field display)
2. If sidebar is open AND active session is NOT "Free Dictation": use `wtype` to type at system cursor instead of inserting into messageInputField
3. Clear the messageInputField text silently (don't show the transcription in the input)

For `wtype` output:
```qml
Quickshell.execDetached(["wtype", text])
```

**File:** `configs/quickshell/ii/modules/sidebarLeft/AiChat.qml` — the `Connections { target: DictationService; function onTranscriptionComplete(text) }` block

**Verification:** 
- Dictate with sidebar open on Chat 1 → text types at system cursor (terminal, editor, etc.)
- Dictate with sidebar open on Free Dictation → message sent to AI without appearing in input field
- Dictate with sidebar closed → voice assistant responds (existing behavior unchanged)

## Fix 5: Voice Assistant Missing Monitor Resolution (Req 2.5)

**Root Cause:** `buildActionContext()` in `ActionPalette.qml` (line ~1224) gathers windows, config, and activeWorkspace but does NOT include `HyprlandData.monitors`. The AI has no monitor data to answer resolution queries.

**Fix:** Add monitors to the context object in `buildActionContext()`:

```qml
function buildActionContext() {
    const config = JSON.parse(JSON.stringify(Config.options));
    const windows = HyprlandData.windowList.map(w => ({
        address: w.address || "",
        appId: w.class || "",
        title: w.title || "",
        workspace: w.workspace?.id ?? -1,
        fullscreen: w.fullscreen || 0,
        floating: w.floating || false,
        focused: w.focusHistoryID === 0
    }));
    const monitors = HyprlandData.monitors.map(m => ({
        name: m.name || "",
        width: m.width || 0,
        height: m.height || 0,
        refreshRate: m.refreshRate || 0,
        x: m.x || 0,
        y: m.y || 0,
        scale: m.scale || 1,
        focused: m.focused || false,
        activeWorkspace: m.activeWorkspace?.id ?? -1,
        description: m.description || ""
    }));
    const activeWorkspace = HyprlandData.activeWorkspace?.id ?? 1;
    return {
        config: config,
        windows: windows,
        monitors: monitors,
        activeWorkspace: activeWorkspace
    };
}
```

**File:** `configs/quickshell/ii/services/ActionPalette.qml` — function `buildActionContext()` around line 1224

**Verification:** Ask voice assistant "What's my resolution?" → should respond with actual resolution (e.g. "3840x2160 at 60Hz").

## Fix 6: QML Cache Prevents Changes (Req 2.6)

**Root Cause:** Quickshell caches compiled QML bytecode at `~/.cache/quickshell/qmlcache`. The service restart doesn't clear it, so edited .qml files are ignored.

**Fix:** Add `ExecStartPre` to the systemd service in `modules/components/quickshell-service.nix` to clear the cache before starting:

```nix
ExecStartPre = "${pkgs.coreutils}/bin/rm -rf %h/.cache/quickshell/qmlcache";
```

This adds ~10ms overhead on each restart (just deleting a directory) and ensures every restart loads fresh QML.

**Per requirement 3.6:** This DOES add a tiny overhead per restart but it's negligible (rm -rf on a small directory is instant). The alternative (only clearing on deploy) requires a separate deploy script that the user would need to remember. Since the service auto-restarts on failure (RestartSec=2), the cold-compile penalty is only a few hundred ms — acceptable.

**File:** `modules/components/quickshell-service.nix` — in `Service` section

**Verification:** Edit any .qml file → rsync to ~/.config → `systemctl --user restart quickshell` → change takes effect immediately without manual cache clearing.

## Files Modified

| File | Fix |
|------|-----|
| `configs/quickshell/ii/modules/sidebarLeft/AiChat.qml` | Fix 3 (Keys.onPressed), Fix 4 (onTranscriptionComplete) |
| `configs/quickshell/ii/services/ActionPalette.qml` | Fix 5 (buildActionContext monitors) |
| `modules/components/quickshell-service.nix` | Fix 6 (ExecStartPre cache clear) |

Fixes 1 and 2 are already implemented in code — they just need the cache clear (Fix 6) to take effect.

## Deploy Procedure

1. Apply all code changes
2. `rsync -av --delete configs/quickshell/ii/ ~/.config/quickshell/ii/`
3. `rm -rf ~/.cache/quickshell/qmlcache`
4. `systemctl --user restart quickshell`
5. Verify each fix independently

## Constraints

- QML: no spread operator (use Object.assign), no replaceAll (use split/join), indexed for loops
- pragma Singleton + ComponentBehavior: Bound on all singletons
- `wtype` must be available on the system (it is — NixOS with Hyprland includes it)
- HyprlandData.monitors is populated from `hyprctl monitors -j` on every Hyprland event
