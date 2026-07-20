import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

// Idle/Power Management Settings
// Controls hypridle timeouts for dimming, locking, DPMS, and suspend

Rectangle {
    id: root
    color: "#313244"
    radius: 8

    property var config: ({})
    property string configPath: `${StandardPaths.writableLocation(StandardPaths.ConfigLocation)}/illogical-impulse/config.json`

    Component.onCompleted: loadConfig()

    function loadConfig() {
        configLoader.running = true
    }

    function saveConfig() {
        configSaver.running = true
    }

    Process {
        id: configLoader
        command: ["cat", root.configPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let cfg = JSON.parse(text)
                    if (!cfg.idle) {
                        cfg.idle = {
                            dimTimeout: 300,
                            lockTimeout: 420,
                            dpmsTimeout: 600,
                            suspendEnabled: false,
                            suspendTimeout: 900
                        }
                    }
                    root.config = cfg
                } catch(e) {
                    console.error("IdleConfig: Failed to parse config:", e)
                }
            }
        }
    }

    Process {
        id: configSaver
        command: ["bash", "-c", `
            cat > '${root.configPath}' << 'JSONEOF'
${JSON.stringify(root.config, null, 2)}
JSONEOF
            ~/.local/bin/apply-idle-config.sh
        `]
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 15
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 20

            // Header
            Text {
                text: "Idle & Power Management"
                color: "#cdd6f4"
                font.pixelSize: 18
                font.bold: true
                Layout.bottomMargin: 5
            }

            Text {
                text: "Configure when your screen dims, locks, and powers off."
                color: "#a6adc8"
                font.pixelSize: 12
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            // Dim timeout
            ColumnLayout {
                spacing: 5
                Layout.fillWidth: true

                RowLayout {
                    Text { text: "Dim screen after"; color: "#cdd6f4"; font.pixelSize: 14 }
                    Item { Layout.fillWidth: true }
                    Text { text: `${Math.floor((root.config?.idle?.dimTimeout ?? 300) / 60)} min`; color: "#89b4fa"; font.pixelSize: 14; font.bold: true }
                }
                Slider {
                    Layout.fillWidth: true
                    from: 60; to: 1800; stepSize: 60
                    value: root.config?.idle?.dimTimeout ?? 300
                    onMoved: {
                        let cfg = root.config
                        if (!cfg.idle) cfg.idle = {}
                        cfg.idle.dimTimeout = value
                        root.config = cfg
                    }
                }
            }

            // Lock timeout
            ColumnLayout {
                spacing: 5
                Layout.fillWidth: true

                RowLayout {
                    Text { text: "Lock screen after"; color: "#cdd6f4"; font.pixelSize: 14 }
                    Item { Layout.fillWidth: true }
                    Text { text: `${Math.floor((root.config?.idle?.lockTimeout ?? 420) / 60)} min`; color: "#89b4fa"; font.pixelSize: 14; font.bold: true }
                }
                Slider {
                    Layout.fillWidth: true
                    from: 60; to: 3600; stepSize: 60
                    value: root.config?.idle?.lockTimeout ?? 420
                    onMoved: {
                        let cfg = root.config
                        if (!cfg.idle) cfg.idle = {}
                        cfg.idle.lockTimeout = value
                        root.config = cfg
                    }
                }
            }

            // DPMS timeout
            ColumnLayout {
                spacing: 5
                Layout.fillWidth: true

                RowLayout {
                    Text { text: "Turn off display after"; color: "#cdd6f4"; font.pixelSize: 14 }
                    Item { Layout.fillWidth: true }
                    Text { text: `${Math.floor((root.config?.idle?.dpmsTimeout ?? 600) / 60)} min`; color: "#89b4fa"; font.pixelSize: 14; font.bold: true }
                }
                Slider {
                    Layout.fillWidth: true
                    from: 60; to: 3600; stepSize: 60
                    value: root.config?.idle?.dpmsTimeout ?? 600
                    onMoved: {
                        let cfg = root.config
                        if (!cfg.idle) cfg.idle = {}
                        cfg.idle.dpmsTimeout = value
                        root.config = cfg
                    }
                }
            }

            // Suspend
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Suspend after idle"; color: "#cdd6f4"; font.pixelSize: 14 }
                Item { Layout.fillWidth: true }
                Switch {
                    checked: root.config?.idle?.suspendEnabled ?? false
                    onToggled: {
                        let cfg = root.config
                        if (!cfg.idle) cfg.idle = {}
                        cfg.idle.suspendEnabled = checked
                        root.config = cfg
                    }
                }
            }

            ColumnLayout {
                visible: root.config?.idle?.suspendEnabled ?? false
                spacing: 5
                Layout.fillWidth: true

                RowLayout {
                    Text { text: "Suspend timeout"; color: "#cdd6f4"; font.pixelSize: 14 }
                    Item { Layout.fillWidth: true }
                    Text { text: `${Math.floor((root.config?.idle?.suspendTimeout ?? 900) / 60)} min`; color: "#89b4fa"; font.pixelSize: 14; font.bold: true }
                }
                Slider {
                    Layout.fillWidth: true
                    from: 300; to: 7200; stepSize: 60
                    value: root.config?.idle?.suspendTimeout ?? 900
                    onMoved: {
                        let cfg = root.config
                        if (!cfg.idle) cfg.idle = {}
                        cfg.idle.suspendTimeout = value
                        root.config = cfg
                    }
                }
            }

            // Apply button
            Button {
                Layout.fillWidth: true
                Layout.topMargin: 10
                text: "Apply"
                background: Rectangle {
                    color: parent.hovered ? "#74c7ec" : "#89b4fa"
                    radius: 8
                }
                contentItem: Text {
                    text: parent.text
                    color: "#1e1e2e"
                    horizontalAlignment: Text.AlignHCenter
                    font.bold: true
                }
                onClicked: root.saveConfig()
            }

            Item { Layout.fillHeight: true }
        }
    }
}
