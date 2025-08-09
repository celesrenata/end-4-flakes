import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// Main Settings Window
// Integrates transparency settings and other configuration options

ApplicationWindow {
    id: settingsWindow
    
    title: "dots-hyprland Settings"
    width: 500
    height: 700
    visible: false
    
    color: "#1e1e2e"
    
    // Make window float and center it
    flags: Qt.Window | Qt.WindowStaysOnTopHint
    
    Component.onCompleted: {
        // Center the window
        x = (Screen.width - width) / 2
        y = (Screen.height - height) / 2
    }
    
    TabBar {
        id: tabBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 50
        
        background: Rectangle {
            color: "#313244"
        }
        
        TabButton {
            text: "Effects"
            width: implicitWidth
            
            background: Rectangle {
                color: parent.checked ? "#45475a" : "transparent"
                radius: 4
            }
            
            contentItem: Text {
                text: parent.text
                color: "#cdd6f4"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
        
        TabButton {
            text: "Appearance"
            width: implicitWidth
            
            background: Rectangle {
                color: parent.checked ? "#45475a" : "transparent"
                radius: 4
            }
            
            contentItem: Text {
                text: parent.text
                color: "#cdd6f4"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
        
        TabButton {
            text: "Keybinds"
            width: implicitWidth
            
            background: Rectangle {
                color: parent.checked ? "#45475a" : "transparent"
                radius: 4
            }
            
            contentItem: Text {
                text: parent.text
                color: "#cdd6f4"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
    
    StackLayout {
        anchors.top: tabBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 10
        
        currentIndex: tabBar.currentIndex
        
        // Effects Tab (Transparency & Blur)
        Item {
            TransparencyUI {
                anchors.fill: parent
                color: "transparent"
                border.width: 0
            }
        }
        
        // Appearance Tab (Future: themes, colors, etc.)
        Item {
            Rectangle {
                anchors.fill: parent
                color: "#313244"
                radius: 8
                
                Text {
                    anchors.centerIn: parent
                    text: "Appearance settings\n(Coming soon)"
                    color: "#a6adc8"
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
        
        // Keybinds Tab (Future: keybind customization)
        Item {
            Rectangle {
                anchors.fill: parent
                color: "#313244"
                radius: 8
                
                Text {
                    anchors.centerIn: parent
                    text: "Keybind settings\n(Coming soon)"
                    color: "#a6adc8"
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
    
    // Close button
    Button {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        
        width: 30
        height: 30
        
        text: "×"
        
        background: Rectangle {
            color: parent.hovered ? "#f38ba8" : "#45475a"
            radius: 15
        }
        
        contentItem: Text {
            text: parent.text
            color: "white"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 16
            font.bold: true
        }
        
        onClicked: settingsWindow.close()
    }
    
    // IPC Handler for external control
    IpcHandler {
        target: "settings"
        
        function show() {
            settingsWindow.show()
            settingsWindow.raise()
            settingsWindow.requestActivate()
        }
        
        function hide() {
            settingsWindow.hide()
        }
        
        function toggle() {
            if (settingsWindow.visible) {
                settingsWindow.hide()
            } else {
                settingsWindow.show()
                settingsWindow.raise()
                settingsWindow.requestActivate()
            }
        }
        
        function showEffects() {
            tabBar.currentIndex = 0
            settingsWindow.show()
            settingsWindow.raise()
            settingsWindow.requestActivate()
        }
        
        function showAppearance() {
            tabBar.currentIndex = 1
            settingsWindow.show()
            settingsWindow.raise()
            settingsWindow.requestActivate()
        }
        
        function showKeybinds() {
            tabBar.currentIndex = 2
            settingsWindow.show()
            settingsWindow.raise()
            settingsWindow.requestActivate()
        }
    }
}
