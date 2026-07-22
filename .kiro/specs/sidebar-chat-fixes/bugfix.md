# Bugfix Requirements Document

## Introduction

The Quickshell sidebar AI chat panel has six related bugs affecting visibility, session management, text input, dictation routing, voice assistant context, and deploy workflow. These collectively degrade the sidebar chat UX — messages don't appear until interacted with, sessions don't switch correctly, text editing breaks after select-all, dictation goes to the wrong target, the voice assistant lacks monitor context, and code changes don't take effect after deploys due to QML compilation cache.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the sidebar chat panel is opened or messages are added THEN the chat messages are invisible until the user clicks inside the chat area, because the SwipeView's `layer.enabled: true` + `OpacityMask` caches rendered content into an FBO that doesn't invalidate when content changes behind it

1.2 WHEN the user clicks a different session in the session drawer THEN the message list does not update to show the selected session's messages, because `loadSession` relies on a FileView path binding that may not update synchronously before `reload()` is called, and the `onMessageIDsChanged` auto-save handler can write new session data to the wrong file during the transition

1.3 WHEN the user presses Ctrl+A to select all text in the chat input and then presses Delete or Backspace THEN nothing happens and the input locks up, because the `Keys.onPressed` handler on the TextArea intercepts key events without falling through to the native selection-delete behavior

1.4 WHEN the user dictates text (double-tap Ctrl_R) while focus is outside the sidebar chat THEN the transcribed text is inserted into the sidebar chat input field instead of typing at the system cursor position (wherever focus actually is — terminal, browser, editor, etc.)

1.5 WHEN the user asks the ActionPalette voice assistant about monitor resolution or display information THEN the assistant cannot answer because `buildActionContext()` does not include Hyprland monitor data (`HyprlandData.monitorList`) in the context provided to the LLM

1.6 WHEN QML files are edited and deployed (rsync + service restart) THEN quickshell continues using the old cached versions from `~/.cache/quickshell/qmlcache`, because the systemd service restart does not clear the QML compilation cache

### Expected Behavior (Correct)

2.1 WHEN the sidebar chat panel is opened or messages are added THEN the system SHALL render chat messages immediately and visibly without requiring user interaction, by removing the `layer.enabled`/`OpacityMask` FBO caching from the SwipeView

2.2 WHEN the user clicks a different session in the session drawer THEN the system SHALL display that session's messages correctly by ensuring the file path binding updates and reload completes before the auto-save handler fires, using the `switching` guard to prevent `onMessageIDsChanged` from saving during transition

2.3 WHEN the user selects all text (Ctrl+A) and presses Delete or Backspace THEN the system SHALL delete the selected text normally, by not intercepting Delete/Backspace key events when text is selected in the input field (allowing native TextArea selection-delete to proceed)

2.4 WHEN the user dictates text while focus is outside the sidebar chat THEN the system SHALL type the transcribed text at the system cursor position using `wtype` or `ydotool`, reserving sidebar input insertion only for when the sidebar chat input explicitly has focus

2.5 WHEN the user asks the ActionPalette voice assistant about monitor information THEN the system SHALL include Hyprland monitor data (resolution, name, position, scale, active status) in the `buildActionContext()` response so the LLM can answer monitor-related queries

2.6 WHEN the quickshell systemd service is restarted THEN the system SHALL clear the QML compilation cache at `~/.cache/quickshell/qmlcache` before starting quickshell, ensuring edited QML files take effect immediately

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the sidebar SwipeView displays tabs (AI Chat, Translator, Providers, Anime) THEN the system SHALL CONTINUE TO clip content within the SwipeView bounds and allow tab switching via swipe and tab bar

3.2 WHEN the user is actively viewing the current session's messages and new messages arrive THEN the system SHALL CONTINUE TO auto-scroll to the bottom and auto-save the session normally

3.3 WHEN the user types text without selecting and presses Enter THEN the system SHALL CONTINUE TO submit the message, and Shift+Enter SHALL CONTINUE TO insert a newline

3.4 WHEN the user dictates text while the sidebar chat input has focus THEN the system SHALL CONTINUE TO insert transcribed text into the chat input field at the cursor position (existing behavior for active chat dictation)

3.5 WHEN the ActionPalette voice assistant receives queries about windows, workspaces, or config THEN the system SHALL CONTINUE TO include window list, active workspace, and config state in the context

3.6 WHEN the quickshell service starts normally (not after a config edit) THEN the system SHALL CONTINUE TO start quickly without unnecessary cache clearing overhead on every boot (cache clear should be part of the deploy workflow, not a performance penalty on normal restarts)
