pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * For storing sensitive data in the keyring (or encrypted local file fallback).
 * Uses secret-tool (libsecret) when available for proper keyring integration.
 * Falls back to a permission-restricted file (~/.local/share/illogical-impulse/secrets.json)
 * when secret-tool is not on PATH.
 *
 * Use this for small data only, since it stores a JSON of the contents directly.
 */
Singleton {
    id: root

    property bool loaded: false
    property var keyringData: ({})
    property bool secretToolAvailable: false
    property bool _checkedBackend: false

    // File-based fallback path (stored in XDG state directory alongside other shell data)
    readonly property string fallbackDir: FileUtils.trimFileProtocol(Directories.state + "/user")
    readonly property string fallbackPath: root.fallbackDir + "/secrets.json"

    property var properties: {
        "application": "illogical-impulse",
        "explanation": Translation.tr("For storing API keys and other sensitive information"),
    }
    property var propertiesAsArgs: Object.keys(root.properties).reduce(
        function(arr, key) {
            return arr.concat([key, root.properties[key]]);
        }, []
    )
    property string keyringLabel: Translation.tr("%1 Safe Storage").arg("illogical-impulse")

    function setNestedField(path, value) {
        if (!root.keyringData) root.keyringData = {};
        let keys = path;
        let obj = root.keyringData;
        let parents = [obj];

        // Traverse and collect parent objects
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }

        // Set the value at the innermost key
        obj[keys[keys.length - 1]] = value;

        // Reassign each parent object from the bottom up to trigger change notifications
        for (let i = keys.length - 2; i >= 0; --i) {
            let parent = parents[i];
            let key = keys[i];
            parent[key] = Object.assign({}, parent[key]);
        }

        // Finally, reassign root.keyringData to trigger top-level change
        root.keyringData = Object.assign({}, root.keyringData);

        saveKeyringData();
    }

    function fetchKeyringData() {
        if (!root._checkedBackend) {
            // First check if secret-tool is available
            checkSecretTool.running = true;
        } else {
            root._doFetch();
        }
    }

    function _doFetch() {
        if (root.secretToolAvailable) {
            getData.running = true;
        } else {
            getFileData.command = getFileData.baseCommand.concat([
                "if [ -f '" + root.fallbackPath + "' ]; then cat '" + root.fallbackPath + "'; else echo '{}'; fi"
            ]);
            getFileData.running = true;
        }
    }

    function saveKeyringData() {
        if (!root._checkedBackend) return; // Don't save before backend is determined
        if (root.secretToolAvailable) {
            saveData.stdinEnabled = true;
            saveData.running = true;
        } else {
            // File-based fallback: write with restrictive permissions (0600)
            saveFileData.command = saveFileData.baseCommand.concat([
                "mkdir -p '" + root.fallbackDir + "' && umask 077 && cat > '" + root.fallbackPath + "'"
            ]);
            saveFileData.stdinEnabled = true;
            saveFileData.running = true;
        }
    }

    // === Check if secret-tool is on PATH ===
    Process {
        id: checkSecretTool
        command: ["bash", "-c", "which secret-tool"]
        onExited: (exitCode, exitStatus) => {
            root.secretToolAvailable = (exitCode === 0);
            root._checkedBackend = true;
            if (!root.secretToolAvailable) {
                console.log("[KeyringStorage] secret-tool not found, using file-based storage at: " + root.fallbackPath);
            }
            root._doFetch();
        }
    }

    // === Secret-tool based storage (primary) ===
    Process {
        id: saveData
        command: [
            "secret-tool", "store", "--label=" + keyringLabel,
            ...propertiesAsArgs,
        ]
        onRunningChanged: {
            if (saveData.running) {
                saveData.write(JSON.stringify(root.keyringData));
                stdinEnabled = false; // End input stream
            }
        }
    }

    Process {
        id: getData
        command: [
            "bash", "-c", "echo $(secret-tool lookup 'application' 'illogical-impulse')",
        ]
        stdout: SplitParser {
            onRead: data => {
                if(data.length === 0) return;
                try {
                    root.keyringData = JSON.parse(data);
                } catch (e) {
                    console.error("[KeyringStorage] Failed to parse keyring data, reinitializing.");
                    root.keyringData = {};
                    saveKeyringData();
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.error("[KeyringStorage] secret-tool lookup failed, reinitializing.");
                root.keyringData = {};
                saveKeyringData();
            }
            root.loaded = true;
        }
    }

    // === File-based fallback storage ===
    Process {
        id: saveFileData
        property list<string> baseCommand: ["bash", "-c"]
        stdinEnabled: true
        onRunningChanged: {
            if (saveFileData.running) {
                saveFileData.write(JSON.stringify(root.keyringData));
                saveFileData.stdinEnabled = false;
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.error("[KeyringStorage] Failed to save to fallback file.");
            }
        }
    }

    Process {
        id: getFileData
        property list<string> baseCommand: ["bash", "-c"]
        stdout: SplitParser {
            onRead: data => {
                if(data.length === 0) return;
                try {
                    root.keyringData = JSON.parse(data);
                } catch (e) {
                    console.error("[KeyringStorage] Failed to parse fallback file, reinitializing.");
                    root.keyringData = {};
                    saveKeyringData();
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.error("[KeyringStorage] Failed to read fallback file, reinitializing.");
                root.keyringData = {};
            }
            root.loaded = true;
        }
    }
}
