import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell

Rectangle {
    id: root
    property int messageIndex
    property string messageId: ""
    property var messageData
    property var messageInputField

    property real messagePadding: 7
    property real contentSpacing: 3

    property bool enableMouseSelection: false
    property bool renderMarkdown: true
    property bool editing: false

    property list<var> messageBlocks: StringUtils.splitMarkdownBlocks(root.messageData?.content ?? "")

    // Detect tool output messages (should render minimally, like thinking)
    property bool isToolOutput: (root.messageData?.functionResponse ?? "").length > 0 && root.messageData?.role === "user"

    // MCP tool block detection: show a tool block when message has an MCP function result or is pending
    property bool showRawOutput: false
    property bool hasMcpToolBlock: (root.messageData?.functionName ?? "").startsWith("mcp_") &&
        ((root.messageData?.functionPending ?? false) || (root.messageData?.functionResponse ?? "").length > 0)
    property real toolBlockStartTime: root.messageData?.functionPending ? Date.now() : 0

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: columnLayout.implicitHeight + root.messagePadding * 2

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    function saveMessage() {
        if (!root.editing) return;
        // Get all Loader children (each represents a segment)
        const segments = messageContentColumnLayout.children
            .map(child => child.segment)
            .filter(segment => (segment));

        // Reconstruct markdown
        const newContent = segments.map(segment => {
            if (segment.type === "code") {
                const lang = segment.lang ? segment.lang : "";
                // Remove trailing newlines
                const code = segment.content.replace(/\n+$/, "");
                return "```" + lang + "\n" + code + "\n```";
            } else {
                return segment.content;
            }
        }).join("");

        root.editing = false
        root.messageData.content = newContent;
    }

    Keys.onPressed: (event) => {
        if ( // Prevent de-select
            event.key === Qt.Key_Control || 
            event.key == Qt.Key_Shift || 
            event.key == Qt.Key_Alt || 
            event.key == Qt.Key_Meta
        ) {
            event.accepted = true
        }
        // Ctrl + S to save
        if ((event.key === Qt.Key_S) && event.modifiers == Qt.ControlModifier) {
            root.saveMessage();
            event.accepted = true;
        }
    }

    ColumnLayout { // Main layout of the whole thing
        id: columnLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: messagePadding
        spacing: root.contentSpacing
        
        RowLayout { // Header
            visible: !root.isToolOutput
            spacing: 15
            Layout.fillWidth: true

            Rectangle { // Name
                id: nameWrapper
                color: Appearance.colors.colSecondaryContainer
                // color: "transparent"
                radius: Appearance.rounding.small
                implicitHeight: Math.max(nameRowLayout.implicitHeight + 5 * 2, 30)
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                RowLayout {
                    id: nameRowLayout
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 7

                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillHeight: true
                        implicitWidth: messageData?.role == 'assistant' ? modelIcon.width : roleIcon.implicitWidth
                        implicitHeight: messageData?.role == 'assistant' ? modelIcon.height : roleIcon.implicitHeight

                        CustomIcon {
                            id: modelIcon
                            anchors.centerIn: parent
                            visible: messageData?.role == 'assistant' && Ai.models[messageData?.model].icon
                            width: Appearance.font.pixelSize.large
                            height: Appearance.font.pixelSize.large
                            source: messageData?.role == 'assistant' ? Ai.models[messageData?.model].icon :
                                messageData?.role == 'user' ? 'linux-symbolic' : 'desktop-symbolic'

                            colorize: true
                            color: Appearance.m3colors.m3onSecondaryContainer
                        }

                        MaterialSymbol {
                            id: roleIcon
                            anchors.centerIn: parent
                            visible: !modelIcon.visible
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.m3colors.m3onSecondaryContainer
                            text: messageData?.role == 'user' ? 'person' : 
                                messageData?.role == 'interface' ? 'settings' : 
                                messageData?.role == 'assistant' ? 'neurology' : 
                                'computer'
                        }
                    }

                    StyledText {
                        id: providerName
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.m3colors.m3onSecondaryContainer
                        text: messageData?.role == 'assistant' ? (Ai.models[messageData?.model] ? Ai.models[messageData?.model].name : (messageData?.model || "Assistant")) :
                            (messageData?.role == 'user' && SystemInfo.username) ? SystemInfo.username :
                            (Ai.models[Ai.currentModelId] ? Ai.models[Ai.currentModelId].name : Ai.currentModelId)
                    }
                }
            }

            Button { // Not visible to model
                id: modelVisibilityIndicator
                visible: messageData?.role == 'interface'
                implicitWidth: 16
                implicitHeight: 30
                Layout.alignment: Qt.AlignVCenter

                background: Item

                MaterialSymbol {
                    id: notVisibleToModelText
                    anchors.centerIn: parent
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    text: "visibility_off"
                }
                StyledToolTip {
                    content: Translation.tr("Not visible to model")
                }
            }

            ButtonGroup {
                spacing: 5

                AiMessageControlButton {
                    id: copyButton
                    buttonIcon: activated ? "inventory" : "content_copy"

                    onClicked: {
                        // Copy without thinking blocks
                        const content = root.messageData?.content ?? "";
                        Quickshell.clipboardText = content.replace(/<think>[\s\S]*?<\/think>/g, "").trim();
                        copyButton.activated = true
                        copyIconTimer.restart()
                    }

                    Timer {
                        id: copyIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: {
                            copyButton.activated = false
                        }
                    }
                    
                    StyledToolTip {
                        content: Translation.tr("Copy")
                    }
                }
                AiMessageControlButton {
                    id: copyFullButton
                    visible: (root.messageData?.content ?? "").indexOf("<think>") !== -1
                    buttonIcon: activated ? "inventory" : "copy_all"

                    onClicked: {
                        Quickshell.clipboardText = root.messageData?.content ?? ""
                        copyFullButton.activated = true
                        copyFullIconTimer.restart()
                    }

                    Timer {
                        id: copyFullIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: {
                            copyFullButton.activated = false
                        }
                    }

                    StyledToolTip {
                        content: Translation.tr("Copy with thinking")
                    }
                }
                AiMessageControlButton {
                    id: viewOutputButton
                    visible: (root.messageData?.functionResponse ?? "").length > 0
                    buttonIcon: "terminal"
                    activated: root.showRawOutput

                    onClicked: {
                        root.showRawOutput = !root.showRawOutput
                    }

                    StyledToolTip {
                        content: root.showRawOutput ? Translation.tr("Hide console output") : Translation.tr("View console output")
                    }
                }
                AiMessageControlButton {
                    id: editButton
                    activated: root.editing
                    enabled: root.messageData?.done ?? false
                    buttonIcon: "edit"
                    onClicked: {
                        root.editing = !root.editing
                        if (!root.editing) { // Save changes
                            root.saveMessage()
                        }
                    }
                    StyledToolTip {
                        content: root.editing ? Translation.tr("Save") : Translation.tr("Edit")
                    }
                }
                AiMessageControlButton {
                    id: toggleMarkdownButton
                    activated: !root.renderMarkdown
                    buttonIcon: "code"
                    onClicked: {
                        root.renderMarkdown = !root.renderMarkdown
                    }
                    StyledToolTip {
                        content: Translation.tr("View Markdown source")
                    }
                }
                AiMessageControlButton {
                    id: retryButton
                    visible: root.messageData?.role === "user" && (root.messageData?.done ?? false)
                    buttonIcon: "refresh"

                    property bool spinning: false

                    onClicked: {
                        retryButton.spinning = true;
                        // Remove everything after this user message and re-request
                        const allIds = Ai.messageIDs;
                        let myIdx = allIds.indexOf(root.messageId);
                        if (myIdx < 0) myIdx = allIds.indexOf(Number(root.messageId));
                        if (myIdx < 0) {
                            // Fallback: search by reference
                            for (let i = 0; i < allIds.length; i++) {
                                if (String(allIds[i]) === String(root.messageId)) { myIdx = i; break; }
                            }
                        }
                        if (myIdx >= 0) {
                            // Remove all messages after this one
                            const toRemove = allIds.slice(myIdx + 1);
                            for (const id of toRemove) { delete Ai.messageByID[id]; }
                            Ai.messageIDs = allIds.slice(0, myIdx + 1);
                            Ai._emptyResponseRetries = 0;
                            Ai._emptyCommandRetries = 0;
                            Ai.makeRequest();
                        }
                    }

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        text: "refresh"
                        color: retryButton.enabled ? Appearance.m3colors.m3onSurface :
                            Appearance.colors.colOnLayer1Inactive

                        RotationAnimation on rotation {
                            running: retryButton.spinning
                            from: 0
                            to: 360
                            duration: 800
                            loops: Animation.Infinite
                        }
                    }

                    StyledToolTip {
                        content: Translation.tr("Retry")
                    }
                }
                AiMessageControlButton {
                    id: deleteButton
                    buttonIcon: "close"
                    onClicked: {
                        Ai.removeMessage(root.messageId)
                    }
                    StyledToolTip {
                        content: Translation.tr("Delete")
                    }
                }
            }
        }

        ColumnLayout { // Message content
            id: messageContentColumnLayout

            spacing: 0

            // Attached image thumbnails (Context Lens integration)
            Flow {
                visible: (root.messageData?.images?.length ?? 0) > 0
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                spacing: 5

                Repeater {
                    model: root.messageData?.images?.length ?? 0
                    delegate: Rectangle {
                        required property int index
                        width: 120
                        height: 90
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: (root.messageData?.images?.[index] ?? "").length > 0
                                ? ("data:image/png;base64," + root.messageData.images[index])
                                : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                imageViewPopup.imageSource = "data:image/png;base64," + root.messageData.images[index];
                                imageViewPopup.visible = true;
                            }
                        }
                    }
                }
            }

            // File-based attachments (images show thumbnails, others show chips)
            Flow {
                visible: (root.messageData?.attachments?.length ?? 0) > 0
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                spacing: 5

                Repeater {
                    model: root.messageData?.attachments?.length ?? 0
                    delegate: Rectangle {
                        required property int index
                        property var attachment: root.messageData?.attachments?.[index] ?? {}
                        property bool isImage: (attachment.type || "").startsWith("image/")
                        property string absPath: Directories.aiAttachments + "/" + (attachment.path || "")

                        width: isImage ? 120 : attachChipLayout.implicitWidth + 16
                        height: isImage ? 90 : 32
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2
                        clip: true

                        // Image thumbnail for image attachments
                        Image {
                            visible: parent.isImage
                            anchors.fill: parent
                            source: parent.isImage ? "file://" + parent.absPath : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                        // Chip layout for non-image attachments
                        RowLayout {
                            id: attachChipLayout
                            visible: !parent.isImage
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                text: {
                                    var type = parent.parent.attachment.type || ""
                                    if (type === "application/pdf") return "picture_as_pdf"
                                    if (type.startsWith("audio/")) return "audio_file"
                                    if (type.startsWith("video/")) return "video_file"
                                    if (type.startsWith("text/")) return "description"
                                    return "attach_file"
                                }
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                text: {
                                    var name = parent.parent.attachment.name || "file"
                                    return name.length > 18 ? name.substring(0, 15) + "..." : name
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }

                            // Download button
                            MouseArea {
                                implicitWidth: 18
                                implicitHeight: 18
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var att = parent.parent.attachment
                                    Ai.downloadAttachment(att.path, att.name)
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "download"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: Appearance.m3colors.m3primary
                                }
                            }
                        }

                        // Click to open file (xdg-open)
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Ai.openAttachment(parent.attachment.path)
                            }
                        }
                    }
                }
            }

            // MCP Tool Result Block — rendered when message carries an MCP function response or is pending
            MessageToolBlock {
                visible: root.hasMcpToolBlock
                Layout.fillWidth: true
                toolName: root.messageData?.functionName ?? ""
                content: root.messageData?.functionResponse ?? ""
                isError: (root.messageData?.functionResponse ?? "").startsWith("MCP tool error:") ||
                         (root.messageData?.functionResponse ?? "").startsWith("Error:")
                pending: root.messageData?.functionPending ?? false
                startTime: root.toolBlockStartTime
                messageData: root.messageData
            }

            Repeater {
                model: root.isToolOutput ? 0 : root.messageBlocks.length
                delegate: Loader {
                    required property int index
                    property var thisBlock: root.messageBlocks[index]
                    Layout.fillWidth: true
                    // property var segment: thisBlock
                    property var segmentContent: thisBlock.content
                    property var segmentLang: thisBlock.lang
                    property var messageData: root.messageData
                    property var editing: root.editing
                    property var renderMarkdown: root.renderMarkdown
                    property var enableMouseSelection: root.enableMouseSelection
                    property bool thinking: root.messageData?.thinking ?? true
                    property bool done: root.messageData?.done ?? false
                    property bool completed: thisBlock.completed ?? false
                    
                    source: thisBlock.type === "code" && (thisBlock.lang === "dot" || thisBlock.lang === "graphviz" || thisBlock.lang === "mermaid") ? "MessageDiagramBlock.qml" :
                        thisBlock.type === "code" ? "MessageCodeBlock.qml" : 
                        thisBlock.type === "think" ? "MessageThinkBlock.qml" :
                        "MessageTextBlock.qml"

                }
            }
            // Raw console output panel — toggle via terminal button
            Rectangle {
                visible: root.showRawOutput && (root.messageData?.functionResponse ?? "").length > 0
                Layout.fillWidth: true
                implicitHeight: rawOutputColumn.implicitHeight
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                clip: true

                ColumnLayout {
                    id: rawOutputColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 0

                    // Header
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: rawOutputHeaderRow.implicitHeight + 6
                        color: Appearance.colors.colSurfaceContainerHighest

                        RowLayout {
                            id: rawOutputHeaderRow
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            MaterialSymbol {
                                text: "terminal"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                text: Translation.tr("Console Output")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                            }

                            Item { Layout.fillWidth: true }

                            // Copy raw output button
                            RippleButton {
                                implicitWidth: 22
                                implicitHeight: 22
                                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active

                                onClicked: {
                                    Quickshell.clipboardText = root.messageData?.functionResponse ?? ""
                                }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "content_copy"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer2
                                }
                            }
                        }
                    }

                    // Output content
                    ScrollView {
                        Layout.fillWidth: true
                        implicitHeight: Math.min(rawOutputText.implicitHeight + 8, 400)
                        clip: true

                        ScrollBar.horizontal.policy: ScrollBar.AsNeeded

                        TextArea {
                            id: rawOutputText
                            readOnly: true
                            selectByMouse: true
                            renderType: Text.NativeRendering
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                            wrapMode: TextEdit.Wrap
                            text: root.messageData?.functionResponse ?? ""
                        }
                    }
                }
            }

        }

        Flow { // Annotations
            visible: root.messageData?.annotationSources?.length > 0
            spacing: 5
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.annotationSources || []
                }
                delegate: AnnotationSourceButton {
                    required property var modelData
                    displayText: modelData.text
                    url: modelData.url
                }
            }
        }

        Flow { // Search queries
            visible: root.messageData?.searchQueries?.length > 0
            spacing: 5
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.searchQueries || []
                }
                delegate: SearchQueryButton {
                    required property var modelData
                    query: modelData
                }
            }
        }

    }

    // Full-image view popup overlay
    Rectangle {
        id: imageViewPopup
        property string imageSource: ""
        visible: false
        anchors.fill: parent
        color: "#cc000000"
        z: 100

        MouseArea {
            anchors.fill: parent
            onClicked: imageViewPopup.visible = false
        }

        Image {
            anchors.centerIn: parent
            width: Math.min(parent.width - 20, sourceSize.width)
            height: Math.min(parent.height - 20, sourceSize.height)
            source: imageViewPopup.imageSource
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
    }
}