import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property string sectionTitle: ""
    property string providerType: "stt"  // "stt" or "tts"
    property var providerData: ({})       // JsonObject from Config (sttProviders or ttsProviders)
    property int aiPolicy: 1             // Config.options.policies.ai

    signal providerSelected(string providerKey)

    // Internal state: which provider is being viewed in detail mode
    property string _selectedProvider: ""

    // Computed filtered provider list based on policy
    property var filteredProviders: {
        var allKeys = Object.keys(root.providerData || {})
        if (root.aiPolicy === 0) return []
        if (root.aiPolicy === 1) return allKeys

        // policy === 2: local-only
        var result = []
        for (var i = 0; i < allKeys.length; i++) {
            var key = allKeys[i]
            var config = root.providerData[key]
            if (!config) continue
            // Include if no endpoint (local CLI tool) or endpoint is local
            if (!config.endpoint || VoiceProviderCheckService.isLocal(config.endpoint)) {
                result.push(key)
            }
        }
        return result
    }

    // Don't render anything if no providers after filtering
    visible: filteredProviders.length > 0
    implicitHeight: visible ? contentColumn.implicitHeight : 0

    ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6

        // Section header (only show in list mode)
        StyledText {
            visible: root._selectedProvider === ""
            text: root.sectionTitle
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: Appearance.colors.colSubtext
            Layout.fillWidth: true
            Layout.topMargin: 8
        }

        // List view (when no provider selected)
        ListView {
            id: providerListView
            visible: root._selectedProvider === ""
            Layout.fillWidth: true
            implicitHeight: contentHeight
            interactive: false  // Let the parent scroll
            model: root.filteredProviders
            spacing: 4

            delegate: VoiceProviderListItem {
                required property string modelData
                required property int index
                width: providerListView.width
                providerKey: modelData
                providerConfig: root.providerData[modelData] || ({})
                statusState: {
                    var state = VoiceProviderCheckService.checkStates[modelData]
                    if (state) return state.status
                    // If no endpoint, show "local" by default
                    var config = root.providerData[modelData]
                    if (config && !config.endpoint) return "local"
                    return "idle"
                }
                onClicked: {
                    root._selectedProvider = modelData
                    root.providerSelected(modelData)
                }
            }
        }

        // Detail view (when provider selected)
        Loader {
            visible: root._selectedProvider !== ""
            active: root._selectedProvider !== ""
            Layout.fillWidth: true
            Layout.fillHeight: true

            sourceComponent: VoiceProviderDetailView {
                providerKey: root._selectedProvider
                providerType: root.providerType
                providerConfig: root.providerData[root._selectedProvider] || ({})
                onBack: root._selectedProvider = ""
            }
        }
    }
}
