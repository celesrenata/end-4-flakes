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

    // Config-bound
    property string voiceBackend: Config.options.dictation.voiceBackend || "none"

    // Internal properties
    property string _fifoPath: ""
    property int _previousState: VoiceAgentService.State.Idle  // For ToolExecuting return
    property int _sampleRate: root.voiceBackend === "openai-realtime" ? 24000 : 16000

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

        // Backend gate: no voice backend configured
        if (root.voiceBackend === "none" || !root.voiceBackend) {
            console.warn("[VoiceAgentService] GATE_REJECT | reason=no_backend")
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

        // Transition to Connecting
        _setState(VoiceAgentService.State.Connecting, "activate()")

        // Create named FIFO for audio piping
        _createFifoAndLaunch()
    }

    /**
     * Creates a unique FIFO path and launches the audio + helper processes.
     */
    function _createFifoAndLaunch() {
        // Generate a unique FIFO path
        var timestamp = Date.now()
        root._fifoPath = "/tmp/voice-agent-" + timestamp + ".pcm"

        // Create FIFO via helper process, then launch pipeline
        fifoCreateProcess.command = ["bash", "-c",
            "mkfifo '" + root._fifoPath + "' && echo OK"
        ]
        fifoCreateProcess.running = true
    }

    /**
     * Launches pw-cat and the helper after FIFO is created.
     */
    function _launchProcesses() {
        var rate = root._sampleRate

        // Launch pw-cat writing to the FIFO
        captureProcess.command = [
            "pw-cat", "--record", "--format=s16",
            "--rate=" + rate, "--channels=1",
            "--target=-", root._fifoPath
        ]
        captureProcess.running = true

        // Build helper command
        var helperPath = Quickshell.shellPath("ii/scripts/voice-agent-stream.py")
        var cmd = ["python3", helperPath,
            "--backend=" + root.voiceBackend,
            "--audio-fifo=" + root._fifoPath,
            "--sample-rate=" + rate
        ]

        // Add backend-specific credentials/config
        if (root.voiceBackend === "nova-sonic") {
            cmd.push("--region=" + (Config.options.dictation.awsRegion || "us-west-2"))
            cmd.push("--profile=bedrock")
        } else if (root.voiceBackend === "openai-realtime") {
            var apiKey = ""
            if (KeyringStorage.keyringData && KeyringStorage.keyringData.apiKeys) {
                apiKey = KeyringStorage.keyringData.apiKeys["openai"] || ""
            }
            if (apiKey) {
                cmd.push("--api-key=" + apiKey)
            }
        }

        // Optional system prompt
        var systemPrompt = Config.options.dictation.voiceSystemPrompt || ""
        if (systemPrompt) {
            cmd.push("--system-prompt=" + systemPrompt)
        }

        // Optional context from active chat session
        var contextPath = _writeSessionContext()
        if (contextPath) {
            cmd.push("--context=" + contextPath)
        }

        helperProcess.stdinEnabled = true
        helperProcess.command = cmd
        helperProcess.running = true

        // Start connection timeout
        connectionTimeoutTimer.restart()
    }

    /**
     * Writes active session context to a temp JSON file for the helper.
     * Returns the file path, or empty string if no context available.
     */
    function _writeSessionContext(): string {
        // Delegate to Ai service for session context if available
        // For now, return empty — context injection is extended in task 9
        return ""
    }

    // ─── Deactivate ──────────────────────────────────────────────────────

    /**
     * Deactivates the voice agent session.
     * Sends STOP to helper stdin, closes FIFO, kills processes, transitions to Idle.
     */
    function deactivate() {
        console.log("[VoiceAgentService] deactivate() called | state=" + root._stateNames[root.voiceAgentState])

        // Send STOP to helper if it's running
        if (helperProcess.running) {
            var stopEvent = JSON.stringify({"type": "STOP"})
            helperProcess.write(stopEvent + "\n")
        }

        // Stop all timers
        connectionTimeoutTimer.stop()
        errorDismissTimer.stop()

        // Kill processes
        captureProcess.running = false
        helperProcess.running = false
        playbackProcess.running = false

        // Clean up FIFO
        _cleanupFifo()

        // Reset state
        root.partialText = ""
        root.responseText = ""
        root.currentToolName = ""
        root.audioLevel = 0.0
        root.credentialError = ""
        root.errorMessage = ""

        _setState(VoiceAgentService.State.Idle, "deactivate()")
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

        // Kill playback
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
     * Sends a TOOL_RESULT event to the helper stdin and transitions back
     * to the previous state (before ToolExecuting).
     */
    function sendToolResult(name, result, isError) {
        if (!helperProcess.running) return

        var event = JSON.stringify({
            "type": "TOOL_RESULT",
            "name": name,
            "result": result,
            "is_error": isError || false
        })
        helperProcess.write(event + "\n")

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
        root.responseText = event.text || ""

        if (root.voiceAgentState === VoiceAgentService.State.Speaking ||
            root.voiceAgentState === VoiceAgentService.State.Thinking) {
            _setState(VoiceAgentService.State.Listening, "TURN_COMPLETE")
        }
    }

    function _onAudioResponse(event) {
        if (root.voiceAgentState === VoiceAgentService.State.Thinking ||
            root.voiceAgentState === VoiceAgentService.State.Listening) {
            _setState(VoiceAgentService.State.Speaking, "AUDIO_RESPONSE")
        }

        // Decode base64 audio and pipe to pw-play
        var audioData = event.audio || ""
        if (audioData && playbackProcess.running) {
            // Write raw decoded base64 to pw-play stdin
            // The helper sends base64-encoded PCM; we decode and write
            playbackDecodeProcess.command = ["bash", "-c",
                "echo '" + audioData + "' | base64 -d"
            ]
            playbackDecodeProcess.running = true
        } else if (audioData && !playbackProcess.running) {
            // Start pw-play if not running yet
            _startPlayback()
            // Queue the audio — will be handled on next event after pw-play starts
            root._pendingAudio = audioData
        }

        // Update response text if provided
        if (event.text) {
            root.responseText = event.text
        }
    }

    property string _pendingAudio: ""

    function _startPlayback() {
        var rate = root._sampleRate
        playbackProcess.command = [
            "pw-play", "--format=s16",
            "--rate=" + rate, "--channels=1",
            "-"
        ]
        playbackProcess.stdinEnabled = true
        playbackProcess.running = true
    }

    function _onToolCall(event) {
        root._previousState = root.voiceAgentState
        root.currentToolName = event.name || ""
        _setState(VoiceAgentService.State.ToolExecuting, "TOOL_CALL: " + root.currentToolName)
        root.toolCallReceived(event.name || "", JSON.stringify(event.arguments || {}))
    }

    function _onSessionEnd(event) {
        console.log("[VoiceAgentService] SESSION_END received")
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
            // Auto-dismiss after 5s
            errorDismissTimer.restart()
        } else {
            // Non-fatal error — log but continue
            console.warn("[VoiceAgentService] Non-fatal error: " + message)
        }
    }

    function _onFallback(event) {
        var reason = event.reason || "connection failed"
        console.warn("[VoiceAgentService] FALLBACK: " + reason + " — delegating to batch pipeline")

        // Kill our processes
        captureProcess.running = false
        helperProcess.running = false
        playbackProcess.running = false
        connectionTimeoutTimer.stop()
        _cleanupFifo()

        _setState(VoiceAgentService.State.Idle, "FALLBACK → batch")

        // Delegate to DictationService batch pipeline (Requirement 10.1)
        DictationService.activate()
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

    // ─── Audio Capture Process (pw-cat → FIFO) ──────────────────────────

    Process {
        id: captureProcess

        onExited: (exitCode, exitStatus) => {
            if (root.voiceAgentState !== VoiceAgentService.State.Idle) {
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
                console.warn("[VoiceAgentService] helper stderr: " + data.trim())
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (root.voiceAgentState !== VoiceAgentService.State.Idle) {
                console.warn("[VoiceAgentService] Helper exited unexpectedly (exit " + exitCode + ")")
                // Requirement 2.6: transition to Error with exit reason
                captureProcess.running = false
                playbackProcess.running = false
                connectionTimeoutTimer.stop()
                root._cleanupFifo()

                root.errorMessage = "Voice agent helper exited (code " + exitCode + ")"
                root._setState(VoiceAgentService.State.Error, "helper exit " + exitCode)
                errorDismissTimer.restart()
            }
        }
    }

    // ─── Playback Process (pw-play) ─────────────────────────────────────

    Process {
        id: playbackProcess
        stdinEnabled: true

        onRunningChanged: {
            if (playbackProcess.running) {
                // If there's pending audio from before playback started, write it now
                if (root._pendingAudio) {
                    playbackDecodeForPipe.command = ["bash", "-c",
                        "echo '" + root._pendingAudio + "' | base64 -d"
                    ]
                    root._pendingAudio = ""
                    playbackDecodeForPipe.running = true
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            // pw-play exiting during Speaking is normal (audio finished)
            if (root.voiceAgentState === VoiceAgentService.State.Speaking) {
                // Playback finished naturally — stay in Speaking until TURN_COMPLETE
                console.log("[VoiceAgentService] pw-play finished (exit " + exitCode + ")")
            }
        }
    }

    // ─── Audio decode helper processes ───────────────────────────────────

    // Decodes base64 audio and writes to pw-play stdin
    Process {
        id: playbackDecodeProcess

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                if (playbackProcess.running) {
                    playbackProcess.write(data)
                }
            }
        }
    }

    // Decodes pending audio when pw-play first starts
    Process {
        id: playbackDecodeForPipe

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                if (playbackProcess.running) {
                    playbackProcess.write(data)
                }
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
                console.warn("[VoiceAgentService] Connection timeout (5s) — falling back to batch")
                // Kill helper and capture
                helperProcess.running = false
                captureProcess.running = false
                playbackProcess.running = false
                root._cleanupFifo()

                root._setState(VoiceAgentService.State.Idle, "connection timeout → fallback")

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
}
