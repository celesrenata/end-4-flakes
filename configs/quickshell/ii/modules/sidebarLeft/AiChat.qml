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
import Quickshell.Io

Item {
    id: root
    property var inputField: messageInputField
    property string commandPrefix: "/"
    property bool searchOpen: false

    property var suggestionQuery: ""
    property var suggestionList: []

    onFocusChanged: (focus) => {
        if (focus) {
            root.inputField.forceActiveFocus()
        }
    }

    property bool _scrollToMatchActive: false
    property int highlightedMessageIndex: -1

    // URL detection state — stores detected URLs from the last user message
    property var lastDetectedUrls: []

    // Detect URLs in text matching https://, http://, www. prefixes (max 2048 chars)
    function detectUrls(text) {
        const regex = /(?:https?:\/\/|www\.)[^\s<>"']{1,2048}/gi;
        const matches = [];
        let match;
        while ((match = regex.exec(text)) !== null) {
            matches.push({ url: match[0], start: match.index, end: match.index + match[0].length });
        }
        return matches;
    }

    // Handle "Fetch with AI" — fetch URL content, truncate to 8000 chars, summarize
    function handleFetchUrl(url) {
        const promise = McpClient.callTool("mcp_fetch_fetch", { url: url, max_length: 8000 });
        promise.then(function(content) {
            // Truncate to 8000 characters
            const truncated = (typeof content === "string" && content.length > 8000)
                ? content.substring(0, 8000) : (content || "");
            // Add fetched content to conversation and instruct LLM to summarize
            Ai.sendUserMessage("Fetched content from " + url + ":\n\n" + truncated + "\n\nPlease summarize this content.");
            // Clear the chip for this URL
            root.lastDetectedUrls = root.lastDetectedUrls.filter(function(u) { return u.url !== url; });
        });
        promise.catch(function(err) {
            // Display error message and offer "Open in browser" fallback
            Ai.addMessage(
                Translation.tr("Failed to fetch %1: %2\n\nYou can try opening it in the browser instead.")
                    .arg(url).arg(err),
                Ai.interfaceRole
            );
        });
    }

    // Clipboard image type checker — runs wl-paste --list-types to see if clipboard has image
    Process {
        id: clipboardTypeChecker
        command: ["wl-paste", "--list-types"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var types = text.trim().split("\n")
                var hasImage = types.some(t => t.startsWith("image/"))
                if (hasImage) {
                    // Clipboard has an image — store it as attachment
                    Ai.storeClipboardImage(function(meta) {
                        Ai.addPendingAttachment(meta)
                    })
                }
            }
        }
    }

    // File picker via zenity (native file dialog)
    Process {
        id: filePickerProcess
        command: ["zenity", "--file-selection", "--multiple", "--separator=\n"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length === 0) return
                var files = text.trim().split("\n")
                for (var i = 0; i < files.length; i++) {
                    var filePath = files[i]
                    if (filePath.length === 0) continue
                    var fileName = filePath.split("/").pop()
                    var ext = fileName.split(".").pop().toLowerCase()
                    var mimeMap = {
                        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                        "gif": "image/gif", "webp": "image/webp", "svg": "image/svg+xml",
                        "pdf": "application/pdf", "txt": "text/plain", "md": "text/markdown",
                        "json": "application/json", "zip": "application/zip",
                        "tar": "application/x-tar", "gz": "application/gzip",
                        "mp3": "audio/mpeg", "wav": "audio/wav", "mp4": "video/mp4",
                        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    }
                    var mimeType = mimeMap[ext] || "application/octet-stream"
                    var meta = Ai.storeAttachment(filePath, fileName, mimeType)
                    Ai.addPendingAttachment(meta)
                }
            }
        }
    }

    property bool _needsInitialScroll: false

    onVisibleChanged: {
        if (visible) {
            if (root._scrollToMatchActive) {
                root._scrollToMatchActive = false
                return
            }
            // If layout is ready, snap immediately; otherwise flag for onContentHeightChanged
            if (messageListView.height > 0 && messageListView.contentHeight > 0) {
                scrollBehavior.enabled = false
                messageListView.contentY = 0
                scrollBehavior.enabled = true
            } else {
                root._needsInitialScroll = true
            }
        }
    }

    Timer {
        id: highlightResetTimer
        interval: 3000
        repeat: false
        onTriggered: root.highlightedMessageIndex = -1
    }

    Keys.onPressed: (event) => {
        // Close session drawer on any keypress
        if (root.sessionDrawerOpen) root.sessionDrawerOpen = false;
        // Only steal focus if no other text input currently has focus
        if (!messageInputField.activeFocus && !root.Window.activeFocusItem?.hasOwnProperty("text")) {
            messageInputField.forceActiveFocus()
        }
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
                Ai.purgeSession(Ai.activeSessionName);
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
            name: "tune",
            description: Translation.tr("Set per-model tuning. Usage: /tune [get|temp|reasoning|websearch|context|verbosity] [value]. Settings are saved per-model."),
            execute: (args) => {
                const modelId = Ai.currentModelId;
                const modelName = Ai.currentModelName;
                if (args.length == 0 || args[0] == "get") {
                    const tuning = Ai.getModelTuning();
                    let lines = [`**Model tuning for ${modelName}** (\`${modelId}\`):\n`];
                    lines.push(`- **Temperature**: ${tuning.temperature}`);
                    lines.push(`- **Reasoning effort**: ${tuning.reasoningEffort || "default (not set)"}`);
                    lines.push(`- **Web search**: ${tuning.webSearch ? "enabled" : "disabled"}`);
                    lines.push(`- **Search context size**: ${tuning.searchContextSize}`);
                    lines.push(`- **Verbosity**: ${tuning.verbosity || "default (not set)"}`);
                    Ai.addMessage(lines.join("\n"), Ai.interfaceRole);
                } else if (args[0] === "temp" || args[0] === "temperature") {
                    if (args.length < 2) {
                        Ai.addMessage(Translation.tr("Usage: /tune temp VALUE (0.0-2.0)"), Ai.interfaceRole);
                        return;
                    }
                    const val = parseFloat(args[1]);
                    if (isNaN(val) || val < 0 || val > 2) {
                        Ai.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole);
                        return;
                    }
                    Ai.setModelSetting(modelId, "temperature", val);
                    Ai.addMessage(Translation.tr("Set temperature to %1 for %2").arg(val).arg(modelName), Ai.interfaceRole);
                } else if (args[0] === "reasoning" || args[0] === "reason") {
                    const valid = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "off"];
                    if (args.length < 2 || valid.indexOf(args[1]) === -1) {
                        Ai.addMessage(Translation.tr("Usage: /tune reasoning [none|minimal|low|medium|high|xhigh|max|off]\n\n`off` clears the setting."), Ai.interfaceRole);
                        return;
                    }
                    const val = args[1] === "off" ? "" : args[1];
                    Ai.setModelSetting(modelId, "reasoningEffort", val);
                    Ai.addMessage(Translation.tr("Set reasoning effort to %1 for %2").arg(val || "default").arg(modelName), Ai.interfaceRole);
                } else if (args[0] === "websearch" || args[0] === "web") {
                    const valid = ["on", "off", "true", "false"];
                    if (args.length < 2 || valid.indexOf(args[1]) === -1) {
                        Ai.addMessage(Translation.tr("Usage: /tune websearch [on|off]"), Ai.interfaceRole);
                        return;
                    }
                    const val = args[1] === "on" || args[1] === "true";
                    Ai.setModelSetting(modelId, "webSearch", val);
                    Ai.addMessage(Translation.tr("Set web search to %1 for %2").arg(val ? "enabled" : "disabled").arg(modelName), Ai.interfaceRole);
                } else if (args[0] === "context" || args[0] === "searchcontext") {
                    const valid = ["low", "medium", "high"];
                    if (args.length < 2 || valid.indexOf(args[1]) === -1) {
                        Ai.addMessage(Translation.tr("Usage: /tune context [low|medium|high]"), Ai.interfaceRole);
                        return;
                    }
                    Ai.setModelSetting(modelId, "searchContextSize", args[1]);
                    Ai.addMessage(Translation.tr("Set search context size to %1 for %2").arg(args[1]).arg(modelName), Ai.interfaceRole);
                } else if (args[0] === "verbosity" || args[0] === "verbose") {
                    const valid = ["low", "medium", "high", "off"];
                    if (args.length < 2 || valid.indexOf(args[1]) === -1) {
                        Ai.addMessage(Translation.tr("Usage: /tune verbosity [low|medium|high|off]\n\n`off` clears the setting."), Ai.interfaceRole);
                        return;
                    }
                    const val = args[1] === "off" ? "" : args[1];
                    Ai.setModelSetting(modelId, "verbosity", val);
                    Ai.addMessage(Translation.tr("Set verbosity to %1 for %2").arg(val || "default").arg(modelName), Ai.interfaceRole);
                } else {
                    Ai.addMessage(Translation.tr("Unknown tuning option: %1\n\nAvailable: temp, reasoning, websearch, context, verbosity").arg(args[0]), Ai.interfaceRole);
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
            name: "summarize",
            description: Translation.tr("Summarize conversation into a new session"),
            execute: (args) => {
                Ai.summarizeToNewChat(args.join(" "));
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
            // Detect URLs in user message before sending
            const urls = root.detectUrls(inputText);
            if (urls.length > 0) {
                root.lastDetectedUrls = urls;
            } else {
                root.lastDetectedUrls = [];
            }

            // Use attachment-aware send if there are pending attachments
            if (Ai.pendingAttachments.length > 0) {
                Ai.sendUserMessageWithAttachments(inputText);
            } else {
                Ai.sendUserMessage(inputText);
            }
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

    // Delete confirmation state
    property string deleteConfirmSession: ""

    // Close the drawer when the active session changes (e.g. after a switch)
    Connections {
        target: Ai
        function onActiveSessionNameChanged() {
            root.sessionDrawerOpen = false
            root.searchOpen = false
            Ai.clearSearch()
        }
    }

    Connections {
        target: DictationService
        function onTranscriptionComplete(text) {
            if (!text || text.trim().length === 0) return;
            // Only route to ActionPalette if DictationService hasn't already done so
            // (DictationService._voiceAssistantPending is set by _processVoiceAssistant)
            if (DictationService._voiceAssistantPending) return;
            // Sidebar-open dictation: route to voice assistant
            DictationService._voiceAssistantPending = true
            Ai.appendToFreeDictation(text, "user")
            ActionPalette.submitQueryDirect(text, DictationService._voiceAssistantPrompt)
        }
    }

    // Auto-scroll to bottom when new messages arrive (only if near bottom)
    Connections {
        target: Ai
        function onMessageIDsChanged() {
            if (messageListView._shouldStickToBottom && !messageListView.userScrolling) {
                scrollBehavior.enabled = false;
                messageListView.positionViewAtBeginning();
                scrollBehavior.enabled = true;
            }
        }
    }

    // Suppress animations and prepare for session switch
    Connections {
        target: Ai
        function onSessionSwitchStarted() {
            root._needsInitialScroll = true
        }
        function onSessionSwitchCompleted() {
            // Snap to bottom immediately without animation
            scrollBehavior.enabled = false
            messageListView.contentY = 0
            scrollBehavior.enabled = true
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
                    : Ai.contextMeterText
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
                statusText: Ai.effectiveTemperature.toFixed(1)
                description: Translation.tr("Temperature\nChange with /temp VALUE or /tune temp VALUE")
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
            StatusSeparator {}
            RippleButton {
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: 14
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: {
                    root.searchOpen = !root.searchOpen
                    if (root.searchOpen) {
                        root.sessionDrawerOpen = false
                        Ai.maybeGenerateKeywords()
                    }
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "search"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.searchOpen ? Appearance.m3colors.m3primary : Appearance.m3colors.m3onSurface
                }
            }
            StatusSeparator {
                visible: Object.keys(McpClient.serverStates).length > 0
            }
            // MCP Server Status Indicators
            Flow {
                spacing: 4
                visible: Object.keys(McpClient.serverStates).length > 0
                Repeater {
                    model: Object.keys(McpClient.serverStates)
                    delegate: MouseArea {
                        id: mcpDot
                        required property int index
                        required property string modelData
                        width: 10
                        height: 10
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        // Flash states: "" = idle, "connecting" = yellow pulse, "success" = green, "failed" = red
                        property string flashState: ""

                        onClicked: {
                            const currentState = McpClient.serverStates[modelData];
                            console.warn("[MCP-UI] Clicked " + modelData + " state=" + currentState);
                            if (currentState === "connected") {
                                McpClient.setServerDisabled(modelData, true);
                            } else {
                                if (currentState === "disabled") {
                                    McpClient.setServerDisabled(modelData, false);
                                }
                                mcpDot.flashState = "connecting";
                                connectTimeoutTimer.restart();
                                McpClient.connectServer(modelData);
                            }
                        }

                        Connections {
                            target: McpClient
                            function onServerStateChanged(serverName, state) {
                                if (serverName !== mcpDot.modelData) return;
                                console.warn("[MCP-UI] " + serverName + " stateChanged → " + state + " (flashState=" + mcpDot.flashState + ")");
                                if (mcpDot.flashState !== "connecting") return;
                                // Only react to terminal states
                                if (state === "connected") {
                                    connectTimeoutTimer.stop();
                                    mcpDot.flashState = "success";
                                    fadeBackTimer.restart();
                                } else if (state === "error") {
                                    connectTimeoutTimer.stop();
                                    mcpDot.flashState = "failed";
                                    fadeBackTimer.restart();
                                }
                                // Ignore "connecting", "disconnected" — keep pulsing
                            }
                        }

                        // If no state change within 10s, mark as failed
                        Timer {
                            id: connectTimeoutTimer
                            interval: 10000
                            repeat: false
                            onTriggered: {
                                if (mcpDot.flashState === "connecting") {
                                    mcpDot.flashState = "failed";
                                    fadeBackTimer.restart();
                                }
                            }
                        }

                        // Hold green/red for 3s then fade back
                        Timer {
                            id: fadeBackTimer
                            interval: 3000
                            repeat: false
                            onTriggered: {
                                const finalState = McpClient.serverStates[mcpDot.modelData];
                                console.warn("[MCP-UI] " + mcpDot.modelData + " fadeBack: flashState=" + mcpDot.flashState + " → idle, serverState=" + finalState);
                                mcpDot.flashState = "";
                            }
                        }

                        Rectangle {
                            id: dotRect
                            anchors.fill: parent
                            radius: width / 2
                            color: {
                                switch (mcpDot.flashState) {
                                    case "connecting": return "#FFD700";
                                    case "success": return "#4CAF50";
                                    case "failed": return "#F44336";
                                    default: break;
                                }
                                const state = McpClient.serverStates[mcpDot.modelData];
                                switch (state) {
                                    case "connected": return Appearance.m3colors.m3primary;
                                    case "connecting": return Appearance.m3colors.m3tertiary;
                                    case "error": return Appearance.m3colors.m3error;
                                    case "disabled": return Appearance.m3colors.m3outlineVariant;
                                    default: return Appearance.m3colors.m3outline; // disconnected but enabled
                                }
                            }
                            opacity: {
                                if (mcpDot.flashState === "") {
                                    const state = McpClient.serverStates[mcpDot.modelData];
                                    if (state === "disabled") return 0.3;
                                    if (state === "connected") return 1.0;
                                    return 0.5; // disconnected, error, anything else
                                }
                                return 1.0;
                            }

                            Behavior on color { ColorAnimation { duration: 300 } }
                            Behavior on opacity { NumberAnimation { duration: 300 } }

                            SequentialAnimation {
                                id: pulseAnimation
                                running: mcpDot.flashState === "connecting"
                                loops: Animation.Infinite
                                NumberAnimation { target: dotRect; property: "opacity"; to: 0.3; duration: 400; easing.type: Easing.InOutSine }
                                NumberAnimation { target: dotRect; property: "opacity"; to: 1.0; duration: 400; easing.type: Easing.InOutSine }
                            }
                        }

                        StyledToolTip {
                            content: mcpDot.modelData + ": " + (McpClient.serverStates[mcpDot.modelData] || "unknown")
                            extraVisibleCondition: false
                            alternativeVisibleCondition: mcpDot.containsMouse
                        }
                    }
                }
            }
        }

        // Session drawer — collapsible panel showing all sessions
        Rectangle {
            id: sessionDrawer
            Layout.fillWidth: true
            visible: root.sessionDrawerOpen || closeAnim.running
            clip: true
            implicitHeight: root.sessionDrawerOpen ? sessionDrawerColumn.implicitHeight + 12 : 0
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            border.color: Appearance.colors.colOutlineVariant
            border.width: 1

            Behavior on implicitHeight {
                NumberAnimation {
                    id: closeAnim
                    duration: root.sessionDrawerOpen
                        ? Appearance.animation.elementMoveEnter.duration
                        : Appearance.animation.elementMoveExit.duration
                    easing.type: root.sessionDrawerOpen
                        ? Appearance.animation.elementMoveEnter.type
                        : Appearance.animation.elementMoveExit.type
                    easing.bezierCurve: root.sessionDrawerOpen
                        ? Appearance.animation.elementMoveEnter.bezierCurve
                        : Appearance.animation.elementMoveExit.bezierCurve
                }
            }

            // Track which session is being renamed
            property string renamingSession: ""
            property string renameText: ""

            // Track which session is being grouped
            property string groupingSession: ""
            property string groupText: ""

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

                // Session list (active — not archived)
                Repeater {
                    model: ScriptModel {
                        values: {
                            var sessions = Ai.listSessions();
                            var active = [];
                            for (var i = 0; i < sessions.length; i++) {
                                if (!sessions[i].archived) active.push(sessions[i]);
                            }
                            // Sort by group (alphabetical, case-insensitive), then by name asc
                            active.sort(function(a, b) {
                                var ga = (a.group || "").toLowerCase();
                                var gb = (b.group || "").toLowerCase();
                                if (ga < gb) return -1;
                                if (ga > gb) return 1;
                                var na = (a.name || "").toLowerCase();
                                var nb = (b.name || "").toLowerCase();
                                if (na < nb) return -1;
                                if (na > nb) return 1;
                                return 0;
                            });
                            return active;
                        }
                    }
                    delegate: ColumnLayout {
                        id: sessionDelegate
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0

                        // Group header (show when this is the first item in its group or group differs from previous)
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: groupHeaderText.implicitHeight + 6
                            color: "transparent"
                            visible: {
                                var grp = sessionDelegate.modelData.group || "";
                                if (grp.length === 0) return false;
                                if (sessionDelegate.index === 0) return true;
                                // Check if previous session has a different group
                                var sessions = Ai.listSessions();
                                var active = [];
                                for (var i = 0; i < sessions.length; i++) {
                                    if (!sessions[i].archived) active.push(sessions[i]);
                                }
                                active.sort(function(a, b) {
                                    var ga2 = (a.group || "").toLowerCase();
                                    var gb2 = (b.group || "").toLowerCase();
                                    if (ga2 < gb2) return -1;
                                    if (ga2 > gb2) return 1;
                                    return (b.lastModified || 0) - (a.lastModified || 0);
                                });
                                if (sessionDelegate.index > 0 && sessionDelegate.index < active.length) {
                                    return (active[sessionDelegate.index - 1].group || "") !== grp;
                                }
                                return false;
                            }

                            StyledText {
                                id: groupHeaderText
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: sessionDelegate.modelData.group || ""
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: Appearance.m3colors.m3primary
                            }
                        }

                        Item {
                            id: sessionRow
                            Layout.fillWidth: true
                            implicitHeight: Math.max(36, sessionRowContent.implicitHeight + 8)

                            readonly property bool isActive: sessionDelegate.modelData.name === Ai.activeSessionName
                            readonly property bool isRenaming: sessionDrawer.renamingSession === sessionDelegate.modelData.name
                            readonly property bool isProtected: sessionDelegate.modelData.name === "Free Dictation" || (sessionDelegate.modelData.protected === true)
                            readonly property bool hovered: sessionRowHover.containsMouse || sessionRowHoverHandler.hovered

                            // HoverHandler propagates through child items (fixes glyph disappearing)
                            HoverHandler {
                                id: sessionRowHoverHandler
                            }

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
                                            Ai.switchSession(sessionDelegate.modelData.name)
                                        }
                                        root.sessionDrawerOpen = false
                                    }
                                }
                                onDoubleClicked: {
                                    if (!sessionRow.isProtected) {
                                        sessionDrawer.renamingSession = sessionDelegate.modelData.name
                                        sessionDrawer.renameText = sessionDelegate.modelData.name
                                    }
                                }
                            }

                            RowLayout {
                                id: sessionRowContent
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
                                        ColumnLayout {
                                            spacing: 1
                                            // Title row with date/group tag — uses Flow to wrap when narrow
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                StyledText {
                                                    text: sessionDelegate.modelData.name
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: sessionRow.isActive ? Font.Medium : Font.Normal
                                                    color: sessionRow.isActive
                                                        ? Appearance.m3colors.m3onSecondaryContainer
                                                        : Appearance.m3colors.m3onSurface
                                                    elide: Text.ElideRight
                                                    width: Math.min(implicitWidth, parent.width)
                                                }

                                                // Date/group tag — right side, wraps to new line when narrow
                                                StyledText {
                                                    property int ts: sessionDelegate.modelData.lastModified || 0
                                                    property string groupText: sessionDelegate.modelData.group || ""
                                                    property string dateText: {
                                                        if (ts === 0) return ""
                                                        var now = Math.floor(Date.now() / 1000)
                                                        var diff = now - ts
                                                        if (diff < 60) return "now"
                                                        if (diff < 3600) return Math.floor(diff / 60) + "m"
                                                        if (diff < 86400) return Math.floor(diff / 3600) + "h"
                                                        if (diff < 604800) return Math.floor(diff / 86400) + "d"
                                                        return Math.floor(diff / 604800) + "w"
                                                    }
                                                    visible: dateText.length > 0 || groupText.length > 0
                                                    text: groupText.length > 0 ? groupText + " · " + dateText : dateText
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    color: Appearance.colors.colSubtext
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }

                                            // Subject/summary line
                                            StyledText {
                                                visible: (sessionDelegate.modelData.subject || "").length > 0
                                                text: sessionDelegate.modelData.subject || ""
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colSubtext
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }

                                    Component {
                                        id: renameFieldComponent
                                        ColumnLayout {
                                            spacing: 2
                                            TextField {
                                                id: renameField
                                                text: sessionDrawer.renameText
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                color: Appearance.m3colors.m3onSurface
                                                background: Rectangle {
                                                    color: Qt.alpha(Appearance.m3colors.m3onSurface, 0.06)
                                                    radius: 4
                                                    border.color: Ai.lastRenameError.length > 0 ? Appearance.m3colors.m3error : "transparent"
                                                    border.width: Ai.lastRenameError.length > 0 ? 1 : 0
                                                }
                                                leftPadding: 4
                                                rightPadding: 4
                                                topPadding: 2
                                                bottomPadding: 2
                                                Layout.fillWidth: true
                                                onTextChanged: {
                                                    sessionDrawer.renameText = text
                                                    Ai.lastRenameError = ""
                                                }

                                                Component.onCompleted: {
                                                    forceActiveFocus()
                                                    selectAll()
                                                }

                                                Keys.onReturnPressed: commitRename()
                                                Keys.onEscapePressed: {
                                                    Ai.lastRenameError = ""
                                                    sessionDrawer.renamingSession = ""
                                                }

                                                function commitRename() {
                                                    const oldName = sessionDrawer.renamingSession
                                                    const newName = sessionDrawer.renameText.trim()
                                                    if (newName.length > 0 && newName !== oldName) {
                                                        Ai.renameSession(oldName, newName)
                                                        // Only close rename mode if no error
                                                        if (Ai.lastRenameError.length === 0) {
                                                            sessionDrawer.renamingSession = ""
                                                        }
                                                    } else {
                                                        Ai.lastRenameError = ""
                                                        sessionDrawer.renamingSession = ""
                                                    }
                                                }
                                            }
                                            // Inline error text
                                            StyledText {
                                                visible: Ai.lastRenameError.length > 0 && sessionDrawer.renamingSession === sessionDelegate.modelData.name
                                                text: Ai.lastRenameError
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.m3colors.m3error
                                                wrapMode: Text.Wrap
                                                Layout.fillWidth: true
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

                                    // Purge button (all sessions)
                                    RippleButton {
                                        implicitWidth: 22
                                        implicitHeight: 22
                                        buttonRadius: 11
                                        colBackground: "transparent"
                                        colBackgroundHover: Qt.alpha(Appearance.m3colors.m3onSurface, 0.08)
                                        visible: !sessionRow.isRenaming

                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "delete_sweep"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colSubtext
                                        }

                                        StyledToolTip {
                                            content: Translation.tr("Purge messages")
                                            extraVisibleCondition: false
                                            alternativeVisibleCondition: parent.hovered
                                        }

                                        onClicked: Ai.purgeSession(sessionDelegate.modelData.name)
                                    }

                                    // Rename button (not for Free Dictation / protected)
                                    RippleButton {
                                        implicitWidth: 22
                                        implicitHeight: 22
                                        buttonRadius: 11
                                        colBackground: "transparent"
                                        colBackgroundHover: Qt.alpha(Appearance.m3colors.m3onSurface, 0.08)
                                        visible: !sessionRow.isRenaming && !sessionRow.isProtected

                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "edit"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colSubtext
                                        }

                                        StyledToolTip {
                                            content: Translation.tr("Rename")
                                            extraVisibleCondition: false
                                            alternativeVisibleCondition: parent.hovered
                                        }

                                        onClicked: {
                                            sessionDrawer.renamingSession = sessionDelegate.modelData.name
                                            sessionDrawer.renameText = sessionDelegate.modelData.name
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
                                            if (nameLoader.item) {
                                                var field = nameLoader.item.children ? nameLoader.item.children[0] : nameLoader.item;
                                                if (field && field.commitRename) field.commitRename();
                                            }
                                        }
                                    }

                                    // Group button — assign session to a group
                                    RippleButton {
                                        implicitWidth: 22
                                        implicitHeight: 22
                                        buttonRadius: 11
                                        colBackground: "transparent"
                                        colBackgroundHover: Qt.alpha(Appearance.m3colors.m3onSurface, 0.08)
                                        visible: !sessionRow.isRenaming

                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "folder"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colSubtext
                                        }

                                        StyledToolTip {
                                            content: Translation.tr("Set group")
                                            extraVisibleCondition: false
                                            alternativeVisibleCondition: parent.hovered
                                        }

                                        onClicked: {
                                            sessionDrawer.groupingSession = sessionDelegate.modelData.name
                                            sessionDrawer.groupText = sessionDelegate.modelData.group || ""
                                        }
                                    }

                                    // Archive button
                                    RippleButton {
                                        implicitWidth: 22
                                        implicitHeight: 22
                                        buttonRadius: 11
                                        colBackground: "transparent"
                                        colBackgroundHover: Qt.alpha(Appearance.m3colors.m3onSurface, 0.08)
                                        visible: !sessionRow.isRenaming && !sessionRow.isActive

                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "archive"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colSubtext
                                        }

                                        StyledToolTip {
                                            content: Translation.tr("Archive")
                                            extraVisibleCondition: false
                                            alternativeVisibleCondition: parent.hovered
                                        }

                                        onClicked: Ai.archiveSession(sessionDelegate.modelData.name)
                                    }

                                    // Delete button (not for protected sessions)
                                    RippleButton {
                                        implicitWidth: 22
                                        implicitHeight: 22
                                        buttonRadius: 11
                                        colBackground: "transparent"
                                        colBackgroundHover: Qt.alpha(Appearance.m3colors.m3error, 0.12)
                                        visible: !sessionRow.isRenaming && !sessionRow.isProtected

                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "delete"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.m3colors.m3error
                                        }

                                        StyledToolTip {
                                            content: Translation.tr("Delete")
                                            extraVisibleCondition: false
                                            alternativeVisibleCondition: parent.hovered
                                        }

                                        onClicked: root.deleteConfirmSession = sessionDelegate.modelData.name
                                    }
                                }
                            }
                        }
                    }
                }

                // Archived sessions — collapsible section
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.5
                    visible: archivedRepeater.count > 0
                }

                // Archived header (toggle)
                MouseArea {
                    id: archivedHeaderArea
                    Layout.fillWidth: true
                    implicitHeight: archivedHeaderRow.implicitHeight + 4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    visible: archivedRepeater.count > 0

                    property bool expanded: false
                    onClicked: expanded = !expanded

                    RowLayout {
                        id: archivedHeaderRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 8
                        spacing: 4

                        MaterialSymbol {
                            text: archivedHeaderArea.expanded ? "expand_less" : "expand_more"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: Translation.tr("Archived (%1)").arg(archivedRepeater.count)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            Layout.fillWidth: true
                        }
                    }
                }

                // Archived session list
                Repeater {
                    id: archivedRepeater
                    model: ScriptModel {
                        values: {
                            var sessions = Ai.listSessions();
                            var archived = [];
                            for (var i = 0; i < sessions.length; i++) {
                                if (sessions[i].archived) archived.push(sessions[i]);
                            }
                            archived.sort(function(a, b) {
                                return (b.lastModified || 0) - (a.lastModified || 0);
                            });
                            return archived;
                        }
                    }
                    delegate: Item {
                        id: archivedRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 32
                        visible: archivedHeaderArea.expanded

                        readonly property bool hovered: archivedRowHover.containsMouse

                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            color: archivedRow.hovered ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.06) : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }

                        MouseArea {
                            id: archivedRowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Ai.unarchiveSession(archivedRow.modelData.name)
                                Ai.switchSession(archivedRow.modelData.name)
                                root.sessionDrawerOpen = false
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

                            MaterialSymbol {
                                text: "inventory_2"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    text: archivedRow.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                StyledText {
                                    visible: (archivedRow.modelData.subject || "").length > 0
                                    text: archivedRow.modelData.subject || ""
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOutlineVariant
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            // Unarchive button
                            RippleButton {
                                implicitWidth: 22
                                implicitHeight: 22
                                buttonRadius: 11
                                colBackground: "transparent"
                                colBackgroundHover: Qt.alpha(Appearance.m3colors.m3onSurface, 0.08)
                                opacity: archivedRow.hovered ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 80 } }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "unarchive"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }

                                StyledToolTip {
                                    content: Translation.tr("Unarchive")
                                    extraVisibleCondition: false
                                    alternativeVisibleCondition: parent.hovered
                                }

                                onClicked: Ai.unarchiveSession(archivedRow.modelData.name)
                            }

                            // Delete archived session
                            RippleButton {
                                implicitWidth: 22
                                implicitHeight: 22
                                buttonRadius: 11
                                colBackground: "transparent"
                                colBackgroundHover: Qt.alpha(Appearance.m3colors.m3error, 0.12)
                                opacity: archivedRow.hovered ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 80 } }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "delete"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: Appearance.m3colors.m3error
                                }

                                onClicked: root.deleteConfirmSession = archivedRow.modelData.name
                            }
                        }
                    }
                }

                // Delete confirmation banner (shown inline when delete is requested)
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.deleteConfirmSession.length > 0
                    implicitHeight: visible ? deleteConfirmRow.implicitHeight + 12 : 0
                    radius: Appearance.rounding.small
                    color: Qt.alpha(Appearance.m3colors.m3errorContainer, 0.8)
                    border.color: Appearance.m3colors.m3error
                    border.width: 1

                    RowLayout {
                        id: deleteConfirmRow
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 8
                            rightMargin: 6
                        }
                        spacing: 6

                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3onErrorContainer
                            text: Translation.tr("Delete \"%1\"?").arg(root.deleteConfirmSession)
                            elide: Text.ElideRight
                        }

                        ApiCommandButton {
                            bounce: false
                            colBackground: Appearance.m3colors.m3error
                            colBackgroundHover: Qt.darker(Appearance.m3colors.m3error, 1.1)
                            contentItem: StyledText {
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.m3colors.m3onError
                                text: Translation.tr("Delete")
                            }
                            onClicked: {
                                Ai.deleteSession(root.deleteConfirmSession)
                                root.deleteConfirmSession = ""
                            }
                        }

                        RippleButton {
                            implicitWidth: 24
                            implicitHeight: 24
                            buttonRadius: 12
                            colBackground: "transparent"
                            colBackgroundHover: Qt.alpha(Appearance.m3colors.m3onErrorContainer, 0.12)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.m3colors.m3onErrorContainer
                            }
                            onClicked: root.deleteConfirmSession = ""
                        }
                    }
                }

                // Group assignment banner (shown inline when group button is clicked)
                Rectangle {
                    Layout.fillWidth: true
                    visible: sessionDrawer.groupingSession.length > 0
                    implicitHeight: visible ? groupBannerColumn.implicitHeight + 12 : 0
                    radius: Appearance.rounding.small
                    color: Qt.alpha(Appearance.m3colors.m3secondaryContainer, 0.8)
                    border.color: Appearance.m3colors.m3secondary
                    border.width: 1

                    ColumnLayout {
                        id: groupBannerColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 8
                            rightMargin: 6
                        }
                        spacing: 6

                        RowLayout {
                            id: groupInputRow
                            Layout.fillWidth: true
                            spacing: 6

                            MaterialSymbol {
                                text: "folder"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.m3colors.m3onSecondaryContainer
                            }

                            TextField {
                                id: groupInputField
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.m3colors.m3onSecondaryContainer
                                placeholderText: Translation.tr("Group name (or empty to clear)")
                                text: sessionDrawer.groupText
                                background: Rectangle {
                                    color: Qt.alpha(Appearance.m3colors.m3onSecondaryContainer, 0.06)
                                    radius: 4
                                }
                                leftPadding: 6
                                rightPadding: 6
                                topPadding: 4
                                bottomPadding: 4

                                Component.onCompleted: forceActiveFocus()
                                onTextChanged: sessionDrawer.groupText = text

                                Keys.onReturnPressed: {
                                    var name = sessionDrawer.groupingSession
                                    var group = sessionDrawer.groupText.trim()
                                    if (group.length > 0) {
                                        Ai.setSessionGroup(name, group)
                                    } else {
                                        Ai.setSessionGroup(name, "")
                                    }
                                    sessionDrawer.groupingSession = ""
                                }
                                Keys.onEscapePressed: sessionDrawer.groupingSession = ""
                            }

                            ApiCommandButton {
                                bounce: false
                                colBackground: Appearance.m3colors.m3secondary
                                colBackgroundHover: Qt.darker(Appearance.m3colors.m3secondary, 1.1)
                                contentItem: StyledText {
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.m3colors.m3onSecondary
                                    text: Translation.tr("Set")
                                }
                                onClicked: {
                                    var name = sessionDrawer.groupingSession
                                    var group = sessionDrawer.groupText.trim()
                                    if (group.length > 0) {
                                        Ai.setSessionGroup(name, group)
                                    } else {
                                        Ai.setSessionGroup(name, "")
                                    }
                                    sessionDrawer.groupingSession = ""
                                }
                            }

                            RippleButton {
                                implicitWidth: 24
                                implicitHeight: 24
                                buttonRadius: 12
                                colBackground: "transparent"
                                colBackgroundHover: Qt.alpha(Appearance.m3colors.m3onSecondaryContainer, 0.12)
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: Appearance.m3colors.m3onSecondaryContainer
                                }
                                onClicked: sessionDrawer.groupingSession = ""
                            }
                        }

                        // Existing group suggestions
                        Flow {
                            Layout.fillWidth: true
                            spacing: 4
                            visible: existingGroups.length > 0

                            property var existingGroups: {
                                var groups = [];
                                var sessions = Ai.sessionsIndex.sessions || [];
                                for (var i = 0; i < sessions.length; i++) {
                                    var g = sessions[i].group || "";
                                    if (g.length > 0 && groups.indexOf(g) === -1) {
                                        groups.push(g);
                                    }
                                }
                                return groups;
                            }

                            Repeater {
                                model: parent.existingGroups
                                delegate: RippleButton {
                                    required property string modelData
                                    required property int index
                                    implicitHeight: 24
                                    implicitWidth: groupChipText.implicitWidth + 12
                                    buttonRadius: 12
                                    colBackground: Qt.alpha(Appearance.m3colors.m3secondaryContainer, 0.6)
                                    colBackgroundHover: Appearance.m3colors.m3secondaryContainer

                                    contentItem: StyledText {
                                        id: groupChipText
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.m3colors.m3onSecondaryContainer
                                    }

                                    onClicked: {
                                        sessionDrawer.groupText = modelData
                                        groupInputField.text = modelData
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Search panel — conditionally visible above message list
        SearchPanel {
            id: chatSearchPanel
            Layout.fillWidth: true
            visible: root.searchOpen
            totalMatches: Ai.searchResults.length
            currentMatchIndex: Ai.searchIndex >= 0 ? Ai.searchIndex : 0

            onSearchRequested: {
                Ai.searchMessages({
                    keyword: chatSearchPanel.keyword,
                    dateStart: chatSearchPanel.dateStart,
                    dateEnd: chatSearchPanel.dateEnd,
                    subject: chatSearchPanel.subjectFilter,
                    group: chatSearchPanel.groupFilter,
                });
            }
            onNextMatch: Ai.nextSearchResult()
            onPrevMatch: Ai.prevSearchResult()
            onClearSearch: Ai.clearSearch()
            onCloseSearch: root.searchOpen = false
        }

        Item { // Messages
            visible: !root.searchOpen
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView { // Message list
                id: messageListView
                anchors.fill: parent
                spacing: 10
                popin: false
                verticalLayoutDirection: ListView.BottomToTop

                // Override scrollbar — always visible when content overflows
                ScrollBar.vertical: ScrollBar {
                    id: chatScrollBar
                    padding: 2
                    policy: ScrollBar.AlwaysOn
                    visible: size < 1

                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: chatScrollBar.active
                            ? Appearance.colors.colPrimary
                            : Qt.alpha(Appearance.colors.colOnLayer1, 0.35)

                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                    }

                    background: Rectangle {
                        implicitWidth: 10
                        radius: 5
                        color: Qt.alpha(Appearance.colors.colLayer1, 0.3)
                    }
                }

                property int lastResponseLength: 0

                // Scroll-position guards (BottomToTop: contentY=0 is at bottom)
                readonly property real scrollThreshold: 10
                readonly property bool isNearBottom: contentY <= scrollThreshold
                property bool userScrolling: false
                property bool _shouldStickToBottom: true

                // Snap to bottom when content first loads after becoming visible
                onContentHeightChanged: {
                    if (root._needsInitialScroll && height > 0 && contentHeight > 0) {
                        root._needsInitialScroll = false
                        scrollBehavior.enabled = false
                        positionViewAtBeginning()
                        scrollBehavior.enabled = true
                    } else if (_shouldStickToBottom && !userScrolling) {
                        scrollBehavior.enabled = false
                        positionViewAtBeginning()
                        scrollBehavior.enabled = true
                    }
                }

                onMovementStarted: {
                    messageListView.userScrolling = true;
                    scrollAnim.stop();
                    if (root.sessionDrawerOpen) root.sessionDrawerOpen = false;
                }
                onMovementEnded: {
                    messageListView.userScrolling = false;
                    _shouldStickToBottom = isNearBottom;
                }

                clip: true
                // layer.enabled: true — DISABLED: causes invisible content until interaction
                // layer.effect: OpacityMask {
                //     maskSource: Rectangle {
                //         width: swipeView.width
                //         height: swipeView.height
                //         radius: Appearance.rounding.small
                //     }
                // }

                add: null // Prevent function calls from being janky
                remove: null // Prevent old messages flying away on session switch
                removeDisplaced: null // Prevent displacement animation on model change
                addDisplaced: null // Prevent add displacement animation

                Behavior on contentY {
                    id: scrollBehavior
                    NumberAnimation {
                        id: scrollAnim
                        duration: Appearance.animation.scroll.duration
                        easing.type: Appearance.animation.scroll.type
                        easing.bezierCurve: Appearance.animation.scroll.bezierCurve
                    }
                }

                model: ScriptModel {
                    values: {
                        // messageVersion forces re-evaluation on session switch
                        void(Ai.messageVersion);
                        return Ai.messageIDs.filter(id => {
                            const message = Ai.messageByID[id];
                            if (!(message?.visibleToUser ?? true)) return false;
                            // Hide finished assistant messages with no visible content
                            if (message?.role === "assistant" && message?.done === true) {
                                const raw = (message?.rawContent ?? "").trim();
                                if (raw.length === 0) return false;
                                const visible = raw.replace(/<think>[\s\S]*?<\/think>/g, "")
                                                   .replace(/<think>[\s\S]*$/, "")
                                                   .trim();
                                if (visible.length === 0) return false;
                            }
                            return true;
                        }).slice().reverse();
                    }
                }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: messageListView.width
                    implicitHeight: aiMsg.implicitHeight
                    radius: Appearance.rounding.small
                    color: root.highlightedMessageIndex >= 0 && index === (Ai.messageIDs.length - 1 - root.highlightedMessageIndex)
                        ? Qt.alpha(Appearance.m3colors.m3primary, 0.08)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: 300 } }

                    AiMessage {
                        id: aiMsg
                        anchors.left: parent.left
                        anchors.right: parent.right
                        messageIndex: parent.index
                        messageId: parent.modelData
                        messageData: Ai.messageByID[parent.modelData]
                        messageInputField: root.inputField
                    }
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

        // Search results view — shows matching messages when search is active
        Item {
            visible: root.searchOpen
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Empty state when no results
            StyledText {
                anchors.centerIn: parent
                visible: Ai.searchResults.length === 0
                text: Translation.tr("Type at least 2 characters to search")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }

            ListView {
                id: searchResultsView
                anchors.fill: parent
                visible: Ai.searchResults.length > 0
                spacing: 6
                clip: true
                model: Ai.searchResults

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: searchResultsView.width
                    implicitHeight: resultColumn.implicitHeight + 12
                    radius: Appearance.rounding.small
                    color: index === Ai.searchIndex
                        ? Qt.alpha(Appearance.m3colors.m3primary, 0.12)
                        : Appearance.colors.colLayer2

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Ai.searchIndex = index
                            root._scrollToMatchActive = true
                            root.highlightedMessageIndex = modelData.messageIndex
                            highlightResetTimer.restart()
                            // Close search and scroll chat to the matched message
                            root.searchOpen = false
                            // The ScriptModel is reversed, so convert messageIndex to display index
                            var totalMessages = Ai.messageIDs.length
                            var displayIndex = totalMessages - 1 - modelData.messageIndex
                            messageListView.positionViewAtIndex(displayIndex, ListView.Center)
                        }
                    }

                    ColumnLayout {
                        id: resultColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 10
                            rightMargin: 10
                        }
                        spacing: 2

                        // Role label
                        StyledText {
                            property var msg: Ai.messageByID[Ai.messageIDs[modelData.messageIndex]] || null
                            text: msg ? msg.role : "?"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.m3colors.m3primary
                        }

                        // Message snippet with match highlighted
                        StyledText {
                            property var msg: Ai.messageByID[Ai.messageIDs[modelData.messageIndex]] || null
                            property string raw: msg ? (msg.rawContent || "") : ""
                            property int start: Math.max(0, modelData.matchStart - 40)
                            property int end: Math.min(raw.length, modelData.matchEnd + 80)
                            text: (start > 0 ? "…" : "") + raw.substring(start, end) + (end < raw.length ? "…" : "")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
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

        // URL action chips — shown when user message contains detected URLs
        Flow {
            id: urlChipsRow
            visible: root.lastDetectedUrls.length > 0
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.lastDetectedUrls.length

                UrlActionChip {
                    required property int index
                    url: root.lastDetectedUrls[index]?.url ?? ""

                    onFetchRequested: function(chipUrl) {
                        root.handleFetchUrl(chipUrl);
                    }
                    onOpenRequested: function(chipUrl) {
                        // Remove chip after opening
                        root.lastDetectedUrls = root.lastDetectedUrls.filter(function(u) { return u.url !== chipUrl; });
                    }
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
                + attachmentPreviewRow.implicitHeight + (attachmentPreviewRow.visible ? 4 : 0)
                + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + columnSpacing, 45)
            clip: true
            border.color: dropArea.containsDrag ? Appearance.m3colors.m3primary : Appearance.colors.colOutlineVariant
            border.width: dropArea.containsDrag ? 2 : 1

            // Hide normal input content when context is full
            opacity: Ai.contextFull ? 0 : 1
            visible: !Ai.contextFull

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            // Drop area for file attachments
            DropArea {
                id: dropArea
                anchors.fill: parent
                keys: ["text/uri-list"]

                onDropped: (drop) => {
                    if (drop.hasUrls) {
                        for (var i = 0; i < drop.urls.length; i++) {
                            var url = drop.urls[i].toString()
                            // Strip file:// prefix
                            var filePath = url.replace(/^file:\/\//, "")
                            var fileName = filePath.split("/").pop()
                            // Determine MIME type from extension
                            var ext = fileName.split(".").pop().toLowerCase()
                            var mimeMap = {
                                "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                                "gif": "image/gif", "webp": "image/webp", "svg": "image/svg+xml",
                                "pdf": "application/pdf", "txt": "text/plain", "md": "text/markdown",
                                "json": "application/json", "zip": "application/zip",
                                "tar": "application/x-tar", "gz": "application/gzip",
                                "mp3": "audio/mpeg", "wav": "audio/wav", "mp4": "video/mp4",
                            }
                            var mimeType = mimeMap[ext] || "application/octet-stream"
                            var meta = Ai.storeAttachment(filePath, fileName, mimeType)
                            Ai.addPendingAttachment(meta)
                        }
                    }
                }
            }

            // Pending attachments preview row
            Flow {
                id: attachmentPreviewRow
                visible: Ai.pendingAttachments.length > 0
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 6
                spacing: 4

                Repeater {
                    model: Ai.pendingAttachments.length

                    Rectangle {
                        required property int index
                        width: attachChipRow.implicitWidth + 12
                        height: 28
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2

                        RowLayout {
                            id: attachChipRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                text: {
                                    var type = Ai.pendingAttachments[parent.parent.index]?.type || ""
                                    if (type.startsWith("image/")) return "image"
                                    if (type === "application/pdf") return "picture_as_pdf"
                                    if (type.startsWith("audio/")) return "audio_file"
                                    if (type.startsWith("video/")) return "video_file"
                                    return "attach_file"
                                }
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                text: {
                                    var name = Ai.pendingAttachments[parent.parent.parent.index]?.name || ""
                                    return name.length > 20 ? name.substring(0, 17) + "..." : name
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }

                            // Remove button
                            MouseArea {
                                implicitWidth: 14
                                implicitHeight: 14
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Ai.removePendingAttachment(parent.parent.parent.index)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }
            }

            RowLayout { // Input field and send button
                id: inputFieldRowLayout
                anchors.top: attachmentPreviewRow.visible ? attachmentPreviewRow.bottom : parent.top
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
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}tune`)) {
                            const parts = messageInputField.text.trim().split(" ");
                            const subCmd = parts[1] ?? "";
                            const subVal = parts[2] ?? "";

                            if (parts.length <= 2 && !subVal) {
                                // Show sub-command options
                                const tuning = Ai.getModelTuning();
                                const options = [
                                    { name: `${root.commandPrefix}tune get`, displayName: "get", description: Translation.tr("Show current tuning settings") },
                                    { name: `${root.commandPrefix}tune temp `, displayName: "temp", description: Translation.tr("Temperature: %1").arg(tuning.temperature) },
                                    { name: `${root.commandPrefix}tune reasoning `, displayName: "reasoning", description: Translation.tr("Effort: %1").arg(tuning.reasoningEffort || "default") },
                                    { name: `${root.commandPrefix}tune websearch `, displayName: "websearch", description: Translation.tr("Web search: %1").arg(tuning.webSearch ? "on" : "off") },
                                    { name: `${root.commandPrefix}tune context `, displayName: "context", description: Translation.tr("Search context: %1").arg(tuning.searchContextSize) },
                                    { name: `${root.commandPrefix}tune verbosity `, displayName: "verbosity", description: Translation.tr("Verbosity: %1").arg(tuning.verbosity || "default") },
                                ];
                                root.suggestionList = options.filter(o => o.displayName.startsWith(subCmd));
                            } else if (subCmd === "reasoning" || subCmd === "reason") {
                                const vals = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "off"];
                                root.suggestionList = vals.filter(v => v.startsWith(subVal)).map(v => ({
                                    name: `${root.commandPrefix}tune reasoning ${v}`,
                                    displayName: v,
                                    description: v === "off" ? Translation.tr("Clear reasoning setting") : Translation.tr("Set reasoning effort to %1").arg(v),
                                }));
                            } else if (subCmd === "websearch" || subCmd === "web") {
                                const vals = ["on", "off"];
                                root.suggestionList = vals.filter(v => v.startsWith(subVal)).map(v => ({
                                    name: `${root.commandPrefix}tune websearch ${v}`,
                                    displayName: v,
                                    description: v === "on" ? Translation.tr("Enable web search") : Translation.tr("Disable web search"),
                                }));
                            } else if (subCmd === "context" || subCmd === "searchcontext") {
                                const vals = ["low", "medium", "high"];
                                root.suggestionList = vals.filter(v => v.startsWith(subVal)).map(v => ({
                                    name: `${root.commandPrefix}tune context ${v}`,
                                    displayName: v,
                                    description: Translation.tr("Set search context size to %1").arg(v),
                                }));
                            } else if (subCmd === "verbosity" || subCmd === "verbose") {
                                const vals = ["low", "medium", "high", "off"];
                                root.suggestionList = vals.filter(v => v.startsWith(subVal)).map(v => ({
                                    name: `${root.commandPrefix}tune verbosity ${v}`,
                                    displayName: v,
                                    description: v === "off" ? Translation.tr("Clear verbosity setting") : Translation.tr("Set verbosity to %1").arg(v),
                                }));
                            }
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
                        } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                            // Ctrl+V: check if clipboard has an image, attach it
                            clipboardTypeChecker.running = true
                            // Don't prevent normal text paste — the checker will add image if found
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

                RippleButton { // Attach file button
                    id: attachButton
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            filePickerProcess.running = true
                        }
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                        text: "attach_file"
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
                    enabled: messageInputField.text.length > 0 || Ai.pendingAttachments.length > 0
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

                // YOLO mode toggle
                Rectangle {
                    implicitHeight: yoloRow.implicitHeight + 8
                    implicitWidth: yoloRow.implicitWidth + 8
                    radius: Appearance.rounding.small
                    color: Ai.yoloMode ? ColorUtils.transparentize(Appearance.m3colors.m3error, 0.8) : "transparent"

                    RowLayout {
                        id: yoloRow
                        anchors.centerIn: parent
                        spacing: 2

                        MaterialSymbol {
                            text: Ai.yoloMode ? "bolt" : "shield"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Ai.yoloMode ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Ai.yoloMode ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                            text: Ai.yoloMode ? "YOLO" : "Safe"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Ai.yoloMode = !Ai.yoloMode
                    }

                    StyledToolTip {
                        content: Ai.yoloMode
                            ? Translation.tr("YOLO mode: commands auto-execute\nClick to require approval")
                            : Translation.tr("Safe mode: commands need approval\nClick to auto-execute")
                    }
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

    // Dismiss overlay — click-away closes session drawer
    MouseArea {
        anchors.fill: parent
        visible: root.sessionDrawerOpen
        z: 50
        propagateComposedEvents: true
        onPressed: (mouse) => {
            root.sessionDrawerOpen = false
            mouse.accepted = false
        }
    }

}
