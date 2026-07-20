pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Category grouping for cheatsheet keybinds
// Groups keybinds by "Category: Description" format and displays them with distinct headers
Column {
    id: root
    required property string categoryName
    readonly property bool isCategorized: categoryName?.length > 0
    property int maxBindWidth: 0
    property real columnSpacing: 40
    property real titleSpacing: 7

    property var keyBlacklist: ["SUPER_L", "SUPER_R"]
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
    })

    function modMaskToStringList(modMask: int): list<string> {
        var list = [];
        if (modMask & (1 << 2)) { list.push("Ctrl"); }
        if (modMask & (1 << 6)) { list.push("Super"); }
        if (modMask & (1 << 0)) { list.push("Shift"); }
        if (modMask & (1 << 3)) { list.push("Alt"); }
        if (modMask & (1 << 1)) { list.push("Caps"); }
        if (modMask & (1 << 4)) { list.push("Mod2"); }
        if (modMask & (1 << 5)) { list.push("Mod3"); }
        if (modMask & (1 << 7)) { list.push("Mod5"); }
        return list;
    }

    visible: repeater.model.length > 0
    spacing: titleSpacing

    StyledText {
        text: root.isCategorized ? root.categoryName : "Uncategorized"
        font.family: Appearance.font.family.title
        font.pixelSize: Appearance.font.pixelSize.huge
        color: Appearance.colors.colOnLayer0
    }

    function hasDescription(bind) {
        return bind.description?.length > 0;
    }

    function isCategory(bind, categoryName) {
        return bind.description.substring(0, bind.description.indexOf(":")) === categoryName;
    }

    function isUncategorized(bind) {
        return bind.description.indexOf(":") === -1;
    }

    function containsNonFirstRepetitive(bind) {
        const key = bind.key;
        if (key.includes("mouse") || key.includes("page")) return false;
        if (/\d/.test(key) && !key.includes("1")) return true;
        if (/^(right|up|down)\b/i.test(key)) return true;
        return false;
    }

    function containsFirstRepetitive(bind) {
        const key = bind.key;
        return key.includes("1") || /left/i.test(key);
    }

    function transformKey(key) {
        const replaced = root.keySubstitutions[key] || key;
        const denumbered = replaced.replace("1", "<Number>");
        const dedirectioned = denumbered.replace("Left", "<Direction>");
        return dedirectioned;
    }

    function transformDescription(bind, categoryName) {
        const description = bind.description
        const regex = new RegExp("\\s*" + categoryName + "\\s*:\\s*");
        const decategorized = description.replace(regex, "");
        if (!containsFirstRepetitive(bind)) return decategorized;
        const denumbered = decategorized.replace("1", "<Number>");
        const dedirectioned = denumbered.replace(/ \b(left|right|up|down)\b/i, " <Direction>");
        return dedirectioned;
    }

    Column {
        spacing: 4
        Repeater {
            id: repeater
            model: {
                if (!root.isCategorized) {
                    return HyprlandKeybinds.keybinds.filter(bind => root.hasDescription(bind) && root.isUncategorized(bind) && !root.containsNonFirstRepetitive(bind));
                }
                return HyprlandKeybinds.keybinds.filter(bind => root.hasDescription(bind) && root.isCategory(bind, root.categoryName) && !root.containsNonFirstRepetitive(bind));
            }
            delegate: BindLine {
                required property var modelData
                keyData: modelData
                categoryName: root.categoryName
            }
        }
    }

    component BindLine: Row {
        id: bindLine
        required property var keyData
        property string categoryName: ""

        Row {
            spacing: 16
            Row {
                id: modRow
                Component.onCompleted: root.maxBindWidth = Math.max(root.maxBindWidth, implicitWidth)
                width: root.maxBindWidth
                spacing: 4
                Repeater {
                    model: {
                        const modList = root.modMaskToStringList(bindLine.keyData.modmask).map(mod => root.keySubstitutions[mod] || mod)
                        if (modList.length == 0) return []
                        return [modList.join(" ")]
                    }
                    delegate: KeyboardKey {
                        required property var modelData
                        key: root.transformKey(modelData)
                    }
                }
                StyledText {
                    id: keybindPlus
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.keyBlacklist.includes(bindLine.keyData.key) && bindLine.keyData.modmask > 0
                    text: "+"
                }
                KeyboardKey {
                    id: keybindKey
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.keyBlacklist.includes(bindLine.keyData.key)
                    key: root.transformKey(bindLine.keyData.key)
                    color: Appearance.colors.colOnLayer0
                }
            }
            Item {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: commentText.implicitWidth + root.columnSpacing
                implicitHeight: commentText.implicitHeight
                StyledText {
                    id: commentText
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: root.transformDescription(bindLine.keyData, bindLine.categoryName)
                }
            }
        }
    }
}
