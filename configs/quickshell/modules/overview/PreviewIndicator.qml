pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Floating bar shown during AI Action Palette preview mode.
 * Displays "Previewing changes" text with Commit and Revert buttons.
 * Visible only when ActionPalette.previewActive is true.
 */
Item {
    id: root
    visible: ActionPalette.previewActive
    implicitWidth: barBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: barBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

    StyledRectangularShadow {
        target: barBackground
    }

    Rectangle {
        id: barBackground
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin

        implicitWidth: rowLayout.implicitWidth + 24
        implicitHeight: rowLayout.implicitHeight + 16
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer1Border

        RowLayout {
            id: rowLayout
            anchors.centerIn: parent
            spacing: 12

            MaterialSymbol {
                text: "preview"
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.m3colors.m3primary
            }

            StyledText {
                text: Translation.tr("Previewing changes")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3onSurface
            }

            RippleButton {
                implicitHeight: 30
                implicitWidth: commitLabel.implicitWidth + 30
                buttonRadius: Appearance.rounding.full

                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover

                contentItem: StyledText {
                    id: commitLabel
                    anchors.centerIn: parent
                    text: Translation.tr("Commit")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.m3colors.m3onPrimary
                    horizontalAlignment: Text.AlignHCenter
                }

                onClicked: ActionPalette.commitPreview()
            }

            RippleButton {
                implicitHeight: 30
                implicitWidth: revertLabel.implicitWidth + 30
                buttonRadius: Appearance.rounding.full

                contentItem: StyledText {
                    id: revertLabel
                    anchors.centerIn: parent
                    text: Translation.tr("Revert")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.m3colors.m3onSurface
                    horizontalAlignment: Text.AlignHCenter
                }

                onClicked: ActionPalette.revertPreview()
            }
        }
    }
}
