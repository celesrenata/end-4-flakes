import QtQuick
import QtQuick.Layouts
import qs.modules.common

// Workspace widget variant selector
// Loads "default" or "hefty" variant based on Config.options.bar.workspaces.variant
Item {
    id: workspacesRoot

    required property var bar
    property int widgetPadding: loader.item?.widgetPadding ?? 4

    Layout.fillHeight: true
    implicitWidth: loader.item?.implicitWidth ?? 0
    implicitHeight: loader.item?.implicitHeight ?? Appearance.sizes.barHeight

    Loader {
        id: loader
        anchors.fill: parent
        sourceComponent: Config.options.bar.workspaces.variant === "hefty" ? heftyComponent : defaultComponent
    }

    Component {
        id: defaultComponent
        WorkspacesDefault {
            bar: workspacesRoot.bar
        }
    }

    Component {
        id: heftyComponent
        WorkspacesHefty {
            bar: workspacesRoot.bar
        }
    }
}
