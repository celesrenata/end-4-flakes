pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Renders Graphviz DOT diagrams inline as SVG images.
 * Detects ```dot or ```graphviz code fences, pipes through `dot -Tsvg`,
 * and displays the result as an Image.
 */
ColumnLayout {
    id: root
    property bool editing: parent?.editing ?? false
    property bool renderMarkdown: parent?.renderMarkdown ?? true
    property bool enableMouseSelection: parent?.enableMouseSelection ?? false
    property var segmentContent: parent?.segmentContent ?? ""
    property var segmentLang: parent?.segmentLang ?? "dot"
    property var messageData: parent?.messageData ?? {}
    property bool done: parent?.done ?? true

    property string svgPath: ""
    property bool rendering: false
    property bool renderError: false
    property string errorText: ""

    property real diagramRounding: Appearance.rounding.small

    spacing: 2
    anchors.left: parent.left
    anchors.right: parent.right

    Component.onCompleted: {
        if (segmentContent && segmentContent.length > 0) {
            root.renderDiagram();
        }
    }

    onSegmentContentChanged: {
        if (segmentContent && segmentContent.length > 0 && root.done) {
            root.renderDiagram();
        }
    }

    onDoneChanged: {
        if (done && segmentContent && segmentContent.length > 0 && !svgPath) {
            root.renderDiagram();
        }
    }

    function renderDiagram() {
        root.rendering = true;
        root.renderError = false;
        root.errorText = "";
        // Generate unique filename based on content hash
        let hash = Qt.md5(segmentContent);
        let outPath = "/tmp/quickshell-diagrams/" + hash + ".svg";
        root.svgPath = outPath;
        dotProcess.command = ["bash", "-c",
            "mkdir -p /tmp/quickshell-diagrams && echo '" +
            StringUtils.shellSingleQuoteEscape(segmentContent) +
            "' | dot -Tsvg -o '" + outPath + "' 2>&1 && echo SUCCESS || echo FAILED"
        ];
        dotProcess.running = true;
    }

    Process {
        id: dotProcess
        stdout: SplitParser {
            onRead: data => {
                if (data.trim() === "SUCCESS") {
                    root.rendering = false;
                    root.renderError = false;
                    // Force image reload by toggling source
                    diagramImage.source = "";
                    diagramImage.source = "file://" + root.svgPath;
                } else if (data.trim() === "FAILED") {
                    root.rendering = false;
                    root.renderError = true;
                } else if (data.trim().length > 0 && root.errorText.length === 0) {
                    root.errorText = data.trim();
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.rendering = false;
                root.renderError = true;
                if (!root.errorText) root.errorText = "dot process exited with code " + exitCode;
            }
        }
    }

    // Header bar
    Rectangle {
        Layout.fillWidth: true
        topLeftRadius: diagramRounding
        topRightRadius: diagramRounding
        bottomLeftRadius: Appearance.rounding.unsharpen
        bottomRightRadius: Appearance.rounding.unsharpen
        color: Appearance.colors.colSurfaceContainerHighest
        implicitHeight: headerRow.implicitHeight + 6

        RowLayout {
            id: headerRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 10
            anchors.rightMargin: 3
            spacing: 5

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
                text: "schema"
            }

            StyledText {
                Layout.fillWidth: false
                Layout.topMargin: 7
                Layout.bottomMargin: 7
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                text: "Diagram"
            }

            Item { Layout.fillWidth: true }

            ButtonGroup {
                AiMessageControlButton {
                    id: copyButton
                    buttonIcon: activated ? "inventory" : "content_copy"
                    onClicked: {
                        Quickshell.clipboardText = segmentContent;
                        copyButton.activated = true;
                        copyTimer.restart();
                    }
                    Timer {
                        id: copyTimer
                        interval: 1500
                        repeat: false
                        onTriggered: copyButton.activated = false
                    }
                    StyledToolTip { content: Translation.tr("Copy source") }
                }
            }
        }
    }

    // Diagram display area
    Rectangle {
        Layout.fillWidth: true
        topLeftRadius: Appearance.rounding.unsharpen
        topRightRadius: Appearance.rounding.unsharpen
        bottomLeftRadius: diagramRounding
        bottomRightRadius: diagramRounding
        color: Appearance.colors.colLayer2
        implicitHeight: Math.max(60, diagramImage.implicitHeight + 20)

        // Loading state
        BusyIndicator {
            anchors.centerIn: parent
            running: root.rendering
            visible: root.rendering
        }

        // Error state
        ColumnLayout {
            anchors.centerIn: parent
            visible: root.renderError
            spacing: 4

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: "⚠ " + Translation.tr("Diagram render failed")
                color: Appearance.m3colors.m3error
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: root.errorText.length > 0
                text: root.errorText
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                Layout.maximumWidth: parent.parent.width - 40
                wrapMode: Text.Wrap
            }
        }

        // SVG image
        Image {
            id: diagramImage
            anchors.centerIn: parent
            anchors.margins: 10
            width: Math.min(implicitWidth, parent.width - 20)
            fillMode: Image.PreserveAspectFit
            visible: !root.rendering && !root.renderError && source.toString().length > 0
            asynchronous: true
            cache: false
        }
    }
}
