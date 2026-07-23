pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions as CF
import qs.services

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
    property int debounceMs: Config.options.dictation.debounceMs

    // Recording file path
    property string _recordingPath: ""

    // API key for remote transcription providers (populated by task 7.2 via KeyringStorage)
    property string _apiKey: ""

    // Debounce guard state
    property bool _debounceActive: false

    // STT fallback chain index: 0 = configured endpoint, 1 = localhost, 2 = OpenAI API
    property int _fallbackIndex: 0

    // Signals
    signal activated()
    signal transcriptionComplete(string text)
    signal error(string message)

    // Intent classification constants
    readonly property var _commandVerbs: [
        "open", "close", "launch", "set", "change", "toggle", "switch",
        "move", "kill", "run", "show", "hide", "play", "pause", "stop",
        "mute", "unmute", "find", "search", "check", "tell", "give", "list",
        "maximize", "minimize", "resize", "start", "increase", "decrease", "adjust"
    ]
    readonly property var _questionWords: [
        "what", "how", "when", "where", "who", "which",
        "why", "can", "could", "would", "should",
        "is", "are", "do", "does", "did", "will"
    ]

    // Voice assistant response text — Floating Indicator binds to this
    property string responseText: ""

    onResponseTextChanged: {
        // Auto-start dismiss timer when responseText is set externally (e.g. from postResponseHook)
        if (responseText.length > 0 && !responsePinned && !TtsService.playing) {
            responseDismissTimer.interval = _calculateDismissInterval(responseText)
            responseDismissTimer.restart()
        } else if (responseText.length === 0) {
            responseDismissTimer.stop()
        }
    }

    // Whether the response popup is pinned (won't auto-dismiss)
    property bool responsePinned: false

    // Toggle pin state. If pinning, stop dismiss timer. If unpinning, restart it.
    function toggleResponsePin() {
        responsePinned = !responsePinned
        if (responsePinned) {
            responseDismissTimer.stop()
        } else if (responseText !== "") {
            responseDismissTimer.interval = _calculateDismissInterval(responseText)
            responseDismissTimer.restart()
        }
    }

    // Calculate dismiss interval: 10s base + 50ms per character, capped at 60s
    function _calculateDismissInterval(text) {
        var base = 10000
        var perChar = 50
        var calculated = base + (text.length * perChar)
        return Math.min(calculated, 60000)
    }

    // Manually dismiss the voice response indicator, stopping any active dismiss timers.
    // Called by click-to-copy in DictationIndicator.
    function dismissResponse() {
        responseText = ""
        responsePinned = false
        responseClearTimer.stop()
        errorDismissTimer.stop()
        responseDismissTimer.stop()
    }

    // Shell.exec approval state — Floating Indicator shows approve/reject UI when true
    property bool awaitingApproval: false
    property string approvalCommand: ""
    property int approvalActionIndex: -1

    // Voice assistant system prompt — passed as extraSystemPrompt to submitQueryDirect
    // Verbosity scales based on Config.options.dictation.verbosity setting
    readonly property string _voiceAssistantPrompt: {
        var verbosity = Config.options.dictation.verbosity || "concise";

        var verbosityRules = "";
        if (verbosity === "concise") {
            verbosityRules =
                "VERBOSITY: CONCISE (user preference)\n" +
                "- ONE short sentence for most answers. Example: \"You have 450GB free of 1TB.\"\n" +
                "- For status queries: give the KEY number only. Filter out all noise.\n" +
                "- Maximum 2 sentences even for complex questions.\n";
        } else if (verbosity === "normal") {
            verbosityRules =
                "VERBOSITY: NORMAL (user preference)\n" +
                "- 1-3 sentences depending on complexity.\n" +
                "- For simple lookups: one sentence. For status queries: the key info plus one line of context.\n" +
                "- For complex questions: up to 3 sentences with enough detail to be useful.\n";
        } else {
            verbosityRules =
                "VERBOSITY: DETAILED (user preference)\n" +
                "- Give thorough answers — a short paragraph when appropriate.\n" +
                "- For status queries: include the main drive plus any notable secondary drives.\n" +
                "- For complex questions: explain fully but still in spoken conversational language.\n" +
                "- Still NO raw command output. Summarize into human-readable form.\n";
        }

        return "You are answering a voice query. Your response will be displayed as a brief notification and optionally spoken aloud via TTS.\n\n" +
            verbosityRules + "\n" +
            "RULES:\n" +
            "- NEVER dump raw command output. Summarize it into human-readable form.\n" +
            "- NEVER explain your reasoning or methodology. Just give the answer.\n" +
            "- For disk/system queries: filter out virtual filesystems, tmpfs, snap mounts, duplicates.\n" +
            "- Report only what the user cares about.\n\n" +
            "STYLE: Contractions, informal units (gigs not gigabytes), spoken language. No markdown, no tables, no bullet points, no code blocks.";
    }

    // Structured state transition logging helper
    function _logTransition(from, to, context) {
        var stateNames = ["Idle", "Listening", "StreamingActive", "Processing", "Error"]
        var fromName = stateNames[from] || String(from)
        var toName = stateNames[to] || String(to)
        console.log("[DictationService] STATE: " + fromName + " → " + toName + " | " + (context || ""))
    }

    function _setState(newState, context) {
        var oldState = root.state
        root.state = newState
        _logTransition(oldState, newState, context)
        // Reset debounce guard when returning to Idle (Requirement 4.5)
        if (newState === DictationService.State.Idle) {
            root._debounceActive = false
            debounceTimer.stop()
        }
    }

    // Intent classification: returns "command" | "dictation" | "ambiguous"
    // Heuristic mode: imperative verb prefix → "command", question patterns → "dictation",
    // everything else → "ambiguous".
    // When intentMode is "ai" and the text is ambiguous, _classifyIntentAi can be called
    // for async LLM classification with a 5-second timeout fallback.
    function _classifyIntent(text) {
        if (!text || text.trim().length === 0) return "ambiguous"

        var trimmed = text.trim()
        var lowerTrimmed = trimmed.toLowerCase()
        var firstWord = lowerTrimmed.split(" ")[0]

        // Imperative verb prefixes → "command"
        if (_commandVerbs.indexOf(firstWord) !== -1) return "command"

        // Question patterns → "dictation"
        if (_questionWords.indexOf(firstWord) !== -1) return "dictation"

        // Contains question mark → "dictation"
        if (trimmed.indexOf("?") !== -1) return "dictation"

        // Long text (>20 words) without heuristic match → "dictation"
        var words = trimmed.split(/\s+/)
        if (words.length > 20) return "dictation"

        // Ambiguous short text: if AI mode, return "ambiguous" for async classification
        if (Config.options.dictation.intentMode === "ai") return "ambiguous"

        // Default heuristic fallback → "ambiguous"
        return "ambiguous"
    }

    // AI-based intent classification for ambiguous cases.
    // Sends a lightweight LLM request to classify text as "command" or "dictation".
    // Uses the current model from Ai.qml with a 2-second timeout.
    // Calls callback(result) with "command" or "dictation" when done.
    property var _aiClassifyCallback: null
    property string _aiClassifyBuffer: ""

    function _classifyIntentAi(text, callback) {
        root._aiClassifyCallback = callback
        root._aiClassifyBuffer = ""

        var model = Ai.models[Ai.currentModelId]
        if (!model) {
            console.warn("[DictationService] AI intent: no model available, defaulting to command")
            callback("command")
            return
        }

        // Policy: local-only mode — verify LLM endpoint is local before making the call
        if (Config.options.policies.ai === 2) {
            var endpoint = model.endpoint || ""
            var isLocal = endpoint.startsWith("http://localhost") ||
                          endpoint.startsWith("http://127.0.0.1") ||
                          endpoint.startsWith("http://10.") ||
                          endpoint.startsWith("http://192.168.")
            if (!isLocal) {
                console.warn("[DictationService] AI intent: policy requires local-only, endpoint '" + endpoint + "' is not local. Defaulting to command.")
                callback("command")
                return
            }
        }

        // Build the classification prompt
        var classifyPrompt = "Classify this as 'command' or 'dictation'. Reply with one word only: " + text

        // Get API key
        var apiKey = ""
        if (model.requires_key && Ai.apiKeys) {
            apiKey = Ai.apiKeys[model.key_id] || ""
        }

        // Set API key in environment for curl
        if (apiKey) {
            aiClassifyProcess.environment["API_KEY"] = apiKey
        }

        // Build request based on API format
        var endpoint = ""
        var data = {}
        var authHeader = ""

        if (model.api_format === "gemini") {
            // Gemini: key in URL, generateContent (non-streaming)
            endpoint = model.endpoint.replace(":streamGenerateContent", ":generateContent")
                + "?key=${API_KEY}"
            data = {
                "contents": [{ "role": "user", "parts": [{ "text": classifyPrompt }] }],
                "generationConfig": { "temperature": 0, "maxOutputTokens": 10 }
            }
            authHeader = ""
        } else {
            // OpenAI-compatible (openai, mistral, ollama, etc): non-streaming completions
            endpoint = model.endpoint
            data = {
                "model": model.model,
                "messages": [
                    { "role": "user", "content": classifyPrompt }
                ],
                "stream": false,
                "temperature": 0,
                "max_tokens": 10
            }
            authHeader = '-H "Authorization: Bearer ${API_KEY}"'
        }

        var curlCmd = 'curl -s --max-time 2 "' + endpoint + '"'
            + " -H 'Content-Type: application/json'"
            + (authHeader ? " " + authHeader : "")
            + " -d '" + CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data)) + "'"

        aiClassifyProcess.command = ["bash", "-c", curlCmd]
        aiClassifyTimeoutTimer.restart()
        aiClassifyProcess.running = true
    }

    // Process for AI intent classification (lightweight, non-streaming)
    Process {
        id: aiClassifyProcess

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                root._aiClassifyBuffer += data
            }
        }

        onExited: (exitCode, exitStatus) => {
            aiClassifyTimeoutTimer.stop()

            if (exitCode !== 0 || !root._aiClassifyCallback) {
                console.warn("[DictationService] AI intent classification failed (exit: " + exitCode + "), defaulting to command")
                if (root._aiClassifyCallback) {
                    var cb = root._aiClassifyCallback
                    root._aiClassifyCallback = null
                    cb("command")
                }
                return
            }

            // Parse response
            var result = "command" // default on any parse failure
            try {
                var response = JSON.parse(root._aiClassifyBuffer)
                var responseText = ""

                // Handle Gemini format
                if (response.candidates) {
                    responseText = response.candidates[0]?.content?.parts[0]?.text || ""
                }
                // Handle OpenAI format
                else if (response.choices) {
                    responseText = response.choices[0]?.message?.content || ""
                }

                responseText = responseText.trim().toLowerCase()
                if (responseText === "dictation") {
                    result = "dictation"
                }
                // Any other response (including "command") → command
            } catch (e) {
                console.warn("[DictationService] AI intent: failed to parse response, defaulting to command")
            }

            var cb = root._aiClassifyCallback
            root._aiClassifyCallback = null
            cb(result)
        }
    }

    // Whether a voice assistant request is currently in-flight (waiting for ActionPalette response)
    property bool _voiceAssistantPending: false

    // Timer to auto-clear responseText after showing "Captured" confirmation (2s)
    Timer {
        id: responseClearTimer
        interval: 2000
        repeat: false
        onTriggered: {
            root.responseText = ""
        }
    }

    // Timer to auto-clear responseText after an error or response display (3s)
    Timer {
        id: errorDismissTimer
        interval: 3000
        repeat: false
        onTriggered: {
            root.responseText = ""
            // Always reset to Idle so the service can be activated again
            if (root.state === DictationService.State.Error) {
                root._setState(DictationService.State.Idle, "error dismiss timer")
            }
        }
    }

    // 15-second timeout for voice assistant LLM requests.
    // Fires when a voice assistant request is pending and no response has come back.
    Timer {
        id: voiceAssistantTimeoutTimer
        interval: 35000
        repeat: false
        onTriggered: {
            if (root._voiceAssistantPending) {
                root._voiceAssistantPending = false
                root.responseText = "Request timed out"
                Ai.appendToFreeDictation("Error: Request timed out", "assistant")
                errorDismissTimer.restart()
                console.warn("[DictationService] Voice assistant request timed out (15s)")
            }
        }
    }

    // Connect to ActionPalette approval signal for shell.exec commands
    Connections {
        target: ActionPalette

        function onApprovalRequired(command, actionIndex) {
            if (!root._voiceAssistantPending) return
            root.awaitingApproval = true
            root.approvalCommand = command
            root.approvalActionIndex = actionIndex
        }

        function onExecutionComplete() {
            // Clear approval state when execution finishes (safe actions auto-completed)
            root.awaitingApproval = false
            root.approvalCommand = ""
            root.approvalActionIndex = -1
        }
    }

    // Connect to ActionPalette signals for voice assistant response handling
    Connections {
        target: ActionPalette

        function onResponseSummary(text) {
            if (!root._voiceAssistantPending) return
            root._voiceAssistantPending = false
            voiceAssistantTimeoutTimer.stop()

            // Clear any pending approval state
            root.awaitingApproval = false
            root.approvalCommand = ""
            root.approvalActionIndex = -1

            root.responseText = text
            root.responsePinned = false
            Ai.appendToFreeDictation(text, "assistant")

            // Talkback: speak the response if enabled
            if (Config.options.dictation.talkback) {
                TtsService.speak(text)
                // Don't start dismiss timer — indicator stays until TTS finishes
            } else {
                // No TTS — start auto-dismiss timer (10s base + scales with length)
                responseDismissTimer.interval = root._calculateDismissInterval(text)
                responseDismissTimer.restart()
            }
        }

        function onExecutionFailed(actionType, index, reason) {
            if (!root._voiceAssistantPending) return
            root._voiceAssistantPending = false
            voiceAssistantTimeoutTimer.stop()

            // Clear any pending approval state
            root.awaitingApproval = false
            root.approvalCommand = ""
            root.approvalActionIndex = -1

            var errorMsg = "Action failed: " + reason
            root.responseText = errorMsg
            Ai.appendToFreeDictation("Error: " + errorMsg, "assistant")
            errorDismissTimer.restart()
            console.warn("[DictationService] ActionPalette execution failed: " + reason)
        }
    }

    // Timer to auto-dismiss voice assistant response text.
    // Base interval is 10s, scaled dynamically with response length (set before restart).
    // Only starts when TTS is NOT playing; if talkback is on, the indicator
    // stays visible until TTS finishes (see Connections on TtsService below).
    Timer {
        id: responseDismissTimer
        interval: 10000
        repeat: false
        onTriggered: {
            if (!root.responsePinned) {
                root.responseText = ""
            }
        }
    }

    // When TTS finishes playing, start the dismiss timer for the response indicator
    Connections {
        target: TtsService
        function onPlayingChanged() {
            if (!TtsService.playing && root.responseText !== "") {
                responseDismissTimer.restart()
            }
        }
    }

    // 2-second timeout for AI classification — defaults to "command" on timeout
    Timer {
        id: aiClassifyTimeoutTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (aiClassifyProcess.running) {
                aiClassifyProcess.running = false // kill the process
            }
            if (root._aiClassifyCallback) {
                console.warn("[DictationService] AI intent classification timed out, defaulting to command")
                var cb = root._aiClassifyCallback
                root._aiClassifyCallback = null
                cb("command")
            }
        }
    }

    // Smart routing pipeline — routes dictation text based on intent when sidebar is open.
    // When smartRouting is enabled AND active session is "Free Dictation":
    //   - "command" → route to ActionPalette (skip chat submission)
    //   - "dictation" / "ambiguous" → normal transcriptionComplete for AiChat
    // When smartRouting is disabled or session is not "Free Dictation": normal behavior.
    // Requirements: 8.2, 8.3
    function _smartRoute(text) {
        if (!text || text.trim().length === 0) return

        // If smart routing is disabled or not Free Dictation, emit normally
        if (!Config.options.dictation.smartRouting || Ai.activeSessionName !== "Free Dictation") {
            root.transcriptionComplete(text)
            return
        }

        var intent = root._classifyIntent(text)

        if (intent === "command") {
            // Route to ActionPalette — trivial command, skip chat
            ActionPalette.submitQueryDirect(text)
            return
        }

        if (intent === "ambiguous" && Config.options.dictation.intentMode === "ai") {
            // AI classification for ambiguous text with 5-second timeout fallback
            // On timeout or failure, defaults to normal message send
            _classifyIntentAi(text, function(result) {
                if (result === "command") {
                    ActionPalette.submitQueryDirect(text)
                } else {
                    // "dictation" or fallback → send as normal message
                    root.transcriptionComplete(text)
                }
            })
            return
        }

        // Non-trivial or ambiguous (heuristic mode): send as normal message to Free Dictation
        // AiChat handles auto-submit via transcriptionComplete
        root.transcriptionComplete(text)
    }

    // Voice assistant pipeline — processes transcribed text when sidebar is closed.
    // Classifies intent, logs to Free Dictation, and routes to appropriate handler.
    function _processVoiceAssistant(text) {
        // Policy safety guard: AI completely disabled (already caught in activate(), but belt-and-suspenders)
        if (Config.options.policies.ai === 0) return

        var intent = _classifyIntent(text)

        // Always log user input to Free Dictation session
        Ai.appendToFreeDictation(text, "user")

        // In voice assistant mode (sidebar closed), both "command" and "dictation" (questions)
        // route to ActionPalette — the user is speaking to the AI either way.
        // Only long-form text (classified as "dictation" due to >20 words) gets captured without action.
        var words = text.trim().split(/\s+/)
        if (intent === "dictation" && words.length > 20) {
            // Pure long-form dictation — show brief confirmation, no action execution
            root.responseText = "Captured to Free Dictation"
            responseClearTimer.restart()
            return
        }

        if (intent === "command" || intent === "dictation") {
            // Direct command or question — invoke ActionPalette without opening overview
            root._voiceAssistantPending = true
            voiceAssistantTimeoutTimer.restart()
            ActionPalette.submitQueryDirect(text, root._voiceAssistantPrompt)
            return
        }

        if (intent === "ambiguous") {
            // AI mode — async classification for ambiguous text
            _classifyIntentAi(text, function(result) {
                if (result === "dictation") {
                    root.responseText = "Captured to Free Dictation"
                    responseClearTimer.restart()
                } else {
                    // "command" or any other result → treat as command
                    root._voiceAssistantPending = true
                    voiceAssistantTimeoutTimer.restart()
                    ActionPalette.submitQueryDirect(text, root._voiceAssistantPrompt)
                }
            })
            return
        }
    }

    // Debounce guard timer — suppresses rapid re-activation after initial tap
    Timer {
        id: debounceTimer
        interval: root.debounceMs
        repeat: false
        onTriggered: {
            root._debounceActive = false
        }
    }

    // Double-tap detection
    property bool _waitingForSecondTap: false
    // When true, batch transcription result types at cursor instead of voice assistant
    property bool _dictationToCursor: false

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
            console.log("[DictationService] GlobalShortcut dictationTap RECEIVED | state=" + root.state + " enabled=" + root.enabled + " provider=" + root.provider)
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
                root._setState(DictationService.State.Processing, "recordProcess unexpected exit")
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
                // Extract endpoint from command array for diagnostics
                var endpoint = transcribeProcess.command.length > 0 ? transcribeProcess.command[transcribeProcess.command.length - 1] : "unknown"
                console.warn("[DictationService] TRANSCRIPTION_FAIL | endpoint=" + endpoint + " exit=" + exitCode + " fallbackIndex=" + root._fallbackIndex)

                // Transcription failed — attempt fallback to next endpoint
                if (root._attemptFallbackTranscription(root._recordingPath, root._fallbackIndex + 1)) {
                    return // Fallback in progress
                }
                // All fallbacks exhausted
                root.errorMessage = "Transcription failed: all endpoints unreachable"
                root._setState(DictationService.State.Error, "all transcription endpoints failed")
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

        stderr: SplitParser {
            splitMarker: ""
            onRead: data => {
                console.warn("[DictationService] TRANSCRIPTION_STDERR | " + data.trim())
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
                root._setState(DictationService.State.Processing, "streamProcess unexpected exit")
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
            "awk '{for(i=1;i<=NF;i++){s+=$i*$i;n++}} END{if(n>0){rms=sqrt(s/n); if(rms>250) print \"AUDIO\"; else print \"SILENCE\"}}'; " +
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

    // Rapid-fire guard: ignore taps within 300ms of last processed tap
    // The Logi button sends multiple events per physical press (key down + up both fire the bind)
    property real _lastTapTime: 0

    // Called when dictation trigger fires (keyd dispatch via hyprctl global)
    function onKeyTap() {
        // Rapid-fire guard: ignore events within 100ms of last tap
        // The Logi button fires 2-3 events per physical press (keydown+keyup)
        var now = Date.now()
        if (now - root._lastTapTime < 100) {
            console.log("[DictationService] DEBOUNCE: ignoring rapid tap (" + (now - root._lastTapTime) + "ms)")
            return
        }
        root._lastTapTime = now

        console.log("[DictationService] onKeyTap: state=" + root.state + " _waitingForSecondTap=" + root._waitingForSecondTap)

        // ─── Voice Agent active session handling ─────────────────────
        // If voice agent is already in an active state, handle taps as
        // toggle/barge-in controls — BUT check double-tap first.
        // If we're still in the double-tap window, a second tap means
        // "switch to batch dictation", not "cancel voice agent".
        if (VoiceAgentService.voiceBackend && VoiceAgentService.voiceBackend !== "none") {
            var vasState = VoiceAgentService.voiceAgentState

            // Double-tap override: if waiting for second tap and voice agent
            // is still connecting (from first tap), treat as double-tap → realtime dictation
            if (root._waitingForSecondTap && vasState === VoiceAgentService.State.Connecting) {
                root._waitingForSecondTap = false
                doubleTapTimer.stop()
                console.log("[DictationService] Double-tap detected (during Connecting) → realtime dictation")
                // VoiceAgentService is already connecting — switch to dictation mode
                VoiceAgentService.dictationToCursorMode = true
                return
            }

            if (vasState === VoiceAgentService.State.Speaking) {
                // Tap during playback: barge-in (Requirement 7.5)
                console.log("[DictationService] Routing to VoiceAgentService.bargeIn()")
                VoiceAgentService.bargeIn()
                return
            } else if (vasState === VoiceAgentService.State.Listening) {
                // Tap during listening: commit and deactivate (Requirement 7.4, 2.4)
                console.log("[DictationService] Routing to VoiceAgentService.deactivate() from Listening")
                VoiceAgentService.sendEndTurn()
                VoiceAgentService.deactivate()
                return
            } else if (vasState !== VoiceAgentService.State.Idle) {
                // Tap during Thinking, ToolExecuting, Error: deactivate
                console.log("[DictationService] Routing to VoiceAgentService.deactivate()")
                VoiceAgentService.deactivate()
                return
            }
        }

        // ─── Idle state: double-tap detection ────────────────────────
        // Single tap → batch voice assistant (record, transcribe, execute, show summary)
        // Double tap (second tap within doubleTapMs) → realtime streaming dictation to cursor
        // Single tap gets the fast path since voice commands are the primary use.

        // Double-tap detection — must be checked BEFORE "already recording" logic
        if (root._waitingForSecondTap) {
            // ─── Second tap: cancel batch, activate realtime dictation ───────
            root._waitingForSecondTap = false
            doubleTapTimer.stop()
            console.log("[DictationService] Double-tap detected → realtime dictation to cursor")

            // Cancel the batch recording we just started on the first tap
            if (root.state === DictationService.State.Listening || root.state === DictationService.State.StreamingActive) {
                recordProcess.running = false
                root._setState(DictationService.State.Idle, "double-tap cancel batch")
            }

            // Activate realtime voice agent in dictation-to-cursor mode
            if (VoiceAgentService.voiceBackend && VoiceAgentService.voiceBackend !== "none") {
                VoiceAgentService.dictationToCursorMode = true
                VoiceAgentService.activate()
            }
            return
        }

        // If batch pipeline is already active, tap stops recording
        if (root.state === DictationService.State.Listening || root.state === DictationService.State.StreamingActive) {
            console.log("[DictationService] Already recording, stopping")
            stopRecording()
            return
        }

        // ─── First tap ───────────────────────────────────────────────
        // Activate batch voice assistant immediately
        // Start timer to detect possible double-tap for realtime dictation
        console.log("[DictationService] Single tap → batch voice assistant (waiting " + root.doubleTapMs + "ms for possible double-tap)")
        root._waitingForSecondTap = true
        doubleTapTimer.restart()

        if (root._debounceActive) {
            console.log("[DictationService] GATE_REJECT | reason=debounce")
            return
        }

        if (root.debounceMs > 0) {
            root._debounceActive = true
            debounceTimer.restart()
        }
        activate()
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
        // Force reset from any stuck state (Error, Processing) so activation always works
        if (root.state === DictationService.State.Error || root.state === DictationService.State.Processing) {
            console.log("[DictationService] Resetting from stuck state: " + root.state)
            root._setState(DictationService.State.Idle, "reset stuck state")
        }

        // Stop any in-progress TTS playback before starting a new dictation session
        TtsService.stop()

        console.log("[DictationService] activate() called | state=" + root.state + " enabled=" + root.enabled + " provider=" + root.provider + " policy=" + Config.options.policies.ai)

        // Policy gate: AI completely disabled
        if (Config.options.policies.ai === 0) {
            console.warn("[DictationService] GATE_REJECT | reason=ai_disabled")
            root.errorMessage = "Dictation disabled: AI is turned off in policies"
            root._setState(DictationService.State.Error, "ai disabled by policy")
            root.error(root.errorMessage)
            return
        }

        // Config gate: dictation disabled
        if (!root.enabled) {
            console.warn("[DictationService] GATE_REJECT | reason=not_enabled")
            return  // Silently ignore — feature is simply off
        }

        // Provider gate: no transcription provider configured
        if (!root.provider) {
            console.warn("[DictationService] GATE_REJECT | reason=no_provider")
            root.errorMessage = "No transcription provider configured. Set dictation.provider in config."
            root._setState(DictationService.State.Error, "no provider configured")
            root.error(root.errorMessage)
            return
        }

        // Policy gate: local-only mode with remote provider
        if (Config.options.policies.ai === 2) {
            var knownLocalProviders = ["whisper-cpp", "faster-whisper", "local-whisper"]
            if (knownLocalProviders.indexOf(root.provider) === -1) {
                console.warn("[DictationService] GATE_REJECT | reason=local_only_policy_rejects_remote")
                root.errorMessage = "Online transcription disallowed by policy. Configure a local provider."
                root._setState(DictationService.State.Error, "local-only policy rejects remote provider")
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
            root._setState(DictationService.State.Listening, "activate() batch mode")
            root.activated()
        } else {
            // Streaming or chunked mode — launch piped process
            root.partialText = ""
            root._setState(DictationService.State.StreamingActive, "activate() streaming mode")
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
            root._setState(DictationService.State.Processing, "stopRecording() streaming finalize")
            // The FINAL message handler will complete the flow
            return
        }

        if (root.state !== DictationService.State.Listening) return

        // Batch mode: existing behavior
        recordProcess.running = false

        // Transition to processing — timers auto-stop via their running bindings
        root._setState(DictationService.State.Processing, "stopRecording() batch")

        // Begin transcription
        startTranscription()
    }

    function startTranscription() {
        // Reset fallback chain for a new transcription attempt
        root._fallbackIndex = 0

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
                root._setState(DictationService.State.Error, "no API key for provider")
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
            var curlCmd = ["curl", "-s", "--fail",
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

    // STT fallback chain: attempts the next available endpoint when the current one fails.
    // Returns true if a fallback attempt was started, false if all options are exhausted.
    // Chain: 0 = configured endpoint, 1 = localhost, 2 = OpenAI API (if policy allows)
    function _attemptFallbackTranscription(recordingPath, fallbackIndex) {
        root._fallbackIndex = fallbackIndex

        if (fallbackIndex === 1) {
            // Fallback 1: Try localhost equivalent
            var configuredEndpoint = (root.streamingEndpoint || "").replace(/\/+$/, "")
            if (!configuredEndpoint) {
                if (root.provider === "openai") configuredEndpoint = "https://api.openai.com"
                else configuredEndpoint = "http://localhost:8080"
            }

            // Skip localhost fallback if we're already targeting localhost
            if (configuredEndpoint.indexOf("localhost") !== -1 || configuredEndpoint.indexOf("127.0.0.1") !== -1) {
                // Already localhost — skip to next fallback
                return _attemptFallbackTranscription(recordingPath, 2)
            }

            console.warn("[DictationService] Falling back to localhost STT endpoint")

            var localhostUrl = "http://localhost:8080/v1/audio/transcriptions"
            var modelName = root.model || "whisper-1"
            var curlCmd = ["curl", "-s", "--fail",
                "-F", "file=@" + recordingPath,
                "-F", "model=" + modelName,
                localhostUrl
            ]
            transcribeProcess.command = curlCmd
            transcribeProcess.running = true
            return true
        }

        if (fallbackIndex === 2) {
            // Fallback 2: Try OpenAI API (only if policy allows remote)
            if (Config.options.policies.ai === 2) {
                // Policy is local-only — cannot fall back to OpenAI
                console.warn("[DictationService] Cannot fall back to OpenAI: local-only policy")
                return false
            }

            // Need an OpenAI API key
            var apiKey = ""
            if (KeyringStorage.keyringData && KeyringStorage.keyringData.apiKeys) {
                apiKey = KeyringStorage.keyringData.apiKeys["openai"] || ""
            }
            if (!apiKey) {
                console.warn("[DictationService] Cannot fall back to OpenAI: no API key configured")
                return false
            }

            console.warn("[DictationService] Falling back to OpenAI STT API")

            var openaiUrl = "https://api.openai.com/v1/audio/transcriptions"
            var curlCmd = ["curl", "-s", "--fail",
                "-F", "file=@" + recordingPath,
                "-F", "model=whisper-1",
                "-H", "Authorization: Bearer " + apiKey,
                openaiUrl
            ]
            transcribeProcess.command = curlCmd
            transcribeProcess.running = true
            return true
        }

        // No more fallbacks available
        return false
    }

    function _handleTranscriptionResult(data) {
        var text = ""
        var knownLocalProviders = ["whisper-cpp", "faster-whisper", "local-whisper"]

        // When on a fallback endpoint (index > 0), response is always JSON from curl HTTP API.
        // Only parse as plain text for the original local whisper CLI (index 0, no endpoint).
        if (root._fallbackIndex === 0 && knownLocalProviders.indexOf(root.provider) !== -1 && !root.streamingEndpoint) {
            // Local whisper CLI outputs text directly
            text = data.trim()
        } else {
            // HTTP API (configured, localhost fallback, or OpenAI fallback) returns JSON: {"text": "..."}
            try {
                var response = JSON.parse(data)
                text = response.text || ""
            } catch (e) {
                root.errorMessage = "Failed to parse transcription response"
                root._setState(DictationService.State.Error, "failed to parse transcription response")
                root.error(root.errorMessage)
                return
            }
        }

        if (!text) {
            root.errorMessage = "Transcription returned empty text"
            root._setState(DictationService.State.Error, "transcription returned empty text")
            root.error(root.errorMessage)
            return
        }

        // Double-tap dictation mode: type text at cursor position
        if (root._dictationToCursor) {
            root._dictationToCursor = false
            console.log("[DictationService] Typing at cursor: " + text.substring(0, 50) + "...")
            Quickshell.execDetached(["wtype", "--", text])
            root.transcriptionComplete(text)
            Quickshell.execDetached(["rm", "-f", root._recordingPath])
            root._setState(DictationService.State.Idle, "dictation-to-cursor complete")
            return
        }

        // Route based on sidebar state
        if (GlobalStates.sidebarLeftOpen) {
            // Sidebar open — route through smart routing (checks intent when enabled)
            root._smartRoute(text)
        } else {
            // Sidebar closed — route through voice assistant pipeline
            root._processVoiceAssistant(text)
            root.transcriptionComplete(text)
        }

        // Clean up temp audio file
        Quickshell.execDetached(["rm", "-f", root._recordingPath])

        // Return to idle
        root._setState(DictationService.State.Idle, "transcription complete")
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
                root._setState(DictationService.State.Error, "stream error: " + payload)
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
            root._setState(DictationService.State.Error, "streaming transcription empty")
            root.error(root.errorMessage)
            return
        }

        // Double-tap dictation mode: type text at cursor position
        if (root._dictationToCursor) {
            root._dictationToCursor = false
            console.log("[DictationService] Typing at cursor (streaming): " + text.substring(0, 50) + "...")
            Quickshell.execDetached(["wtype", "--", text])
            root.transcriptionComplete(text)
            root.partialText = ""
            root._setState(DictationService.State.Idle, "dictation-to-cursor streaming complete")
            return
        }

        // Route based on sidebar state
        if (GlobalStates.sidebarLeftOpen) {
            // Sidebar open — route through smart routing (checks intent when enabled)
            root._smartRoute(text)
        } else {
            // Sidebar closed — route through voice assistant pipeline
            root._processVoiceAssistant(text)
            root.transcriptionComplete(text)
        }

        // Clean up — no temp files in streaming mode
        root.partialText = ""
        root._setState(DictationService.State.Idle, "streaming transcription complete")
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
        root._setState(DictationService.State.Listening, "fallback to batch mode")
    }
}
