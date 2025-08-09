import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// Transparency and Blur UI Controls
// Replicates the AGS configuration UI from configure.js

Rectangle {
    id: transparencyUI
    
    property alias transparencySettings: settingsLoader.item
    
    width: 400
    height: 600
    color: "#1e1e2e"
    radius: 12
    border.color: "#45475a"
    border.width: 1
    
    // Load the settings module
    Loader {
        id: settingsLoader
        source: "TransparencySettings.qml"
    }
    
    ScrollView {
        anchors.fill: parent
        anchors.margins: 20
        
        ColumnLayout {
            width: parent.width
            spacing: 20
            
            // Header
            Text {
                text: "Effects Configuration"
                color: "#cdd6f4"
                font.pixelSize: 18
                font.bold: true
                Layout.fillWidth: true
            }
            
            // Global Transparency Section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: transparencySection.height + 20
                color: "#313244"
                radius: 8
                
                ColumnLayout {
                    id: transparencySection
                    anchors.fill: parent
                    anchors.margins: 15
                    spacing: 15
                    
                    // Transparency Toggle
                    RowLayout {
                        Layout.fillWidth: true
                        
                        Rectangle {
                            width: 24
                            height: 24
                            color: "#89b4fa"
                            radius: 4
                            
                            Text {
                                anchors.centerIn: parent
                                text: "◫"
                                color: "white"
                                font.pixelSize: 14
                            }
                        }
                        
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            
                            Text {
                                text: "Transparency"
                                color: "#cdd6f4"
                                font.pixelSize: 14
                                font.bold: true
                            }
                            
                            Text {
                                text: "Make shell elements transparent\nBlur is also recommended if you enable this"
                                color: "#a6adc8"
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                        
                        Switch {
                            id: transparencySwitch
                            checked: transparencySettings ? transparencySettings.globalTransparency : false
                            
                            onToggled: {
                                if (transparencySettings) {
                                    transparencySettings.setGlobalTransparency(checked)
                                }
                            }
                        }
                    }
                    
                    // Terminal Opacity Slider (subcategory)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: terminalOpacitySection.height + 10
                        color: "#45475a"
                        radius: 6
                        Layout.leftMargin: 20
                        
                        ColumnLayout {
                            id: terminalOpacitySection
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10
                            
                            RowLayout {
                                Layout.fillWidth: true
                                
                                Rectangle {
                                    width: 20
                                    height: 20
                                    color: "#f9e2af"
                                    radius: 3
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: "○"
                                        color: "black"
                                        font.pixelSize: 12
                                    }
                                }
                                
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    
                                    Text {
                                        text: "Terminal Opacity"
                                        color: "#cdd6f4"
                                        font.pixelSize: 13
                                        font.bold: true
                                    }
                                    
                                    Text {
                                        text: "Changes the opacity of the foot terminal"
                                        color: "#a6adc8"
                                        font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                                
                                Text {
                                    text: (transparencySettings ? transparencySettings.terminalOpacity : 100) + "%"
                                    color: "#cdd6f4"
                                    font.pixelSize: 12
                                    Layout.preferredWidth: 40
                                }
                            }
                            
                            Slider {
                                id: terminalOpacitySlider
                                Layout.fillWidth: true
                                from: 0
                                to: 100
                                stepSize: 1
                                value: transparencySettings ? transparencySettings.terminalOpacity : 100
                                
                                onValueChanged: {
                                    if (transparencySettings && Math.abs(value - transparencySettings.terminalOpacity) > 0.5) {
                                        transparencySettings.setTerminalOpacity(Math.round(value))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Blur Section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: blurSection.height + 20
                color: "#313244"
                radius: 8
                
                ColumnLayout {
                    id: blurSection
                    anchors.fill: parent
                    anchors.margins: 15
                    spacing: 15
                    
                    // Blur Toggle
                    RowLayout {
                        Layout.fillWidth: true
                        
                        Rectangle {
                            width: 24
                            height: 24
                            color: "#94e2d5"
                            radius: 4
                            
                            Text {
                                anchors.centerIn: parent
                                text: "◐"
                                color: "black"
                                font.pixelSize: 14
                            }
                        }
                        
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            
                            Text {
                                text: "Blur"
                                color: "#cdd6f4"
                                font.pixelSize: 14
                                font.bold: true
                            }
                            
                            Text {
                                text: "Enable blur on transparent elements\nDoesn't affect performance/power consumption unless you have transparent windows."
                                color: "#a6adc8"
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                        
                        Switch {
                            id: blurSwitch
                            checked: transparencySettings ? transparencySettings.blurEnabled : false
                            
                            onToggled: {
                                if (transparencySettings) {
                                    transparencySettings.setBlurEnabled(checked)
                                }
                            }
                        }
                    }
                    
                    // Blur Subcategory
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: blurSubcategory.height + 10
                        color: "#45475a"
                        radius: 6
                        Layout.leftMargin: 20
                        visible: transparencySettings ? transparencySettings.blurEnabled : false
                        
                        ColumnLayout {
                            id: blurSubcategory
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 15
                            
                            // X-ray Toggle
                            RowLayout {
                                Layout.fillWidth: true
                                
                                Rectangle {
                                    width: 20
                                    height: 20
                                    color: "#f38ba8"
                                    radius: 3
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: "⚡"
                                        color: "white"
                                        font.pixelSize: 10
                                    }
                                }
                                
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    
                                    Text {
                                        text: "X-ray"
                                        color: "#cdd6f4"
                                        font.pixelSize: 13
                                        font.bold: true
                                    }
                                    
                                    Text {
                                        text: "Make everything behind a window/layer except the wallpaper not rendered on its blurred surface\nRecommended to improve performance (if you don't abuse transparency/blur)"
                                        color: "#a6adc8"
                                        font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                                
                                Switch {
                                    checked: transparencySettings ? transparencySettings.blurXray : true
                                    
                                    onToggled: {
                                        if (transparencySettings) {
                                            transparencySettings.setBlurXray(checked)
                                        }
                                    }
                                }
                            }
                            
                            // Blur Size
                            RowLayout {
                                Layout.fillWidth: true
                                
                                Rectangle {
                                    width: 20
                                    height: 20
                                    color: "#a6e3a1"
                                    radius: 3
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: "◎"
                                        color: "black"
                                        font.pixelSize: 10
                                    }
                                }
                                
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    
                                    Text {
                                        text: "Size"
                                        color: "#cdd6f4"
                                        font.pixelSize: 13
                                        font.bold: true
                                    }
                                    
                                    Text {
                                        text: "Adjust the blur radius. Generally doesn't affect performance\nHigher = more color spread"
                                        color: "#a6adc8"
                                        font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                                
                                SpinBox {
                                    from: 1
                                    to: 1000
                                    value: transparencySettings ? transparencySettings.blurSize : 8
                                    
                                    onValueChanged: {
                                        if (transparencySettings && value !== transparencySettings.blurSize) {
                                            transparencySettings.setBlurSize(value)
                                        }
                                    }
                                }
                            }
                            
                            // Blur Passes
                            RowLayout {
                                Layout.fillWidth: true
                                
                                Rectangle {
                                    width: 20
                                    height: 20
                                    color: "#cba6f7"
                                    radius: 3
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: "↻"
                                        color: "white"
                                        font.pixelSize: 10
                                    }
                                }
                                
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    
                                    Text {
                                        text: "Passes"
                                        color: "#cdd6f4"
                                        font.pixelSize: 13
                                        font.bold: true
                                    }
                                    
                                    Text {
                                        text: "Adjust the number of runs of the blur algorithm\nMore passes = more spread and power consumption\n4 is recommended\n2- would look weird and 6+ would look lame."
                                        color: "#a6adc8"
                                        font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                                
                                SpinBox {
                                    from: 1
                                    to: 10
                                    value: transparencySettings ? transparencySettings.blurPasses : 4
                                    
                                    onValueChanged: {
                                        if (transparencySettings && value !== transparencySettings.blurPasses) {
                                            transparencySettings.setBlurPasses(value)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Apply/Reset buttons
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 20
                
                Button {
                    text: "Reset to Defaults"
                    Layout.fillWidth: true
                    
                    onClicked: {
                        if (transparencySettings) {
                            transparencySettings.setGlobalTransparency(false)
                            transparencySettings.setTerminalOpacity(100)
                            transparencySettings.setBlurEnabled(false)
                            transparencySettings.setBlurXray(true)
                            transparencySettings.setBlurSize(8)
                            transparencySettings.setBlurPasses(4)
                        }
                    }
                }
                
                Button {
                    text: "Reload Settings"
                    Layout.fillWidth: true
                    
                    onClicked: {
                        if (transparencySettings) {
                            transparencySettings.loadSettings()
                        }
                    }
                }
            }
        }
    }
    
    // IPC Handler for external control
    IpcHandler {
        target: "transparencyUI"
        
        function show() {
            transparencyUI.visible = true
        }
        
        function hide() {
            transparencyUI.visible = false
        }
        
        function toggle() {
            transparencyUI.visible = !transparencyUI.visible
        }
    }
}
