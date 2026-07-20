import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property var editingProvider: null
    signal back()
    signal saved(string providerId)

    property bool isEditing: editingProvider !== null

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // --- Header row ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer1
                }
                releaseAction: function() { root.back() }
            }

            StyledText {
                text: root.isEditing ? Translation.tr("Edit Provider") : Translation.tr("Add Custom Provider")
                font.pixelSize: Appearance.font.pixelSize.large
                font.bold: true
                color: Appearance.colors.colOnLayer1
                Layout.fillWidth: true
            }
        }

        // --- Display name field ---
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                text: Translation.tr("Display Name")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            TextField {
                id: nameInput
                Layout.fillWidth: true
                placeholderText: "My vLLM Server"
                text: root.editingProvider ? root.editingProvider.name : ""
            }
        }

        // --- Base URL field ---
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                text: Translation.tr("Base URL")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            TextField {
                id: urlInput
                Layout.fillWidth: true
                placeholderText: "http://localhost:5000/v1"
                text: root.editingProvider ? root.editingProvider.baseUrl : ""
            }
        }

        // --- Optional API key field ---
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                text: Translation.tr("API Key (optional)")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            TextField {
                id: keyInput
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: Translation.tr("Leave empty if not required")
                text: root.editingProvider ? (root.editingProvider.apiKey || "") : ""
            }
        }

        // --- Error message ---
        StyledText {
            id: errorLabel
            visible: false
            text: ""
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colError
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        // --- Buttons row ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            RippleButton {
                implicitHeight: 36
                buttonRadius: Appearance.rounding.small
                contentItem: StyledText {
                    text: Translation.tr("Save")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                releaseAction: function() {
                    var name = nameInput.text.trim();
                    var url = urlInput.text.trim();
                    // Validate name
                    if (name.length === 0) {
                        errorLabel.text = Translation.tr("Name is required");
                        errorLabel.visible = true;
                        return;
                    }
                    // Validate URL
                    if (url.length === 0 || (url.indexOf("http://") !== 0 && url.indexOf("https://") !== 0)) {
                        errorLabel.text = Translation.tr("A valid URL starting with http:// or https:// is required");
                        errorLabel.visible = true;
                        return;
                    }
                    errorLabel.visible = false;

                    var apiKey = keyInput.text.trim();
                    var providerId = "";
                    if (root.isEditing) {
                        providerId = root.editingProvider.id;
                        ModelDiscoveryService.updateCustomProvider(providerId, name, url, apiKey);
                    } else {
                        providerId = ModelDiscoveryService.addCustomProvider(name, url, apiKey);
                    }
                    root.saved(providerId);
                }
            }

            RippleButton {
                implicitHeight: 36
                buttonRadius: Appearance.rounding.small
                contentItem: StyledText {
                    text: Translation.tr("Cancel")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                releaseAction: function() { root.back() }
            }

            // Delete button (only visible when editing)
            RippleButton {
                visible: root.isEditing
                implicitHeight: 36
                buttonRadius: Appearance.rounding.small
                contentItem: StyledText {
                    text: Translation.tr("Delete")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colError
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                releaseAction: function() {
                    ModelDiscoveryService.deleteCustomProvider(root.editingProvider.id);
                    root.back();
                }
            }
        }

        // Spacer to push content up
        Item {
            Layout.fillHeight: true
        }
    }
}
