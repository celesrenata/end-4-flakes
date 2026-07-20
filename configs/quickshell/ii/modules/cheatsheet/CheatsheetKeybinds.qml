import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: root
    
    // Constrain the content to reasonable size
    implicitWidth: Math.min(rowLayout.implicitWidth, 1200)
    implicitHeight: Math.min(rowLayout.implicitHeight, 800)
    
    readonly property var keybinds: HyprlandKeybinds.keybinds
    property real spacing: 20
    property real titleSpacing: 7
    
    Component.onCompleted: {
        console.log("[CheatsheetKeybinds] Component loaded")
        console.log("[CheatsheetKeybinds] Keybinds object:", JSON.stringify(keybinds))
        console.log("[CheatsheetKeybinds] Keybinds children length:", keybinds?.children?.length || 0)
        console.log("[CheatsheetKeybinds] Keybinds keybinds length:", keybinds?.keybinds?.length || 0)
    }
    
    onKeybindsChanged: {
        console.log("[CheatsheetKeybinds] Keybinds changed:", JSON.stringify(keybinds))
        console.log("[CheatsheetKeybinds] Children:", keybinds?.children?.length || 0, "Keybinds:", keybinds?.keybinds?.length || 0)
    }

    property var keyBlacklist: ["Super_L"]
    property var keySubstitutions: ({
        "Super": "󰖳",
        "mouse_up": "Scroll ↓",    // ikr, weird
        "mouse_down": "Scroll ↑",  // trust me bro
        "mouse:272": "LMB",
        "mouse:273": "RMB",
        "mouse:275": "MouseBack",
        "Slash": "/",
        "Hash": "#",
        "Return": "Enter",
        // "Shift": "",
    })

    ScrollView {
        id: scrollView
        anchors.fill: parent
        clip: true
        
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOn
        ScrollBar.vertical.policy: ScrollBar.AlwaysOn
        
        GridLayout {
            id: rowLayout
            columns: 2
            
            Repeater {
                model: {
                    var result = [];
                    var kb = keybinds?.keybinds || [];
                    for (var i = 0; i < kb.length; i++) {
                        const keybind = kb[i];
                        result.push({
                            "type": "keys",
                            "mods": keybind.mods,
                            "key": keybind.key,
                        });
                        result.push({
                            "type": "comment",
                            "comment": keybind.comment,
                        });
                    }
                    return result;
                }
                
                delegate: Item {
                    required property var modelData
                    implicitWidth: keybindLoader.implicitWidth
                    implicitHeight: keybindLoader.implicitHeight

                    Loader {
                        id: keybindLoader
                        sourceComponent: (modelData.type === "keys") ? keysComponent : commentComponent
                    }

                    Component {
                        id: keysComponent
                        RowLayout {
                            spacing: 4
                            Repeater {
                                model: modelData.mods
                                delegate: KeyboardKey {
                                    required property var modelData
                                    key: keySubstitutions[modelData] || modelData
                                }
                            }
                            StyledText {
                                id: keybindPlus
                                visible: !keyBlacklist.includes(modelData.key) && modelData.mods.length > 0
                                Layout.alignment: Qt.AlignVCenter
                                text: "+"
                            }
                            KeyboardKey {
                                id: keybindKey
                                visible: !keyBlacklist.includes(modelData.key)
                                key: keySubstitutions[modelData.key] || modelData.key
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }

                    Component {
                        id: commentComponent
                        Item {
                            id: commentItem
                            implicitWidth: commentText.implicitWidth + 8 * 2
                            implicitHeight: commentText.implicitHeight

                            StyledText {
                                id: commentText
                                anchors.centerIn: parent
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                text: modelData.comment
                            }
                        }
                    }
                }
            }
        }
    }
}
