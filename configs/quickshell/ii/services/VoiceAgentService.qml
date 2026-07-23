pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.services

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * VoiceAgentService — orchestrates bidirectional streaming voice conversations.
 * Manages pw-cat (capture) → FIFO → voice-agent-stream.py (helper) → pw-play (playback)
 * with JSON control messages on helper stdin/stdout.
 *
 * Requirements: 2.1–2.6, 10.1, 14.1, 14.2
 */
Singleton {
    id: root

    // State enum
    enum State {
        Idle,
        Connecting,
        Listening,
        Thinking,
        Speaking,
        ToolExecuting,
        Error
    }

    // Public state properties
    property int voiceAgentState: VoiceAgentService.State.Idle
    property string partialText: ""
    property string responseText: ""
    property string currentToolName: ""
    property real audioLevel: 0.0
    property string credentialError: ""
    property string errorMessage: ""

    // Dictation-to-cursor mode: when true, user transcripts are typed at cursor via wtype
    // and audio responses are suppressed. Activated by double-tap.
    property bool dictationToCursorMode: false

    // Config-bound
    property string voiceBackend: Config.options.dictation.voiceBackend || "none"

    // Internal properties
    property string _fifoPath: ""
    property string _contextFilePath: ""  // Temp JSON file for session context
    property string _savedWindowAddress: ""  // Window to restore focus to after deactivation
    property string _deferredFlushText: ""   // Text to flush after focus settles
    property var _sessionTranscript: []   // Accumulated turns [{role, text}] during session
    property int _previousState: VoiceAgentService.State.Idle  // For ToolExecuting return
    property int _sampleRate: root.voiceBackend === "openai-realtime" ? 24000 : 16000
    property string _pendingToolCallId: ""  // Track tool call ID for TOOL_RESULT pairing
    property bool _shuttingDown: false  // Guards exit handlers during intentional shutdown
    property bool _bargeInActive: false  // Guards playback exit during barge-in
    property string _helperStderr: ""  // Buffered stderr output for error reporting

    // Signals
    signal sessionStarted()
    signal sessionEnded()
    signal toolCallReceived(string name, string args)

    // State names for logging
    readonly property var _stateNames: ["Idle", "Connecting", "Listening", "Thinking", "Speaking", "ToolExecuting", "Error"]

    function _logTransition(from, to, context) {
        var fromName = root._stateNames[from] || String(from)
        var toName = root._stateNames[to] || String(to)
        console.log("[VoiceAgentService] STATE: " + fromName + " → " + toName + " | " + (context || ""))
    }

    function _setState(newState, context) {
        var oldState = root.voiceAgentState
        root.voiceAgentState = newState
        _logTransition(oldState, newState, context)
    }

    // ─── Credential Validation ───────────────────────────────────────────

    /**
     * Validates credentials for the currently configured voice backend.
     * Returns an empty string if credentials are valid, or a descriptive
     * error message identifying the missing credential.
     */
    function validateCredentials(): string {
        if (root.voiceBackend === "nova-sonic") {
            if (!AwsCredentialReader.credentialsDetected) {
                return "AWS credentials missing: add a [bedrock] profile to ~/.aws/credentials"
            }
        } else if (root.voiceBackend === "openai-realtime") {
            var apiKey = ""
            if (KeyringStorage.keyringData && KeyringStorage.keyringData.apiKeys) {
                apiKey = KeyringStorage.keyringData.apiKeys["openai"] || ""
            }
            if (!apiKey) {
                return "OpenAI API key missing: add your key in Provider Settings"
            }
        }
        return ""
    }

    // ─── Activate ────────────────────────────────────────────────────────

    /**
     * Attempts to activate a streaming voice session.
     * Validates policy + credentials, creates FIFO, launches pw-cat and helper.
     */
    function activate() {
        // Policy gate: AI completely disabled (Requirement 14.1)
        if (Config.options.policies.ai === 0) {
            console.warn("[VoiceAgentService] GATE_REJECT | reason=ai_disabled")
            root.errorMessage = "Voice agent disabled: AI is turned off in policies"
            root.credentialError = root.errorMessage
            _setState(VoiceAgentService.State.Error, "ai disabled by policy")
            DictationService.errorMessage = root.errorMessage
            DictationService.state = DictationService.State.Error
            errorDismissTimer.restart()
            return
        }

        // Policy gate: local-only rejects remote backends (Requirement 14.2)
        if (Config.options.policies.ai === 2) {
            if (root.voiceBackend === "nova-sonic" || root.voiceBackend === "openai-realtime") {
                console.warn("[VoiceAgentService] GATE_REJECT | reason=local_only_rejects_remote_voice")
                root.errorMessage = "Streaming voice requires remote API access, but policy is set to local-only"
                root.credentialError = root.errorMessage
                _setState(VoiceAgentService.State.Error, "local-only policy rejects streaming backend")
                DictationService.errorMessage = root.errorMessage
                DictationService.state = DictationService.State.Error
                errorDismissTimer.restart()
                return
            }
        }

        // Backend gate: no voice backend configured → activate batch pipeline directly
        // Requirement 10.4: when voiceBackend is "none", use batch pipeline without streaming attempt
        if (root.voiceBackend === "none" || !root.voiceBackend) {
            console.log("[VoiceAgentService] FALLBACK | reason=no_voice_backend_configured — activating batch pipeline")
            DictationService.activate()
            return
        }

        // Credential gate
        var error = validateCredentials()
        if (error) {
            root.credentialError = error
            root.errorMessage = error
            _setState(VoiceAgentService.State.Idle, "credential validation failed")
            DictationService.errorMessage = error
            DictationService.state = DictationService.State.Error
            return
        }

        root.credentialError = ""
        root.errorMessage = ""
        root.partialText = ""
        root.responseText = ""
        root.currentToolName = ""
        root.audioLevel = 0.0
        root._sessionTranscript = []  // Reset transcript for new session
        root._helperStderr = ""  // Clear stderr buffer for new session

        // Transition to Connecting
        _setState(VoiceAgentService.State.Connecting, "activate()")

        // Save the currently focused window so we can restore focus after deactivation
        // (prevents workspace switching when the stop key triggers other handlers)
        if (root.dictationToCursorMode) {
            root._savedWindowAddress = ""
            _saveFocusedWindow.command = ["hyprctl", "activewindow", "-j"]
            _saveFocusedWindow.running = true
        }

        // Create named FIFO for audio piping
        _createFifoAndLaunch()
    }

    /**
     * Creates a unique FIFO path and launches the audio + helper processes.
     */
    function _createFifoAndLaunch() {
        // No FIFO needed — helper spawns pw-cat internally.
        // Go straight to launching the helper.
        root._fifoPath = ""
        _launchProcesses()
    }

    /**
     * Launches the helper after FIFO is created.
     * pw-cat is now spawned internally by the helper script (no FIFO needed).
     */
    function _launchProcesses() {
        var rate = root._sampleRate

        // Build helper command — voice-agent-stream wrapper (nix-built, has websockets+boto3)
        var helperPath = Quickshell.shellPath("scripts/voice-agent-stream.py")
        var cmdParts = [
            helperPath,
            "--backend=" + root.voiceBackend,
            "--audio-fifo=internal",
            "--sample-rate=" + rate
        ]

        // Add backend-specific credentials/config
        if (root.voiceBackend === "nova-sonic") {
            cmdParts.push("--region=" + (Config.options.dictation.awsRegion || "us-west-2"))
            cmdParts.push("--profile=bedrock")
        } else if (root.voiceBackend === "openai-realtime") {
            var apiKey = ""
            if (KeyringStorage.keyringData && KeyringStorage.keyringData.apiKeys) {
                apiKey = KeyringStorage.keyringData.apiKeys["openai"] || ""
            }
            if (apiKey) {
                cmdParts.push("--api-key=" + apiKey)
            }
        }

        // Optional system prompt — resolve placeholders (skip in dictation-to-cursor mode)
        if (!root.dictationToCursorMode) {
            var systemPrompt = Config.options.dictation.voiceSystemPrompt || ""
            if (systemPrompt) {
                // Resolve {DATETIME} placeholder
                var now = new Date()
                var dateTimeStr = now.toLocaleString(Qt.locale(), "ddd, yyyy-MM-dd hh:mm:ss")
                systemPrompt = systemPrompt.replace("{DATETIME}", dateTimeStr)
                cmdParts.push("--system-prompt=" + systemPrompt)
            }
        }

        // Write tools definition and pass to helper (skip in dictation-to-cursor mode)
        if (!root.dictationToCursorMode) {
            var toolsPath = _writeToolsDefinition()
            if (toolsPath) {
                cmdParts.push("--tools=" + toolsPath)
            }

            // Optional context from active chat session
            var contextPath = _writeSessionContext()
            if (contextPath) {
                cmdParts.push("--context=" + contextPath)
            }
        } else {
            // In dictation mode, use realtime-whisper transcription session
            cmdParts.push("--dictation-mode")
        }

        var cmd = ["voice-agent-stream"].concat(cmdParts)

        helperProcess.stdinEnabled = true
        helperProcess.command = cmd
        helperProcess.running = true

        // Start connection timeout
        connectionTimeoutTimer.restart()
    }

    /**
     * Writes active session context to a temp JSON file for the helper.
     * Serializes the last 20 messages from the active sidebar chat session.
     * Returns the file path, or empty string if no context available.
     * Requirements: 9.1, 9.2, 9.3
     */
    function _writeSessionContext(): string {
        // Read recent messages from the active Ai session
        var messageIDs = Ai.messageIDs || []
        if (messageIDs.length === 0) return ""

        // Take last 20 messages
        var startIdx = Math.max(0, messageIDs.length - 20)
        var contextMessages = []

        for (var i = startIdx; i < messageIDs.length; i++) {
            var id = messageIDs[i]
            var msg = Ai.messageByID[id]
            if (!msg) continue
            // Skip interface messages — they're not real conversation
            if (msg.role === Ai.interfaceRole) continue
            contextMessages.push({
                "role": msg.role,
                "content": msg.rawContent || ""
            })
        }

        if (contextMessages.length === 0) return ""

        // Use a stable path — write synchronously via printf to avoid race conditions
        var contextPath = "/tmp/voice-agent-context.json"
        root._contextFilePath = contextPath

        var jsonContent = JSON.stringify(contextMessages)
        // Escape for shell: replace single quotes and backslashes
        var escaped = jsonContent.replace(/\\/g, "\\\\").replace(/'/g, "'\\''")
        contextWriteProcess.command = ["bash", "-c", "printf '%s' '" + escaped + "' > " + contextPath]
        contextWriteProcess.running = true
        // Process will exit on its own after writing — we wait briefly
        return contextPath
    }

    /**
     * Writes the available tool definitions to a temp JSON file for the voice helper.
     * These tools match what ActionPalette.executeToolDirect() supports.
     * Returns the file path, or empty string on failure.
     */
    function _writeToolsDefinition(): string {
        var tools = [
            {
                "name": "shell_exec",
                "description": "Execute a shell command and return its output. Use for system queries like checking time (date), running processes (ps aux), disk usage, etc.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "command": {
                            "type": "string",
                            "description": "The bash command to execute"
                        }
                    },
                    "required": ["command"]
                }
            },
            {
                "name": "system_info",
                "description": "Get basic system information: kernel, memory usage, and disk usage.",
                "parameters": {
                    "type": "object",
                    "properties": {}
                }
            },
            {
                "name": "config_get",
                "description": "Read a Quickshell configuration value by dot-separated key path (e.g. 'bar.weather.city', 'dictation.provider').",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "key": {
                            "type": "string",
                            "description": "Dot-separated config key path"
                        }
                    },
                    "required": ["key"]
                }
            },
            {
                "name": "config_set",
                "description": "Set a Quickshell configuration value by dot-separated key path.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "key": {
                            "type": "string",
                            "description": "Dot-separated config key path"
                        },
                        "value": {
                            "description": "The value to set"
                        }
                    },
                    "required": ["key", "value"]
                }
            },
            {
                "name": "hyprland_dispatch",
                "description": "Execute a Hyprland dispatcher command (e.g. workspace switching, window focus, fullscreen toggle).",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "dispatcher": {
                            "type": "string",
                            "description": "The Hyprland dispatcher name (e.g. 'workspace', 'focuswindow', 'fullscreen')"
                        },
                        "args": {
                            "type": "string",
                            "description": "Arguments for the dispatcher"
                        }
                    },
                    "required": ["dispatcher"]
                }
            },
            {
                "name": "app_launch",
                "description": "Launch a desktop application by its .desktop entry ID (e.g. 'firefox', 'org.kde.dolphin', 'kitty').",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "id": {
                            "type": "string",
                            "description": "The desktop entry ID of the application to launch"
                        }
                    },
                    "required": ["id"]
                }
            },
            {
                "name": "weather",
                "description": "Get the current weather conditions including temperature, humidity, wind, and conditions for the configured city.",
                "parameters": {
                    "type": "object",
                    "properties": {}
                }
            }
        ]

        var toolsPath = "/tmp/voice-agent-tools.json"

        var jsonContent = JSON.stringify(tools)
        var escaped = jsonContent.replace(/\\/g, "\\\\").replace(/'/g, "'\\''")
        toolsWriteProcess.command = ["bash", "-c", "printf '%s' '" + escaped + "' > " + toolsPath]
        toolsWriteProcess.running = true

        return toolsPath
    }

    // ─── Deactivate ──────────────────────────────────────────────────────

    /**
     * Deactivates the voice agent session.
     * Sends STOP to helper stdin, closes FIFO, kills processes, transitions to Idle.
     */
    function deactivate() {
        console.log("[VoiceAgentService] deactivate() called | state=" + root._stateNames[root.voiceAgentState])

        // Guard exit handlers from triggering error transitions during intentional shutdown
        root._shuttingDown = true

        // In dictation-to-cursor mode, flush any un-injected text to cursor
        // before tearing down. Use a delayed injection so it fires AFTER any
        // focus-stealing key events from the activation key have settled.
        if (root.dictationToCursorMode && root._pendingText.length > root._injectedText.length) {
            var remaining = root._pendingText.substring(root._injectedText.length)
            console.log("[VoiceAgentService] Flushing remaining text on deactivate: " + remaining.substring(0, 60))
            root._deferredFlushText = remaining
            _deferredFlushTimer.restart()
        }

        // Send STOP to helper if it's running
        if (helperProcess.running) {
            var stopEvent = JSON.stringify({"type": "STOP"})
            helperProcess.write(stopEvent + "\n")
        }

        // Stop all timers
        connectionTimeoutTimer.stop()
        errorDismissTimer.stop()
        transcriptCompletionTimer.stop()

        // Kill processes
        captureProcess.running = false
        helperProcess.running = false
        playbackProcess.running = false

        // Clean up FIFO and context file
        _cleanupFifo()
        _cleanupContextFile()

        // Reset state
        root.partialText = ""
        root._injectedText = ""
        root._pendingText = ""
        root.responseText = ""
        root.currentToolName = ""
        root.audioLevel = 0.0
        root.credentialError = ""
        root.errorMessage = ""

        _setState(VoiceAgentService.State.Idle, "deactivate()")
        root._shuttingDown = false
        root._helperStderr = ""

        root.dictationToCursorMode = false
        root.sessionEnded()
    }

    /**
     * Removes the named FIFO if it exists.
     */
    function _cleanupFifo() {
        if (root._fifoPath) {
            Quickshell.execDetached(["rm", "-f", root._fifoPath])
            root._fifoPath = ""
        }
    }

    // ─── Barge-In ────────────────────────────────────────────────────────

    /**
     * Interrupts playback: kills pw-play, sends BARGE_IN to helper,
     * transitions to Listening.
     */
    function bargeIn() {
        if (root.voiceAgentState !== VoiceAgentService.State.Speaking) return

        console.log("[VoiceAgentService] bargeIn()")

        // Kill playback — set _bargeInActive to suppress playback exit error handler
        root._bargeInActive = true
        playbackProcess.running = false

        // Send BARGE_IN to helper
        if (helperProcess.running) {
            var bargeEvent = JSON.stringify({"type": "BARGE_IN"})
            helperProcess.write(bargeEvent + "\n")
        }

        root.responseText = ""
        _setState(VoiceAgentService.State.Listening, "bargeIn()")
    }

    // ─── Send Tool Result ────────────────────────────────────────────────

    /**
     * Sends an END_TURN event to the helper stdin, triggering explicit
     * end-of-turn (input_audio_buffer.commit for OpenAI, content end/restart
     * for Nova Sonic). Used when user taps activation key during Listening
     * to force the backend to begin responding immediately.
     * Requirement: 7.4
     */
    function sendEndTurn() {
        if (!helperProcess.running) return

        console.log("[VoiceAgentService] sendEndTurn()")
        var event = JSON.stringify({"type": "END_TURN"})
        helperProcess.write(event + "\n")

        // In dictation-to-cursor mode with manual commits (no VAD),
        // start a safety timeout in case the completed transcript never arrives.
        if (root.dictationToCursorMode) {
            transcriptCompletionTimer.restart()
        }
    }

    /**
     * Sends a TOOL_RESULT event to the helper stdin and transitions back
     * to the previous state (before ToolExecuting).
     */
    function sendToolResult(name, result, isError) {
        if (!helperProcess.running) return

        var event = JSON.stringify({
            "type": "TOOL_RESULT",
            "id": root._pendingToolCallId,
            "name": name,
            "result": result,
            "is_error": isError || false
        })
        helperProcess.write(event + "\n")

        root._pendingToolCallId = ""
        root.currentToolName = ""
        _setState(root._previousState, "sendToolResult(" + name + ")")
    }

    // ─── Event Routing ───────────────────────────────────────────────────

    /**
     * Handles a JSON event line from the helper's stdout.
     */
    function _handleHelperEvent(line) {
        if (!line || line.trim().length === 0) return

        var event
        try {
            event = JSON.parse(line.trim())
        } catch (e) {
            console.warn("[VoiceAgentService] Failed to parse helper event: " + line)
            return
        }

        var eventType = event.type || ""

        switch (eventType) {
            case "READY":
                _onReady(event)
                break
            case "PARTIAL_TRANSCRIPT":
                _onPartialTranscript(event)
                break
            case "TURN_END":
                _onTurnEnd(event)
                break
            case "TURN_COMPLETE":
                _onTurnComplete(event)
                break
            case "AUDIO_RESPONSE":
                _onAudioResponse(event)
                break
            case "TOOL_CALL":
                _onToolCall(event)
                break
            case "SESSION_END":
                _onSessionEnd(event)
                break
            case "ERROR":
                _onError(event)
                break
            case "FALLBACK":
                _onFallback(event)
                break
            case "AMPLITUDE":
                _onAmplitude(event)
                break
            case "USER_TRANSCRIPT":
                _onUserTranscript(event)
                break
            case "USER_TRANSCRIPT_DELTA":
                _onUserTranscriptDelta(event)
                break
            default:
                console.warn("[VoiceAgentService] Unknown event type: " + eventType)
        }
    }

    function _onReady(event) {
        if (root.voiceAgentState !== VoiceAgentService.State.Connecting) return

        connectionTimeoutTimer.stop()
        _setState(VoiceAgentService.State.Listening, "READY event received")
        root.sessionStarted()
    }

    function _onPartialTranscript(event) {
        root.partialText = event.text || ""
    }

    function _onTurnEnd(event) {
        if (root.voiceAgentState === VoiceAgentService.State.Listening) {
            root.partialText = ""
            _setState(VoiceAgentService.State.Thinking, "TURN_END")
        }
    }

    function _onTurnComplete(event) {
        // Turn complete — clear partial, prepare for next turn
        root.partialText = ""

        // Capture AI response text from this turn before overwriting (Requirement 9.4)
        if (root.responseText && root.responseText.length > 0) {
            root._sessionTranscript.push({"role": "assistant", "content": root.responseText})
        }

        root.responseText = event.text || ""

        // TURN_COMPLETE carries the finalized user utterance
        if (event.text) {
            root._sessionTranscript.push({"role": "user", "content": event.text})

            // Dictation-to-cursor mode: type user transcript at cursor
            if (root.dictationToCursorMode && event.text.trim().length > 0) {
                console.log("[VoiceAgentService] Dictation-to-cursor: typing '" + event.text.substring(0, 40) + "'...")
                Quickshell.execDetached(["wtype", "--", event.text])
            }
        }

        if (root.voiceAgentState === VoiceAgentService.State.Speaking ||
            root.voiceAgentState === VoiceAgentService.State.Thinking) {
            _setState(VoiceAgentService.State.Listening, "TURN_COMPLETE")
        }
    }

    function _onAudioResponse(event) {
        // In dictation-to-cursor mode, suppress audio playback entirely
        if (root.dictationToCursorMode) return

        if (root.voiceAgentState === VoiceAgentService.State.Thinking ||
            root.voiceAgentState === VoiceAgentService.State.Listening) {
            _setState(VoiceAgentService.State.Speaking, "AUDIO_RESPONSE")
        }

        // Decode base64 audio and pipe to the playback pipeline (Requirement 13.3)
        // The playbackProcess is a persistent pipeline that accepts base64 lines on stdin,
        // decodes them, and feeds the raw PCM to pw-play.
        var audioData = event.audio || ""
        if (audioData) {
            if (!playbackProcess.running) {
                _startPlayback()
            }
            // Write base64 chunk as a line — the pipeline decodes + plays
            playbackProcess.write(audioData + "\n")
        }

        // Update response text if provided
        if (event.text) {
            root.responseText = event.text
        }
    }

    function _startPlayback() {
        var rate = root._sampleRate
        // Persistent playback pipeline: reads base64 lines from stdin,
        // decodes each line to raw PCM, feeds into pw-play.
        // Uses Python for reliable streaming base64 decode (handles partial lines, flush).
        playbackProcess.command = ["bash", "-c",
            "python3 -c \""
            + "import sys, base64\\n"
            + "for line in sys.stdin:\\n"
            + "    chunk = line.strip()\\n"
            + "    if chunk:\\n"
            + "        sys.stdout.buffer.write(base64.b64decode(chunk))\\n"
            + "        sys.stdout.buffer.flush()\\n"
            + "\" | pw-play --format=s16 --rate=" + rate + " --channels=1 -"
        ]
        playbackProcess.stdinEnabled = true
        playbackProcess.running = true
    }

    function _onToolCall(event) {
        root._previousState = root.voiceAgentState
        root._pendingToolCallId = event.id || ""
        root.currentToolName = event.name || ""
        _setState(VoiceAgentService.State.ToolExecuting, "TOOL_CALL: " + root.currentToolName)
        root.toolCallReceived(event.name || "", JSON.stringify(event.arguments || {}))

        // Parse arguments and execute via ActionPalette
        var toolName = event.name || ""
        var toolArgs = event.arguments || {}

        // If arguments came as a JSON string, parse it
        if (typeof toolArgs === "string") {
            try {
                toolArgs = JSON.parse(toolArgs)
            } catch (e) {
                toolArgs = { command: toolArgs }
            }
        }

        // Execute through ActionPalette's direct tool execution
        ActionPalette.executeToolDirect(toolName, toolArgs, function(result) {
            // Send TOOL_RESULT back to helper stdin
            root.sendToolResult(toolName, result.result, result.isError)
        })
    }

    function _onSessionEnd(event) {
        console.log("[VoiceAgentService] SESSION_END received")

        // Capture any final AI response text that hasn't been logged yet
        if (root.responseText && root.responseText.length > 0) {
            root._sessionTranscript.push({"role": "assistant", "content": root.responseText})
        }

        // Append accumulated transcript to sidebar session (Requirements 9.4, 9.5)
        _appendTranscriptToSession()

        // Clean up context file
        _cleanupContextFile()

        deactivate()
    }

    function _onError(event) {
        var message = event.message || event.text || "Unknown error"
        var fatal = event.fatal !== undefined ? event.fatal : true

        console.warn("[VoiceAgentService] ERROR: " + message + " (fatal=" + fatal + ")")

        if (fatal) {
            root.errorMessage = message
            _setState(VoiceAgentService.State.Error, "ERROR: " + message)
            // Clean up processes
            captureProcess.running = false
            helperProcess.running = false
            playbackProcess.running = false
            _cleanupFifo()
            _cleanupContextFile()
            // Auto-dismiss after 5s
            errorDismissTimer.restart()
        } else {
            // Non-fatal error — log but continue
            console.warn("[VoiceAgentService] Non-fatal error: " + message)
        }
    }

    function _onFallback(event) {
        var reason = event.reason || "connection failed"
        console.log("[VoiceAgentService] FALLBACK | reason=" + reason + " — delegating to batch pipeline")

        // Preserve dictation mode flag before reset
        var wasDictationMode = root.dictationToCursorMode

        // Kill our processes
        captureProcess.running = false
        helperProcess.running = false
        playbackProcess.running = false
        connectionTimeoutTimer.stop()
        _cleanupFifo()
        _cleanupContextFile()

        _setState(VoiceAgentService.State.Idle, "FALLBACK → batch")
        root.dictationToCursorMode = false

        // Delegate to DictationService batch pipeline.
        // If we were in dictation-to-cursor mode, set the flag so batch types at cursor.
        if (wasDictationMode) {
            DictationService._dictationToCursor = true
        }
        DictationService.activate()
    }

    function _onAmplitude(event) {
        // Update audioLevel from helper's RMS calculation (Requirement 13.4)
        // The level is already normalized to 0.0–1.0 by the Python helper
        var level = event.level
        if (typeof level === "number" && isFinite(level)) {
            root.audioLevel = Math.max(0.0, Math.min(1.0, level))
        }
    }

    /**
     * Injects text at the focused cursor position using wtype.
     * Called with complete words (buffered one word behind the stream)
     * to avoid race conditions from rapid concurrent calls.
     */
    function _injectText(text) {
        if (!text || text.length === 0) return
        Quickshell.execDetached(["wtype", "--", text])
    }

    function _onUserTranscript(event) {
        // Completed event — flush the trailing word that hasn't been injected yet.
        var text = event.text || ""

        // Stop the safety timeout — transcript arrived
        transcriptCompletionTimer.stop()

        if (!text || text.trim().length === 0) return

        console.log("[VoiceAgentService] USER_TRANSCRIPT: " + text.substring(0, 60))

        if (root.dictationToCursorMode) {
            // Inject any remaining un-injected text (the trailing word)
            var remaining = root._pendingText.substring(root._injectedText.length)
            if (remaining.length > 0) {
                _injectText(remaining + " ")
            } else {
                _injectText(" ")
            }
            // Reset for next utterance
            root._injectedText = ""
            root._pendingText = ""
            root.partialText = ""
        }
    }

    // Track what's been injected vs what's pending
    property string _injectedText: ""  // Text already typed at cursor
    property string _pendingText: ""   // Full accumulated delta text (including un-injected trailing word)

    function _onUserTranscriptDelta(event) {
        // Buffer deltas and inject complete words (one word behind the stream).
        // The trailing partial word stays in the overlay until a space confirms it.
        var delta = event.delta || ""
        if (!delta) return

        if (root.dictationToCursorMode) {
            root._pendingText += delta
            root.partialText = root._pendingText  // Overlay shows everything

            // Find complete words: everything up to (and including) the last space
            var lastSpace = root._pendingText.lastIndexOf(" ")
            if (lastSpace > root._injectedText.length) {
                // There are new complete words to inject
                var toInject = root._pendingText.substring(root._injectedText.length, lastSpace + 1)
                if (toInject.length > 0) {
                    _injectText(toInject)
                    root._injectedText = root._pendingText.substring(0, lastSpace + 1)
                }
            }
        }
    }

    // ─── Session Context and Transcript ──────────────────────────────────

    /**
     * Appends accumulated transcript turns to the active sidebar session.
     * Falls back to "Free Dictation" session if no active session exists.
     * Requirements: 9.4, 9.5
     */
    function _appendTranscriptToSession() {
        if (root._sessionTranscript.length === 0) return

        console.log("[VoiceAgentService] Appending " + root._sessionTranscript.length + " transcript entries to session")

        // Determine target: use active session if available, fall back to Free Dictation
        var activeSession = Ai.activeSessionName || ""
        var useFreeDictation = (!activeSession || activeSession.length === 0)

        for (var i = 0; i < root._sessionTranscript.length; i++) {
            var entry = root._sessionTranscript[i]
            if (!entry.content || entry.content.trim().length === 0) continue

            if (useFreeDictation) {
                // Requirement 9.5: Fall back to "Free Dictation" session
                Ai.appendToFreeDictation(entry.content, entry.role)
            } else {
                // Append to the active session's in-memory messages
                Ai.addMessage(entry.content, entry.role)
            }
        }

        // Clear transcript after appending
        root._sessionTranscript = []
    }

    /**
     * Removes the temporary context JSON file if it exists.
     */
    function _cleanupContextFile() {
        if (root._contextFilePath) {
            Quickshell.execDetached(["rm", "-f", root._contextFilePath])
            root._contextFilePath = ""
        }
    }

    // ─── FIFO Creation Process ───────────────────────────────────────────

    Process {
        id: fifoCreateProcess

        stdout: SplitParser {
            onRead: data => {
                if (data.trim() === "OK") {
                    root._launchProcesses()
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("[VoiceAgentService] Failed to create FIFO (exit " + exitCode + ")")
                root.errorMessage = "Failed to create audio FIFO"
                root._setState(VoiceAgentService.State.Error, "FIFO creation failed")
                errorDismissTimer.restart()
            }
        }
    }

    // ─── Context File View (for writing session context) ────────────────

    FileView {
        id: contextFileView
        blockLoading: true
    }

    FileView {
        id: toolsFileView
        blockLoading: true
    }

    Process {
        id: contextWriteProcess
    }

    Process {
        id: toolsWriteProcess
    }

    // ─── Audio Capture Process (pw-cat → FIFO) ──────────────────────────

    Process {
        id: captureProcess

        onExited: (exitCode, exitStatus) => {
            if (root._shuttingDown) return  // Intentional shutdown — ignore
            if (root.voiceAgentState !== VoiceAgentService.State.Idle &&
                root.voiceAgentState !== VoiceAgentService.State.Error) {
                console.warn("[VoiceAgentService] pw-cat exited unexpectedly (exit " + exitCode + ")")
                // Requirement 13.5: send STOP and transition to Error
                if (helperProcess.running) {
                    var stopEvent = JSON.stringify({"type": "STOP"})
                    helperProcess.write(stopEvent + "\n")
                }
                root.errorMessage = "Audio capture stopped unexpectedly"
                root._setState(VoiceAgentService.State.Error, "pw-cat exit " + exitCode)
                helperProcess.running = false
                playbackProcess.running = false
                root._cleanupFifo()
                errorDismissTimer.restart()
            }
        }
    }

    // ─── Helper Process (voice-agent-stream.py) ─────────────────────────

    Process {
        id: helperProcess
        stdinEnabled: true

        stdout: SplitParser {
            onRead: data => {
                root._handleHelperEvent(data)
            }
        }

        stderr: SplitParser {
            splitMarker: ""
            onRead: data => {
                var line = data.trim()
                if (line) {
                    console.warn("[VoiceAgentService] helper stderr: " + line)
                    // Buffer last stderr line for error display on unexpected exit
                    root._helperStderr = line
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (root._shuttingDown) return  // Intentional shutdown — ignore
            if (root.voiceAgentState !== VoiceAgentService.State.Idle &&
                root.voiceAgentState !== VoiceAgentService.State.Error) {
                // Requirement 2.6, 10.4: unexpected helper exit → capture exit code + stderr, Error state
                var stderrInfo = root._helperStderr ? " (" + root._helperStderr + ")" : ""
                console.warn("[VoiceAgentService] ERROR | helper_exit_code=" + exitCode + " stderr=" + root._helperStderr)
                captureProcess.running = false
                playbackProcess.running = false
                connectionTimeoutTimer.stop()
                root._cleanupFifo()
                root._cleanupContextFile()

                root.errorMessage = "Voice agent helper exited (code " + exitCode + ")" + stderrInfo
                root._setState(VoiceAgentService.State.Error, "helper exit " + exitCode)
                root._helperStderr = ""
                errorDismissTimer.restart()
            }
        }
    }

    // ─── Playback Process (base64 decode → pw-play pipeline) ────────────

    Process {
        id: playbackProcess
        stdinEnabled: true

        onExited: (exitCode, exitStatus) => {
            if (root._shuttingDown || root._bargeInActive) {
                // Intentional kill (deactivate or barge-in) — reset flag, ignore
                root._bargeInActive = false
                return
            }
            if (root.voiceAgentState === VoiceAgentService.State.Speaking) {
                // Playback finished naturally — audio stream exhausted.
                // Stay in Speaking until TURN_COMPLETE arrives from the helper.
                console.log("[VoiceAgentService] Playback pipeline finished (exit " + exitCode + ")")
            } else if (root.voiceAgentState !== VoiceAgentService.State.Idle &&
                       root.voiceAgentState !== VoiceAgentService.State.Error) {
                // Unexpected exit in non-terminal state — send STOP, transition to Error
                // (Requirement 13.5: handle pw-play unexpected exit)
                console.warn("[VoiceAgentService] Playback pipeline exited unexpectedly (exit " + exitCode + ")")
                if (helperProcess.running) {
                    var stopEvent = JSON.stringify({"type": "STOP"})
                    helperProcess.write(stopEvent + "\n")
                }
                root.errorMessage = "Audio playback stopped unexpectedly"
                root._setState(VoiceAgentService.State.Error, "playback exit " + exitCode)
                captureProcess.running = false
                helperProcess.running = false
                root._cleanupFifo()
                errorDismissTimer.restart()
            }
        }
    }

    // ─── Timers ──────────────────────────────────────────────────────────

    // 5-second connection timeout (Connecting → Error/fallback)
    // Requirement 10.1
    Timer {
        id: connectionTimeoutTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (root.voiceAgentState === VoiceAgentService.State.Connecting) {
                console.log("[VoiceAgentService] FALLBACK | reason=connection_timeout_5s — killing helper, activating batch pipeline")
                // Kill helper and capture
                root._shuttingDown = true
                helperProcess.running = false
                captureProcess.running = false
                playbackProcess.running = false
                root._cleanupFifo()
                root._cleanupContextFile()

                root._setState(VoiceAgentService.State.Idle, "connection timeout → fallback")
                root._shuttingDown = false

                // Requirement 10.1: fallback to batch pipeline
                DictationService.activate()
            }
        }
    }

    // Auto-dismiss error after 5 seconds → Idle
    // Requirement 11.6
    Timer {
        id: errorDismissTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (root.voiceAgentState === VoiceAgentService.State.Error) {
                root.errorMessage = ""
                root._setState(VoiceAgentService.State.Idle, "error auto-dismiss (5s)")
            }
        }
    }

    // Safety timeout for dictation-to-cursor: if no completed transcript arrives
    // within 5s after commit (sendEndTurn), deactivate to avoid hanging.
    Timer {
        id: transcriptCompletionTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (root.dictationToCursorMode && root.voiceAgentState === VoiceAgentService.State.Listening) {
                console.warn("[VoiceAgentService] Transcript completion timeout — deactivating")
                root.partialText = ""
                root.deactivate()
            }
        }
    }

    // Deferred flush: types the last buffered word after a short delay,
    // giving time for any focus-stealing key events to settle and for
    // the focuswindow restore to take effect.
    Timer {
        id: _deferredFlushTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (root._deferredFlushText.length > 0) {
                // Restore focus first, then type
                if (root._savedWindowAddress) {
                    Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + root._savedWindowAddress])
                }
                // Small additional delay for focus to actually switch
                _deferredTypeTimer.restart()
            }
        }
    }

    Timer {
        id: _deferredTypeTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (root._deferredFlushText.length > 0) {
                Quickshell.execDetached(["wtype", "--", root._deferredFlushText])
                root._deferredFlushText = ""
                root._savedWindowAddress = ""
            }
        }
    }

    // Process to capture the focused window address on dictation start
    Process {
        id: _saveFocusedWindow
        command: ["hyprctl", "activewindow", "-j"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                try {
                    var win = JSON.parse(data)
                    if (win && win.address) {
                        root._savedWindowAddress = win.address
                        console.log("[VoiceAgentService] Saved focused window: " + win.address)
                    }
                } catch(e) {}
            }
        }
    }
}
