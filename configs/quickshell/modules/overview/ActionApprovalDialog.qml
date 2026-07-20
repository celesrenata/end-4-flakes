pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Approval dialog for shell.exec actions in the AI Action Palette.
 * Shows the full command text and requires explicit user approval before
 * execution proceeds. Styling is consistent with the sidebar's existing
 * command approval gate (ButtonGroup + GroupButton pattern).
 *
 * Requirements: 5.3, 5.4
 */
Rectangle {
    id: root

    property string command: ""
    property int actionIndex: -1
    property bool shown: false

    visible: root.shown
    implicitWidth: contentLayout.implicitWidth + 32
    implicitHeight: contentLayout.implicitHeight + 32
    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    Connections {
        target: ActionPalette
        function onApprovalRequired(command, actionIndex) {
            root.command = command;
            root.actionIndex = actionIndex;
            root.shown = true;
        }
    }

    ColumnLayout {
        id: contentLayout
        anchors.centerIn: parent
        anchors.margins: 16
        spacing: 12

        // Header with shield icon and title
        RowLayout {
            spacing: 8

            MaterialSymbol {
                text: "shield"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.m3colors.m3error
            }

            StyledText {
                text: Translation.tr("Approve shell command?")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.bold: true
                color: Appearance.m3colors.m3onSurface
            }
        }

        // Command display in monospace within a distinct container
        Rectangle {
            Layout.fillWidth: true
            Layout.minimumWidth: 300
            Layout.maximumWidth: 500
            implicitHeight: commandText.implicitHeight + 16
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            StyledText {
                id: commandText
                anchors.fill: parent
                anchors.margins: 8
                text: root.command
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3onSurface
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }
        }

        // Approve/Reject buttons using the same ButtonGroup pattern as sidebar
        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 0

            Item { Layout.fillWidth: true }

            ButtonGroup {
                GroupButton {
                    contentItem: StyledText {
                        text: Translation.tr("Reject")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                    }
                    onClicked: {
                        root.shown = false;
                        ActionPalette.rejectCommand();
                    }
                }
                GroupButton {
                    toggled: true
                    contentItem: StyledText {
                        text: Translation.tr("Approve")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnPrimary
                    }
                    onClicked: {
                        root.shown = false;
                        ActionPalette.approveCommand(root.actionIndex);
                    }
                }
            }
        }
    }
}
