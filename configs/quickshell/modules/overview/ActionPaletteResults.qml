pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Delegate for rendering AI Action Palette results in the search list.
 * Wraps SearchItem with per-action type icons and warning indicators
 * for invalid actions. Reuses SearchItem patterns for consistent appearance.
 *
 * Per-action icon mapping:
 *   config.set       → "settings"
 *   shell.exec       → "terminal"
 *   hyprland.dispatch → "open_with"
 *   app.launch       → "apps"
 *
 * Requirements: 4.1, 4.2
 */
Item {
    id: root

    required property var entry
    property string query: ""

    // Per-action icon mapping for visual differentiation
    readonly property var typeIcons: ({
        "config.set": "settings",
        "shell.exec": "terminal",
        "hyprland.dispatch": "open_with",
        "app.launch": "apps"
    })

    // Whether this entry represents an invalid/warning action
    readonly property bool isWarning: entry?.materialSymbol === "warning"

    implicitHeight: searchItem.implicitHeight
    implicitWidth: parent?.width ?? 400

    // Warning accent bar for invalid actions
    Rectangle {
        id: warningIndicator
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: parent.height - 12
        radius: 2
        color: Appearance.m3colors.m3error
        visible: root.isWarning
        opacity: 0.8
    }

    SearchItem {
        id: searchItem
        anchors.left: parent.left
        anchors.right: parent.right
        entry: root.entry
        query: root.query
    }
}
