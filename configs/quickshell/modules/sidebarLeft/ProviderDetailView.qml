import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    required property string providerId
    signal back()
    signal editCustom(var provider)

    property var config: ModelDiscoveryService.getEffectiveProviderConfig(providerId)
    property var validationState: ModelDiscoveryService.validationStates[providerId] || { status: "idle", message: "" }
    property bool isCustomProvider: {
        return !ModelDiscoveryService.providerConfigs[providerId];
    }

    // Debounce timer for auto-validation (1000ms)
    Timer {
        id: debounceTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (keyInput.text.length > 0) {
                ModelDiscoveryService.validateKey(root.providerId, keyInput.text);
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // --- Header row ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer1
                }
                releaseAction: function() { root.back() }
            }

            CustomIcon {
                source: root.config ? root.config.icon : "ai-openai-symbolic"
                width: 24
                height: 24
                colorize: true
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                text: root.config ? root.config.name : root.providerId
                font.pixelSize: Appearance.font.pixelSize.large
                font.bold: true
                color: Appearance.colors.colOnLayer1
                Layout.fillWidth: true
            }

            // Edit button for custom providers
            RippleButton {
                visible: root.isCustomProvider
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "edit"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer1
                }
                releaseAction: function() {
                    var customs = ModelDiscoveryService.customProviders || [];
                    for (var i = 0; i < customs.length; i++) {
                        if (customs[i].id === root.providerId) {
                            root.editCustom(customs[i]);
                            return;
                        }
                    }
                }
            }
        }

        // --- API Key Input (hidden for providers that don't require a key) ---
        ColumnLayout {
            visible: root.config ? root.config.requires_key : false
            Layout.fillWidth: true
            spacing: 6

            StyledText {
                text: Translation.tr("API Key")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextField {
                    id: keyInput
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    placeholderText: Translation.tr("Enter API key...")
                    text: {
                        if (!root.config || !root.config.key_id) return "";
                        var keys = KeyringStorage.keyringData ? KeyringStorage.keyringData.apiKeys : null;
                        return keys ? (keys[root.config.key_id] || "") : "";
                    }
                    onTextChanged: {
                        debounceTimer.restart();
                    }
                }

                // Validation status indicators
                BusyIndicator {
                    visible: root.validationState.status === "loading"
                    implicitWidth: 24
                    implicitHeight: 24
                }

                MaterialSymbol {
                    visible: root.validationState.status === "success"
                    text: "check_circle"
                    iconSize: 24
                    color: "green"
                }

                MaterialSymbol {
                    visible: root.validationState.status === "error"
                    text: "error"
                    iconSize: 24
                    color: Appearance.colors.colError
                }

                // Re-test button: visible when key exists, disabled during loading
                RippleButton {
                    visible: keyInput.text.length > 0
                    enabled: root.validationState.status !== "loading"
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "refresh"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer1
                    }
                    releaseAction: function() {
                        ModelDiscoveryService.validateKey(root.providerId, keyInput.text);
                    }
                }
            }

            // Error message
            StyledText {
                visible: root.validationState.status === "error"
                text: root.validationState.message || ""
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colError
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        // --- AWS Bedrock Credentials Section ---
        ColumnLayout {
            visible: root.config ? root.config.auth_type === "aws_cli" : false
            Layout.fillWidth: true
            spacing: 6

            // AWS CLI availability check
            StyledText {
                visible: !AwsCredentialReader.awsCliAvailable
                text: Translation.tr("AWS CLI not found. Install the aws-cli package to use Bedrock.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colError
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            // Credential status
            StyledText {
                visible: AwsCredentialReader.credentialsDetected
                text: Translation.tr("Credentials: %1").arg(AwsCredentialReader.credentialsFilePath)
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            StyledText {
                visible: !AwsCredentialReader.credentialsDetected && AwsCredentialReader.awsCliAvailable
                text: Translation.tr("No AWS credentials found. Create ~/.aws/credentials.bedrock with access key on line 1 and secret key on line 2.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colError
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            // Region display
            StyledText {
                visible: AwsCredentialReader.credentialsDetected
                text: Translation.tr("Region: %1").arg(AwsCredentialReader.region)
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                Layout.fillWidth: true
            }

            // Test Connection button row
            RowLayout {
                visible: AwsCredentialReader.credentialsDetected && AwsCredentialReader.awsCliAvailable
                Layout.fillWidth: true
                spacing: 8

                RippleButton {
                    enabled: root.validationState.status !== "loading"
                    implicitWidth: 120
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.small
                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Test Connection")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                    releaseAction: function() {
                        ModelDiscoveryService.validateBedrock();
                    }
                }

                BusyIndicator {
                    visible: root.validationState.status === "loading"
                    implicitWidth: 24
                    implicitHeight: 24
                }

                MaterialSymbol {
                    visible: root.validationState.status === "success"
                    text: "check_circle"
                    iconSize: 24
                    color: "green"
                }

                MaterialSymbol {
                    visible: root.validationState.status === "error"
                    text: "error"
                    iconSize: 24
                    color: Appearance.colors.colError
                }
            }

            // Error message for bedrock validation
            StyledText {
                visible: root.validationState.status === "error" && (root.config ? root.config.auth_type === "aws_cli" : false)
                text: root.validationState.message || ""
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colError
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        // --- Balance display (only for providers that support it) ---
        RowLayout {
            visible: (root.config ? root.config.supports_balance : false) && root.validationState.status === "success"
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                text: Translation.tr("Balance:")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            StyledText {
                text: ModelDiscoveryService.balances[root.providerId] || "—"
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
            }
        }

        // --- Models section header ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                text: Translation.tr("Models")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.bold: true
                color: Appearance.colors.colOnLayer1
                Layout.fillWidth: true
            }

            // Refresh button (visible when validated or no key required)
            RippleButton {
                visible: root.validationState.status === "success" || (root.config ? !root.config.requires_key : false)
                enabled: !ModelDiscoveryService.isRefreshing(root.providerId)
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: Appearance.rounding.full
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer1
                }
                releaseAction: function() {
                    ModelDiscoveryService.discoverModels(root.providerId);
                }
            }

            BusyIndicator {
                visible: ModelDiscoveryService.isRefreshing(root.providerId)
                implicitWidth: 20
                implicitHeight: 20
            }
        }

        // --- Model list ---
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: ModelDiscoveryService.discoveredModels[root.providerId] || []
            spacing: 2
            delegate: ModelListItem {
                required property int index
                required property var modelData
                width: parent ? parent.width : 200
                modelName: modelData.name || ""
                modelId: modelData.model || ""
                providerIcon: modelData.icon || ""
            }
        }
    }
}
