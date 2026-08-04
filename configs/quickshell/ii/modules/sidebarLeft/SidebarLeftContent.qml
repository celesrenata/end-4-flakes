import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    required property var scopeRoot
    anchors.fill: parent
    property var tabButtonList: [
        ...(Config.options.policies.ai !== 0 ? [{"icon": "neurology", "name": Translation.tr("Intelligence")}, {"icon": "key", "name": Translation.tr("Providers")}] : []),
        {"icon": "translate", "name": Translation.tr("Translator")},
        ...(Config.options.policies.weeb === 1 ? [{"icon": "bookmark_heart", "name": Translation.tr("Anime")}] : [])
    ]
    property int selectedTab: 0

    function focusActiveItem() {
        contentStack.currentItem?.forceActiveFocus()
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                root.selectedTab = Math.min(root.selectedTab + 1, root.tabButtonList.length - 1)
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                root.selectedTab = Math.max(root.selectedTab - 1, 0)
                event.accepted = true;
            }
            else if (event.key === Qt.Key_Tab) {
                root.selectedTab = (root.selectedTab + 1) % root.tabButtonList.length;
                event.accepted = true;
            }
            else if (event.key === Qt.Key_Backtab) {
                root.selectedTab = (root.selectedTab - 1 + root.tabButtonList.length) % root.tabButtonList.length;
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.topMargin: sidebarPadding
        anchors.bottomMargin: sidebarPadding
        anchors.rightMargin: 4
        spacing: 0

        // ── Icon-only tab bar ──
        ColumnLayout {
            id: tabBarContainer
            Layout.fillWidth: true
            spacing: 0

            TabBar {
                id: tabBar
                Layout.fillWidth: true
                currentIndex: root.selectedTab
                onCurrentIndexChanged: {
                    root.selectedTab = currentIndex
                }

                background: Item {
                    WheelHandler {
                        onWheel: (event) => {
                            if (event.angleDelta.y < 0)
                                tabBar.currentIndex = Math.min(tabBar.currentIndex + 1, root.tabButtonList.length - 1)
                            else if (event.angleDelta.y > 0)
                                tabBar.currentIndex = Math.max(tabBar.currentIndex - 1, 0)
                        }
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    }
                }

                Repeater {
                    model: root.tabButtonList
                    delegate: TabButton {
                        id: iconTab
                        required property int index
                        required property var modelData
                        property bool selected: index === root.selectedTab

                        implicitHeight: 40
                        padding: 0

                        // Use Layout.fillWidth instead of binding to tabBar.width to avoid loop
                        Layout.fillWidth: true

                        background: Rectangle {
                            radius: Appearance.rounding.small
                            color: iconTab.hovered
                                ? Appearance.colors.colLayer1Hover
                                : "transparent"
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }

                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: iconTab.modelData.icon
                            iconSize: Appearance.font.pixelSize.hugeass
                            fill: iconTab.selected ? 1 : 0
                            color: iconTab.selected
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnLayer1

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }

                        StyledToolTip {
                            content: iconTab.modelData.name
                            extraVisibleCondition: false
                            alternativeVisibleCondition: iconTab.hovered
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tabBar.currentIndex = iconTab.index
                        }
                    }
                }
            }

            // Tab indicator
            Item {
                Layout.fillWidth: true
                height: 3

                Rectangle {
                    id: indicator
                    property int tabCount: root.tabButtonList.length
                    property real fullTabSize: tabBar.width / tabCount
                    property real targetWidth: Math.min(24, fullTabSize * 0.5)

                    implicitWidth: targetWidth
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    x: tabBar.currentIndex * fullTabSize + (fullTabSize - targetWidth) / 2

                    color: Appearance.colors.colPrimary
                    radius: Appearance.rounding.full

                    Behavior on x {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
            }

            // Bottom border
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.m3colors.m3outlineVariant
            }
        }

        // ── Content area ──
        SwipeView {
            id: contentStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 8
            currentIndex: root.selectedTab
            onCurrentIndexChanged: root.selectedTab = currentIndex
            clip: true

            contentChildren: [
                ...(Config.options.policies.ai !== 0 ? [aiChatComponent.createObject(), providerPanelComponent.createObject()] : []),
                translatorComponent.createObject(),
                ...(Config.options.policies.weeb === 0 ? [] : [animeComponent.createObject()])
            ]
        }

        Component {
            id: aiChatComponent
            AiChat {}
        }
        Component {
            id: providerPanelComponent
            ProviderPanel {}
        }
        Component {
            id: translatorComponent
            Translator {}
        }
        Component {
            id: animeComponent
            Anime {}
        }
    }
}
