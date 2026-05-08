pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions as Functions
import Qt.labs.platform
import QtQuick
import Quickshell

Singleton {
    // XDG Dirs, with "file://"
    readonly property string config: StandardPaths.standardLocations(StandardPaths.ConfigLocation)[0]
    readonly property string state: StandardPaths.standardLocations(StandardPaths.StateLocation)[0]
    readonly property string cache: StandardPaths.standardLocations(StandardPaths.CacheLocation)[0]
    readonly property string pictures: StandardPaths.standardLocations(StandardPaths.PicturesLocation)[0]
    readonly property string downloads: StandardPaths.standardLocations(StandardPaths.DownloadLocation)[0]
    
    // Other dirs used by the shell, without "file://"
    property string assetsPath: Quickshell.shellPath("assets")
    property string scriptPath: Quickshell.shellPath("scripts")
    property string favicons: Functions.FileUtils.trimFileProtocol(`${cache}/media/favicons`)
    property string coverArt: Functions.FileUtils.trimFileProtocol(`${cache}/media/coverart`)
    property string booruPreviews: Functions.FileUtils.trimFileProtocol(`${cache}/media/boorus`)
    property string booruDownloads: Functions.FileUtils.trimFileProtocol(pictures  + "/homework")
    property string booruDownloadsNsfw: Functions.FileUtils.trimFileProtocol(pictures + "/homework/🌶️")
    property string latexOutput: Functions.FileUtils.trimFileProtocol(`${cache}/media/latex`)
    property string shellConfig: Functions.FileUtils.trimFileProtocol(`${config}/illogical-impulse`)
    property string shellConfigName: "config.json"
    property string shellConfigPath: `${shellConfig}/${shellConfigName}`
    property string todoPath: Functions.FileUtils.trimFileProtocol(`${state}/user/todo.json`)
    property string notificationsPath: Functions.FileUtils.trimFileProtocol(`${cache}/notifications/notifications.json`)
    property string generatedMaterialThemePath: Functions.FileUtils.trimFileProtocol(`${state}/user/generated/colors.json`)
    property string cliphistDecode: Functions.FileUtils.trimFileProtocol(`/tmp/quickshell/media/cliphist`)
    property string screenshotTemp: "/tmp/quickshell/media/screenshot"
    property string wallpaperSwitchScriptPath: Functions.FileUtils.trimFileProtocol(`${scriptPath}/colors/switchwall.sh`)
    property string defaultAiPrompts: Quickshell.shellPath("defaults/ai/prompts")
    property string userAiPrompts: FileUtils.trimFileProtocol(`${Directories.shellConfig}/ai/prompts`)
    property string aiChats: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/chats`)
    // Cleanup on init
    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", `${shellConfig}`])
        Quickshell.execDetached(["mkdir", "-p", `${favicons}`])
        Quickshell.execDetached(["bash", "-c", `rm -rf '${coverArt}'; mkdir -p '${coverArt}'`])
        Quickshell.execDetached(["bash", "-c", `rm -rf '${booruPreviews}'; mkdir -p '${booruPreviews}'`])
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${booruDownloads}' && mkdir -p '${booruDownloadsNsfw}'`])
        Quickshell.execDetached(["bash", "-c", `rm -rf '${latexOutput}'; mkdir -p '${latexOutput}'`])
        Quickshell.execDetached(["bash", "-c", `rm -rf '${cliphistDecode}'; mkdir -p '${cliphistDecode}'`])
        Quickshell.execDetached(["mkdir", "-p", `${aiChats}`])
    }
}
