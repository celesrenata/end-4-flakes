import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property bool isActive: DictationService.state !== DictationService.State.Idle
    property bool isStreaming: DictationService.state === DictationService.State.StreamingActive
    property bool hasPartialText: isStreaming && DictationService.partialText !== ""

    // Voice response visibility: show when responseText is non-empty and state is Idle
    property bool hasResponseText: DictationService.responseText !== "" && DictationService.state === DictationService.State.Idle

    // Shell.exec approval state
    property bool isAwaitingApproval: DictationService.awaitingApproval

    PanelWindow {
        id: indicatorWindow
        visible: (root.isActive || root.hasResponseText || root.isAwaitingApproval) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

        WlrLayershell.namespace: "quickshell:dictationIndicator"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        anchors {
            top: true
            right: true
            bottom: true
        }

        mask: Region {
            item: indicatorMaskItem
        }

        // Unified mask item that encompasses whichever content is active
        Item {
            id: indicatorMaskItem
            x: root.isAwaitingApproval && !root.isActive ? approvalContent.x : root.hasResponseText && !root.isActive ? responseContent.x : indicatorContent.x
            y: root.isAwaitingApproval && !root.isActive ? approvalContent.y : root.hasResponseText && !root.isActive ? responseContent.y : indicatorContent.y
            width: root.isAwaitingApproval && !root.isActive ? approvalContent.width : root.hasResponseText && !root.isActive ? responseContent.width : indicatorContent.width
            height: root.isAwaitingApproval && !root.isActive ? approvalContent.height : root.hasResponseText && !root.isActive ? responseContent.height : indicatorContent.height
        }

        color: "transparent"
        implicitWidth: root.isAwaitingApproval && !root.isActive
            ? approvalContent.implicitWidth + Appearance.sizes.elevationMargin * 2
            : root.hasResponseText && !root.isActive
                ? responseContent.implicitWidth + Appearance.sizes.elevationMargin * 2
                : indicatorContent.implicitWidth + Appearance.sizes.elevationMargin * 2

        // Measure partial text width for dynamic sizing
        TextMetrics {
            id: partialTextMetrics
            font.pixelSize: Appearance.font.pixelSize.small
            text: DictationService.partialText
        }

        // === Voice Response Indicator ===
        // Displays AI response text with max 500px width, word wrap.
        // Visible when responseText is non-empty and dictation state is Idle.
        // Auto-dismiss (10s+ scaled) is handled by DictationService.responseDismissTimer.
        // While TtsService.playing, the dismiss timer is paused — indicator stays visible.
        // User can pin to prevent auto-dismiss, or click to copy and dismiss.
        Rectangle {
            id: responseContent
            visible: root.hasResponseText && !root.isActive && !root.isAwaitingApproval

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: Appearance.sizes.hyprlandGapsOut + Appearance.sizes.barHeight + 8
            anchors.rightMargin: Appearance.sizes.hyprlandGapsOut

            implicitWidth: Math.min(responseLayout.implicitWidth + 24, 500)
            implicitHeight: responseLayout.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 2
            border.color: Appearance.m3colors.m3primary

            Behavior on implicitWidth {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            ColumnLayout {
                id: responseLayout
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                // Header row with TTS, pin, copy, and close buttons
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Item { Layout.fillWidth: true }

                    // TTS toggle button
                    MouseArea {
                        implicitWidth: 20
                        implicitHeight: 20
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Config.options.dictation.talkback = !Config.options.dictation.talkback
                            // If just enabled and there's text showing, speak it now
                            if (Config.options.dictation.talkback && DictationService.responseText !== "") {
                                TtsService.speak(DictationService.responseText)
                            } else if (!Config.options.dictation.talkback) {
                                TtsService.stop()
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: Config.options.dictation.talkback ? "volume_up" : "volume_off"
                            iconSize: Appearance.font.pixelSize.small
                            color: Config.options.dictation.talkback
                                ? Appearance.m3colors.m3primary
                                : Appearance.colors.colSubtext
                        }
                    }

                    // Pin button
                    MouseArea {
                        implicitWidth: 20
                        implicitHeight: 20
                        cursorShape: Qt.PointingHandCursor
                        onClicked: DictationService.toggleResponsePin()

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: DictationService.responsePinned ? "push_pin" : "keep"
                            iconSize: Appearance.font.pixelSize.small
                            color: DictationService.responsePinned
                                ? Appearance.m3colors.m3primary
                                : Appearance.colors.colSubtext
                        }
                    }

                    // Copy button
                    MouseArea {
                        implicitWidth: 20
                        implicitHeight: 20
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var text = DictationService.responseText
                            if (text !== "") {
                                Quickshell.execDetached(["wl-copy", text])
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "content_copy"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }

                    // Close button
                    MouseArea {
                        implicitWidth: 20
                        implicitHeight: 20
                        cursorShape: Qt.PointingHandCursor
                        onClicked: DictationService.dismissResponse()

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true

                    StyledText {
                        text: DictationService.responseText
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        textFormat: Text.MarkdownText
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    // TTS playback animation icon — visible while speaking
                    MaterialSymbol {
                        id: ttsPlaybackIcon
                        visible: TtsService.playing
                        text: "graphic_eq"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.m3colors.m3primary
                        Layout.alignment: Qt.AlignTop

                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: TtsService.playing
                            NumberAnimation { to: 0.4; duration: 500; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }
        }

        // === Shell.exec Approval UI ===
        // Shows command text with Approve/Reject buttons when a shell.exec action
        // needs user confirmation. Indicator stays visible until user responds.
        Rectangle {
            id: approvalContent
            visible: root.isAwaitingApproval && !root.isActive

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: Appearance.sizes.hyprlandGapsOut + Appearance.sizes.barHeight + 8
            anchors.rightMargin: Appearance.sizes.hyprlandGapsOut

            implicitWidth: Math.min(approvalLayout.implicitWidth + 32, 500)
            implicitHeight: approvalLayout.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: approvalLayout
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                // Header with shield icon
                RowLayout {
                    spacing: 8

                    MaterialSymbol {
                        text: "shield"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.m3colors.m3error
                    }

                    StyledText {
                        text: "Approve shell command?"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                        color: Appearance.colors.colOnLayer1
                    }
                }

                // Command text in monospace container
                Rectangle {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 200
                    Layout.maximumWidth: 468
                    implicitHeight: approvalCommandText.implicitHeight + 12
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer0

                    StyledText {
                        id: approvalCommandText
                        anchors.fill: parent
                        anchors.margins: 6
                        text: DictationService.approvalCommand
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                }

                // Approve / Reject buttons
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 0

                    Item { Layout.fillWidth: true }

                    ButtonGroup {
                        GroupButton {
                            contentItem: StyledText {
                                text: "Reject"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                            }
                            onClicked: {
                                DictationService.awaitingApproval = false
                                DictationService.approvalCommand = ""
                                DictationService.approvalActionIndex = -1
                                ActionPalette.rejectCommand()
                            }
                        }
                        GroupButton {
                            toggled: true
                            contentItem: StyledText {
                                text: "Approve"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnPrimary
                            }
                            onClicked: {
                                var idx = DictationService.approvalActionIndex
                                DictationService.awaitingApproval = false
                                DictationService.approvalCommand = ""
                                DictationService.approvalActionIndex = -1
                                ActionPalette.approveCommand(idx)
                            }
                        }
                    }
                }
            }
        }

        // === Active Dictation Indicator ===
        Rectangle {
            id: indicatorContent
            visible: root.isActive

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: Appearance.sizes.hyprlandGapsOut + Appearance.sizes.barHeight + 8
            anchors.rightMargin: Appearance.sizes.hyprlandGapsOut

            implicitWidth: Math.min(Math.max(indicatorRow.implicitWidth + 24, root.hasPartialText ? partialTextMetrics.width + 24 : 0), 400)
            implicitHeight: contentColumn.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 2
            border.color: Appearance.m3colors.m3primary

            Behavior on implicitWidth {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            ColumnLayout {
                id: contentColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                RowLayout {
                    id: indicatorRow
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    // Pulsing mic icon when recording (Listening or StreamingActive)
                    MaterialSymbol {
                        visible: DictationService.state === DictationService.State.Listening ||
                                 DictationService.state === DictationService.State.StreamingActive
                        text: "mic"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.m3colors.m3error

                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: DictationService.state === DictationService.State.Listening ||
                                     DictationService.state === DictationService.State.StreamingActive
                            NumberAnimation { to: 0.4; duration: 600; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                        }
                    }

                    // Spinner when processing
                    MaterialSymbol {
                        id: spinnerIcon
                        visible: DictationService.state === DictationService.State.Processing
                        text: "progress_activity"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.m3colors.m3primary

                        RotationAnimation on rotation {
                            loops: Animation.Infinite
                            running: DictationService.state === DictationService.State.Processing
                            from: 0
                            to: 360
                            duration: 1000
                        }
                    }

                    // Error icon
                    MaterialSymbol {
                        visible: DictationService.state === DictationService.State.Error
                        text: "error"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.m3colors.m3error
                    }

                    // Status text
                    StyledText {
                        text: {
                            switch (DictationService.state) {
                                case DictationService.State.Listening:
                                case DictationService.State.StreamingActive:
                                    return Math.floor(DictationService.recordingDuration / 1000) + "s"
                                case DictationService.State.Processing:
                                    return "Transcribing..."
                                case DictationService.State.Error:
                                    return DictationService.errorMessage
                                default:
                                    return ""
                            }
                        }
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                // Live partial text display (streaming/chunked mode)
                StyledText {
                    id: partialTextLabel
                    visible: root.hasPartialText
                    text: DictationService.partialText
                    Layout.fillWidth: true
                    clip: true
                    elide: Text.ElideLeft
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    opacity: root.hasPartialText ? 1 : 0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }

        // Auto-dismiss error after 2 seconds
        Timer {
            interval: 2000
            running: DictationService.state === DictationService.State.Error
            onTriggered: {
                DictationService.state = DictationService.State.Idle
                DictationService.errorMessage = ""
            }
        }
    }
}
