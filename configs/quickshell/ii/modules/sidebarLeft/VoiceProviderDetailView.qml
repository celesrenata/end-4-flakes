import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    required property string providerKey
    required property string providerType  // "stt" or "tts"
    required property var providerConfig

    signal back()

    // Trigger connectivity check on load
    Component.onCompleted: {
        if (root.providerConfig && root.providerConfig.endpoint) {
            VoiceProviderCheckService.checkEndpoint(
                root.providerKey,
                root.providerConfig.endpoint,
                root.providerConfig.protocol || "rest"
            )
        }
    }

    // URL validation helper
    function isValidEndpoint(url) {
        return url.startsWith("http://") || url.startsWith("https://") ||
               url.startsWith("tcp://") || url.startsWith("ws://")
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // Back button row
        RowLayout {
            spacing: 8
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                colBackground: "transparent"
                colBackgroundHover: Qt.alpha(Appearance.m3colors.m3onSurface, 0.08)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                onClicked: root.back()
            }

            StyledText {
                text: root.providerKey
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
                Layout.fillWidth: true
            }

            // Status indicator
            Rectangle {
                width: 10
                height: 10
                radius: 5
                color: {
                    var state = VoiceProviderCheckService.checkStates[root.providerKey]
                    if (!state) return Appearance.colors.colOutlineVariant
                    switch (state.status) {
                        case "reachable": return Appearance.colors.colPrimary
                        case "unreachable": return Appearance.m3colors.m3error
                        case "local": return Appearance.m3colors.m3tertiary
                        case "checking": return Appearance.colors.colSubtext
                        default: return Appearance.colors.colOutlineVariant
                    }
                }
            }
        }

        // Dynamic fields from provider config
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: fieldsColumn.implicitHeight
            clip: true

            ColumnLayout {
                id: fieldsColumn
                width: parent.width
                spacing: 12

                Repeater {
                    model: Object.keys(root.providerConfig || {})

                    delegate: ColumnLayout {
                        id: fieldDelegate
                        required property string modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 4

                        readonly property string fieldKey: modelData
                        readonly property var fieldValue: root.providerConfig[fieldKey]
                        readonly property bool isEndpoint: fieldKey === "endpoint"
                        readonly property bool isProtocol: fieldKey === "protocol"
                        property bool hasError: false
                        property string errorText: ""

                        // Field label
                        StyledText {
                            text: fieldDelegate.fieldKey
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colSubtext
                        }

                        // Protocol field — constrained selector
                        RowLayout {
                            visible: fieldDelegate.isProtocol
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: ["rest", "websocket", "wyoming"]
                                delegate: RippleButton {
                                    required property string modelData
                                    required property int index
                                    implicitHeight: 28
                                    implicitWidth: implicitContentWidth + 16
                                    buttonRadius: Appearance.rounding.small
                                    colBackground: fieldDelegate.fieldValue === modelData
                                        ? Appearance.m3colors.m3secondaryContainer
                                        : Appearance.colors.colLayer2
                                    colBackgroundHover: fieldDelegate.fieldValue === modelData
                                        ? Appearance.m3colors.m3secondaryContainer
                                        : Appearance.colors.colLayer2Hover
                                    contentItem: StyledText {
                                        text: modelData
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: fieldDelegate.fieldValue === modelData
                                            ? Appearance.m3colors.m3onSecondaryContainer
                                            : Appearance.colors.colOnLayer2
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    onClicked: {
                                        Config.setNestedValue(
                                            "dictation." + root.providerType + "Providers." + root.providerKey + "." + fieldDelegate.fieldKey,
                                            modelData
                                        )
                                    }
                                }
                            }
                        }

                        // Text input for other fields
                        TextField {
                            visible: !fieldDelegate.isProtocol
                            Layout.fillWidth: true
                            text: String(fieldDelegate.fieldValue || "")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                            placeholderText: fieldDelegate.fieldKey
                            background: Rectangle {
                                color: Appearance.colors.colLayer2
                                radius: Appearance.rounding.small
                                border.color: fieldDelegate.hasError ? Appearance.m3colors.m3error : Appearance.colors.colOutlineVariant
                                border.width: 1
                            }
                            leftPadding: 8
                            rightPadding: 8
                            topPadding: 6
                            bottomPadding: 6

                            onEditingFinished: {
                                var newValue = text.trim()
                                // Endpoint URL validation
                                if (fieldDelegate.isEndpoint && newValue !== "" && !root.isValidEndpoint(newValue)) {
                                    fieldDelegate.hasError = true
                                    fieldDelegate.errorText = "Must start with http://, https://, tcp://, or ws://"
                                    return
                                }
                                fieldDelegate.hasError = false
                                fieldDelegate.errorText = ""
                                Config.setNestedValue(
                                    "dictation." + root.providerType + "Providers." + root.providerKey + "." + fieldDelegate.fieldKey,
                                    newValue
                                )
                            }
                        }

                        // Error text for validation
                        StyledText {
                            visible: fieldDelegate.hasError
                            text: fieldDelegate.errorText
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.m3colors.m3error
                        }
                    }
                }
            }
        }
    }
}
