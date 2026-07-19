pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.common.models.hyprland

Singleton {
    id: root

    readonly property string shaderPath: Quickshell.shellPath("services/hyprlandAntiFlashbangShader/anti-flashbang.glsl")
    readonly property string weakShaderPath: Quickshell.shellPath("services/hyprlandAntiFlashbangShader/anti-flashbang-weak.glsl")
    property bool enabled: confOpt.value == shaderPath || weak
    property bool weak: confOpt.value == weakShaderPath

    function enable() {
        HyprlandConfig.setMany({
            "decoration:screen_shader": root.shaderPath,
            "debug:damage_tracking": 1,
        });
    }

    function enableWeak() {
        HyprlandConfig.setMany({
            "decoration:screen_shader": root.weakShaderPath,
            "debug:damage_tracking": 1,
        });
    }

    function disable() {
        HyprlandConfig.resetMany([
            "decoration:screen_shader",
            "debug:damage_tracking"
        ]);
    }

    function toggle() {
        if (root.enabled) disable()
        else enable()
    }

    function cycle() {
        if (!enabled) {
            enableWeak();
        } else if (weak) {
            enable();
        } else {
            disable();
        }
    }

    // Apply config option on startup
    Component.onCompleted: {
        const setting = Config.options.appearance.antiFlashbang;
        if (setting === "weak") {
            enableWeak();
        } else if (setting === "strong") {
            enable();
        }
    }

    HyprlandConfigOption {
        id: confOpt
        key: "decoration:screen_shader"
    }
}
