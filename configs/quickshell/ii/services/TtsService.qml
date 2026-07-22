pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Text-to-Speech service supporting piper, espeak-ng, and OpenAI TTS backends.
 * Audio output is piped through pw-play (PipeWire).
 */
Singleton {
    id: root

    // Config-bound properties
    property string provider: Config.options.dictation.ttsProvider
    property string voice: Config.options.dictation.ttsVoice
    property bool playing: ttsProcess.running

    // Emitted when TTS playback fails (non-zero exit). The response text
    // should remain visible in the Floating Indicator regardless.
    signal speakFailed(string error)

    // API key for OpenAI TTS (populated from KeyringStorage)
    property string _apiKey: {
        if (KeyringStorage.keyringData && KeyringStorage.keyringData.apiKeys)
            return KeyringStorage.keyringData.apiKeys["openai"] || ""
        return ""
    }

    // TTS execution process
    Process {
        id: ttsProcess
        stderr: SplitParser {
            splitMarker: ""
            onRead: data => {
                if (data.trim().length > 0) {
                    console.warn("[TtsService] stderr: " + data.trim())
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                const msg = "TTS process exited with code " + exitCode
                console.warn("[TtsService] " + msg)
                root.speakFailed(msg)
            }
        }
    }

    /**
     * Speak the given text using the configured TTS provider.
     * If already playing, stops current playback first.
     */
    function speak(text) {
        if (provider === "none" || !text) return
        if (playing) stop()

        // Policy: local-only mode — block OpenAI TTS (remote API)
        if (Config.options.policies.ai === 2 && provider === "openai") {
            console.warn("[TtsService] OpenAI TTS blocked by local-only policy (policies.ai=2). Skipping TTS.")
            return
        }

        let command = []

        if (provider === "piper") {
            // Escape single quotes for safe shell embedding: ' → '\''
            const escaped = text.replace(/'/g, "'\\''")
            command = ["sh", "-c",
                `echo '${escaped}' | piper --model ${voice} --output_raw | pw-play --format=s16 --rate=22050 --channels=1 -`]
        } else if (provider === "espeak-ng") {
            // Escape double quotes for safe shell embedding: " → \"
            const escaped = text.replace(/"/g, '\\"')
            command = ["sh", "-c",
                `espeak-ng "${escaped}" --stdout | pw-play -`]
        } else if (provider === "openai") {
            if (!_apiKey) {
                console.warn("[TtsService] OpenAI TTS requires an API key — set 'openai' in KeyringStorage")
                return
            }
            // Strip markdown formatting for cleaner speech
            var cleanText = text.replace(/\*\*/g, "").replace(/\*/g, "").replace(/`/g, "").replace(/#{1,6}\s/g, "").replace(/- /g, "")
            // Escape for JSON string: backslashes, double quotes, newlines, tabs
            var escaped = cleanText.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, " ").replace(/\t/g, " ")
            // Truncate to avoid massive TTS requests (max 4096 chars for OpenAI TTS)
            if (escaped.length > 4000) escaped = escaped.substring(0, 4000)
            var selectedVoice = voice || "nova"
            // Use a temp file approach to avoid shell quoting issues
            var jsonPayload = JSON.stringify({"model": "tts-1", "input": escaped, "voice": selectedVoice})
            // Escape single quotes in JSON for shell embedding
            var shellSafeJson = jsonPayload.split("'").join("'\\''")
            command = ["sh", "-c",
                "curl -s https://api.openai.com/v1/audio/speech -H 'Authorization: Bearer " + _apiKey + "' -H 'Content-Type: application/json' -d '" + shellSafeJson + "' | pw-play -"]
        } else if (provider === "bedrock") {
            // AWS Polly via CLI — uses credentials from ~/.aws or environment
            var cleanText = text.replace(/\*\*/g, "").replace(/\*/g, "").replace(/`/g, "").replace(/#{1,6}\s/g, "").replace(/- /g, "")
            var escaped = cleanText.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, " ").replace(/\t/g, " ")
            if (escaped.length > 3000) escaped = escaped.substring(0, 3000)
            var selectedVoice = voice || "Joanna"
            command = ["sh", "-c",
                'aws polly synthesize-speech --output-format pcm --sample-rate 16000 --voice-id ' + selectedVoice + ' --text "' + escaped + '" /dev/stdout | pw-play --format=s16 --rate=16000 --channels=1 -']
        } else {
            console.log("[TtsService] speak() called with unknown provider=" + provider)
            return
        }

        ttsProcess.command = command
        ttsProcess.running = true
    }

    /**
     * Stop current TTS playback (sends SIGTERM to the process).
     */
    function stop() {
        ttsProcess.running = false
    }
}
