pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Singleton {
    id: root

    // State enum
    enum State {
        Idle,
        Listening,
        StreamingActive,
        Processing,
        Error
    }

    // Public properties
    property int state: DictationService.State.Idle
    property int recordingDuration: 0  // in milliseconds
    property string errorMessage: ""
    property string transcriptionMode: "batch"  // "streaming" | "chunked" | "batch"
    property string partialText: ""             // Live transcription text (streaming/chunked)

    // Config shortcuts
    property bool enabled: Config.options.dictation.enabled
    property int doubleTapMs: Config.options.dictation.doubleTapMs
    property int silenceTimeoutMs: Config.options.dictation.silenceTimeoutMs
    property int maxDurationMs: Config.options.dictation.maxDurationMs
    property string provider: Config.options.dictation.provider
    property string model: Config.options.dictation.model
    property string streamingEndpoint: Config.options.dictation.streamingEndpoint || ""
    property int chunkDurationMs: Config.options.dictation.chunkDurationMs || 3000

    // Recording file path
    property string _recordingPath: ""

    // API key for remote transcription providers (populated by task 7.2 via KeyringStorage)
    property string _apiKey: ""

    // Signals
    signal activated()
    signal transcriptionComplete(string text)
    signal error(string message)

    // Double-tap detection
    property bool _waitingForSecondTap: false

    Timer {
        id: doubleTapTimer
        interval: root.doubleTapMs
        repeat: false
        onTriggered: {
            // First tap expired without second tap — reset
            root._waitingForSecondTap = false
        }
    }

    // GlobalShortcut that receives the Control_R release event from Hyprland
    GlobalShortcut {
        name: "dictationTap"
        description: "Dictation double-tap detection (Control_R release)"

        onPressed: {
            root.onKeyTap()
        }
    }

    // Audio recording process (pw-record)
    Process {
        id: recordProcess
        command: ["pw-record", "--target=@DEFAULT_SOURCE@", root._recordingPath]
        onExited: (exitCode, exitStatus) => {
            // Recording stopped (either by us or by error)
            if (root.state === DictationService.State.Listening) {
                // Unexpected stop — transition to processing anyway
                root.state = DictationService.State.Processing
                root.startTranscription()
            }
        }
    }

    // Transcription process (curl for API, whisper-cpp for local)
    Process {
        id: transcribeProcess
        // Command is set dynamically in startTranscription()
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.errorMessage = "Transcription failed (exit code: " + exitCode + ")"
                root.state = DictationService.State.Error
                root.error(root.errorMessage)
                return
            }
        }

        stdout: SplitParser {
            splitMarker: ""  // Read all stdout at once (on process exit)
            onRead: data => {
                root._handleTranscriptionResult(data)
            }
        }
    }

    // Streaming/chunked pipeline process (pw-cat piped to dictation-stream.py)
    Process {
        id: streamProcess
        // Command is set dynamically in _startStreamingProcess()
        onExited: (exitCode, exitStatus) => {
            if (root.state === DictationService.State.StreamingActive) {
                // Unexpected exit while streaming — transition to processing
                root.state = DictationService.State.Processing
            }
        }

        stdout: SplitParser {
            onRead: data => {
                root._handleStreamMessage(data.trim())
            }
        }
    }

    // Duration counter — updates every 100ms while recording
    Timer {
        id: durationTimer
        interval: 100
        repeat: true
        running: root.state === DictationService.State.Listening || root.state === DictationService.State.StreamingActive
        onTriggered: {
            root.recordingDuration += 100
        }
    }

    // Maximum recording duration safety limit
    Timer {
        id: maxTimer
        interval: root.maxDurationMs
        repeat: false
        running: root.state === DictationService.State.Listening || root.state === DictationService.State.StreamingActive
        onTriggered: {
            root.stopRecording()
        }
    }

    // Silence timeout — stops recording after configured silence duration.
    // Reset by silenceMonitor when audio activity (RMS > threshold) is detected.
    Timer {
        id: silenceTimer
        interval: root.silenceTimeoutMs
        repeat: false
        running: root.state === DictationService.State.Listening
        onTriggered: {
            root.stopRecording()
        }
    }

    // Silence detection monitor — periodically samples 1s of audio from the default
    // source and prints "AUDIO" or "SILENCE" based on RMS level. Resets silenceTimer
    // whenever speech activity is detected.
    Process {
        id: silenceMonitor
        command: ["sh", "-c",
            "while true; do " +
            "pw-cat --record --target=@DEFAULT_SOURCE@ --format=s16 --rate=16000 --channels=1 - 2>/dev/null | " +
            "head -c 32000 | " +
            "od -A none -v -t d2 | " +
            "awk '{for(i=1;i<=NF;i++){s+=$i*$i;n++}} END{if(n>0){rms=sqrt(s/n); if(rms>500) print \"AUDIO\"; else print \"SILENCE\"}}'; " +
            "done"
        ]
        running: root.state === DictationService.State.Listening

        stdout: SplitParser {
            onRead: data => {
                if (data.trim() === "AUDIO") {
                    root.resetSilenceTimer()
                }
            }
        }
    }

    // Reset silence timer — called when audio activity is detected by silenceMonitor.
    // Can also be called externally if other components detect user activity.
    function resetSilenceTimer() {
        if (root.state === DictationService.State.Listening) {
            silenceTimer.restart()
        }
    }

    // Called when Control_R is released (from GlobalShortcut dictationTap)
    function onKeyTap() {
        if (root.state === DictationService.State.Listening || root.state === DictationService.State.StreamingActive) {
            // Already recording — tap stops recording
            stopRecording()
            return
        }

        if (root._waitingForSecondTap) {
            // Second tap within threshold — activate!
            root._waitingForSecondTap = false
            doubleTapTimer.stop()
            activate()
        } else {
            // First tap — start waiting for second
            root._waitingForSecondTap = true
            doubleTapTimer.restart()
        }
    }

    function detectCapability(provider, streamingEndpoint) {
        // Explicit streaming endpoint configured → streaming
        if (streamingEndpoint) return "streaming"

        // OpenAI Whisper is batch-only (HTTP POST), not the Realtime API
        if (provider === "openai") return "batch"

        // Known local providers — attempt streaming (fallback handled by helper)
        var knownLocalProviders = ["whisper-cpp", "faster-whisper", "local-whisper"]
        if (knownLocalProviders.indexOf(provider) !== -1) {
            return "streaming"
        }

        // Unknown provider → batch
        return "batch"
    }

    function _startStreamingProcess(mode) {
        // Resolve endpoint
        var endpoint = root.streamingEndpoint
        if (!endpoint) {
            if (root.provider === "openai") {
                endpoint = "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview"
            } else {
                endpoint = "ws://localhost:8765"
            }
        }

        // Get API key
        var apiKey = ""
        if (KeyringStorage.keyringData && KeyringStorage.keyringData.apiKeys) {
            apiKey = KeyringStorage.keyringData.apiKeys[root.provider] || ""
        }

        // Build the piped command
        var helperPath = Quickshell.shellPath("ii/scripts/dictation-stream.py")
        var cmd = "pw-cat --record --target=@DEFAULT_SOURCE@ --format=s16 --rate=16000 --channels=1 - | " +
                  "python3 " + helperPath +
                  " --mode=" + mode +
                  " --endpoint=" + endpoint +
                  " --provider=" + root.provider +
                  " --chunk-duration=" + root.chunkDurationMs +
                  " --policy-ai=" + Config.options.policies.ai

        if (apiKey) {
            cmd += " --api-key=" + apiKey
        }

        streamProcess.command = ["sh", "-c", cmd]
        streamProcess.running = true
    }

    function activate() {
        // Policy gate: AI completely disabled
        if (Config.options.policies.ai === 0) {
            root.errorMessage = "Dictation disabled: AI is turned off in policies"
            root.state = DictationService.State.Error
            root.error(root.errorMessage)
            return
        }

        // Config gate: dictation disabled
        if (!root.enabled) {
            return  // Silently ignore — feature is simply off
        }

        // Provider gate: no transcription provider configured
        if (!root.provider) {
            root.errorMessage = "No transcription provider configured. Set dictation.provider in config."
            root.state = DictationService.State.Error
            root.error(root.errorMessage)
            return
        }

        // Policy gate: local-only mode with remote provider
        if (Config.options.policies.ai === 2) {
            var knownLocalProviders = ["whisper-cpp", "faster-whisper", "local-whisper"]
            if (knownLocalProviders.indexOf(root.provider) === -1) {
                root.errorMessage = "Online transcription disallowed by policy. Configure a local provider."
                root.state = DictationService.State.Error
                root.error(root.errorMessage)
                return
            }
        }

        // All checks passed — activate recording
        root.recordingDuration = 0
        root.errorMessage = ""

        // Detect transcription mode capability
        var mode = detectCapability(root.provider, root.streamingEndpoint)
        root.transcriptionMode = mode

        if (mode === "batch") {
            // Existing batch flow — unchanged
            // Ensure temp directory exists
            Quickshell.execDetached(["mkdir", "-p", "/tmp/quickshell-dictation"])
            root._recordingPath = "/tmp/quickshell-dictation/" + Date.now() + ".wav"
            recordProcess.running = true
            root.state = DictationService.State.Listening
            root.activated()
        } else {
            // Streaming or chunked mode — launch piped process
            root.partialText = ""
            root.state = DictationService.State.StreamingActive
            root.activated()
            _startStreamingProcess(mode)
        }
    }

    function stopRecording() {
        if (root.state === DictationService.State.StreamingActive) {
            // Streaming/chunked mode: stop the piped process
            // This sends SIGTERM to the shell, which closes pw-cat's output,
            // sending EOF to the helper's stdin, triggering finalization
            streamProcess.running = false
            root.state = DictationService.State.Processing
            // The FINAL message handler will complete the flow
            return
        }

        if (root.state !== DictationService.State.Listening) return

        // Batch mode: existing behavior
        recordProcess.running = false

        // Transition to processing — timers auto-stop via their running bindings
        root.state = DictationService.State.Processing

        // Begin transcription
        startTranscription()
    }

    function startTranscription() {
        var knownLocalProviders = ["whisper-cpp", "faster-whisper", "local-whisper"]

        if (knownLocalProviders.indexOf(root.provider) !== -1 && !root.streamingEndpoint) {
            // Local whisper — run CLI directly (only if no custom endpoint)
            transcribeProcess.command = ["whisper-cpp", "-f", root._recordingPath, "--output-txt", "--model", root.model || "base.en"]
        } else {
            // Remote or local-with-endpoint: use HTTP API
            var apiKey = ""
            if (KeyringStorage.keyringData && KeyringStorage.keyringData.apiKeys) {
                apiKey = KeyringStorage.keyringData.apiKeys[root.provider] || ""
            }

            // For known local providers with an endpoint, key is optional
            if (!apiKey && knownLocalProviders.indexOf(root.provider) === -1) {
                root.errorMessage = "No API key found for provider '" + root.provider + "'. Add it in the Providers panel."
                root.state = DictationService.State.Error
                root.error(root.errorMessage)
                return
            }

            root._apiKey = apiKey || ""

            // Resolve endpoint — use streamingEndpoint if set, else default per provider
            var endpoint = root.streamingEndpoint || ""
            if (!endpoint) {
                if (root.provider === "openai") {
                    endpoint = "https://api.openai.com"
                } else {
                    endpoint = "http://localhost:8080"
                }
            }
            // Ensure endpoint doesn't end with /v1/audio/transcriptions already
            var transcriptionUrl = endpoint.replace(/\/+$/, "")
            if (!transcriptionUrl.endsWith("/v1/audio/transcriptions")) {
                transcriptionUrl += "/v1/audio/transcriptions"
            }

            var modelName = root.model || "whisper-1"
            var curlCmd = ["curl", "-s",
                "-F", "file=@" + root._recordingPath,
                "-F", "model=" + modelName
            ]
            if (root._apiKey) {
                curlCmd.push("-H")
                curlCmd.push("Authorization: Bearer " + root._apiKey)
            }
            curlCmd.push(transcriptionUrl)
            transcribeProcess.command = curlCmd
        }

        transcribeProcess.running = true
    }

    function _handleTranscriptionResult(data) {
        var text = ""
        var knownLocalProviders = ["whisper-cpp", "faster-whisper", "local-whisper"]

        if (knownLocalProviders.indexOf(root.provider) !== -1) {
            // Local whisper outputs text directly
            text = data.trim()
        } else {
            // OpenAI API returns JSON: {"text": "..."}
            try {
                var response = JSON.parse(data)
                text = response.text || ""
            } catch (e) {
                root.errorMessage = "Failed to parse transcription response"
                root.state = DictationService.State.Error
                root.error(root.errorMessage)
                return
            }
        }

        if (!text) {
            root.errorMessage = "Transcription returned empty text"
            root.state = DictationService.State.Error
            root.error(root.errorMessage)
            return
        }

        // Success — put text in input field for review/edit before sending
        root.transcriptionComplete(text)

        // Clean up temp audio file
        Quickshell.execDetached(["rm", "-f", root._recordingPath])

        // Return to idle
        root.state = DictationService.State.Idle
    }

    function _handleStreamMessage(line) {
        // Protocol format: TAG:payload
        var colonIdx = line.indexOf(":")
        if (colonIdx === -1) return

        var tag = line.substring(0, colonIdx)
        var payload = line.substring(colonIdx + 1)

        switch (tag) {
            case "READY":
                // Confirm actual mode (may differ if fallback happened in helper)
                root.transcriptionMode = payload
                console.log("[DictationService] Stream ready: mode=" + payload)
                break

            case "PARTIAL":
                root.partialText = payload
                break

            case "FINAL":
                root.partialText = payload
                // Stop the stream process
                streamProcess.running = false
                // Route the final text
                root._handleFinalStreamResult(payload)
                break

            case "ERROR":
                root.errorMessage = payload
                root.state = DictationService.State.Error
                root.error(payload)
                streamProcess.running = false
                break

            case "FALLBACK":
                // Fall back to batch mode mid-session
                console.warn("[DictationService] Streaming fallback: " + payload)
                root._fallbackToBatch()
                break
        }
    }

    function _handleFinalStreamResult(text) {
        if (!text) {
            root.errorMessage = "Streaming transcription returned empty text"
            root.state = DictationService.State.Error
            root.error(root.errorMessage)
            return
        }

        // Success — put text in input field for review/edit before sending
        root.transcriptionComplete(text)

        // Clean up — no temp files in streaming mode
        root.partialText = ""
        root.state = DictationService.State.Idle
    }

    function _fallbackToBatch() {
        // Stop streaming process
        streamProcess.running = false
        root.partialText = ""
        root.transcriptionMode = "batch"

        // Start batch recording
        Quickshell.execDetached(["mkdir", "-p", "/tmp/quickshell-dictation"])
        root._recordingPath = "/tmp/quickshell-dictation/" + Date.now() + ".wav"
        recordProcess.running = true
        root.state = DictationService.State.Listening
    }
}
