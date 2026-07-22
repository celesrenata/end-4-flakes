pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.services

import Quickshell
import QtQuick

/**
 * VoiceAgentService — orchestrates bidirectional streaming voice conversations.
 * This stub provides credential validation and state scaffolding.
 * Full state machine and process management added in task 7.1.
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

    // Config-bound
    property string voiceBackend: Config.options.dictation.voiceBackend || "none"

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

    /**
     * Attempts to activate a streaming voice session.
     * Validates credentials first; on failure sets credentialError,
     * displays error in DictationIndicator, and remains in Idle state.
     * Full activation logic (process launch, FIFO creation) added in task 7.1.
     */
    function activate() {
        // Credential gate
        var error = validateCredentials()
        if (error) {
            root.credentialError = error
            root.voiceAgentState = VoiceAgentService.State.Idle
            // Surface error through DictationService indicator
            DictationService.errorMessage = error
            DictationService.state = DictationService.State.Error
            return
        }

        root.credentialError = ""
        // Full activation logic will be added in task 7.1
    }

    /**
     * Deactivates the voice agent session. Stub for task 7.1.
     */
    function deactivate() {
        root.voiceAgentState = VoiceAgentService.State.Idle
        root.partialText = ""
        root.responseText = ""
        root.currentToolName = ""
        root.audioLevel = 0.0
        root.credentialError = ""
    }
}
