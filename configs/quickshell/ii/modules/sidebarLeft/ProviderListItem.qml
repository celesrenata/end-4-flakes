import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

RippleButton {
    id: root

    required property string providerId
    signal providerClicked()

    property var config: ModelDiscoveryService.getEffectiveProviderConfig(providerId)
    property var validationState: ModelDiscoveryService.validationStates[providerId] || { status: "idle", message: "" }

    implicitHeight: 44
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover

    releaseAction: function() {
        root.providerClicked()
    }

    contentItem: RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        CustomIcon {
            id: providerIcon
            width: Appearance.font.pixelSize.larger
            height: Appearance.font.pixelSize.larger
            source: root.config ? root.config.icon : "ai-openai-symbolic"
            colorize: true
            color: Appearance.m3colors.m3onSecondaryContainer
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            text: root.config ? root.config.name : root.providerId
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer2
        }

        // Validation status indicator (green dot for success, nothing otherwise)
        Rectangle {
            visible: root.validationState.status === "success"
            width: 8
            height: 8
            radius: 4
            color: Appearance.colors.colPrimary
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
