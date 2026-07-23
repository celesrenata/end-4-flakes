import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    implicitWidth: rowLayout.implicitWidth + rowLayout.spacing * 2
    implicitHeight: rowLayout.implicitHeight

    RowLayout {
        id: rowLayout

        spacing: 4
        anchors.centerIn: parent

        Loader {
            active: Config.options.bar.utilButtons.showScreenSnip
            visible: Config.options.bar.utilButtons.showScreenSnip
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: Quickshell.execDetached(["quickshell", "-p", Quickshell.shellPath("screenshot.qml")])
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 1
                    text: "screenshot_region"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showColorPicker
            visible: Config.options.bar.utilButtons.showColorPicker
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: Quickshell.execDetached(["hyprpicker", "-a"])
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 1
                    text: "colorize"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showKeyboardToggle
            visible: Config.options.bar.utilButtons.showKeyboardToggle
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: GlobalStates.oskOpen = !GlobalStates.oskOpen
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: "keyboard"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showMicToggle
            visible: Config.options.bar.utilButtons.showMicToggle
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_SOURCE@", "toggle"])
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: Pipewire.defaultAudioSource?.audio?.muted ? "mic_off" : "mic"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showDarkModeToggle
            visible: Config.options.bar.utilButtons.showDarkModeToggle
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: event => {
                    if (Appearance.m3colors.darkmode) {
                        Hyprland.dispatch(`exec ${Directories.wallpaperSwitchScriptPath} --mode light --noswitch`);
                    } else {
                        Hyprland.dispatch(`exec ${Directories.wallpaperSwitchScriptPath} --mode dark --noswitch`);
                    }
                }
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: Appearance.m3colors.darkmode ? "light_mode" : "dark_mode"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showNightLightToggle
            visible: Config.options.bar.utilButtons.showNightLightToggle
            sourceComponent: Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: nightSliderRow.implicitWidth
                implicitHeight: nightSliderRow.implicitHeight

                RowLayout {
                    id: nightSliderRow
                    spacing: 2
                    anchors.centerIn: parent

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        fill: nightSlider.value > 0 ? 1 : 0
                        text: "eyeglasses"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }

                    // Compact slider: 0 = off (6500K), 1 = max warmth (2500K)
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 60
                        height: 6
                        radius: 3
                        color: Qt.alpha(Appearance.colors.colOnLayer2, 0.15)

                        Rectangle {
                            width: nightSlider.value * parent.width
                            height: parent.height
                            radius: parent.radius
                            color: nightSlider.value > 0
                                ? Qt.rgba(1.0, 0.6 + 0.4 * (1 - nightSlider.value), 0.2 + 0.3 * (1 - nightSlider.value), 0.9)
                                : "transparent"
                        }

                        // Thumb
                        Rectangle {
                            x: nightSlider.value * (parent.width - width)
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            radius: 6
                            color: nightSlider.value > 0
                                ? Qt.rgba(1.0, 0.5 + 0.3 * (1 - nightSlider.value), 0.1, 1.0)
                                : Appearance.colors.colOnLayer2
                            opacity: nightSliderArea.containsMouse || nightSliderArea.pressed ? 1.0 : 0.7
                        }

                        MouseArea {
                            id: nightSliderArea
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onPressed: (mouse) => updateFromMouse(mouse)
                            onPositionChanged: (mouse) => {
                                if (pressed) updateFromMouse(mouse)
                            }

                            function updateFromMouse(mouse) {
                                var ratio = Math.max(0, Math.min(1, (mouse.x - 6) / (parent.width)));
                                nightSlider.value = ratio;
                                // Map: 0 = 6500K (off), 1 = 2500K (max warmth)
                                var temp = Math.round(6500 - ratio * 4000);
                                Hyprsunset.setTemperature(temp);
                            }
                        }
                    }
                }

                // Slider state: 0 = off, 1 = max redshift
                QtObject {
                    id: nightSlider
                    property real value: 0
                    Component.onCompleted: {
                        value = Qt.binding(function() {
                            return Hyprsunset.active
                                ? Math.max(0, Math.min(1, (6500 - Hyprsunset.colorTemperature) / 4000))
                                : 0;
                        });
                    }
                }
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showPerformanceProfileToggle
            visible: Config.options.bar.utilButtons.showPerformanceProfileToggle
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: event => {
                    if (PowerProfiles.hasPerformanceProfile) {
                        switch(PowerProfiles.profile) {
                            case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced
                            break;
                            case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance
                            break;
                            case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver
                            break;
                        }
                    } else {
                        PowerProfiles.profile = PowerProfiles.profile == PowerProfile.Balanced ? PowerProfile.PowerSaver : PowerProfile.Balanced
                    }
                }
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: switch(PowerProfiles.profile) {
                        case PowerProfile.PowerSaver: return "energy_savings_leaf"
                        case PowerProfile.Balanced: return "settings_slow_motion"
                        case PowerProfile.Performance: return "local_fire_department"
                    }
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
    }
}
