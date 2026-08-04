pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property real padding: 4
    implicitWidth: Math.min(flow.implicitWidth + Appearance.rounding.small * 2, QsWindow?.window?.screen.width * 0.75 ?? 800)
    implicitHeight: Math.min(flow.implicitHeight + Appearance.rounding.small * 2, QsWindow?.window?.screen.height * 0.7 ?? 600)

    StyledFlickable {
        id: flickable
        clip: true
        anchors.fill: parent
        anchors.margins: Appearance.rounding.small
        contentHeight: flow.implicitHeight
        contentWidth: flow.implicitWidth

        Flow {
            id: flow
            height: flickable.height
            flow: Flow.TopToBottom
            spacing: 30

            Repeater {
                model: [...HyprlandKeybinds.keybindCategories, ""]
                delegate: CheatsheetKeybindsCategory {
                    required property var modelData
                    categoryName: modelData
                }
            }
        }
    }

    ScrollEdgeFade {
        target: flickable
        vertical: false
        color: Appearance.colors.colLayer0Base ?? Appearance.colors.colLayer0 ?? "transparent"
    }
}
