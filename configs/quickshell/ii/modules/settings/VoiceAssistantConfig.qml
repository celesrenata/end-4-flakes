import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    // Endpoint health check state: "unknown", "reachable", "unreachable"
    property string endpointStatus: "unknown"
    property bool endpointReachable: endpointStatus === "reachable"

    Timer {
        id: healthCheckDebounce
        interval: 500
        repeat: false
        onTriggered: {
            const endpoint = Config.options.dictation.httpEndpoint.trim();
            if (endpoint === "") {
                root.endpointStatus = "unknown";
                return;
            }
            // Extract base URL (scheme + host + port)
            let baseUrl = endpoint;
            try {
                const url = new URL(endpoint);
                baseUrl = url.origin;
            } catch (e) {
                baseUrl = endpoint;
            }
            healthCheckProcess.command = ["curl", "-s", "--max-time", "3", "-o", "/dev/null", "-w", "%{http_code}", baseUrl];
            healthCheckProcess.running = true;
        }
    }

    Process {
        id: healthCheckProcess
        property string output: ""
        stdout: SplitParser {
            onRead: data => {
                healthCheckProcess.output = data.trim();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && healthCheckProcess.output !== "" && healthCheckProcess.output !== "000") {
                root.endpointStatus = "reachable";
            } else {
                root.endpointStatus = "unreachable";
            }
            healthCheckProcess.output = "";
        }
    }

    ContentSection {
        title: Translation.tr("Voice Assistant")

        ContentSubsection {
            title: Translation.tr("Speech-to-Text")

            ColumnLayout {
                ContentSubsectionLabel {
                    text: Translation.tr("Provider")
                }
                ConfigSelectionArray {
                    currentValue: Config.options.dictation.provider
                    configOptionName: "dictation.provider"
                    onSelected: newValue => {
                        Config.options.dictation.provider = newValue;
                    }
                    options: [
                        { displayName: "OpenAI", value: "openai" },
                        { displayName: "Faster Whisper", value: "faster-whisper" },
                        { displayName: "Whisper.cpp", value: "whisper-cpp" },
                        { displayName: Translation.tr("Custom"), value: "custom" },
                    ]
                }
            }

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("WebSocket streaming endpoint")
                text: Config.options.dictation.streamingEndpoint
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.dictation.streamingEndpoint = text;
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialTextField {
                    id: httpEndpointField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("HTTP batch endpoint")
                    text: Config.options.dictation.httpEndpoint
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.dictation.httpEndpoint = text;
                        root.endpointStatus = "unknown";
                        healthCheckDebounce.restart();
                    }
                }

                // Health check indicator dot
                Rectangle {
                    id: healthDot
                    Layout.alignment: Qt.AlignVCenter
                    width: 12
                    height: 12
                    radius: 6
                    property bool hovered: healthDotHover.hovered
                    color: root.endpointStatus === "reachable" ? "#4caf50"
                         : root.endpointStatus === "unreachable" ? "#f44336"
                         : "#9e9e9e"
                    opacity: root.endpointStatus === "unknown" ? 0.5 : 1.0

                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }

                    HoverHandler {
                        id: healthDotHover
                    }

                    StyledToolTip {
                        content: root.endpointStatus === "reachable" ? Translation.tr("Endpoint reachable")
                               : root.endpointStatus === "unreachable" ? Translation.tr("Endpoint unreachable")
                               : Translation.tr("Checking...")
                    }
                }
            }
            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Model (e.g. whisper-1)")
                text: Config.options.dictation.model
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.dictation.model = text;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Text-to-Speech")

            ColumnLayout {
                ContentSubsectionLabel {
                    text: Translation.tr("Provider")
                }
                ConfigSelectionArray {
                    currentValue: Config.options.dictation.ttsProvider
                    configOptionName: "dictation.ttsProvider"
                    onSelected: newValue => {
                        Config.options.dictation.ttsProvider = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("None"), value: "none" },
                        { displayName: "Piper", value: "piper" },
                        { displayName: "espeak-ng", value: "espeak-ng" },
                        { displayName: "OpenAI", value: "openai" },
                    ]
                }
            }

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Voice (provider-specific ID or model path)")
                text: Config.options.dictation.ttsVoice
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.dictation.ttsVoice = text;
                }
            }

            ConfigSwitch {
                text: Translation.tr("Talkback")
                checked: Config.options.dictation.talkback
                onCheckedChanged: {
                    Config.options.dictation.talkback = checked;
                }
                StyledToolTip {
                    content: Translation.tr("Speak responses aloud after voice commands")
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Intent Classification")

            ColumnLayout {
                ContentSubsectionLabel {
                    text: Translation.tr("Mode")
                }
                ConfigSelectionArray {
                    currentValue: Config.options.dictation.intentMode
                    configOptionName: "dictation.intentMode"
                    onSelected: newValue => {
                        Config.options.dictation.intentMode = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Heuristic"), value: "heuristic" },
                        { displayName: Translation.tr("AI"), value: "ai" },
                    ]
                }
            }
        }
    }
}
