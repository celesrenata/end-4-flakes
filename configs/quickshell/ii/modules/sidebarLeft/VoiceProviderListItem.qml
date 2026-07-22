import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

RippleButton {
    id: root

    required property string providerKey
    required property var providerConfig
    property string statusState: "idle"  // "idle", "checking", "reachable", "unreachable", "local"

    implicitHeight: 52
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover

    contentItem: RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        // Provider name and endpoint in a column
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                text: root.providerKey
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer2
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            StyledText {
                text: root.providerConfig ? (root.providerConfig.endpoint || "local") : ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                Layout.fillWidth: true
                visible: text !== ""
            }
        }

        // Status indicator dot
        Rectangle {
            id: statusDot
            width: 10
            height: 10
            radius: 5
            Layout.alignment: Qt.AlignVCenter
            color: {
                switch (root.statusState) {
                    case "reachable": return Appearance.colors.colPrimary
                    case "unreachable": return Appearance.m3colors.m3error
                    case "local": return Appearance.m3colors.m3tertiary
                    case "checking": return Appearance.colors.colSubtext
                    default: return Appearance.colors.colOutlineVariant  // idle
                }
            }

            // Spinning animation for "checking" state
            SequentialAnimation on rotation {
                running: root.statusState === "checking"
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: 360; duration: 1000 }
            }

            // Pulsing opacity for "checking" state
            SequentialAnimation on opacity {
                running: root.statusState === "checking"
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.4; duration: 500 }
                NumberAnimation { from: 0.4; to: 1.0; duration: 500 }
            }
        }
    }
}
