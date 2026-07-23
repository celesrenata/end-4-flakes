pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * A service that provides access to Hyprland keybinds.
 *
 * Parses keybinds from the deployed keybinds.conf file (which contains
 * `bindd` lines with descriptions and `##! Category` section headers).
 * Falls back to `hyprctl binds -j` if the file can't be read.
 *
 * The keybinds.conf format:
 *   ##! Category Name         → defines a category
 *   bindd = MOD, KEY, Description, dispatcher, arg  # comment
 *   bind = MOD, KEY, dispatcher, arg  # Visible comment (no [hidden])
 *   Lines with [hidden] are excluded.
 */
Singleton {
    id: root
    property var keybinds: []
    property var keybindCategories: []

    readonly property string keybindsPath: Directories.hyprlandDir + "/keybinds.conf"
    readonly property string hyprlandConfPath: FileUtils.trimFileProtocol(Directories.config + "/hypr/hyprland.conf")

    // Modifier name → bitmask mapping (matches Hyprland's modmask field)
    readonly property var modBits: ({
        "Shift": 1 << 0,
        "Caps": 1 << 1,
        "Ctrl": 1 << 2,
        "Alt": 1 << 3,
        "Mod2": 1 << 4,
        "Mod3": 1 << 5,
        "Super": 1 << 6,
        "Mod5": 1 << 7,
    })

    // Modifier variable expansion (from keybinds template and NixOS config)
    readonly property var modVars: ({
        "$Primary": "Super",
        "$Secondary": "Control",
        "$Tertiary": "Shift",
        "$Alternate": "Alt",
    })

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                readHyprlandConf.running = true;
            }
        }
    }

    // Primary: parse the NixOS-generated hyprland.conf (has all runtime binds)
    Process {
        id: readHyprlandConf
        running: true
        command: ["cat", root.hyprlandConfPath]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const nixBinds = root.parseKeybindsConf(text);
                    if (nixBinds.binds.length > 0) {
                        // Also try to load the template for additional binds
                        readKeybindsFile.nixResult = nixBinds;
                        readKeybindsFile.running = true;
                    } else {
                        fallbackProcess.running = true;
                    }
                } catch (e) {
                    console.error("[HyprlandKeybinds] Error parsing hyprland.conf:", e);
                    readKeybindsFile.nixResult = null;
                    readKeybindsFile.running = true;
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    console.warn("[HyprlandKeybinds] Cannot read hyprland.conf, trying keybinds.conf");
                    readKeybindsFile.nixResult = null;
                    readKeybindsFile.running = true;
                }
            }
        }
    }

    // Secondary: parse keybinds.conf template (may have additional described binds)
    Process {
        id: readKeybindsFile
        running: false
        property var nixResult: null
        command: ["cat", root.keybindsPath]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const templateBinds = root.parseKeybindsConf(text);
                    root.mergeResults(readKeybindsFile.nixResult, templateBinds);
                } catch (e) {
                    console.error("[HyprlandKeybinds] Error parsing keybinds.conf:", e);
                    // Use whatever we got from hyprland.conf
                    if (readKeybindsFile.nixResult) {
                        root.keybinds = readKeybindsFile.nixResult.binds;
                        root.keybindCategories = readKeybindsFile.nixResult.categories;
                        console.log("[HyprlandKeybinds] Loaded " + root.keybinds.length + " keybinds from hyprland.conf only");
                    }
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                // keybinds.conf doesn't exist — only act if stdout didn't produce results
                if (text.trim().length > 0 && !readKeybindsFile.nixResult) {
                    fallbackProcess.running = true;
                }
            }
        }
    }

    // Fallback: hyprctl binds -j
    Process {
        id: fallbackProcess
        running: false
        command: ["hyprctl", "binds", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.keybinds = JSON.parse(text);
                    var groups = [];
                    for (var i = 0; i < root.keybinds.length; i++) {
                        var bind = root.keybinds[i].description;
                        if (!bind) continue;
                        var colonIdx = bind.indexOf(":");
                        if (colonIdx === -1) continue;
                        var group = bind.substring(0, colonIdx);
                        if (!groups.includes(group) && group.length > 0) {
                            groups.push(group);
                        }
                    }
                    root.keybindCategories = groups;
                } catch (e) {
                    console.error("[HyprlandKeybinds] Error parsing hyprctl binds:", e);
                }
            }
        }
    }

    /**
     * Merge results from hyprland.conf and keybinds.conf template.
     * Prefers keybinds.conf for overlapping keys (it has better formatting).
     * Adds unique binds from hyprland.conf that aren't in the template.
     */
    function mergeResults(nixResult, templateResult) {
        // Build a lookup from template by "modmask:key"
        const templateLookup = {};
        if (templateResult) {
            for (const bind of templateResult.binds) {
                templateLookup[bind.modmask + ":" + bind.key.toLowerCase()] = true;
            }
        }

        // Start with template binds (they have better descriptions from bindd)
        let merged = templateResult ? [...templateResult.binds] : [];
        let categories = templateResult ? [...templateResult.categories] : [];

        // Add unique binds from NixOS config
        if (nixResult) {
            for (const bind of nixResult.binds) {
                const key = bind.modmask + ":" + bind.key.toLowerCase();
                if (!templateLookup[key]) {
                    merged.push(bind);
                }
            }
            // Merge categories
            for (const cat of nixResult.categories) {
                if (!categories.includes(cat)) {
                    categories.push(cat);
                }
            }
        }

        root.keybinds = merged;
        root.keybindCategories = categories;
        console.log("[HyprlandKeybinds] Merged: " + merged.length + " keybinds in " + categories.length + " categories");
    }

    /**
     * Parse keybinds config content into binds and categories.
     * Supports both formats:
     *   ##! Category (keybinds.conf template format)
     *   #+! Category (NixOS hyprland.conf format)
     *   bindd = MOD, KEY, Description, dispatcher, arg
     *   bind = MOD, KEY, dispatcher, arg  # Trailing comment
     * Returns { binds: [...], categories: [...] }
     */
    function parseKeybindsConf(content) {
        const lines = content.split("\n");
        let currentCategory = "";
        const binds = [];
        const categories = [];

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();

            // Skip empty lines
            if (!line) continue;

            // Category header: ##! Category Name OR #+! Category Name
            if (line.startsWith("##!") || line.startsWith("#+!")) {
                const prefix = line.startsWith("##!") ? "##!" : "#+!";
                currentCategory = line.substring(prefix.length).trim();
                if (currentCategory.length > 0 && !categories.includes(currentCategory)) {
                    categories.push(currentCategory);
                }
                continue;
            }

            // Skip regular comments and #/ shorthand lines
            if (line.startsWith("#")) continue;

            // Skip hidden binds
            if (line.includes("[hidden]")) continue;

            // Parse bind/bindd/bindl/binde/bindm/bindr lines
            const bindMatch = line.match(/^bind[a-z]*\s*=\s*(.+)/);
            if (!bindMatch) continue;

            const parts = bindMatch[1];

            // Extract trailing comment as description source
            let trailingComment = "";
            const commentIdx = parts.lastIndexOf("#");
            let mainPart = parts;
            if (commentIdx !== -1) {
                trailingComment = parts.substring(commentIdx + 1).trim();
                mainPart = parts.substring(0, commentIdx).trim();
            }

            // Split main part by comma
            const fields = mainPart.split(",").map(f => f.trim());

            if (fields.length < 2) continue;

            let modStr = fields[0];
            let key = fields[1];
            let bindDescription = "";

            if (line.startsWith("bindd")) {
                // bindd: 3rd field is the description
                bindDescription = fields[2] || "";
            } else if (trailingComment && !trailingComment.includes("[hidden]")) {
                // Regular bind with trailing # comment
                bindDescription = trailingComment;
            }

            if (!bindDescription) continue;

            // Expand modifier variables and compute modmask
            let modmask = 0;
            let expandedMod = modStr;
            for (const [varName, modName] of Object.entries(root.modVars)) {
                expandedMod = expandedMod.split(varName).join(modName);
            }

            // Also handle direct "Super+Shift" etc format
            const modNames = expandedMod.split("+").map(m => m.trim()).filter(m => m.length > 0);
            for (const mod of modNames) {
                if (root.modBits[mod] !== undefined) {
                    modmask |= root.modBits[mod];
                }
            }

            // Prepend category to description (Category: Description format)
            const fullDescription = currentCategory
                ? currentCategory + ": " + bindDescription
                : bindDescription;

            binds.push({
                modmask: modmask,
                key: key,
                description: fullDescription,
                dispatcher: "",
                arg: "",
            });
        }

        return { binds: binds, categories: categories };
    }
}
