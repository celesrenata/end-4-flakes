pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.syntaxhighlighting


Item {
    id: root

    property string toolName: ""
    property string content: ""
    property bool isError: false
    property bool pending: false
    property real startTime: 0
    property var messageData: null

    property real toolBlockBackgroundRounding: Appearance.rounding.small
    property real toolBlockHeaderPaddingVertical: 3
    property real toolBlockHeaderPaddingHorizontal: 10
    property real toolBlockComponentSpacing: 2
    property int maxLines: 500

    property var collapseAnimation: bodyContent.implicitHeight > 40 ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveFast
    property bool collapsed: (root.messageData?.functionResponse ?? "").length > 0

    // Detect if content is valid JSON
    property bool contentIsJson: {
        if (content.length === 0) return false;
        try {
            JSON.parse(content);
            return true;
        } catch (e) {
            return false;
        }
    }

    // Truncation logic
    property var contentLines: content.split("\n")
    property bool isTruncated: contentLines.length > maxLines
    property string displayContent: isTruncated ? contentLines.slice(0, maxLines).join("\n") : content
    property int totalLineCount: contentLines.length

    // Timeout detection (30 seconds)
    property bool isTimedOut: pending && startTime > 0 && (Date.now() - startTime) > 30000

    Layout.fillWidth: true
    implicitHeight: collapsed ? header.implicitHeight : columnLayout.implicitHeight
    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: toolBlockBackgroundRounding
        }
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: collapseAnimation.duration
            easing.type: collapseAnimation.type
            easing.bezierCurve: collapseAnimation.bezierCurve
        }
    }

    // Forward vertical scroll to parent message list
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.NoButton
        onWheel: (event) => {
            if (event.angleDelta.y !== 0) {
                let item = root.parent
                while (item && !item.hasOwnProperty("flickableDirection")) {
                    item = item.parent
                }
                if (item) {
                    item.contentY -= event.angleDelta.y
                    item.returnToBounds()
                }
                event.accepted = true
            } else {
                event.accepted = false
            }
        }
    }

    // Timer for timeout detection refresh
    Timer {
        id: timeoutCheckTimer
        interval: 1000
        repeat: true
        running: root.pending && root.startTime > 0
        onTriggered: root.isTimedOut = (Date.now() - root.startTime) > 30000
    }

    ColumnLayout {
        id: columnLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        Rectangle { // Header background
            id: header
            color: root.isError ? Appearance.m3colors.m3errorContainer : Appearance.m3colors.m3secondaryContainer
            Layout.fillWidth: true
            implicitHeight: toolBlockTitleBarRowLayout.implicitHeight + toolBlockHeaderPaddingVertical * 2

            MouseArea {
                id: headerMouseArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                    root.collapsed = !root.collapsed
                }
            }

            RowLayout {
                id: toolBlockTitleBarRowLayout
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: toolBlockHeaderPaddingHorizontal
                anchors.rightMargin: toolBlockHeaderPaddingHorizontal
                spacing: 10

                MaterialSymbol {
                    Layout.fillWidth: false
                    Layout.topMargin: 7
                    Layout.bottomMargin: 7
                    Layout.leftMargin: 3
                    text: root.isError ? "error" : "build"
                    color: root.isError ? Appearance.m3colors.m3onErrorContainer : Appearance.m3colors.m3onSecondaryContainer
                }

                StyledText {
                    id: toolBlockTitle
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignLeft
                    text: "Tool: " + root.toolName
                    color: root.isError ? Appearance.m3colors.m3onErrorContainer : Appearance.m3colors.m3onSecondaryContainer
                }

                Item { Layout.fillWidth: true }

                // Timeout indicator
                StyledText {
                    visible: root.isTimedOut
                    text: Translation.tr("Timeout")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3error
                }

                RippleButton {
                    id: expandButton
                    visible: !root.pending
                    implicitWidth: 22
                    implicitHeight: 22
                    colBackground: headerMouseArea.containsMouse ? Appearance.colors.colLayer2Hover
                        : ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active

                    onClicked: { root.collapsed = !root.collapsed }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "keyboard_arrow_down"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.isError ? Appearance.m3colors.m3onErrorContainer : Appearance.m3colors.m3onSecondaryContainer
                        rotation: root.collapsed ? 0 : 180
                        Behavior on rotation {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: bodyContent
            Layout.fillWidth: true
            implicitHeight: collapsed ? 0 : bodyBackground.implicitHeight + toolBlockComponentSpacing
            clip: true

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: collapseAnimation.duration
                    easing.type: collapseAnimation.type
                    easing.bezierCurve: collapseAnimation.bezierCurve
                }
            }

            Rectangle {
                id: bodyBackground
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                implicitHeight: bodyColumnLayout.implicitHeight
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: bodyColumnLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 4

                    // Loading state
                    RowLayout {
                        visible: root.pending
                        Layout.fillWidth: true
                        Layout.margins: 10
                        spacing: 10

                        BusyIndicator {
                            implicitWidth: 20
                            implicitHeight: 20
                            running: root.pending && !root.messageData?.functionPending
                        }

                        StyledText {
                            text: root.messageData?.functionPending
                                ? Translation.tr("Tool %1 requires approval").arg(root.toolName)
                                : root.isTimedOut
                                    ? Translation.tr("Calling %1... (timed out)").arg(root.toolName)
                                    : Translation.tr("Calling %1...").arg(root.toolName)
                            color: root.isTimedOut ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                        }

                        Item { Layout.fillWidth: true }

                        // Approve button
                        RippleButton {
                            visible: root.messageData?.functionPending ?? false
                            implicitWidth: approveText.implicitWidth + 16
                            implicitHeight: 28
                            colBackground: Appearance.m3colors.m3primary
                            colBackgroundHover: Qt.lighter(Appearance.m3colors.m3primary, 1.1)
                            colRipple: Appearance.m3colors.m3onPrimary

                            contentItem: StyledText {
                                id: approveText
                                anchors.centerIn: parent
                                text: Translation.tr("Approve")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.m3colors.m3onPrimary
                            }

                            onClicked: {
                                if (root.messageData) Ai.approveMcpTool(root.messageData);
                            }
                        }

                        // Reject button
                        RippleButton {
                            visible: root.messageData?.functionPending ?? false
                            implicitWidth: rejectText.implicitWidth + 16
                            implicitHeight: 28
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active

                            contentItem: StyledText {
                                id: rejectText
                                anchors.centerIn: parent
                                text: Translation.tr("Reject")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }

                            onClicked: {
                                if (root.messageData) Ai.rejectMcpTool(root.messageData);
                            }
                        }
                    }

                    // Content area (shown when not pending)
                    Loader {
                        id: contentLoader
                        active: !root.pending && root.content.length > 0
                        visible: active
                        Layout.fillWidth: true
                        sourceComponent: root.contentIsJson ? jsonBlockComponent : plainTextComponent
                    }

                    // Truncation indicator
                    Rectangle {
                        visible: root.isTruncated && !root.pending
                        Layout.fillWidth: true
                        implicitHeight: truncationText.implicitHeight + 8
                        color: Appearance.colors.colSurfaceContainerHighest

                        StyledText {
                            id: truncationText
                            anchors.centerIn: parent
                            text: Translation.tr("Output truncated: showing %1 of %2 lines").arg(root.maxLines).arg(root.totalLineCount)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }

    // JSON code block component (syntax-highlighted)
    Component {
        id: jsonBlockComponent

        RowLayout {
            spacing: root.toolBlockComponentSpacing

            Rectangle { // Line numbers
                implicitWidth: 40
                Layout.fillHeight: true
                Layout.fillWidth: false
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    anchors {
                        left: parent.left
                        right: parent.right
                        rightMargin: 5
                        top: parent.top
                        topMargin: 6
                    }
                    spacing: 0

                    Repeater {
                        model: root.displayContent.split("\n").length
                        Text {
                            required property int index
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            horizontalAlignment: Text.AlignRight
                            text: index + 1
                        }
                    }
                }
            }

            Rectangle { // Code background
                Layout.fillWidth: true
                color: Appearance.colors.colLayer2
                implicitHeight: jsonScrollView.implicitHeight

                ScrollView {
                    id: jsonScrollView
                    anchors.left: parent.left
                    anchors.right: parent.right
                    implicitHeight: jsonTextArea.implicitHeight + 1
                    contentWidth: jsonTextArea.width - 1
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                    ScrollBar.horizontal: ScrollBar {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        padding: 5
                        policy: ScrollBar.AsNeeded
                        opacity: visualSize == 1 ? 0 : 1
                        visible: opacity > 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }

                        contentItem: Rectangle {
                            implicitHeight: 6
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2Active
                        }
                    }

                    TextArea {
                        id: jsonTextArea
                        readOnly: true
                        selectByMouse: true
                        renderType: Text.NativeRendering
                        font.family: Appearance.font.family.monospace
                        font.hintingPreference: Font.PreferNoHinting
                        font.pixelSize: Appearance.font.pixelSize.small
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        color: Appearance.colors.colOnLayer1
                        text: root.displayContent

                        SyntaxHighlighter {
                            id: jsonHighlighter
                            textEdit: jsonTextArea
                            repository: Repository
                            definition: Repository.definitionForName("json")
                            theme: Appearance.syntaxHighlightingTheme
                        }
                    }
                }
            }
        }
    }

    // Plain text component
    Component {
        id: plainTextComponent

        ScrollView {
            Layout.fillWidth: true
            implicitHeight: plainTextArea.implicitHeight + 1
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff

            ScrollBar.horizontal: ScrollBar {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                padding: 5
                policy: ScrollBar.AsNeeded
                opacity: visualSize == 1 ? 0 : 1
                visible: opacity > 0

                contentItem: Rectangle {
                    implicitHeight: 6
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2Active
                }
            }

            TextArea {
                id: plainTextArea
                readOnly: true
                selectByMouse: true
                renderType: Text.NativeRendering
                font.family: Appearance.font.family.monospace
                font.hintingPreference: Font.PreferNoHinting
                font.pixelSize: Appearance.font.pixelSize.small
                selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                selectionColor: Appearance.colors.colSecondaryContainer
                color: Appearance.colors.colOnLayer1
                wrapMode: TextEdit.Wrap
                text: root.displayContent
            }
        }
    }
}
