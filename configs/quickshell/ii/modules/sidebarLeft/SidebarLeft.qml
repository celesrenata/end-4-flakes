import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property int sidebarPadding: 15
    property bool detach: false
    property Component contentComponent: SidebarLeftContent {}
    property Item sidebarContent

    Component.onCompleted: {
        root.sidebarContent = contentComponent.createObject(null, {
            "scopeRoot": root,
        });
        sidebarLoader.item.contentParent.children = [root.sidebarContent];
    }

    onDetachChanged: {
        if (root.detach) {
            sidebarContent.parent = null; // Detach content from sidebar
            sidebarLoader.active = false; // Unload sidebar
            detachedSidebarLoader.active = true; // Load detached window
            detachedSidebarLoader.item.contentParent.children = [sidebarContent];
        } else {
            sidebarContent.parent = null; // Detach content from window
            detachedSidebarLoader.active = false; // Unload detached window
            sidebarLoader.active = true; // Load sidebar
            sidebarLoader.item.contentParent.children = [sidebarContent];
        }
    }

    Loader {
        id: sidebarLoader
        active: true
        
        sourceComponent: PanelWindow { // Window
            id: sidebarRoot
            visible: poppedOut || GlobalStates.sidebarLeftOpen
            
            property bool poppedOut: Persistent.states.sidebar.poppedOut
            property bool extend: false
            property real userWidth: Persistent.states.sidebar?.leftWidth ?? Appearance.sizes.sidebarWidth
            property real minWidth: Appearance.sizes.sidebarWidth
            property real maxWidth: sidebarRoot.screen ? sidebarRoot.screen.width * 0.8 : 1500
            property real sidebarWidth: Math.max(minWidth, Math.min(maxWidth, userWidth))
            property var contentParent: sidebarLeftBackground

            function hide() {
                GlobalStates.sidebarLeftOpen = false
            }

            // Delay exclusive zone claim at startup to avoid blocking background rendering
            property bool startupComplete: false
            Timer {
                interval: 100
                running: true
                repeat: false
                onTriggered: sidebarRoot.startupComplete = true
            }
            exclusionMode: (poppedOut && startupComplete) ? ExclusionMode.Normal : ExclusionMode.Ignore
            exclusiveZone: (poppedOut && startupComplete) ? sidebarWidth : 0
            implicitWidth: maxWidth + Appearance.sizes.elevationMargin
            WlrLayershell.namespace: "quickshell:sidebarLeft"
            WlrLayershell.keyboardFocus: poppedOut ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
                left: true
                bottom: true
            }

            mask: Region {
                item: sidebarLeftBackground
            }

            HyprlandFocusGrab { // Click outside to close
                id: grab
                windows: [ sidebarRoot ]
                active: sidebarRoot.visible && !sidebarRoot.poppedOut
                onActiveChanged: { // Focus the selected tab
                    if (active) sidebarLeftBackground.children[0].focusActiveItem()
                }
                onCleared: () => {
                    if (!active) sidebarRoot.hide()
                }
            }

            // Content
            StyledRectangularShadow {
                target: sidebarLeftBackground
                radius: sidebarLeftBackground.radius
            }

            // Popout toggle button (above sidebar content to avoid being covered)
            RippleButton {
                id: popoutButton
                anchors.top: sidebarLeftBackground.top
                anchors.right: sidebarLeftBackground.right
                anchors.topMargin: Appearance.sizes.hyprlandGapsOut + 8
                anchors.rightMargin: 8
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: Appearance.rounding.full
                z: 200

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "push_pin"
                    iconSize: 16
                    fill: sidebarRoot.poppedOut ? 1 : 0
                    color: Appearance.colors.colOnLayer1
                }

                releaseAction: function() {
                    Persistent.states.sidebar.poppedOut = !sidebarRoot.poppedOut;
                }
            }

            Rectangle {
                id: sidebarLeftBackground
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: Appearance.sizes.hyprlandGapsOut
                anchors.leftMargin: Appearance.sizes.hyprlandGapsOut
                width: sidebarRoot.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                height: parent.height - Appearance.sizes.hyprlandGapsOut * 2
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

                Behavior on width {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        sidebarRoot.hide();
                    }
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_O) {
                            // Toggle between min width and extended
                            if (sidebarRoot.userWidth > sidebarRoot.minWidth + 20) {
                                sidebarRoot.userWidth = sidebarRoot.minWidth;
                            } else {
                                sidebarRoot.userWidth = Appearance.sizes.sidebarWidthExtended;
                            }
                            Persistent.states.sidebar.leftWidth = sidebarRoot.userWidth;
                        }
                        else if (event.key === Qt.Key_P) {
                            Persistent.states.sidebar.poppedOut = !sidebarRoot.poppedOut;
                        }
                        event.accepted = true;
                    }
                }
            }

            // Resize handle on the right edge of the sidebar
            Rectangle {
                id: resizeHandle
                anchors.top: sidebarLeftBackground.top
                anchors.bottom: sidebarLeftBackground.bottom
                x: sidebarLeftBackground.x + sidebarLeftBackground.width - 2
                width: 6
                color: resizeMouseArea.containsMouse || resizeMouseArea.pressed ? Appearance.colors.colPrimary : "transparent"
                opacity: resizeMouseArea.containsMouse || resizeMouseArea.pressed ? 0.3 : 0
                radius: 3

                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }

                MouseArea {
                    id: resizeMouseArea
                    anchors.fill: parent
                    anchors.margins: -3
                    hoverEnabled: true
                    cursorShape: Qt.SplitHCursor
                    property real startX: 0
                    property real startWidth: 0

                    onPressed: (mouse) => {
                        startX = mouse.x + resizeHandle.x;
                        startWidth = sidebarRoot.userWidth;
                    }
                    onPositionChanged: (mouse) => {
                        if (pressed) {
                            let delta = (mouse.x + resizeHandle.x) - startX;
                            let newWidth = startWidth + delta;
                            sidebarRoot.userWidth = Math.max(sidebarRoot.minWidth, Math.min(sidebarRoot.maxWidth, newWidth));
                        }
                    }
                    onReleased: {
                        // Persist the new width
                        Persistent.states.sidebar.leftWidth = sidebarRoot.userWidth;
                    }
                }
            }
        }
    }

    Loader {
        id: detachedSidebarLoader
        active: false

        sourceComponent: FloatingWindow {
            id: detachedSidebarRoot
            visible: GlobalStates.sidebarLeftOpen
            property var contentParent: detachedSidebarBackground
            
            Rectangle {
                id: detachedSidebarBackground
                anchors.fill: parent
                color: Appearance.colors.colLayer0

                Keys.onPressed: (event) => {
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_P) {
                            root.detach = !root.detach;
                        }
                        event.accepted = true;
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
        }

        function close(): void {
            GlobalStates.sidebarLeftOpen = false
        }

        function open(): void {
            GlobalStates.sidebarLeftOpen = true
        }

        function togglePopout(): void {
            Persistent.states.sidebar.poppedOut = !Persistent.states.sidebar.poppedOut
        }
    }

    IpcHandler {
        target: "contextLens"

        function sendToChat(imageBase64, resultText, actionLabel) {
            GlobalStates.sidebarLeftOpen = true;
            var content = "[Context Lens: " + actionLabel + "]\n\n" + resultText;
            var message = Ai.aiMessageComponent.createObject(Ai, {
                "role": "user",
                "content": content,
                "rawContent": content,
                "images": [imageBase64],
                "thinking": false,
                "done": true,
            });
            var id = Ai.idForMessage(message);
            Ai.messageIDs = [...Ai.messageIDs, id];
            Ai.messageByID[id] = message;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Opens left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftClose"
        description: "Closes left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = false;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggleDetach"
        description: "Detach left sidebar into a window/Attach it back"

        onPressed: {
            root.detach = !root.detach;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftTogglePopout"
        description: "Toggles left sidebar popout mode"

        onPressed: {
            Persistent.states.sidebar.poppedOut = !Persistent.states.sidebar.poppedOut;
        }
    }

}
