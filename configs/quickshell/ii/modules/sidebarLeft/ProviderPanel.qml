import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string selectedProvider: ""
    property bool showCustomForm: false
    property var editingCustomProvider: null

    // Deselect non-local voice providers when policy changes to local-only (Requirement 7.3)
    Connections {
        target: Config.options.policies
        function onAiChanged() {
            if (Config.options.policies.ai === 2) {
                // Deselect STT provider if it's not local
                var sttProvider = Config.options.dictation.provider
                if (sttProvider && sttProvider !== "") {
                    var sttConfig = Config.options.dictation.sttProviders[sttProvider]
                    if (sttConfig && sttConfig.endpoint && !VoiceProviderCheckService.isLocal(sttConfig.endpoint)) {
                        Config.setNestedValue("dictation.provider", "")
                    }
                }
                // Deselect TTS provider if it's not local
                var ttsProvider = Config.options.dictation.ttsProvider
                if (ttsProvider && ttsProvider !== "none" && ttsProvider !== "") {
                    var ttsConfig = Config.options.dictation.ttsProviders[ttsProvider]
                    if (ttsConfig && ttsConfig.endpoint && !VoiceProviderCheckService.isLocal(ttsConfig.endpoint)) {
                        Config.setNestedValue("dictation.ttsProvider", "none")
                    }
                }
                // Deselect voice agent backend (all streaming backends require remote API)
                var voiceBackend = Config.options.dictation.voiceBackend
                if (voiceBackend && voiceBackend !== "none") {
                    Config.setNestedValue("dictation.voiceBackend", "none")
                }
            }
        }
    }

    // Compute the list of provider IDs based on policy and custom providers
    property var providerList: {
        var builtIn = [];
        if (Config.options.policies.ai === 2) {
            builtIn = ["ollama"];
        } else {
            builtIn = ["openai", "anthropic", "gemini", "mistral", "openrouter", "ollama", "bedrock"];
        }
        // Add custom providers
        var customs = ModelDiscoveryService.customProviders || [];
        var customIds = [];
        for (var i = 0; i < customs.length; i++) {
            if (Config.options.policies.ai === 2) {
                // In local-only mode, only show custom providers with localhost URLs
                var baseUrl = customs[i].baseUrl || "";
                if (baseUrl.indexOf("localhost") !== -1 || baseUrl.indexOf("127.0.0.1") !== -1) {
                    customIds.push(customs[i].id);
                }
            } else {
                customIds.push(customs[i].id);
            }
        }
        return builtIn.concat(customIds);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Provider list view (when no provider selected and not showing custom form)
        ListView {
            id: providerListView
            visible: root.selectedProvider === "" && !root.showCustomForm
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.providerList
            spacing: 4
            clip: true

            delegate: ProviderListItem {
                required property int index
                required property string modelData
                width: providerListView.width
                providerId: modelData
                onClicked: root.selectedProvider = providerId
            }

            footer: Item {
                width: providerListView.width
                height: addCustomBtn.height + 16

                RippleButton {
                    id: addCustomBtn
                    anchors.centerIn: parent
                    buttonText: Translation.tr("Add Custom")
                    onClicked: {
                        root.showCustomForm = true;
                        root.editingCustomProvider = null;
                    }
                }
            }
        }

        // Provider detail view (when provider selected)
        Loader {
            visible: root.selectedProvider !== "" && !root.showCustomForm
            active: root.selectedProvider !== "" && !root.showCustomForm
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: ProviderDetailView {
                providerId: root.selectedProvider
                onBack: root.selectedProvider = ""
                onEditCustom: function(provider) {
                    root.editingCustomProvider = provider;
                    root.showCustomForm = true;
                }
            }
        }

        // Custom provider form (when adding/editing)
        Loader {
            visible: root.showCustomForm
            active: root.showCustomForm
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: CustomProviderForm {
                editingProvider: root.editingCustomProvider
                onBack: {
                    root.showCustomForm = false;
                    root.editingCustomProvider = null;
                }
                onSaved: function(providerId) {
                    root.showCustomForm = false;
                    root.editingCustomProvider = null;
                    root.selectedProvider = providerId;
                }
            }
        }

        // === Voice Settings (Dropdowns) ===
        ColumnLayout {
            visible: root.selectedProvider === "" && !root.showCustomForm && Config.options.policies.ai !== 0
            Layout.fillWidth: true
            spacing: 8
            Layout.topMargin: 12

            // Section header
            StyledText {
                text: Translation.tr("Voice Settings")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }

            // STT Provider dropdown
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: Translation.tr("Speech-to-Text")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                // Provider selector
                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: ["openai", "bedrock", "whisperCpp", "fasterWhisper", "vosk", "whisperLive"]
                        delegate: RippleButton {
                            required property string modelData
                            required property int index
                            implicitHeight: 26
                            implicitWidth: sttChipText.implicitWidth + 14
                            buttonRadius: 13
                            colBackground: Config.options.dictation.provider === modelData
                                ? Appearance.m3colors.m3primaryContainer
                                : Appearance.colors.colLayer2
                            colBackgroundHover: Config.options.dictation.provider === modelData
                                ? Appearance.m3colors.m3primaryContainer
                                : Appearance.colors.colLayer2Hover

                            contentItem: StyledText {
                                id: sttChipText
                                anchors.centerIn: parent
                                text: modelData
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Config.options.dictation.provider === modelData
                                    ? Appearance.m3colors.m3onPrimaryContainer
                                    : Appearance.colors.colOnLayer2
                            }
                            onClicked: Config.setNestedValue("dictation.provider", modelData)
                        }
                    }
                }
            }

            // TTS Provider dropdown
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: Translation.tr("Text-to-Speech")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                // Provider selector
                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: ["none", "openai", "bedrock", "piper", "espeak-ng"]
                        delegate: RippleButton {
                            required property string modelData
                            required property int index
                            implicitHeight: 26
                            implicitWidth: ttsChipText.implicitWidth + 14
                            buttonRadius: 13
                            colBackground: Config.options.dictation.ttsProvider === modelData
                                ? Appearance.m3colors.m3primaryContainer
                                : Appearance.colors.colLayer2
                            colBackgroundHover: Config.options.dictation.ttsProvider === modelData
                                ? Appearance.m3colors.m3primaryContainer
                                : Appearance.colors.colLayer2Hover

                            contentItem: StyledText {
                                id: ttsChipText
                                anchors.centerIn: parent
                                text: modelData === "none" ? Translation.tr("Off") : modelData
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Config.options.dictation.ttsProvider === modelData
                                    ? Appearance.m3colors.m3onPrimaryContainer
                                    : Appearance.colors.colOnLayer2
                            }
                            onClicked: Config.setNestedValue("dictation.ttsProvider", modelData)
                        }
                    }
                }

                // Voice selector (only when TTS is openai)
                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: Config.options.dictation.ttsProvider === "openai"

                    Repeater {
                        model: ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]
                        delegate: RippleButton {
                            required property string modelData
                            required property int index
                            implicitHeight: 24
                            implicitWidth: voiceChipText.implicitWidth + 12
                            buttonRadius: 12
                            colBackground: Config.options.dictation.ttsVoice === modelData
                                ? Appearance.m3colors.m3tertiaryContainer
                                : Qt.alpha(Appearance.colors.colLayer2, 0.6)
                            colBackgroundHover: Config.options.dictation.ttsVoice === modelData
                                ? Appearance.m3colors.m3tertiaryContainer
                                : Appearance.colors.colLayer2Hover

                            contentItem: StyledText {
                                id: voiceChipText
                                anchors.centerIn: parent
                                text: modelData
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Config.options.dictation.ttsVoice === modelData
                                    ? Appearance.m3colors.m3onTertiaryContainer
                                    : Appearance.colors.colOnLayer2
                            }
                            onClicked: Config.setNestedValue("dictation.ttsVoice", modelData)
                        }
                    }
                }

                // Voice selector (only when TTS is bedrock/Polly)
                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: Config.options.dictation.ttsProvider === "bedrock"

                    Repeater {
                        model: ["Joanna", "Matthew", "Amy", "Brian", "Ruth", "Stephen"]
                        delegate: RippleButton {
                            required property string modelData
                            required property int index
                            implicitHeight: 24
                            implicitWidth: pollyChipText.implicitWidth + 12
                            buttonRadius: 12
                            colBackground: Config.options.dictation.ttsVoice === modelData
                                ? Appearance.m3colors.m3tertiaryContainer
                                : Qt.alpha(Appearance.colors.colLayer2, 0.6)
                            colBackgroundHover: Config.options.dictation.ttsVoice === modelData
                                ? Appearance.m3colors.m3tertiaryContainer
                                : Appearance.colors.colLayer2Hover

                            contentItem: StyledText {
                                id: pollyChipText
                                anchors.centerIn: parent
                                text: modelData
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Config.options.dictation.ttsVoice === modelData
                                    ? Appearance.m3colors.m3onTertiaryContainer
                                    : Appearance.colors.colOnLayer2
                            }
                            onClicked: Config.setNestedValue("dictation.ttsVoice", modelData)
                        }
                    }
                }
            }

            // Talkback toggle
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: Translation.tr("Speak responses")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    Layout.fillWidth: true
                }

                Switch {
                    checked: Config.options.dictation.talkback
                    onToggled: Config.setNestedValue("dictation.talkback", checked)
                }
            }

            // Response verbosity selector
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: Translation.tr("Response Verbosity")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: ["concise", "normal", "detailed"]
                        delegate: RippleButton {
                            required property string modelData
                            required property int index
                            implicitHeight: 24
                            implicitWidth: verbChipText.implicitWidth + 12
                            buttonRadius: 12
                            colBackground: Config.options.dictation.verbosity === modelData
                                ? Appearance.m3colors.m3secondaryContainer
                                : Qt.alpha(Appearance.colors.colLayer2, 0.6)
                            colBackgroundHover: Config.options.dictation.verbosity === modelData
                                ? Appearance.m3colors.m3secondaryContainer
                                : Appearance.colors.colLayer2Hover

                            contentItem: StyledText {
                                id: verbChipText
                                anchors.centerIn: parent
                                text: modelData === "concise" ? Translation.tr("Concise")
                                    : modelData === "normal" ? Translation.tr("Normal")
                                    : Translation.tr("Detailed")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Config.options.dictation.verbosity === modelData
                                    ? Appearance.m3colors.m3onSecondaryContainer
                                    : Appearance.colors.colOnLayer2
                            }
                            onClicked: Config.setNestedValue("dictation.verbosity", modelData)
                        }
                    }
                }
            }

            // Voice Agent backend selector (hidden in local-only mode since backends require remote API)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: Config.options.policies.ai !== 2

                StyledText {
                    text: Translation.tr("Voice Agent")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: ["none", "nova-sonic", "openai-realtime"]
                        delegate: RippleButton {
                            required property string modelData
                            required property int index
                            implicitHeight: 26
                            implicitWidth: vaChipText.implicitWidth + 14
                            buttonRadius: 13
                            colBackground: Config.options.dictation.voiceBackend === modelData
                                ? Appearance.m3colors.m3primaryContainer
                                : Appearance.colors.colLayer2
                            colBackgroundHover: Config.options.dictation.voiceBackend === modelData
                                ? Appearance.m3colors.m3primaryContainer
                                : Appearance.colors.colLayer2Hover

                            contentItem: StyledText {
                                id: vaChipText
                                anchors.centerIn: parent
                                text: modelData === "none" ? Translation.tr("Off") : modelData
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Config.options.dictation.voiceBackend === modelData
                                    ? Appearance.m3colors.m3onPrimaryContainer
                                    : Appearance.colors.colOnLayer2
                            }
                            onClicked: Config.setNestedValue("dictation.voiceBackend", modelData)
                        }
                    }
                }
            }

            // Override endpoint (optional, collapsed by default)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: overrideToggle.checked

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    color: Appearance.colors.colLayer2
                    radius: Appearance.rounding.small

                    StyledTextInput {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Appearance.m3colors.m3onSurface
                        clip: true
                        text: Config.options.dictation.httpEndpoint
                        onEditingFinished: Config.setNestedValue("dictation.httpEndpoint", text)

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Custom STT endpoint")
                            color: Appearance.m3colors.m3outline
                            font: parent.font
                            visible: !parent.text && !parent.activeFocus
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    color: Appearance.colors.colLayer2
                    radius: Appearance.rounding.small

                    StyledTextInput {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Appearance.m3colors.m3onSurface
                        clip: true
                        text: Config.options.dictation.ttsHttpEndpoint
                        onEditingFinished: Config.setNestedValue("dictation.ttsHttpEndpoint", text)

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Custom TTS endpoint")
                            color: Appearance.m3colors.m3outline
                            font: parent.font
                            visible: !parent.text && !parent.activeFocus
                        }
                    }
                }
            }

            // Show/hide override fields
            MouseArea {
                id: overrideToggle
                implicitWidth: overrideRow.implicitWidth
                implicitHeight: overrideRow.implicitHeight
                cursorShape: Qt.PointingHandCursor
                onClicked: overrideToggle.checked = !overrideToggle.checked

                property bool checked: false

                RowLayout {
                    id: overrideRow
                    spacing: 4
                    MaterialSymbol {
                        text: overrideToggle.checked ? "expand_less" : "tune"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: Translation.tr("Endpoint override")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
