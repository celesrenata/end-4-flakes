pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string url: ""
    property bool fetchAvailable: {
        const state = McpClient.serverStates["fetch"];
        return state !== undefined && state !== "disabled";
    }

    signal fetchRequested(string url)
    signal openRequested(string url)

    Layout.fillWidth: false
    implicitWidth: chipRow.implicitWidth + 8
    implicitHeight: 28

    Rectangle {
        id: background
        anchors.fill: parent
        radius: Appearance.rounding.full
        color: Appearance.colors.colSurfaceContainerHighest
    }

    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: 2

        // "Fetch with AI" button — only visible if fetch server is available
        RippleButton {
            id: fetchButton
            visible: root.fetchAvailable
            implicitWidth: 24
            implicitHeight: 24
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
            colRipple: Appearance.colors.colSurfaceContainerHighestActive

            PointingHandInteraction {}
            onClicked: {
                root.fetchRequested(root.url);
            }

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "download"
                iconSize: 16
                color: Appearance.m3colors.m3primary
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        // "Open in browser" button
        RippleButton {
            id: openButton
            implicitWidth: 24
            implicitHeight: 24
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
            colRipple: Appearance.colors.colSurfaceContainerHighestActive

            PointingHandInteraction {}
            onClicked: {
                Qt.openUrlExternally(root.url);
                root.openRequested(root.url);
            }

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "open_in_new"
                iconSize: 16
                color: Appearance.m3colors.m3onSurface
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
