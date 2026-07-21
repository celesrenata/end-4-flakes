import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    required property string modelName
    required property string modelId
    property string providerIcon: ""

    implicitHeight: 44
    width: parent ? parent.width : 200

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        CustomIcon {
            visible: root.providerIcon !== ""
            source: root.providerIcon
            width: Appearance.font.pixelSize.large
            height: Appearance.font.pixelSize.large
            Layout.alignment: Qt.AlignVCenter
            colorize: true
            color: Appearance.colors.colOnLayer1
        }

        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            StyledText {
                text: root.modelName
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            StyledText {
                text: root.modelId
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }
}
