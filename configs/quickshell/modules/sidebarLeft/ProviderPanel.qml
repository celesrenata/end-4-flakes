import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string selectedProvider: ""
    property bool showCustomForm: false
    property var editingCustomProvider: null

    // Compute the list of provider IDs based on policy and custom providers
    property var providerList: {
        var builtIn = [];
        if (Config.options.policies.ai === 2) {
            builtIn = ["ollama"];
        } else {
            builtIn = ["openai", "anthropic", "gemini", "mistral", "openrouter", "ollama"];
        }
        // Add custom providers
        var customs = ModelDiscoveryService.customProviders || [];
        var customIds = [];
        for (var i = 0; i < customs.length; i++) {
            if (Config.options.policies.ai === 2) {
                // In local-only mode, only show custom providers with localhost URLs
                var baseUrl = customs[i].baseUrl || "";
                if (baseUrl.indexOf("localhost") !== -1 || baseUrl.indexOf("127.0.0.1") !== -1) {
                    customIds.push(customs[i].id);
                }
            } else {
                customIds.push(customs[i].id);
            }
        }
        return builtIn.concat(customIds);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Provider list view (when no provider selected and not showing custom form)
        ListView {
            id: providerListView
            visible: root.selectedProvider === "" && !root.showCustomForm
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.providerList
            spacing: 4
            clip: true

            delegate: ProviderListItem {
                required property int index
                required property string modelData
                width: providerListView.width
                providerId: modelData
                onClicked: root.selectedProvider = providerId
            }

            footer: Item {
                width: providerListView.width
                height: addCustomBtn.height + 16

                RippleButton {
                    id: addCustomBtn
                    anchors.centerIn: parent
                    buttonText: Translation.tr("Add Custom")
                    onClicked: {
                        root.showCustomForm = true;
                        root.editingCustomProvider = null;
                    }
                }
            }
        }

        // Provider detail view (when provider selected)
        Loader {
            visible: root.selectedProvider !== "" && !root.showCustomForm
            active: root.selectedProvider !== "" && !root.showCustomForm
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: ProviderDetailView {
                providerId: root.selectedProvider
                onBack: root.selectedProvider = ""
                onEditCustom: function(provider) {
                    root.editingCustomProvider = provider;
                    root.showCustomForm = true;
                }
            }
        }

        // Custom provider form (when adding/editing)
        Loader {
            visible: root.showCustomForm
            active: root.showCustomForm
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: CustomProviderForm {
                editingProvider: root.editingCustomProvider
                onBack: {
                    root.showCustomForm = false;
                    root.editingCustomProvider = null;
                }
                onSaved: function(providerId) {
                    root.showCustomForm = false;
                    root.editingCustomProvider = null;
                    root.selectedProvider = providerId;
                }
            }
        }
    }
}
