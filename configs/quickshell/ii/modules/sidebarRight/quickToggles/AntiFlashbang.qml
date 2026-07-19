import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs
import qs.services

QuickToggleButton {
    id: antiFlashbangButton
    property bool enabled: HyprlandAntiFlashbangShader.enabled
    toggled: enabled
    buttonIcon: HyprlandAntiFlashbangShader.enabled ? (!HyprlandAntiFlashbangShader.weak ? "flash_off" : "sunny_snowing") : "flash_on"
    onClicked: {
        HyprlandAntiFlashbangShader.cycle()
    }

    StyledToolTip {
        content: `${Translation.tr("Anti-flashbang")}: ${HyprlandAntiFlashbangShader.enabled ? (HyprlandAntiFlashbangShader.weak ? Translation.tr("Weak") : Translation.tr("Strong")) : Translation.tr("Off")}`
    }
}
