//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make it smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

pragma ComponentBehavior: "Bound"
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
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    // State enum
    enum State {
        Selecting,
        ActionWheel,
        Loading,
        Result,
        Error
    }

    property int state: ShellRoot.State.Selecting
    property string screenshotDir: "/tmp/quickshell/media/contextlens"
    property color overlayColor: "#77111111"
    property color genericContentColor: Qt.alpha(root.overlayColor, 0.9)
    property color genericContentForeground: "#ddffffff"
    property color selectionBorderColor: "#ddf1f1f1"
    property color selectionFillColor: "#33ffffff"
    property color windowBorderColor: "#dda0c0da"
    property color windowFillColor: "#22a0c0da"
    property color onBorderColor: "#ff000000"
    property real standardRounding: 4
    readonly property var windows: HyprlandData.windowList
    readonly property var layers: HyprlandData.layers

    // Selected region stored for cropping (set on selection complete)
    property real selectedRegionX: 0
    property real selectedRegionY: 0
    property real selectedRegionWidth: 0
    property real selectedRegionHeight: 0
    property real selectedMonitorScale: 1
    property string selectedScreenshotPath: ""

    // Action selection state
    property string selectedAction: ""
    property string selectedPrompt: ""

    // Vision pipeline properties
    property string imageBase64: ""
    property string cropPath: "/tmp/contextlens-crop.png"
    property string errorMessage: ""
    property string resultText: ""
    property bool cancelRequested: false
    property bool resultDone: false

    // Returns the action-specific system prompt for the given action ID
    function getPromptForAction(actionId) {
        switch (actionId) {
        case "explain":
            return "Describe what you see in this screenshot in detail. Explain any UI elements, text, or content visible.";
        case "extract_text":
            return "Extract ALL text visible in this image. Return only the extracted text, preserving layout where possible.";
        case "translate":
            return "Translate all text visible in this image to " + Config.options.contextLens.translateTargetLang + ". Show original and translation.";
        case "summarize":
            return "Summarize the content shown in this screenshot in 2-3 sentences.";
        case "explain_error":
            return "This screenshot shows an error or problem. Identify the error, explain the likely cause, and suggest a fix.";
        case "generate_command":
            return "Based on what's shown in this screenshot, generate the shell command(s) that would accomplish or fix what's shown. Return only the command(s).";
        case "ask_question":
            return root.selectedPrompt;
        case "identify_ui":
            return "Identify the application, UI framework, font, icon theme, and color scheme visible in this screenshot.";
        default:
            return "Describe what you see in this image.";
        }
    }

    // Starts the vision request using the Ai service
    function startVisionRequest() {
        // Determine the vision model
        var modelId = "";
        if (Config.options.contextLens.preferredVisionModel && Config.options.contextLens.preferredVisionModel.length > 0) {
            modelId = Config.options.contextLens.preferredVisionModel;
        } else {
            modelId = Ai.bestVisionModel;
        }

        // If no vision model is available, transition to Error
        if (!modelId || modelId.length === 0) {
            root.errorMessage = Translation.tr("No vision-capable model available. Configure one in the AI Providers panel.");
            root.state = ShellRoot.State.Error;
            return;
        }

        // Policy enforcement (Task 9.1): if policies.ai === 2, only allow local models
        if (Config.options.policies.ai === 2) {
            var endpoint = Ai.getEndpointForModel ? Ai.getEndpointForModel(modelId) : "";
            var isLocal = endpoint.indexOf("localhost") !== -1 ||
                          endpoint.indexOf("127.0.0.1") !== -1 ||
                          endpoint.indexOf("ollama") !== -1;
            if (!isLocal) {
                root.errorMessage = Translation.tr("Online models are not allowed by policy. Configure a local vision model (e.g. Ollama).");
                root.state = ShellRoot.State.Error;
                return;
            }
        }

        // Reset state
        root.resultText = "";
        root.cancelRequested = false;

        // Build the prompt
        var prompt = root.getPromptForAction(root.selectedAction);

        // Start the timeout timer
        visionTimeoutTimer.restart();

        // Send the vision request
        Ai.sendVisionMessage(
            prompt,
            [root.imageBase64],
            function(chunk) {
                // onChunk: accumulate streamed response
                if (!root.cancelRequested) {
                    root.resultText += chunk;
                }
            },
            function() {
                // onDone: request complete
                visionTimeoutTimer.stop();
                if (!root.cancelRequested) {
                    root.resultDone = true;
                    root.state = ShellRoot.State.Result;
                }
            },
            function(errorMsg) {
                // onError: request failed
                visionTimeoutTimer.stop();
                if (!root.cancelRequested) {
                    root.errorMessage = errorMsg;
                    root.state = ShellRoot.State.Error;
                }
            },
            modelId
        );
    }

    // Process: notify user AI is disabled and exit (Task 9.1 — policy enforcement)
    Process {
        id: notifyAndQuitProcess
        running: false
        command: ["notify-send", "Context Lens", "AI is disabled by policy", "-a", "Context Lens", "-t", "3000"]
        onExited: {
            Qt.quit();
        }
    }

    // Force initialization of some singletons
    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();

        // Policy enforcement (Task 9.1): check policies.ai before proceeding
        if (Config.options.policies.ai === 0) {
            notifyAndQuitProcess.running = true;
            return;
        }
    }

    // Privacy policy (Task 9.2): clean up ALL temp files on exit.
    // Image data never persists to disk beyond the request lifecycle:
    // - /tmp/contextlens-crop.png is deleted immediately after base64 encoding (cropCleanupProcess)
    // - Screenshot dir (/tmp/quickshell/media/contextlens/) is removed on exit
    // - Image data only exists in memory (root.imageBase64) during the session
    Component.onDestruction: {
        cleanupProcess.running = true;
    }

    // State change handler — triggers crop when entering Loading
    onStateChanged: {
        if (root.state === ShellRoot.State.Loading) {
            // Validate minimum crop size (10x10 pixels after scale)
            const scaledWidth = Math.round(root.selectedRegionWidth * root.selectedMonitorScale);
            const scaledHeight = Math.round(root.selectedRegionHeight * root.selectedMonitorScale);
            if (scaledWidth < 10 || scaledHeight < 10) {
                root.errorMessage = Translation.tr("Region too small. Please select a larger area (at least 10×10 pixels).");
                root.state = ShellRoot.State.Error;
                return;
            }
            root.imageBase64 = "";
            root.resultDone = false;
            root.resultText = "";
            cropProcess.running = true;
        }
    }

    // Process: crop the screenshot to the selected region via ImageMagick
    Process {
        id: cropProcess
        running: false
        command: ["magick",
            root.selectedScreenshotPath,
            "-crop",
            `${Math.round(root.selectedRegionWidth * root.selectedMonitorScale)}x${Math.round(root.selectedRegionHeight * root.selectedMonitorScale)}+${Math.round(root.selectedRegionX * root.selectedMonitorScale)}+${Math.round(root.selectedRegionY * root.selectedMonitorScale)}`,
            "+repage",
            root.cropPath
        ]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                base64Process.running = true;
            } else {
                root.errorMessage = Translation.tr("Failed to crop the image. ImageMagick exited with code ") + exitCode;
                root.state = ShellRoot.State.Error;
            }
        }
    }

    // Process: base64 encode the cropped image
    Process {
        id: base64Process
        running: false
        command: ["base64", "-w0", root.cropPath]
        stdout: SplitParser {
            onRead: (data) => {
                root.imageBase64 += data;
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && root.imageBase64.length > 0) {
                // base64 encoding complete — ready for vision request (task 5.3)
                // Clean up the temp crop file now that we have the data in memory
                cropCleanupProcess.running = true;
            } else {
                root.errorMessage = Translation.tr("Failed to encode the cropped image.");
                root.state = ShellRoot.State.Error;
            }
        }
    }

    // Process: clean up temp crop file after encoding (Task 9.2 — no image persistence)
    // Ensures /tmp/contextlens-crop.png is deleted immediately after base64 encoding
    Process {
        id: cropCleanupProcess
        running: false
        command: ["rm", "-f", root.cropPath]
        onExited: (exitCode, exitStatus) => {
            // Crop file cleaned up — start the vision request
            root.startVisionRequest();
        }
    }

    // Timer: 30-second timeout for vision request
    Timer {
        id: visionTimeoutTimer
        interval: 30000
        repeat: false
        onTriggered: {
            root.cancelRequested = true;
            root.errorMessage = Translation.tr("Request timed out. The AI model took too long to respond.");
            root.state = ShellRoot.State.Error;
        }
    }

    // Timer: auto-dismiss after result is fully loaded
    Timer {
        id: autoDismissTimer
        interval: Config.options.contextLens.resultTimeout * 1000
        repeat: false
        running: root.state === ShellRoot.State.Result && root.resultDone
        onTriggered: {
            Qt.quit();
        }
    }

    // Process: copy result text to clipboard
    Process {
        id: copyToClipboardProcess
        running: false
        command: ["wl-copy", root.resultText]
    }

    // Process: paste result text (copy then simulate Ctrl+V)
    Process {
        id: pasteProcess
        running: false
        command: ["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(root.resultText)}' | wl-copy && sleep 0.1 && ydotool key 29:1 47:1 47:0 29:0`]
    }

    // Process: send to chat via IPC
    Process {
        id: sendToChatProcess
        running: false
        command: ["quickshell", "ipc", "call", "contextLens", "sendToChat", root.imageBase64, root.resultText, root.selectedAction]
    }

    // Process: clean up all temp files on exit
    Process {
        id: cleanupProcess
        running: false
        command: ["bash", "-c", `rm -f '${StringUtils.shellSingleQuoteEscape(root.cropPath)}' && rm -rf '${StringUtils.shellSingleQuoteEscape(root.screenshotDir)}'`]
    }

    component TargetRegion: Rectangle {
        id: regionRect
        property bool showIcon: false
        property bool targeted: false
        property color borderColor
        property color fillColor: "transparent"
        property string text: ""
        property real textPadding: 10
        z: 2
        color: fillColor
        border.color: borderColor
        border.width: targeted ? 3 : 1
        radius: root.standardRounding

        Rectangle {
            id: regionLabelBackground
            property real verticalPadding: 5
            property real horizontalPadding: 10
            radius: 10
            color: root.genericContentColor
            border.width: 1
            border.color: Appearance.m3colors.m3outlineVariant
            anchors {
                top: parent.top
                left: parent.left
                topMargin: regionRect.textPadding
                leftMargin: regionRect.textPadding
            }
            implicitWidth: regionInfoRow.implicitWidth + horizontalPadding * 2
            implicitHeight: regionInfoRow.implicitHeight + verticalPadding * 2
            RowLayout {
                id: regionInfoRow
                anchors.centerIn: parent
                spacing: 8

                Loader {
                    id: regionIconLoader
                    active: regionRect.showIcon
                    visible: active
                    sourceComponent: IconImage {
                        implicitSize: Appearance.font.pixelSize.larger
                        source: Quickshell.iconPath(AppSearch.guessIcon(regionRect.text), "image-missing")
                    }
                }

                StyledText {
                    id: regionText
                    text: regionRect.text
                    color: root.genericContentForeground
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panelWindow
            required property var modelData
            readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(modelData)
            readonly property real monitorScale: hyprlandMonitor.scale
            readonly property real monitorOffsetX: hyprlandMonitor.x
            readonly property real monitorOffsetY: hyprlandMonitor.y
            property int activeWorkspaceId: hyprlandMonitor.activeWorkspace?.id ?? 0
            property string screenshotPath: `${root.screenshotDir}/image-${modelData.name}`
            property real dragStartX: 0
            property real dragStartY: 0
            property real draggingX: 0
            property real draggingY: 0
            property real dragDiffX: 0
            property real dragDiffY: 0
            property bool draggedAway: (dragDiffX !== 0 || dragDiffY !== 0)
            property bool dragging: false
            readonly property list<var> windowRegions: filterWindowRegionsByLayers(
                root.windows.filter(w => w.workspace.id === panelWindow.activeWorkspaceId),
                panelWindow.layerRegions
            ).map(window => {
                return {
                    at: [window.at[0] - panelWindow.monitorOffsetX, window.at[1] - panelWindow.monitorOffsetY],
                    size: [window.size[0], window.size[1]],
                    class: window.class,
                    title: window.title,
                }
            })
            readonly property list<var> layerRegions: {
                const layersOfThisMonitor = root.layers[panelWindow.hyprlandMonitor.name]
                const topLayers = layersOfThisMonitor.levels["2"]
                const nonBarTopLayers = topLayers
                    .filter(layer => !(layer.namespace.includes(":bar") || layer.namespace.includes(":dock")))
                    .map(layer => {
                    return {
                        at: [layer.x, layer.y],
                        size: [layer.w, layer.h],
                        namespace: layer.namespace,
                    }
                })
                const offsetAdjustedLayers = nonBarTopLayers.map(layer => {
                    return {
                        at: [layer.at[0] - panelWindow.monitorOffsetX, layer.at[1] - panelWindow.monitorOffsetY],
                        size: layer.size,
                        namespace: layer.namespace,
                    }
                });
                return offsetAdjustedLayers;
            }

            property real targetedRegionX: -1
            property real targetedRegionY: -1
            property real targetedRegionWidth: 0
            property real targetedRegionHeight: 0

            function intersectionOverUnion(regionA, regionB) {
                const ax1 = regionA.at[0], ay1 = regionA.at[1];
                const ax2 = ax1 + regionA.size[0], ay2 = ay1 + regionA.size[1];
                const bx1 = regionB.at[0], by1 = regionB.at[1];
                const bx2 = bx1 + regionB.size[0], by2 = by1 + regionB.size[1];

                const interX1 = Math.max(ax1, bx1);
                const interY1 = Math.max(ay1, by1);
                const interX2 = Math.min(ax2, bx2);
                const interY2 = Math.min(ay2, by2);

                const interArea = Math.max(0, interX2 - interX1) * Math.max(0, interY2 - interY1);
                const areaA = (ax2 - ax1) * (ay2 - ay1);
                const areaB = (bx2 - bx1) * (by2 - by1);
                const unionArea = areaA + areaB - interArea;

                return unionArea > 0 ? interArea / unionArea : 0;
            }

            function filterWindowRegionsByLayers(windowRegions, layerRegions) {
                return windowRegions.filter(windowRegion => {
                    for (let i = 0; i < layerRegions.length; ++i) {
                        if (intersectionOverUnion(windowRegion, layerRegions[i]) > 0)
                            return false;
                    }
                    return true;
                });
            }

            function updateTargetedRegion(x, y) {
                // Layer regions (higher priority)
                const clickedLayer = panelWindow.layerRegions.find(region => {
                    return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
                });
                if (clickedLayer) {
                    panelWindow.targetedRegionX = clickedLayer.at[0];
                    panelWindow.targetedRegionY = clickedLayer.at[1];
                    panelWindow.targetedRegionWidth = clickedLayer.size[0];
                    panelWindow.targetedRegionHeight = clickedLayer.size[1];
                    return;
                }

                // Window regions
                const clickedWindow = panelWindow.windowRegions.find(region => {
                    return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
                });
                if (clickedWindow) {
                    panelWindow.targetedRegionX = clickedWindow.at[0];
                    panelWindow.targetedRegionY = clickedWindow.at[1];
                    panelWindow.targetedRegionWidth = clickedWindow.size[0];
                    panelWindow.targetedRegionHeight = clickedWindow.size[1];
                    return;
                }

                panelWindow.targetedRegionX = -1;
                panelWindow.targetedRegionY = -1;
                panelWindow.targetedRegionWidth = 0;
                panelWindow.targetedRegionHeight = 0;
            }

            function completeSelection() {
                let finalX = panelWindow.regionX;
                let finalY = panelWindow.regionY;
                let finalWidth = panelWindow.regionWidth;
                let finalHeight = panelWindow.regionHeight;

                // If it was a click (no drag), use the targeted region
                if (panelWindow.draggingX === panelWindow.dragStartX && panelWindow.draggingY === panelWindow.dragStartY) {
                    if (panelWindow.targetedRegionX >= 0 && panelWindow.targetedRegionY >= 0) {
                        finalX = panelWindow.targetedRegionX;
                        finalY = panelWindow.targetedRegionY;
                        finalWidth = panelWindow.targetedRegionWidth;
                        finalHeight = panelWindow.targetedRegionHeight;
                    }
                }

                // Validate minimum region size
                if (finalWidth <= 0 || finalHeight <= 0) {
                    return;
                }

                // Store the selected region for cropping
                root.selectedRegionX = finalX;
                root.selectedRegionY = finalY;
                root.selectedRegionWidth = finalWidth;
                root.selectedRegionHeight = finalHeight;
                root.selectedMonitorScale = panelWindow.monitorScale;
                root.selectedScreenshotPath = panelWindow.screenshotPath;

                // Transition to ActionWheel state
                root.state = ShellRoot.State.ActionWheel;
            }

            property real regionWidth: Math.abs(draggingX - dragStartX)
            property real regionHeight: Math.abs(draggingY - dragStartY)
            property real regionX: Math.min(dragStartX, draggingX)
            property real regionY: Math.min(dragStartY, draggingY)

            visible: false
            screen: modelData
            WlrLayershell.namespace: "quickshell:contextlens"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            anchors {
                left: true
                right: true
                top: true
                bottom: true
            }

            Process {
                id: screenshotProcess
                running: true
                command: ["bash", "-c", `mkdir -p '${StringUtils.shellSingleQuoteEscape(root.screenshotDir)}' && grim -o '${StringUtils.shellSingleQuoteEscape(modelData.name)}' '${StringUtils.shellSingleQuoteEscape(panelWindow.screenshotPath)}'`]
                onExited: (exitCode, exitStatus) => {
                    panelWindow.visible = true;
                }
            }

            ScreencopyView {
                anchors.fill: parent
                live: false
                captureSource: modelData

                focus: panelWindow.visible
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        Qt.quit();
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: root.state === ShellRoot.State.Selecting ? Qt.CrossCursor : Qt.ArrowCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    enabled: root.state === ShellRoot.State.Selecting

                    // Controls
                    onPressed: mouse => {
                        panelWindow.dragStartX = mouse.x;
                        panelWindow.dragStartY = mouse.y;
                        panelWindow.draggingX = mouse.x;
                        panelWindow.draggingY = mouse.y;
                        panelWindow.dragging = true;
                    }
                    onReleased: mouse => {
                        panelWindow.completeSelection();
                    }
                    onPositionChanged: mouse => {
                        if (panelWindow.dragging) {
                            panelWindow.draggingX = mouse.x;
                            panelWindow.draggingY = mouse.y;
                            panelWindow.dragDiffX = mouse.x - panelWindow.dragStartX;
                            panelWindow.dragDiffY = mouse.y - panelWindow.dragStartY;
                        }
                        panelWindow.updateTargetedRegion(mouse.x, mouse.y);
                    }

                    // Overlay to darken screen
                    Rectangle {
                        id: overlayRect
                        z: 0
                        anchors.fill: parent
                        color: root.overlayColor
                        layer.enabled: true
                    }

                    // Selection border rectangle
                    Rectangle {
                        z: 1
                        visible: root.state === ShellRoot.State.Selecting
                        anchors {
                            left: parent.left
                            top: parent.top
                            leftMargin: panelWindow.regionX
                            topMargin: panelWindow.regionY
                        }
                        width: panelWindow.regionWidth
                        height: panelWindow.regionHeight
                        color: "transparent"
                        border.color: root.selectionBorderColor
                        border.width: 2
                        radius: root.standardRounding
                    }

                    // Instructions
                    Rectangle {
                        anchors {
                            top: parent.top
                            horizontalCenter: parent.horizontalCenter
                            topMargin: (Appearance.sizes.barHeight - implicitHeight) / 2
                        }

                        opacity: (root.state === ShellRoot.State.Selecting && !panelWindow.dragging) ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        color: root.genericContentColor
                        radius: 10
                        border.width: 1
                        border.color: Appearance.m3colors.m3outlineVariant
                        implicitWidth: instructionsRow.implicitWidth + 10 * 2
                        implicitHeight: instructionsRow.implicitHeight + 5 * 2

                        RowLayout {
                            id: instructionsRow
                            anchors.centerIn: parent
                            Item {
                                Layout.fillHeight: true
                                implicitWidth: contextLensIcon.implicitWidth
                                MaterialSymbol {
                                    id: contextLensIcon
                                    anchors.centerIn: parent
                                    iconSize: Appearance.font.pixelSize.larger
                                    text: "center_focus_strong"
                                    color: root.genericContentForeground
                                }
                            }
                            StyledText {
                                text: Translation.tr("Select a region to analyze with AI")
                                color: root.genericContentForeground
                            }
                        }
                    }

                    // Window regions
                    Repeater {
                        model: ScriptModel {
                            values: panelWindow.windowRegions
                        }
                        delegate: TargetRegion {
                            z: 2
                            required property var modelData
                            showIcon: true
                            targeted: !panelWindow.draggedAway &&
                                (panelWindow.targetedRegionX === modelData.at[0]
                                && panelWindow.targetedRegionY === modelData.at[1]
                                && panelWindow.targetedRegionWidth === modelData.size[0]
                                && panelWindow.targetedRegionHeight === modelData.size[1])

                            opacity: (root.state === ShellRoot.State.Selecting && !panelWindow.draggedAway) ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }

                            x: modelData.at[0]
                            y: modelData.at[1]
                            width: modelData.size[0]
                            height: modelData.size[1]
                            borderColor: root.windowBorderColor
                            fillColor: targeted ? root.windowFillColor : "transparent"
                            border.width: targeted ? 4 : 2
                            text: `${modelData.class}`
                            radius: Appearance.rounding.windowRounding
                        }
                    }

                    // Layer regions
                    Repeater {
                        model: ScriptModel {
                            values: panelWindow.layerRegions
                        }
                        delegate: TargetRegion {
                            z: 3
                            required property var modelData
                            targeted: !panelWindow.draggedAway &&
                                (panelWindow.targetedRegionX === modelData.at[0]
                                && panelWindow.targetedRegionY === modelData.at[1]
                                && panelWindow.targetedRegionWidth === modelData.size[0]
                                && panelWindow.targetedRegionHeight === modelData.size[1])

                            opacity: (root.state === ShellRoot.State.Selecting && !panelWindow.draggedAway) ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }

                            x: modelData.at[0]
                            y: modelData.at[1]
                            width: modelData.size[0]
                            height: modelData.size[1]
                            borderColor: root.windowBorderColor
                            fillColor: targeted ? root.windowFillColor : "transparent"
                            border.width: targeted ? 4 : 2
                            text: `${modelData.namespace}`
                            radius: Appearance.rounding.windowRounding
                        }
                    }

                    // ActionWheel overlay
                    Item {
                        id: actionWheelContainer
                        z: 10
                        visible: root.state === ShellRoot.State.ActionWheel
                        anchors.fill: parent

                        // Click outside to dismiss
                        MouseArea {
                            anchors.fill: parent
                            enabled: actionWheelContainer.visible
                            onClicked: {
                                Qt.quit();
                            }
                        }

                        // Action wheel panel
                        Rectangle {
                            id: actionWheelPanel
                            property bool showingInput: false
                            property bool positionAbove: {
                                const belowY = root.selectedRegionY + root.selectedRegionHeight + 12;
                                const panelHeight = actionWheelColumn.implicitHeight + 24;
                                return (belowY + panelHeight) > panelWindow.height;
                            }

                            x: Math.max(12, Math.min(
                                panelWindow.width - width - 12,
                                root.selectedRegionX + (root.selectedRegionWidth - width) / 2
                            ))
                            y: positionAbove
                                ? root.selectedRegionY - height - 12
                                : root.selectedRegionY + root.selectedRegionHeight + 12

                            width: actionWheelColumn.implicitWidth + 24
                            height: actionWheelColumn.implicitHeight + 24
                            radius: 16
                            color: Appearance.m3colors.m3surface
                            border.width: 1
                            border.color: Appearance.m3colors.m3outlineVariant

                            // Consume clicks inside the panel so they don't dismiss
                            MouseArea {
                                anchors.fill: parent
                                onClicked: (mouse) => { mouse.accepted = true; }
                            }

                            ColumnLayout {
                                id: actionWheelColumn
                                anchors.centerIn: parent
                                spacing: 4

                                // Title
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.bottomMargin: 4
                                    text: Translation.tr("What would you like to do?")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.m3colors.m3onSurfaceVariant
                                }

                                // Action buttons grid
                                GridLayout {
                                    id: actionGrid
                                    visible: !actionWheelPanel.showingInput
                                    Layout.alignment: Qt.AlignHCenter
                                    columns: 2
                                    rowSpacing: 6
                                    columnSpacing: 6

                                    Repeater {
                                        model: {
                                            const allActions = [
                                                { id: "explain", icon: "info", label: Translation.tr("Explain") },
                                                { id: "extract_text", icon: "text_fields", label: Translation.tr("Extract text") },
                                                { id: "translate", icon: "translate", label: Translation.tr("Translate") },
                                                { id: "summarize", icon: "summarize", label: Translation.tr("Summarize") },
                                                { id: "explain_error", icon: "error", label: Translation.tr("Explain error") },
                                                { id: "generate_command", icon: "terminal", label: Translation.tr("Generate command") },
                                                { id: "ask_question", icon: "chat", label: Translation.tr("Ask a question") },
                                                { id: "identify_ui", icon: "widgets", label: Translation.tr("Identify UI") },
                                            ];
                                            const enabledActions = Config.options.contextLens.actions;
                                            const filtered = [];
                                            for (let i = 0; i < allActions.length; i++) {
                                                let found = false;
                                                for (let j = 0; j < enabledActions.length; j++) {
                                                    if (enabledActions[j] === allActions[i].id) {
                                                        found = true;
                                                        break;
                                                    }
                                                }
                                                if (found) filtered.push(allActions[i]);
                                            }
                                            return filtered;
                                        }

                                        delegate: RippleButton {
                                            id: actionButton
                                            required property var modelData
                                            required property int index
                                            implicitWidth: 160
                                            implicitHeight: 40
                                            buttonRadius: 10
                                            colBackground: Appearance.m3colors.m3surfaceContainerHigh

                                            onClicked: {
                                                if (actionButton.modelData.id === "ask_question") {
                                                    actionWheelPanel.showingInput = true;
                                                    questionInput.forceActiveFocus();
                                                } else {
                                                    root.selectedAction = actionButton.modelData.id;
                                                    root.selectedPrompt = "";
                                                    root.state = ShellRoot.State.Loading;
                                                }
                                            }

                                            contentItem: RowLayout {
                                                spacing: 8
                                                Item {
                                                    Layout.fillHeight: true
                                                    implicitWidth: actionIcon.implicitWidth
                                                    MaterialSymbol {
                                                        id: actionIcon
                                                        anchors.centerIn: parent
                                                        iconSize: Appearance.font.pixelSize.larger
                                                        text: actionButton.modelData.icon
                                                        color: Appearance.m3colors.m3onSurface
                                                    }
                                                }
                                                StyledText {
                                                    text: actionButton.modelData.label
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    color: Appearance.m3colors.m3onSurface
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }
                                }

                                // "Ask a question" text input
                                ColumnLayout {
                                    visible: actionWheelPanel.showingInput
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 8

                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Translation.tr("Ask a question about this region")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.m3colors.m3onSurfaceVariant
                                    }

                                    TextField {
                                        id: questionInput
                                        Layout.preferredWidth: 300
                                        placeholderText: Translation.tr("Type your question...")
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.m3colors.m3onSurface

                                        background: Rectangle {
                                            radius: 10
                                            color: Appearance.m3colors.m3surfaceContainerHigh
                                            border.width: 1
                                            border.color: questionInput.activeFocus
                                                ? Appearance.m3colors.m3primary
                                                : Appearance.m3colors.m3outlineVariant
                                        }

                                        Keys.onReturnPressed: {
                                            if (questionInput.text.trim().length > 0) {
                                                root.selectedAction = "ask_question";
                                                root.selectedPrompt = questionInput.text.trim();
                                                root.state = ShellRoot.State.Loading;
                                            }
                                        }
                                        Keys.onEscapePressed: {
                                            actionWheelPanel.showingInput = false;
                                            questionInput.text = "";
                                        }
                                    }

                                    RowLayout {
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: 8

                                        RippleButton {
                                            implicitWidth: 80
                                            implicitHeight: 32
                                            buttonRadius: 8
                                            colBackground: Appearance.m3colors.m3surfaceContainerHigh
                                            onClicked: {
                                                actionWheelPanel.showingInput = false;
                                                questionInput.text = "";
                                            }
                                            contentItem: StyledText {
                                                anchors.centerIn: parent
                                                text: Translation.tr("Cancel")
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                color: Appearance.m3colors.m3onSurface
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }

                                        RippleButton {
                                            implicitWidth: 80
                                            implicitHeight: 32
                                            buttonRadius: 8
                                            colBackground: Appearance.m3colors.m3primary
                                            onClicked: {
                                                if (questionInput.text.trim().length > 0) {
                                                    root.selectedAction = "ask_question";
                                                    root.selectedPrompt = questionInput.text.trim();
                                                    root.state = ShellRoot.State.Loading;
                                                }
                                            }
                                            contentItem: StyledText {
                                                anchors.centerIn: parent
                                                text: Translation.tr("Submit")
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                color: Appearance.m3colors.m3onPrimary
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Click-outside-to-dismiss (Task 7.4)
                    // Full-screen MouseArea behind overlays for Loading/Result/Error states
                    MouseArea {
                        id: clickOutsideDismiss
                        z: 9
                        anchors.fill: parent
                        visible: root.state === ShellRoot.State.Loading ||
                                 root.state === ShellRoot.State.Result ||
                                 root.state === ShellRoot.State.Error
                        enabled: visible
                        onClicked: {
                            Qt.quit();
                        }
                    }

                    // Loading overlay (Task 7.1)
                    Rectangle {
                        id: loadingOverlay
                        z: 10
                        visible: root.state === ShellRoot.State.Loading

                        property bool positionAbove: {
                            const belowY = root.selectedRegionY + root.selectedRegionHeight + 12;
                            const panelHeight = loadingColumn.implicitHeight + 32;
                            return (belowY + panelHeight) > panelWindow.height;
                        }

                        x: Math.max(12, Math.min(
                            panelWindow.width - width - 12,
                            root.selectedRegionX + (root.selectedRegionWidth - width) / 2
                        ))
                        y: positionAbove
                            ? root.selectedRegionY - height - 12
                            : root.selectedRegionY + root.selectedRegionHeight + 12

                        width: loadingColumn.implicitWidth + 48
                        height: loadingColumn.implicitHeight + 32
                        radius: 16
                        color: Appearance.m3colors.m3surface
                        border.width: 1
                        border.color: Appearance.m3colors.m3outlineVariant

                        // Prevent click-through
                        MouseArea {
                            anchors.fill: parent
                            onClicked: (mouse) => { mouse.accepted = true; }
                        }

                        ColumnLayout {
                            id: loadingColumn
                            anchors.centerIn: parent
                            spacing: 12

                            BusyIndicator {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 32
                                implicitHeight: 32
                                running: loadingOverlay.visible
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("Analyzing...")
                                color: Appearance.m3colors.m3onSurface
                                font.pixelSize: Appearance.font.pixelSize.normal
                            }

                            RippleButton {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 80
                                implicitHeight: 32
                                buttonRadius: 8
                                colBackground: Appearance.m3colors.m3surfaceContainerHigh
                                onClicked: {
                                    root.cancelRequested = true;
                                    Qt.quit();
                                }
                                contentItem: StyledText {
                                    anchors.centerIn: parent
                                    text: Translation.tr("Cancel")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.m3colors.m3onSurface
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }

                    // Result overlay (Task 7.1 + 7.2 + 7.3)
                    Rectangle {
                        id: resultOverlay
                        z: 10
                        visible: root.state === ShellRoot.State.Result

                        property bool positionAbove: {
                            const belowY = root.selectedRegionY + root.selectedRegionHeight + 12;
                            const panelHeight = Math.min(400, resultContentColumn.implicitHeight + 16);
                            return (belowY + panelHeight) > panelWindow.height;
                        }

                        x: Math.max(12, Math.min(
                            panelWindow.width - width - 12,
                            root.selectedRegionX + (root.selectedRegionWidth - width) / 2
                        ))
                        y: positionAbove
                            ? Math.max(12, root.selectedRegionY - height - 12)
                            : root.selectedRegionY + root.selectedRegionHeight + 12

                        width: Math.min(500, Math.max(280, panelWindow.width * 0.4))
                        height: Math.min(400, resultContentColumn.implicitHeight + 16)
                        radius: 16
                        color: Appearance.m3colors.m3surface
                        border.width: 1
                        border.color: Appearance.m3colors.m3outlineVariant

                        // Prevent click-through and reset auto-dismiss on interaction
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: (mouse) => { mouse.accepted = true; }
                            onPositionChanged: {
                                autoDismissTimer.restart();
                            }
                            onEntered: {
                                autoDismissTimer.restart();
                            }
                        }

                        ColumnLayout {
                            id: resultContentColumn
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            // Scrollable result text
                            ScrollView {
                                id: resultScrollView
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 60
                                clip: true

                                // Reset auto-dismiss on scroll interaction
                                onContentItemChanged: {
                                    if (contentItem) {
                                        contentItem.flickStarted.connect(function() {
                                            autoDismissTimer.restart();
                                        });
                                    }
                                }

                                StyledText {
                                    id: resultTextDisplay
                                    width: resultScrollView.availableWidth
                                    text: root.resultText || Translation.tr("Waiting for response...")
                                    color: Appearance.m3colors.m3onSurface
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    wrapMode: Text.Wrap
                                    textFormat: Text.StyledText
                                }
                            }

                            // Streaming indicator (while not done)
                            RowLayout {
                                Layout.fillWidth: true
                                visible: !root.resultDone
                                spacing: 8

                                BusyIndicator {
                                    implicitWidth: 16
                                    implicitHeight: 16
                                    running: !root.resultDone && resultOverlay.visible
                                }

                                StyledText {
                                    text: Translation.tr("Receiving...")
                                    color: Appearance.m3colors.m3onSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                            }

                            // Separator line
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: Appearance.m3colors.m3outlineVariant
                                visible: root.resultDone
                            }

                            // Action buttons bar (Task 7.2)
                            RowLayout {
                                Layout.fillWidth: true
                                visible: root.resultDone
                                spacing: 6

                                // Copy button
                                RippleButton {
                                    implicitWidth: copyButtonContent.implicitWidth + 16
                                    implicitHeight: 32
                                    buttonRadius: 8
                                    colBackground: Appearance.m3colors.m3primaryContainer
                                    onClicked: {
                                        copyToClipboardProcess.running = true;
                                        autoDismissTimer.restart();
                                    }
                                    contentItem: RowLayout {
                                        id: copyButtonContent
                                        anchors.centerIn: parent
                                        spacing: 4
                                        MaterialSymbol {
                                            iconSize: Appearance.font.pixelSize.normal
                                            text: "content_copy"
                                            color: Appearance.m3colors.m3onPrimaryContainer
                                        }
                                        StyledText {
                                            text: Translation.tr("Copy")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.m3colors.m3onPrimaryContainer
                                        }
                                    }
                                }

                                // Paste button (only for extract_text and generate_command)
                                RippleButton {
                                    visible: root.selectedAction === "extract_text" || root.selectedAction === "generate_command"
                                    implicitWidth: pasteButtonContent.implicitWidth + 16
                                    implicitHeight: 32
                                    buttonRadius: 8
                                    colBackground: Appearance.m3colors.m3secondaryContainer
                                    onClicked: {
                                        pasteProcess.running = true;
                                        Qt.quit();
                                    }
                                    contentItem: RowLayout {
                                        id: pasteButtonContent
                                        anchors.centerIn: parent
                                        spacing: 4
                                        MaterialSymbol {
                                            iconSize: Appearance.font.pixelSize.normal
                                            text: "content_paste"
                                            color: Appearance.m3colors.m3onSecondaryContainer
                                        }
                                        StyledText {
                                            text: Translation.tr("Paste")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.m3colors.m3onSecondaryContainer
                                        }
                                    }
                                }

                                // Send to chat button
                                RippleButton {
                                    implicitWidth: chatButtonContent.implicitWidth + 16
                                    implicitHeight: 32
                                    buttonRadius: 8
                                    colBackground: Appearance.m3colors.m3surfaceContainerHigh
                                    onClicked: {
                                        sendToChatProcess.running = true;
                                        Qt.quit();
                                    }
                                    contentItem: RowLayout {
                                        id: chatButtonContent
                                        anchors.centerIn: parent
                                        spacing: 4
                                        MaterialSymbol {
                                            iconSize: Appearance.font.pixelSize.normal
                                            text: "chat"
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        StyledText {
                                            text: Translation.tr("Chat")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Dismiss button
                                RippleButton {
                                    implicitWidth: dismissButtonContent.implicitWidth + 16
                                    implicitHeight: 32
                                    buttonRadius: 8
                                    colBackground: Appearance.m3colors.m3surfaceContainerHigh
                                    onClicked: {
                                        Qt.quit();
                                    }
                                    contentItem: RowLayout {
                                        id: dismissButtonContent
                                        anchors.centerIn: parent
                                        spacing: 4
                                        MaterialSymbol {
                                            iconSize: Appearance.font.pixelSize.normal
                                            text: "close"
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        StyledText {
                                            text: Translation.tr("Dismiss")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Error overlay (Task 7.1)
                    Rectangle {
                        id: errorOverlay
                        z: 10
                        visible: root.state === ShellRoot.State.Error

                        property bool positionAbove: {
                            const belowY = root.selectedRegionY + root.selectedRegionHeight + 12;
                            const panelHeight = errorColumn.implicitHeight + 32;
                            return (belowY + panelHeight) > panelWindow.height;
                        }

                        x: Math.max(12, Math.min(
                            panelWindow.width - width - 12,
                            root.selectedRegionX + (root.selectedRegionWidth - width) / 2
                        ))
                        y: positionAbove
                            ? root.selectedRegionY - height - 12
                            : root.selectedRegionY + root.selectedRegionHeight + 12

                        width: errorColumn.implicitWidth + 48
                        height: errorColumn.implicitHeight + 32
                        radius: 16
                        color: Appearance.m3colors.m3surface
                        border.width: 1
                        border.color: Appearance.m3colors.m3error

                        // Prevent click-through
                        MouseArea {
                            anchors.fill: parent
                            onClicked: (mouse) => { mouse.accepted = true; }
                        }

                        ColumnLayout {
                            id: errorColumn
                            anchors.centerIn: parent
                            spacing: 12

                            // Error icon
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                iconSize: 32
                                text: "error"
                                color: Appearance.m3colors.m3error
                            }

                            // Error message
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.maximumWidth: 350
                                text: root.errorMessage
                                color: Appearance.m3colors.m3onSurface
                                font.pixelSize: Appearance.font.pixelSize.small
                                wrapMode: Text.Wrap
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Action buttons
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 8

                                // Retry button
                                RippleButton {
                                    implicitWidth: retryContent.implicitWidth + 16
                                    implicitHeight: 32
                                    buttonRadius: 8
                                    colBackground: Appearance.m3colors.m3primaryContainer
                                    onClicked: {
                                        root.errorMessage = "";
                                        root.state = ShellRoot.State.Loading;
                                    }
                                    contentItem: RowLayout {
                                        id: retryContent
                                        anchors.centerIn: parent
                                        spacing: 4
                                        MaterialSymbol {
                                            iconSize: Appearance.font.pixelSize.normal
                                            text: "refresh"
                                            color: Appearance.m3colors.m3onPrimaryContainer
                                        }
                                        StyledText {
                                            text: Translation.tr("Retry")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.m3colors.m3onPrimaryContainer
                                        }
                                    }
                                }

                                // Dismiss button
                                RippleButton {
                                    implicitWidth: errorDismissContent.implicitWidth + 16
                                    implicitHeight: 32
                                    buttonRadius: 8
                                    colBackground: Appearance.m3colors.m3surfaceContainerHigh
                                    onClicked: {
                                        Qt.quit();
                                    }
                                    contentItem: RowLayout {
                                        id: errorDismissContent
                                        anchors.centerIn: parent
                                        spacing: 4
                                        MaterialSymbol {
                                            iconSize: Appearance.font.pixelSize.normal
                                            text: "close"
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        StyledText {
                                            text: Translation.tr("Dismiss")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
