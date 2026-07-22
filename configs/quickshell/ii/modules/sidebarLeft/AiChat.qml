import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "./aiChat/"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

Item {
    id: root
    property var inputField: messageInputField
    property string commandPrefix: "/"

    property var suggestionQuery: ""
    property var suggestionList: []

    onFocusChanged: (focus) => {
        if (focus) {
            root.inputField.forceActiveFocus()
        }
    }

    Keys.onPressed: (event) => {
        messageInputField.forceActiveFocus()
        if (event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageUp) {
                messageListView.contentY = Math.max(0, messageListView.contentY - messageListView.height / 2)
                event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
                messageListView.contentY = Math.min(messageListView.contentHeight - messageListView.height / 2, messageListView.contentY + messageListView.height / 2)
                event.accepted = true
            }
        }
    }

    property var allCommands: [
        {
            name: "model",
            description: Translation.tr("Choose model"),
            execute: (args) => {
                Ai.setModel(args[0]);
            }
        },
        {
            name: "tool",
            description: Translation.tr("Set the tool to use for the model."),
            execute: (args) => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.addMessage(Translation.tr("Usage: %1tool TOOL_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                } else {
                    const tool = args[0];
                    const switched = Ai.setTool(tool);
                    if (switched) {
                        Ai.addMessage(Translation.tr("Tool set to: %1").arg(tool), Ai.interfaceRole);
                    }
                }
            }
        },
        {
            name: "prompt",
            description: Translation.tr("Set the system prompt for the model."),
            execute: (args) => {
                if (args.length === 0 || args[0] === "get") {
                    Ai.printPrompt();
                    return;
                }
                Ai.loadPrompt(args.join(" ").trim());
            }
        },
        {
            name: "key",
            description: Translation.tr("Set API key"),
            execute: (args) => {
                if (args[0] == "get") {
                    Ai.printApiKey()
                } else {
                    Ai.setApiKey(args[0]);
                }
            }
        },
        {
            name: "save",
            description: Translation.tr("Save chat"),
            execute: (args) => {
                const joinedArgs = args.join(" ")
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1save CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.saveChat(joinedArgs)
            }
        },
        {
            name: "load",
            description: Translation.tr("Load chat"),
            execute: (args) => {
                const joinedArgs = args.join(" ")
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1load CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.loadChat(joinedArgs)
            }
        },
        {
            name: "clear",
            description: Translation.tr("Clear chat history"),
            execute: () => {
                Ai.clearMessages();
            }
        },
        {
            name: "temp",
            description: Translation.tr("Set temperature (randomness) of the model. Values range between 0 to 2 for Gemini, 0 to 1 for other models. Default is 0.5."),
            execute: (args) => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.printTemperature()
                } else {
                    const temp = parseFloat(args[0]);
                    Ai.setTemperature(temp);
                }
            }
        },
        {
            name: "compact",
            description: Translation.tr("Compact conversation history into a summary to free context space"),
            execute: (args) => {
                const focus = args.join(" ").trim();
                Ai.compactChat(focus);
            }
        },
        {
            name: "new",
            description: Translation.tr("Create a new chat session"),
            execute: (args) => {
                const name = args.join(" ").trim();
                Ai.newSession(name);
            }
        },
        {
            name: "switch",
            description: Translation.tr("Switch to a named chat session"),
            execute: (args) => {
                const name = args.join(" ").trim();
                if (name.length === 0) {
                    Ai.addMessage(Translation.tr("Usage: %1switch SESSION_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.switchSession(name);
            }
        },
        {
            name: "list",
            description: Translation.tr("List all chat sessions"),
            execute: () => {
                const sessions = Ai.listSessions();
                if (sessions.length === 0) {
                    Ai.addMessage(Translation.tr("No sessions found."), Ai.interfaceRole);
                    return;
                }
                const lines = sessions.map(s => {
                    const date = new Date((s.lastModified || 0) * 1000);
                    const timestamp = date.toLocaleString();
                    const active = s.name === Ai.activeSessionName ? " *(active)*" : "";
                    return `- **${s.name}**${active} — last modified: ${timestamp}`;
                });
                Ai.addMessage(Translation.tr("**Chat Sessions:**\n") + lines.join("\n"), Ai.interfaceRole);
            }
        },
        {
            name: "delete",
            description: Translation.tr("Delete a chat session"),
            execute: (args) => {
                const name = args.join(" ").trim();
                if (name.length === 0) {
                    Ai.addMessage(Translation.tr("Usage: %1delete SESSION_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.deleteSession(name);
            }
        },
        {
            name: "test",
            description: Translation.tr("Markdown test"),
            execute: () => {
                Ai.addMessage(`
<think>
A longer think block to test revealing animation
OwO wem ipsum dowo sit amet, consekituwet awipiscing ewit, sed do eiuwsmod tempow inwididunt ut wabowe et dowo mawa. Ut enim ad minim weniam, quis nostwud exeucitation uwuwamcow bowowis nisi ut awiquip ex ea commowo consequat. Duuis aute iwuwe dowo in wepwependewit in wowuptate velit esse ciwwum dowo eu fugiat nuwa pawiatuw. Excepteuw sint occaecat cupidatat non pwowoident, sunt in cuwpa qui officia desewunt mowit anim id est wabowum. Meouw! >w<
Mowe uwu wem ipsum!
</think>
## ✏️ Markdown test
### Formatting

- *Italic*, \`Monospace\`, **Bold**, [Link](https://example.com)
- Arch lincox icon <img src="${Quickshell.shellPath("assets/icons/arch-symbolic.svg")}" height="${Appearance.font.pixelSize.small}"/>

### Table

Quickshell vs AGS/Astal

|                          | Quickshell       | AGS/Astal         |
|--------------------------|------------------|-------------------|
| UI Toolkit               | Qt               | Gtk3/Gtk4         |
| Language                 | QML              | Js/Ts/Lua         |
| Reactivity               | Implied          | Needs declaration |
| Widget placement         | Mildly difficult | More intuitive    |
| Bluetooth & Wifi support | ❌               | ✅                |
| No-delay keybinds        | ✅               | ❌                |
| Development              | New APIs         | New syntax        |

### Code block

Just a hello world...

\`\`\`cpp
#include <bits/stdc++.h>
// This is intentionally very long to test scrolling
const std::string GREETING = \"UwU\";
int main(int argc, char* argv[]) {
    std::cout << GREETING;
}
\`\`\`

### LaTeX


Inline w/ dollar signs: $\\frac{1}{2} = \\frac{2}{4}$

Inline w/ double dollar signs: $$\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}$$

Inline w/ backslash and square brackets \\[\\int_0^\\infty \\frac{1}{x^2} dx = \\infty\\]

Inline w/ backslash and round brackets \\(e^{i\\pi} + 1 = 0\\)
`, 
                    Ai.interfaceRole);
            }
        },
    ]

    function handleInput(inputText) {
        if (inputText.startsWith(root.commandPrefix)) {
            // Handle special commands
            const command = inputText.split(" ")[0].substring(1);
            const args = inputText.split(" ").slice(1);
            const commandObj = root.allCommands.find(cmd => cmd.name === `${command}`);
            if (commandObj) {
                commandObj.execute(args);
            } else {
                Ai.addMessage(Translation.tr("Unknown command: ") + command, Ai.interfaceRole);
            }
        }
        else {
            Ai.sendUserMessage(inputText);
        }
    }

    component StatusItem: MouseArea {
        id: statusItem
        property string icon
        property string statusText
        property string description
        hoverEnabled: true
        implicitHeight: statusItemRowLayout.implicitHeight
        implicitWidth: statusItemRowLayout.implicitWidth

        RowLayout {
            id: statusItemRowLayout
            spacing: 0
            MaterialSymbol {
                text: statusItem.icon
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colSubtext
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                text: statusItem.statusText
                color: Appearance.colors.colSubtext
            }
        }

        StyledToolTip {
            content: statusItem.description
            extraVisibleCondition: false
            alternativeVisibleCondition: statusItem.containsMouse
        }
    }

    component StatusSeparator: Rectangle {
        implicitWidth: 4
        implicitHeight: 4
        radius: implicitWidth / 2
        color: Appearance.colors.colOutlineVariant
    }

    // Whether the session drawer is open
    property bool sessionDrawerOpen: false

    // Close the drawer when the active session changes (e.g. after a switch)
    Connections {
        target: Ai
        function onActiveSessionNameChanged() {
            root.sessionDrawerOpen = false
        }
    }

    Connections {
        target: DictationService
        function onTranscriptionComplete(text) {
            // Append transcribed text at cursor position (or end if no focus)
            var existing = messageInputField.text
            var pos = messageInputField.cursorPosition
            var before = existing.substring(0, pos)
            var after = existing.substring(pos)
            var separator = (before.length > 0 && !before.endsWith(" ")) ? " " : ""
            messageInputField.text = before + separator + text + after
            messageInputField.cursorPosition = (before + separator + text).length
            messageInputField.forceActiveFocus()
        }
    }

    component ContextIndicator: RowLayout {
        id: contextIndicator
        spacing: 4

        readonly property real usage: Ai.contextUsageRatio
        readonly property color indicatorColor: usage > 0.9 ? Appearance.m3colors.m3error
                                              : usage > 0.7 ? Appearance.m3colors.m3tertiary
                                              : Appearance.colors.colSubtext

        // Session name — clickable chip that toggles the drawer
        MouseArea {
            id: sessionChipArea
            hoverEnabled: true
            implicitWidth: sessionChipRow.implicitWidth + 10
            implicitHeight: sessionChipRow.implicitHeight + 4
            cursorShape: Qt.PointingHandCursor
            onClicked: root.sessionDrawerOpen = !root.sessionDrawerOpen

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: sessionChipArea.containsMouse
                    ? Qt.alpha(Appearance.m3colors.m3secondaryContainer, 0.6)
                    : (root.sessionDrawerOpen ? Qt.alpha(Appearance.m3colors.m3secondaryContainer, 0.9) : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            RowLayout {
                id: sessionChipRow
                anchors.centerIn: parent
                spacing: 3
                MaterialSymbol {
                    text: root.sessionDrawerOpen ? "expand_less" : "chat"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    text: Ai.activeSessionName
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }

        // Separator dot between session name and context usage
        Rectangle {
            visible: Ai.contextUsageRatio > 0 || Ai.compacting
            implicitWidth: 3
            implicitHeight: 3
            radius: implicitWidth / 2
            color: Appearance.colors.colOutlineVariant
        }

        // Context usage pill
        RowLayout {
            visible: Ai.contextUsageRatio > 0 || Ai.compacting
            spacing: 4

            // Progress bar segment
            Rectangle {
                visible: !Ai.compacting
                implicitWidth: 36
                implicitHeight: 4
                radius: implicitHeight / 2
                color: Appearance.colors.colOutlineVariant

                Rectangle {
                    width: Math.min(parent.width, parent.width * contextIndicator.usage)
                    height: parent.height
                    radius: parent.radius
                    color: contextIndicator.indicatorColor

                    Behavior on width {
                        NumberAnimation {
                            duration: Appearance.animation.elementMove.duration
                            easing.type: Appearance.animation.elementMove.type
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMove.duration
                        }
                    }
                }
            }

            // Percentage text or "Compacting..." label
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Ai.compacting ? Appearance.m3colors.m3tertiary : contextIndicator.indicatorColor
                text: Ai.compacting
                    ? Translation.tr("Compacting…")
                    : Translation.tr("%1%").arg(Math.round(contextIndicator.usage * 100))
            }
        }
    }

    ColumnLayout {
        id: columnLayout
        anchors.fill: parent

        RowLayout { // Status
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            StatusItem {
                icon: Ai.currentModelHasApiKey ? "key" : "key_off"
                statusText: ""
                description: Ai.currentModelHasApiKey ? Translation.tr("API key is set\nChange with /key YOUR_API_KEY") : Translation.tr("No API key\nSet it with /key YOUR_API_KEY")
            }
            StatusSeparator {}
            StatusItem {
                icon: "device_thermostat"
                statusText: Ai.temperature.toFixed(1)
                description: Translation.tr("Temperature\nChange with /temp VALUE")
            }
            StatusSeparator {
                visible: Ai.tokenCount.total > 0
            }
            StatusItem {
                visible: Ai.tokenCount.total > 0
                icon: "token"
                statusText: Ai.tokenCount.total
                description: Translation.tr("Total token count\nInput: %1\nOutput: %2")
                    .arg(Ai.tokenCount.input)
                    .arg(Ai.tokenCount.output)
            }
            StatusSeparator {}
            ContextIndicator {}
        }

        // Session drawer — collapsible panel showing all sessions
        Rectangle {
            id: sessionDrawer
            Layout.fillWidth: true
            visible: root.sessionDrawerOpen
            clip: true
            implicitHeight: root.sessionDrawerOpen ? sessionDrawerColumn.implicitHeight + 12 : 0
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            border.color: Appearance.colors.colOutlineVariant
            border.width: 1

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                }
            }

            // Track which session is being renamed
            property string renamingSession: ""
            property string renameText: ""

            ColumnLayout {
                id: sessionDrawerColumn
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 6
                    leftMargin: 8
                    rightMargin: 8
                    bottomMargin: 6
                }
                spacing: 2

                // Header row: "+ New session" button
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        text: Translation.tr("Sessions")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colSubtext
                        Layout.fillWidth: true
                    }

                    // New session button
                    RippleButton {
                        implicitHeight: 26
                        implicitWidth: 26
                        buttonRadius: 13
                        colBackground: "transparent"
                        colBackgroundHover: Qt.alpha(Appearance.m3colors.m3onSurface, 0.08)

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "add"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.m3colors.m3primary
                        }

                        StyledToolTip {
                            content: Translation.tr("New session")
                            extraVisibleCondition: false
                            alternativeVisibleCondition: parent.hovered
                        }

                        onClicked: {
                            Ai.newSession("")
                            sessionDrawer.renamingSession = Ai.activeSessionName
                            sessionDrawer.renameText = Ai.activeSessionName
                        }
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.5
                }

                // Session list
                Repeater {
                    model: ScriptModel {
                        values: Ai.listSessions()
                    }
                    delegate: Item {
                        id: sessionRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 36

                        readonly property bool isActive: modelData.name === Ai.activeSessionName
                        readonly property bool isRenaming: sessionDrawer.renamingSession === modelData.name
                        readonly property bool hovered: sessionRowHover.containsMouse

                        // Hover/active background
                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            color: sessionRow.isActive
                                ? Qt.alpha(Appearance.m3colors.m3secondaryContainer, 0.5)
                                : (sessionRow.hovered ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.06) : "transparent")
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }

                        // Full-row hover detection (underneath everything)
                        MouseArea {
                            id: sessionRowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: sessionRow.isRenaming ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: {
                                if (!sessionRow.isRenaming) {
                                    if (!sessionRow.isActive) {
                                        Ai.switchSession(modelData.name)
                                    }
                                    root.sessionDrawerOpen = false
                                }
                            }
                            onDoubleClicked: {
                                sessionDrawer.renamingSession = sessionRow.modelData.name
                                sessionDrawer.renameText = sessionRow.modelData.name
                            }
                        }

                        RowLayout {
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 8
                                rightMargin: 4
                            }
                            spacing: 6

                            // Active indicator dot
                            Rectangle {
                                implicitWidth: 6
                                implicitHeight: 6
                                radius: 3
                                color: Appearance.m3colors.m3primary
                                visible: sessionRow.isActive
                            }
                            Item {
                                implicitWidth: 6
                                implicitHeight: 6
                                visible: !sessionRow.isActive
                            }

                            // Session name — text when idle, TextInput when renaming
                            Loader {
                                id: nameLoader
                                Layout.fillWidth: true
                                sourceComponent: sessionRow.isRenaming ? renameFieldComponent : nameLabelComponent

                                Component {
                                    id: nameLabelComponent
                                    StyledText {
                                        text: sessionRow.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: sessionRow.isActive ? Font.Medium : Font.Normal
                                        color: sessionRow.isActive
                                            ? Appearance.m3colors.m3onSecondaryContainer
                                            : Appearance.m3colors.m3onSurface
                                        elide: Text.ElideRight
                                    }
                                }

                                Component {
                                    id: renameFieldComponent
                                    TextField {
                                        text: sessionDrawer.renameText
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.m3colors.m3onSurface
                                        background: Rectangle {
                                            color: Qt.alpha(Appearance.m3colors.m3onSurface, 0.06)
                                            radius: 4
                                        }
                                        leftPadding: 4
                                        rightPadding: 4
                                        topPadding: 2
                                        bottomPadding: 2
                                        onTextChanged: sessionDrawer.renameText = text

                                        Component.onCompleted: {
                                            forceActiveFocus()
                                            selectAll()
                                        }

                                        Keys.onReturnPressed: commitRename()
                                        Keys.onEscapePressed: {
                                            sessionDrawer.renamingSession = ""
                                        }

                                        function commitRename() {
                                            const oldName = sessionDrawer.renamingSession
                                            const newName = sessionDrawer.renameText.trim()
                                            if (newName.length > 0 && newName !== oldName) {
                                                Ai.renameSession(oldName, newName)
                                            }
                                            sessionDrawer.renamingSession = ""
                                        }
                                    }
                                }
                            }

                            // Action buttons — fade in on hover or when active (no layout shift)
                            RowLayout {
                                spacing: 0
                                opacity: (sessionRow.hovered || sessionRow.isActive) ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: 80 }
                                }

                                // Rename button
                                RippleButton {
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    buttonRadius: 11
                                    colBackground: "transparent"
                                    colBackgroundHover: Qt.alpha(Appearance.m3colors.m3onSurface, 0.08)
                                    visible: !sessionRow.isRenaming

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "edit"
                                        iconSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colSubtext
                                    }

                                    onClicked: {
                                        sessionDrawer.renamingSession = sessionRow.modelData.name
                                        sessionDrawer.renameText = sessionRow.modelData.name
                                    }
                                }

                                // Confirm rename button (shown while renaming)
                                RippleButton {
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    buttonRadius: 11
                                    colBackground: "transparent"
                                    colBackgroundHover: Qt.alpha(Appearance.m3colors.m3onSurface, 0.08)
                                    visible: sessionRow.isRenaming

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "check"
                                        iconSize: Appearance.font.pixelSize.small
                                        color: Appearance.m3colors.m3primary
                                    }

                                    onClicked: {
                                        // Trigger commit via the TextField's function
                                        if (nameLoader.item && nameLoader.item.commitRename)
                                            nameLoader.item.commitRename()
                                    }
                                }

                                // Delete button (only for non-active, non-protected sessions)
                                RippleButton {
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    buttonRadius: 11
                                    colBackground: "transparent"
                                    colBackgroundHover: Qt.alpha(Appearance.m3colors.m3error, 0.12)
                                    visible: !sessionRow.isActive && !sessionRow.isRenaming && sessionRow.modelData.name !== "Free Dictation"

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "delete"
                                        iconSize: Appearance.font.pixelSize.small
                                        color: Appearance.m3colors.m3error
                                    }

                                    onClicked: Ai.deleteSession(sessionRow.modelData.name)
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { // Messages
            Layout.fillWidth: true
            Layout.fillHeight: true
            StyledListView { // Message list
                id: messageListView
                anchors.fill: parent
                spacing: 10
                popin: false
                verticalLayoutDirection: ListView.BottomToTop

                property int lastResponseLength: 0

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                add: null // Prevent function calls from being janky

                Behavior on contentY {
                    NumberAnimation {
                        id: scrollAnim
                        duration: Appearance.animation.scroll.duration
                        easing.type: Appearance.animation.scroll.type
                        easing.bezierCurve: Appearance.animation.scroll.bezierCurve
                    }
                }

                model: ScriptModel {
                    values: Ai.messageIDs.filter(id => {
                        const message = Ai.messageByID[id];
                        return message?.visibleToUser ?? true;
                    })
                }
                delegate: AiMessage {
                    required property var modelData
                    required property int index
                    messageIndex: index
                    messageData: {
                        Ai.messageByID[modelData]
                    }
                    messageInputField: root.inputField
                }
            }

            Item { // Placeholder when list is empty
                opacity: Ai.messageIDs.length === 0 ? 1 : 0
                visible: opacity > 0
                anchors.fill: parent

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 5

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        iconSize: 60
                        color: Appearance.m3colors.m3outline
                        text: "neurology"
                    }
                    StyledText {
                        id: widgetNameText
                        Layout.alignment: Qt.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.family: Appearance.font.family.title
                        color: Appearance.m3colors.m3outline
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Large language models")
                    }
                    StyledText {
                        id: widgetDescriptionText
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3outline
                        horizontalAlignment: Text.AlignLeft
                        wrapMode: Text.Wrap
                        text: Translation.tr("Type /key to get started with online models\nCtrl+O to expand the sidebar\nCtrl+P to detach sidebar into a window")
                    }
                }
            }
        }

        DescriptionBox {
            text: root.suggestionList[suggestions.selectedIndex]?.description ?? ""
            showArrows: root.suggestionList.length > 1
        }

        FlowButtonGroup { // Suggestions
            id: suggestions
            visible: root.suggestionList.length > 0 && messageInputField.text.length > 0
            property int selectedIndex: 0
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                id: suggestionRepeater
                model: {
                    suggestions.selectedIndex = 0
                    return root.suggestionList.slice(0, 10)
                }
                delegate: ApiCommandButton {
                    id: commandButton
                    colBackground: suggestions.selectedIndex === index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                    bounce: false
                    contentItem: StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.displayName ?? modelData.name
                    }

                    onHoveredChanged: {
                        if (commandButton.hovered) {
                            suggestions.selectedIndex = index;
                        }
                    }
                    onClicked: {
                        suggestions.acceptSuggestion(modelData.name)
                    }
                }
            }

            function acceptSuggestion(word) {
                const words = messageInputField.text.trim().split(/\s+/);
                if (words.length > 0) {
                    words[words.length - 1] = word;
                } else {
                    words.push(word);
                }
                const updatedText = words.join(" ") + " ";
                messageInputField.text = updatedText;
                messageInputField.cursorPosition = messageInputField.text.length;
                messageInputField.forceActiveFocus();
            }

            function acceptSelectedWord() {
                if (suggestions.selectedIndex >= 0 && suggestions.selectedIndex < suggestionRepeater.count) {
                    const word = root.suggestionList[suggestions.selectedIndex].name;
                    suggestions.acceptSuggestion(word);
                }
            }
        }

        // AutoCompactNotification banner
        Rectangle {
            id: autoCompactBanner
            visible: Ai.autoCompactShown && !Ai.autoCompactDismissed
            Layout.fillWidth: true
            implicitHeight: visible ? autoCompactBannerRow.implicitHeight + 12 : 0
            radius: Appearance.rounding.small
            color: Appearance.m3colors.m3tertiaryContainer

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            RowLayout {
                id: autoCompactBannerRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 10
                    rightMargin: 6
                }
                spacing: 6

                MaterialSymbol {
                    text: "info"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.m3colors.m3onTertiaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.m3colors.m3onTertiaryContainer
                    text: Translation.tr("Context is getting full. Consider compacting.")
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                ApiCommandButton {
                    buttonText: Translation.tr("Compact")
                    colBackground: Appearance.m3colors.m3tertiary
                    colBackgroundHover: Qt.darker(Appearance.m3colors.m3tertiary, 1.1)
                    colBackgroundActive: Qt.darker(Appearance.m3colors.m3tertiary, 1.2)
                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onTertiary
                        text: Translation.tr("Compact")
                    }
                    onClicked: {
                        Ai.compactChat("")
                    }
                }

                RippleButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Qt.alpha(Appearance.m3colors.m3onTertiaryContainer, 0.12)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.m3colors.m3onTertiaryContainer
                    }

                    onClicked: {
                        Ai.autoCompactDismissed = true
                    }
                }
            }
        }

        Item { // Input area wrapper (holds normal input + context-full overlay)
            id: inputAreaWrapper
            Layout.fillWidth: true
            implicitHeight: Ai.contextFull ? contextFullOverlay.implicitHeight : inputWrapper.implicitHeight

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

        Rectangle { // Input area
            id: inputWrapper
            property real columnSpacing: 5
            anchors.left: parent.left
            anchors.right: parent.right
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            implicitHeight: Math.max(inputFieldRowLayout.implicitHeight + inputFieldRowLayout.anchors.topMargin 
                + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + columnSpacing, 45)
            clip: true
            border.color: Appearance.colors.colOutlineVariant
            border.width: 1

            // Hide normal input content when context is full
            opacity: Ai.contextFull ? 0 : 1
            visible: !Ai.contextFull

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            RowLayout { // Input field and send button
                id: inputFieldRowLayout
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 5
                spacing: 0

                StyledTextArea { // The actual TextArea
                    id: messageInputField
                    wrapMode: TextArea.Wrap
                    Layout.fillWidth: true
                    padding: 10
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    placeholderText: Translation.tr('Message the model... "%1" for commands').arg(root.commandPrefix)

                    background: null

                    onTextChanged: { // Handle suggestions
                        if (messageInputField.text.length === 0) {
                            root.suggestionQuery = ""
                            root.suggestionList = []
                            return
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}model`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] ?? ""
                            const modelResults = Fuzzy.go(root.suggestionQuery, Ai.modelList.map(model => {
                                return {
                                    name: Fuzzy.prepare(model),
                                    obj: model,
                                }
                            }), {
                                all: true,
                                key: "name"
                            })
                            root.suggestionList = modelResults.map(model => {
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "model ") : ""}${model.target}`,
                                    displayName: `${Ai.models[model.target].name}`,
                                    description: `${Ai.models[model.target].description}`,
                                }
                            })
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}prompt`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] ?? ""
                            const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.promptFiles.map(file => {
                                return {
                                    name: Fuzzy.prepare(file),
                                    obj: file,
                                }
                            }), {
                                all: true,
                                key: "name"
                            })
                            root.suggestionList = promptFileResults.map(file => {
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "prompt ") : ""}${file.target}`,
                                    displayName: `${FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target))}`,
                                    description: Translation.tr("Load prompt from %1").arg(file.target),
                                }
                            })
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}save`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] ?? ""
                            const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                return {
                                    name: Fuzzy.prepare(file),
                                    obj: file,
                                }
                            }), {
                                all: true,
                                key: "name"
                            })
                            root.suggestionList = promptFileResults.map(file => {
                                const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim()
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "save ") : ""}${chatName}`,
                                    displayName: `${chatName}`,
                                    description: Translation.tr("Save chat to %1").arg(chatName),
                                }
                            })
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}load`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] ?? ""
                            const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                return {
                                    name: Fuzzy.prepare(file),
                                    obj: file,
                                }
                            }), {
                                all: true,
                                key: "name"
                            })
                            root.suggestionList = promptFileResults.map(file => {
                                const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim()
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "load ") : ""}${chatName}`,
                                    displayName: `${chatName}`,
                                    description: Translation.tr(`Load chat from %1`).arg(file.target),
                                }
                            })
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}tool`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] ?? ""
                            const toolResults = Fuzzy.go(root.suggestionQuery, Ai.availableTools.map(tool => {
                                return {
                                    name: Fuzzy.prepare(tool),
                                    obj: tool,
                                }
                            }), {
                                all: true,
                                key: "name"
                            })
                            root.suggestionList = toolResults.map(tool => {
                                const toolName = tool.target
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "tool ") : ""}${tool.target}`,
                                    displayName: toolName,
                                    description: Ai.toolDescriptions[toolName],
                                }
                            })
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}switch`)) {
                            root.suggestionQuery = messageInputField.text.split(" ").slice(1).join(" ") ?? ""
                            const sessions = Ai.listSessions();
                            const sessionResults = Fuzzy.go(root.suggestionQuery, sessions.map(s => {
                                return {
                                    name: Fuzzy.prepare(s.name),
                                    obj: s,
                                }
                            }), {
                                all: true,
                                key: "name"
                            })
                            root.suggestionList = sessionResults.map(s => {
                                const session = s.obj;
                                const date = new Date((session.lastModified || 0) * 1000);
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "switch ") : ""}${session.name}`,
                                    displayName: session.name,
                                    description: Translation.tr("Switch to session \"%1\" (last modified: %2)").arg(session.name).arg(date.toLocaleString()),
                                }
                            })
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}delete`)) {
                            root.suggestionQuery = messageInputField.text.split(" ").slice(1).join(" ") ?? ""
                            const sessions = Ai.listSessions();
                            const sessionResults = Fuzzy.go(root.suggestionQuery, sessions.map(s => {
                                return {
                                    name: Fuzzy.prepare(s.name),
                                    obj: s,
                                }
                            }), {
                                all: true,
                                key: "name"
                            })
                            root.suggestionList = sessionResults.map(s => {
                                const session = s.obj;
                                const date = new Date((session.lastModified || 0) * 1000);
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "delete ") : ""}${session.name}`,
                                    displayName: session.name,
                                    description: Translation.tr("Delete session \"%1\" (last modified: %2)").arg(session.name).arg(date.toLocaleString()),
                                }
                            })
                        } else if(messageInputField.text.startsWith(root.commandPrefix)) {
                            root.suggestionQuery = messageInputField.text
                            root.suggestionList = root.allCommands.filter(cmd => cmd.name.startsWith(messageInputField.text.substring(1))).map(cmd => {
                                return {
                                    name: `${root.commandPrefix}${cmd.name}`,
                                    description: `${cmd.description}`,
                                }
                            })
                        }
                    }

                    function accept() {
                        root.handleInput(text)
                        text = ""
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Tab) {
                            suggestions.acceptSelectedWord();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up && suggestions.visible) {
                            suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down && suggestions.visible) {
                            suggestions.selectedIndex = Math.min(root.suggestionList.length - 1, suggestions.selectedIndex + 1);
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                            if (event.modifiers & Qt.ShiftModifier) {
                                // Insert newline
                                messageInputField.insert(messageInputField.cursorPosition, "\n")
                                event.accepted = true
                            } else { // Accept text
                                const inputText = messageInputField.text
                                messageInputField.clear()
                                root.handleInput(inputText)
                                event.accepted = true
                            }
                        }
                    }
                }

                RippleButton { // Mic/dictation button
                    id: micButton
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small
                    visible: Config.options.dictation.enabled
                    toggled: DictationService.state !== DictationService.State.Idle

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (DictationService.state === DictationService.State.Idle) {
                                DictationService.activate()
                            } else {
                                DictationService.stopRecording()
                            }
                        }
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        color: micButton.toggled ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                        text: micButton.toggled ? "stop" : "mic"
                    }
                }

                RippleButton { // Send button
                    id: sendButton
                    Layout.alignment: Qt.AlignTop
                    Layout.rightMargin: 5
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small
                    enabled: messageInputField.text.length > 0
                    toggled: enabled

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: sendButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const inputText = messageInputField.text
                            root.handleInput(inputText)
                            messageInputField.clear()
                        }
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        // fill: sendButton.enabled ? 1 : 0
                        color: sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                        text: "send"
                    }
                }
            }

            RowLayout { // Controls
                id: commandButtonsRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                anchors.leftMargin: 10
                anchors.rightMargin: 5
                spacing: 4

                property var commandsShown: [
                    {
                        name: "",
                        sendDirectly: false,
                        dontAddSpace: true,
                    }, 
                    {
                        name: "clear",
                        sendDirectly: true,
                    }, 
                ]

                ApiInputBoxIndicator { // Model indicator
                    icon: "api"
                    text: Ai.currentModelName
                    tooltipText: Translation.tr("Current model: %1\nSet it with %2model MODEL")
                        .arg(Ai.currentModelName)
                        .arg(root.commandPrefix)
                }

                ApiInputBoxIndicator { // Tool indicator
                    icon: "service_toolbox"
                    text: Ai.currentTool.charAt(0).toUpperCase() + Ai.currentTool.slice(1)
                    tooltipText: Translation.tr("Current tool: %1\nSet it with %2tool TOOL")
                        .arg(Ai.currentTool)
                        .arg(root.commandPrefix)
                }

                Item { Layout.fillWidth: true }

                ButtonGroup { // Command buttons
                    padding: 0

                    Repeater { // Command buttons
                        model: commandButtonsRow.commandsShown
                        delegate: ApiCommandButton {
                            property string commandRepresentation: `${root.commandPrefix}${modelData.name}`
                            buttonText: commandRepresentation
                            onClicked: {
                                if(modelData.sendDirectly) {
                                    root.handleInput(commandRepresentation)
                                } else {
                                    messageInputField.text = commandRepresentation + (modelData.dontAddSpace ? "" : " ")
                                    messageInputField.cursorPosition = messageInputField.text.length
                                    messageInputField.forceActiveFocus()
                                }
                                if (modelData.name === "clear") {
                                    messageInputField.text = ""
                                }
                            }
                        }
                    }
                }
            }

        } // end inputWrapper

        Rectangle { // Context-full overlay
            id: contextFullOverlay
            anchors.left: parent.left
            anchors.right: parent.right
            visible: Ai.contextFull
            opacity: Ai.contextFull ? 1 : 0
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            border.color: Appearance.m3colors.m3error
            border.width: 1
            implicitHeight: contextFullColumn.implicitHeight + 20

            Behavior on opacity {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }

            ColumnLayout {
                id: contextFullColumn
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                spacing: 8

                // Title row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialSymbol {
                        text: "warning"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.m3colors.m3error
                    }
                    StyledText {
                        text: Translation.tr("Context window full")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.m3colors.m3error
                        Layout.fillWidth: true
                    }
                }

                // Model suggestions (only shown when largerContextModels is non-empty)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: Ai.largerContextModels.length > 0

                    StyledText {
                        text: Translation.tr("Switch to a model with a larger context window:")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: Ai.largerContextModels
                            delegate: ApiCommandButton {
                                required property string modelData
                                bounce: false
                                colBackground: Appearance.colors.colSecondaryContainer
                                contentItem: StyledText {
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.m3colors.m3onSurface
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Ai.models[modelData]?.name ?? modelData
                                }
                                onClicked: Ai.switchToModel(modelData)
                            }
                        }
                    }
                }

                // Compact section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Or compact the conversation to free up space:")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: compactFocusInput.implicitHeight + 8
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2
                            border.color: Appearance.colors.colOutlineVariant
                            border.width: 1

                            StyledTextArea {
                                id: compactFocusInput
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                padding: 6
                                wrapMode: TextArea.Wrap
                                background: null
                                placeholderText: Translation.tr("Optional: focus instructions (e.g. keep the code examples)")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                            }
                        }

                        RippleButton {
                            id: compactButton
                            implicitHeight: 34
                            implicitWidth: 90
                            buttonRadius: Appearance.rounding.small
                            enabled: !Ai.compacting
                            toggled: enabled

                            contentItem: RowLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    text: "compress"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: compactButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                                }
                                StyledText {
                                    text: Ai.compacting ? Translation.tr("Compacting…") : Translation.tr("Compact")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: compactButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: compactButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (compactButton.enabled) {
                                        Ai.compactChat(compactFocusInput.text.trim())
                                        compactFocusInput.clear()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } // end contextFullOverlay

        } // end inputAreaWrapper
        
    }

}