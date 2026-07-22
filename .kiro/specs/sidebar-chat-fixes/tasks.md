# Tasks: Sidebar Chat Fixes

## Task 1: Add QML cache clear to systemd service (Fix 6)
- [x] 1.1 In `modules/components/quickshell-service.nix`, add `ExecStartPre` to the Service section that runs `rm -rf %h/.cache/quickshell/qmlcache` before quickshell starts
  - This ensures all subsequent fixes take effect immediately on restart
  - File: `modules/components/quickshell-service.nix`
  - _Requirements: 2.6, 3.6_

## Task 2: Fix Select All + Delete in chat input (Fix 3)
- [x] 2.1 In `configs/quickshell/ii/modules/sidebarLeft/AiChat.qml`, modify the root-level `Keys.onPressed` handler (around line 110) to only call `messageInputField.forceActiveFocus()` when the input field does NOT already have active focus
  - Change: wrap the `forceActiveFocus()` call with `if (!messageInputField.activeFocus)`
  - This prevents disrupting the TextArea's native selection state when Delete/Backspace is pressed after Ctrl+A
  - File: `configs/quickshell/ii/modules/sidebarLeft/AiChat.qml`
  - _Requirements: 2.3, 3.3_

## Task 3: Fix dictation routing — type at system cursor (Fix 4)
- [x] 3.1 In `configs/quickshell/ii/modules/sidebarLeft/AiChat.qml`, replace the `onTranscriptionComplete` handler in the `Connections { target: DictationService }` block with new routing logic:
  - If `Ai.activeSessionName === "Free Dictation"`: call `Ai.sendUserMessage(text)` directly without modifying `messageInputField.text`, set the postResponseHook to surface response to DictationIndicator
  - If `Ai.activeSessionName !== "Free Dictation"`: use `Quickshell.execDetached(["wtype", text])` to type at the system cursor position
  - Remove the old insert-at-cursor logic for non-Free-Dictation sessions
  - File: `configs/quickshell/ii/modules/sidebarLeft/AiChat.qml`
  - _Requirements: 2.4, 3.4_

## Task 4: Add monitor data to ActionPalette context (Fix 5)
- [x] 4.1 In `configs/quickshell/ii/services/ActionPalette.qml`, modify `buildActionContext()` to include a `monitors` array in the returned context object
  - Research if our hyprctl mcp will help solve this, and implement if useful.
  - Map `HyprlandData.monitors` to objects with: name, width, height, refreshRate, x, y, scale, focused, activeWorkspace, description
  - Add `monitors: monitors` to the returned context alongside `config`, `windows`, `activeWorkspace`
  - File: `configs/quickshell/ii/services/ActionPalette.qml`
  - _Requirements: 2.5, 3.5_

## Task 5: Deploy and verify all fixes
- [x] 5.1 Run full deploy procedure:
  - `rsync -av --delete configs/quickshell/ii/ ~/.config/quickshell/ii/`
  - `rm -rf ~/.cache/quickshell/qmlcache`
  - `systemctl --user restart quickshell`
  - _Requirements: 2.1, 2.2, 2.6_

- [ ] 5.2 Verify Fix 1 (invisible chat): Open sidebar → messages visible immediately without clicking
  - _Requirements: 2.1_

- [ ] 5.3 Verify Fix 2 (session switching): Open session drawer → click different session → messages change
  - _Requirements: 2.2_

- [ ] 5.4 Verify Fix 3 (select all + delete): Type text in input → Ctrl+A → Delete → text cleared
  - _Requirements: 2.3_

- [ ] 5.5 Verify Fix 4 (dictation routing): Dictate with sidebar open on non-Free-Dictation session → text types at system cursor via wtype
  - _Requirements: 2.4_

- [ ] 5.6 Verify Fix 5 (monitor resolution): Ask voice assistant "What's my resolution?" → correct answer returned
  - _Requirements: 2.5_
