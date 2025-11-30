pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Automatically reloads generated material colors.
 * It is necessary to run reapplyTheme() on startup because Singletons are lazily loaded.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath

    Component.onCompleted: delayedFileRead.restart()

    function reapplyTheme() {
        delayedFileRead.restart()
    }

    Timer {
        id: delayedFileRead
        interval: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 300
        repeat: false
        running: false
        onTriggered: {
            console.log("MaterialThemeLoader: Timer triggered")
            const fileContent = themeFileView.text()
            console.log("MaterialThemeLoader: Read", fileContent.length, "bytes")
            const json = JSON.parse(fileContent)
            let colorCount = 0
            for (const key in json) {
                if (json.hasOwnProperty(key)) {
                    if (key === 'darkmode' || key === 'transparent' || key.includes('paletteKeyColor') || key.startsWith('term')) {
                        continue
                    }
                    const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
                    const m3Key = `m3${camelCaseKey}`
                    Appearance.m3colors[m3Key] = json[key]
                    colorCount++
                }
            }
            console.log("MaterialThemeLoader: Applied", colorCount, "colors")
            console.log("MaterialThemeLoader: m3primary =", Appearance.m3colors.m3primary)
            Appearance.m3colors.darkmode = (Appearance.m3colors.m3background.hslLightness < 0.5)
        }
    }

	FileView { 
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: {
            this.reload()
            delayedFileRead.restart()
        }
        onLoadedChanged: if (loaded) delayedFileRead.restart()
    }
}
