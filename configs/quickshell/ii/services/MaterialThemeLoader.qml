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

    IpcHandler {
        target: "materialTheme"
        function reload() {
            root.reapplyTheme()
        }
    }

    function reapplyTheme() {
        themeFileView.reload()
    }

    function applyColors(fileContent) {
        console.log("MaterialThemeLoader: applyColors called")
        const json = JSON.parse(fileContent)
        let colorCount = 0
        for (const key in json) {
            if (json.hasOwnProperty(key)) {
                // Skip boolean flags, palette key colors, and terminal colors
                if (key === 'darkmode' || key === 'transparent' || key.includes('paletteKeyColor') || key.startsWith('term')) {
                    continue
                }
                // Convert snake_case to CamelCase
                const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
                const m3Key = `m3${camelCaseKey}`
                Appearance.m3colors[m3Key] = json[key]
                colorCount++
            }
        }
        console.log("MaterialThemeLoader: Applied", colorCount, "colors")
        console.log("MaterialThemeLoader: Sample color m3primary =", Appearance.m3colors.m3primary)
        
        Appearance.m3colors.darkmode = (Appearance.m3colors.m3background.hslLightness < 0.5)
    }

    Timer {
        id: delayedFileRead
        interval: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 100
        repeat: false
        running: false
        onTriggered: {
            console.log("MaterialThemeLoader: Timer triggered, reading file from:", root.filePath)
            // Create a new FileView to read the updated file
            const freshFile = Qt.createQmlObject(`
                import Quickshell.Io
                FileView {
                    path: "file://${root.filePath}"
                    blockLoading: true
                }
            `, root, "freshFileReader")
            const content = freshFile.text()
            console.log("MaterialThemeLoader: Read", content.length, "bytes")
            root.applyColors(content)
            freshFile.destroy()
        }
    }

	FileView { 
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: {
            console.log("MaterialThemeLoader: File changed detected, triggering reload")
            delayedFileRead.start()
        }
        onLoadedChanged: {
            if (this.loaded) {
                console.log("MaterialThemeLoader: Initial load complete")
                const fileContent = themeFileView.text()
                root.applyColors(fileContent)
            }
        }
    }
}
