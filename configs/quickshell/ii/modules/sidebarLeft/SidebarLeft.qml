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
            visible: GlobalStates.sidebarLeftOpen
            
            property bool extend: false
            property real userWidth: Persistent.states.sidebar?.leftWidth ?? Appearance.sizes.sidebarWidth
            property real minWidth: Appearance.sizes.sidebarWidth
            property real maxWidth: sidebarRoot.screen ? sidebarRoot.screen.width * 0.8 : 1500
            property real sidebarWidth: Math.max(minWidth, Math.min(maxWidth, userWidth))
            property var contentParent: sidebarLeftBackground

            function hide() {
                GlobalStates.sidebarLeftOpen = false
            }

            exclusiveZone: 0
            implicitWidth: maxWidth + Appearance.sizes.elevationMargin
            WlrLayershell.namespace: "quickshell:sidebarLeft"
            // Hyprland 0.49: OnDemand is Exclusive, Exclusive just breaks click-outside-to-close
            // WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
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
                active: sidebarRoot.visible
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
                            root.detach = !root.detach;
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

}
