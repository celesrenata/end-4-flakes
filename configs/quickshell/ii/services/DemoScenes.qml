pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root

    // Valid scene categories
    readonly property var categories: ["shell", "workspace", "window",
                                        "utility", "app-launch", "mcp"]

    // ─── Scene Registry ───
    readonly property var registry: [
        // ═══════════════════════════════════════════
        // ─── Shell Module Scenes ───
        // ═══════════════════════════════════════════
        {
            name: "sidebar-left",
            description: "Open and close the AI/chat left sidebar",
            category: "shell",
            duration: 4000,
            closesModule: "sidebarLeft",
            guards: [],
            actions: [
                { type: "globalShortcut", name: "sidebarLeftToggle" },
                { type: "notify", title: "Left Sidebar",
                  body: "AI chat, providers, and tools" },
                { delay: 3000 },
                { type: "globalShortcut", name: "sidebarLeftToggle" }
            ]
        },
        {
            name: "sidebar-right",
            description: "Open and close the notifications/calendar sidebar",
            category: "shell",
            duration: 4000,
            closesModule: "sidebarRight",
            guards: [],
            actions: [
                { type: "globalShortcut", name: "sidebarRightToggle" },
                { type: "notify", title: "Right Sidebar",
                  body: "Notifications, calendar, and system info" },
                { delay: 3000 },
                { type: "globalShortcut", name: "sidebarRightToggle" }
            ]
        },
        {
            name: "overview",
            description: "Open the app launcher / overview",
            category: "shell",
            duration: 4000,
            closesModule: "overview",
            guards: [],
            actions: [
                { type: "globalShortcut", name: "overviewToggle" },
                { type: "notify", title: "Overview",
                  body: "App launcher, window switcher, clipboard, emoji" },
                { delay: 3000 },
                { type: "globalShortcut", name: "overviewClose" }
            ]
        },
        {
            name: "cheatsheet",
            description: "Open and close the keyboard shortcuts cheatsheet",
            category: "shell",
            duration: 4000,
            closesModule: "cheatsheet",
            guards: [],
            actions: [
                { type: "globalShortcut", name: "cheatsheetToggle" },
                { type: "notify", title: "Cheatsheet",
                  body: "All keyboard shortcuts at a glance" },
                { delay: 3000 },
                { type: "globalShortcut", name: "cheatsheetToggle" }
            ]
        },
        {
            name: "media-controls",
            description: "Open and close the media controls panel",
            category: "shell",
            duration: 4000,
            closesModule: "mediaControls",
            guards: [],
            actions: [
                { type: "globalShortcut", name: "mediaControlsToggle" },
                { type: "notify", title: "Media Controls",
                  body: "Playback controls, volume, and now playing" },
                { delay: 3000 },
                { type: "globalShortcut", name: "mediaControlsToggle" }
            ]
        },
        {
            name: "on-screen-keyboard",
            description: "Open and close the on-screen keyboard",
            category: "shell",
            duration: 4000,
            closesModule: "osk",
            guards: [],
            actions: [
                { type: "globalShortcut", name: "oskToggle" },
                { type: "notify", title: "On-Screen Keyboard",
                  body: "Virtual keyboard for touch input" },
                { delay: 3000 },
                { type: "globalShortcut", name: "oskToggle" }
            ]
        },
        {
            name: "session-menu",
            description: "Open and close the session/power menu",
            category: "shell",
            duration: 4000,
            closesModule: "session",
            guards: [],
            actions: [
                { type: "globalShortcut", name: "sessionToggle" },
                { type: "notify", title: "Session Menu",
                  body: "Lock, logout, suspend, reboot, shutdown" },
                { delay: 3000 },
                { type: "globalShortcut", name: "sessionToggle" }
            ]
        },
        {
            name: "clipboard-history",
            description: "Open and close the clipboard history overlay",
            category: "shell",
            duration: 4000,
            closesModule: "overview",
            guards: [],
            actions: [
                { type: "globalShortcut", name: "overviewClipboardToggle" },
                { type: "notify", title: "Clipboard History",
                  body: "Browse and paste previous clipboard entries" },
                { delay: 3000 },
                { type: "globalShortcut", name: "overviewClipboardToggle" }
            ]
        },
        {
            name: "emoji-picker",
            description: "Open and close the emoji picker overlay",
            category: "shell",
            duration: 4000,
            closesModule: "overview",
            guards: [],
            actions: [
                { type: "globalShortcut", name: "overviewEmojiToggle" },
                { type: "notify", title: "Emoji Picker",
                  body: "Search and copy emoji to clipboard" },
                { delay: 3000 },
                { type: "globalShortcut", name: "overviewEmojiToggle" }
            ]
        },
        {
            name: "bar-toggle",
            description: "Toggle the status bar off and back on",
            category: "shell",
            duration: 4000,
            guards: [],
            actions: [
                { type: "globalShortcut", name: "barToggle" },
                { type: "notify", title: "Bar Hidden",
                  body: "Status bar toggled off for clean view" },
                { delay: 3000 },
                { type: "globalShortcut", name: "barToggle" }
            ]
        },
        {
            name: "dock",
            description: "Reveal and hide the dock by mouse movement",
            category: "shell",
            duration: 4000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "notify", title: "Dock",
                  body: "Move mouse to bottom edge to reveal" },
                { type: "mouseMove", x: 960, y: 1070 },
                { delay: 2000 },
                { type: "mouseMove", x: 960, y: 540 }
            ]
        },

        // ═══════════════════════════════════════════
        // ─── Workspace Scenes ───
        // ═══════════════════════════════════════════
        {
            name: "workspace-switching",
            description: "Switch through workspaces 1-5 sequentially",
            category: "workspace",
            duration: 8000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "notify", title: "Workspace Switching",
                  body: "Cycling through workspaces 1-5" },
                { type: "key", keycodes: [125, 2] },
                { type: "key", keycodes: [125, 3] },
                { type: "key", keycodes: [125, 4] },
                { type: "key", keycodes: [125, 5] },
                { type: "key", keycodes: [125, 6] },
                { type: "key", keycodes: [125, 2] }
            ]
        },
        {
            name: "workspace-overview",
            description: "Open the workspace overview showing all workspaces",
            category: "workspace",
            duration: 4000,
            closesModule: "overview",
            guards: [],
            actions: [
                { type: "globalShortcut", name: "overviewWorkspacesToggle" },
                { type: "notify", title: "Workspace Overview",
                  body: "Visual overview of all active workspaces" },
                { delay: 3000 },
                { type: "globalShortcut", name: "overviewWorkspacesToggle" }
            ]
        },
        {
            name: "window-move-workspace",
            description: "Move active window to workspace 3 and back",
            category: "workspace",
            duration: 6000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "notify", title: "Move Window",
                  body: "Moving window to workspace 3" },
                { type: "key", keycodes: [125, 56, 4] },
                { type: "key", keycodes: [125, 4] },
                { delay: 2000 },
                { type: "key", keycodes: [125, 56, 2] },
                { type: "key", keycodes: [125, 2] }
            ]
        },
        {
            name: "workspace-scroll",
            description: "Scroll through adjacent workspaces left and right",
            category: "workspace",
            duration: 5000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "notify", title: "Workspace Scroll",
                  body: "Scrolling between adjacent workspaces" },
                { type: "key", keycodes: [29, 125, 106] },
                { type: "key", keycodes: [29, 125, 106] },
                { delay: 1500 },
                { type: "key", keycodes: [29, 125, 105] },
                { type: "key", keycodes: [29, 125, 105] }
            ]
        },
        {
            name: "special-workspace",
            description: "Toggle the scratchpad/special workspace",
            category: "workspace",
            duration: 4000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "key", keycodes: [125, 31] },
                { type: "notify", title: "Scratchpad",
                  body: "Special workspace for hidden windows" },
                { delay: 3000 },
                { type: "key", keycodes: [125, 31] }
            ]
        },

        // ═══════════════════════════════════════════
        // ─── Window Management Scenes ───
        // ═══════════════════════════════════════════
        {
            name: "window-tile-float",
            description: "Toggle window between tiled and floating mode",
            category: "window",
            duration: 6000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "key", keycodes: [125, 56, 57] },
                { type: "notify", title: "Floating",
                  body: "Window is now floating — drag to move" },
                { type: "drag", startX: 400, startY: 300,
                  endX: 700, endY: 400, button: 0 },
                { delay: 1500 },
                { type: "key", keycodes: [125, 56, 57] }
            ]
        },
        {
            name: "window-fullscreen",
            description: "Maximize and fullscreen the active window",
            category: "window",
            duration: 6000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "key", keycodes: [125, 32] },
                { type: "notify", title: "Maximized",
                  body: "Window maximized (Super+D)" },
                { delay: 2000 },
                { type: "key", keycodes: [125, 33] },
                { type: "notify", title: "Fullscreen",
                  body: "Window fullscreen (Super+F)" },
                { delay: 2000 },
                { type: "key", keycodes: [125, 33] }
            ]
        },
        {
            name: "window-focus",
            description: "Cycle focus between windows using directional keys",
            category: "window",
            duration: 5000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "notify", title: "Focus Cycling",
                  body: "Switching focus with directional keys" },
                { type: "key", keycodes: [125, 105] },
                { type: "key", keycodes: [125, 106] },
                { type: "key", keycodes: [125, 103] },
                { type: "key", keycodes: [125, 108] }
            ]
        },
        {
            name: "window-resize",
            description: "Adjust window split ratio with keyboard",
            category: "window",
            duration: 5000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "notify", title: "Window Resize",
                  body: "Adjusting split ratio" },
                { type: "key", keycodes: [125, 39] },
                { type: "key", keycodes: [125, 39] },
                { delay: 1500 },
                { type: "key", keycodes: [125, 40] },
                { type: "key", keycodes: [125, 40] }
            ]
        },
        {
            name: "window-close",
            description: "Launch a terminal and close it to demonstrate window lifecycle",
            category: "window",
            duration: 5000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "key", keycodes: [125, 28] },
                { type: "notify", title: "Window Close",
                  body: "Opened terminal, closing with Super+Q" },
                { delay: 3000 },
                { type: "key", keycodes: [125, 16] }
            ]
        },

        // ═══════════════════════════════════════════
        // ─── Utility Scenes ───
        // ═══════════════════════════════════════════
        {
            name: "screenshot",
            description: "Capture fullscreen screenshot and demonstrate screen snip",
            category: "utility",
            duration: 6000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "key", keycodes: [99] },
                { type: "notify", title: "Screenshot",
                  body: "Fullscreen screenshot captured" },
                { delay: 2000 },
                { type: "key", keycodes: [125, 42, 31] },
                { type: "mouseMove", x: 200, y: 200 },
                { type: "drag", startX: 200, startY: 200,
                  endX: 800, endY: 600, button: 0 },
                { delay: 1500 }
            ]
        },
        {
            name: "color-picker",
            description: "Invoke the color picker and select a color from screen",
            category: "utility",
            duration: 5000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "key", keycodes: [125, 42, 46] },
                { type: "notify", title: "Color Picker",
                  body: "Click anywhere to pick a color" },
                { type: "mouseMove", x: 500, y: 400 },
                { delay: 1500 },
                { type: "click", button: 0 }
            ]
        },
        {
            name: "zoom",
            description: "Zoom in and out three times to demonstrate screen magnification",
            category: "utility",
            duration: 6000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "notify", title: "Zoom",
                  body: "Zooming in 3x then back out" },
                { type: "key", keycodes: [125, 13] },
                { type: "key", keycodes: [125, 13] },
                { type: "key", keycodes: [125, 13] },
                { delay: 2000 },
                { type: "key", keycodes: [125, 12] },
                { type: "key", keycodes: [125, 12] },
                { type: "key", keycodes: [125, 12] }
            ]
        },
        {
            name: "wallpaper",
            description: "Trigger a random wallpaper change",
            category: "utility",
            duration: 4000,
            guards: [],
            actions: [
                { type: "globalShortcut", name: "wallpaperSelectorRandom" },
                { type: "notify", title: "Wallpaper",
                  body: "Random wallpaper applied" },
                { delay: 3000 }
            ]
        },
        {
            name: "light-dark-toggle",
            description: "Toggle between light and dark mode",
            category: "utility",
            duration: 5000,
            guards: [],
            actions: [
                { type: "globalShortcut", name: "toggleLightDark" },
                { type: "notify", title: "Theme Toggle",
                  body: "Switched color scheme" },
                { delay: 3000 },
                { type: "globalShortcut", name: "toggleLightDark" }
            ]
        },

        // ═══════════════════════════════════════════
        // ─── App Launch Scenes ───
        // ═══════════════════════════════════════════
        {
            name: "launch-terminal",
            description: "Launch a terminal emulator and close it",
            category: "app-launch",
            duration: 4000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "key", keycodes: [125, 28] },
                { type: "notify", title: "Terminal",
                  body: "Launched terminal (Super+Return)" },
                { delay: 2500 },
                { type: "key", keycodes: [125, 16] }
            ]
        },
        {
            name: "launch-browser",
            description: "Launch a web browser and close it",
            category: "app-launch",
            duration: 5000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "key", keycodes: [125, 17] },
                { type: "notify", title: "Browser",
                  body: "Launched browser (Super+W)" },
                { delay: 3500 },
                { type: "key", keycodes: [125, 16] }
            ]
        },
        {
            name: "launch-file-manager",
            description: "Launch the file manager and close it",
            category: "app-launch",
            duration: 5000,
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "key", keycodes: [125, 18] },
                { type: "notify", title: "File Manager",
                  body: "Launched file manager (Super+E)" },
                { delay: 3500 },
                { type: "key", keycodes: [125, 16] }
            ]
        },
        {
            name: "launch-from-overview",
            description: "Open overview, type an app name, then close without launching",
            category: "app-launch",
            duration: 5000,
            closesModule: "overview",
            guards: [{ type: "ydotool" }],
            actions: [
                { type: "globalShortcut", name: "overviewToggle" },
                { type: "notify", title: "App Search",
                  body: "Type to search for applications" },
                { delay: 1500 },
                { type: "key", keycodes: [33] },
                { type: "key", keycodes: [18] },
                { type: "key", keycodes: [19] },
                { type: "key", keycodes: [33] },
                { type: "key", keycodes: [24] },
                { type: "key", keycodes: [45] },
                { delay: 1500 },
                { type: "globalShortcut", name: "overviewClose" }
            ]
        },

        // ═══════════════════════════════════════════
        // ─── MCP Integration Scenes ───
        // ═══════════════════════════════════════════
        {
            name: "mcp-system-info",
            description: "Query system hardware info via MCP",
            category: "mcp",
            duration: 4000,
            guards: [],
            actions: [
                { type: "mcp", tool: "system_info", args: {} },
                { type: "notify", title: "MCP: System Info",
                  body: "Querying CPU, GPU, memory, and disk" },
                { delay: 3000 }
            ]
        },
        {
            name: "mcp-audio-control",
            description: "Read and adjust audio volume via MCP",
            category: "mcp",
            duration: 5000,
            guards: [{ type: "audioUnmuted" }],
            actions: [
                { type: "mcp", tool: "audio_status", args: {} },
                { type: "notify", title: "MCP: Audio",
                  body: "Reading current volume, adjusting +10%" },
                { type: "mcp", tool: "audio_set_volume",
                  args: { target: "@DEFAULT_AUDIO_SINK@", volume: "+10%" } },
                { delay: 2000 },
                { type: "mcp", tool: "audio_set_volume",
                  args: { target: "@DEFAULT_AUDIO_SINK@", volume: "-10%" } }
            ]
        },
        {
            name: "mcp-workspace-query",
            description: "Enumerate active workspaces via MCP",
            category: "mcp",
            duration: 4000,
            guards: [],
            actions: [
                { type: "mcp", tool: "list_workspaces", args: {} },
                { type: "notify", title: "MCP: Workspaces",
                  body: "Querying active workspace list" },
                { delay: 3000 }
            ]
        },
        {
            name: "mcp-network-status",
            description: "Query network connectivity state via MCP",
            category: "mcp",
            duration: 4000,
            guards: [],
            actions: [
                { type: "mcp", tool: "network_status", args: {} },
                { type: "notify", title: "MCP: Network",
                  body: "Checking connectivity and active connections" },
                { delay: 3000 }
            ]
        },
        {
            name: "mcp-clipboard",
            description: "List clipboard history entries via MCP",
            category: "mcp",
            duration: 4000,
            guards: [],
            actions: [
                { type: "mcp", tool: "clipboard_list", args: { limit: 5 } },
                { type: "notify", title: "MCP: Clipboard",
                  body: "Listing recent clipboard entries" },
                { delay: 3000 }
            ]
        },
        {
            name: "mcp-diagnostics",
            description: "Collect full desktop diagnostic snapshot via MCP",
            category: "mcp",
            duration: 5000,
            guards: [],
            actions: [
                { type: "mcp", tool: "diagnostic_bundle", args: {} },
                { type: "notify", title: "MCP: Diagnostics",
                  body: "Collecting system health snapshot" },
                { delay: 4000 }
            ]
        }
    ]

    // ═══════════════════════════════════════════
    // ─── Query Functions ───
    // ═══════════════════════════════════════════

    function getScenes(filter, filterType) {
        if (!filter) return root.registry

        if (filterType === "category") {
            return root.registry.filter(function(s) { return s.category === filter })
        }
        if (filterType === "scene") {
            return root.registry.filter(function(s) { return s.name === filter })
        }
        return root.registry
    }

    function getCategories() {
        return root.categories
    }

    function getSceneByName(name) {
        for (var i = 0; i < root.registry.length; i++) {
            if (root.registry[i].name === name) return root.registry[i]
        }
        return null
    }

    function getTotalDuration(speedMultiplier) {
        var total = 0
        for (var i = 0; i < root.registry.length; i++) {
            total += root.registry[i].duration
        }
        // Add inter-scene delays (2000ms default between each scene)
        total += Math.max(0, root.registry.length - 1) * 2000
        return Math.round(total / (speedMultiplier || 1.0))
    }
}
