pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // State map: { "whisperCpp": { status: "reachable", message: "" }, ... }
    // Possible status values: "idle", "checking", "reachable", "unreachable", "local"
    property var checkStates: ({})

    // Check endpoint connectivity for a voice provider
    // providerKey: string key like "whisperCpp"
    // endpoint: URL string like "http://localhost:8080"
    // protocol: "rest", "websocket", or "wyoming"
    function checkEndpoint(providerKey, endpoint, protocol) {
        // If no endpoint, mark as "local" (CLI tool like espeak-ng)
        if (!endpoint) {
            var newStates = Object.assign({}, root.checkStates)
            newStates[providerKey] = { status: "local", message: "" }
            root.checkStates = newStates
            return
        }

        // Validate endpoint URL
        if (!endpoint.startsWith("http://") && !endpoint.startsWith("https://") &&
            !endpoint.startsWith("tcp://") && !endpoint.startsWith("ws://")) {
            var newStates = Object.assign({}, root.checkStates)
            newStates[providerKey] = { status: "unreachable", message: "Invalid URL format" }
            root.checkStates = newStates
            return
        }

        // Set state to "checking"
        var newStates = Object.assign({}, root.checkStates)
        newStates[providerKey] = { status: "checking", message: "" }
        root.checkStates = newStates

        // Build curl command based on protocol
        var cmd = ""
        if (endpoint.startsWith("http://") || endpoint.startsWith("https://")) {
            // HTTP — use curl HEAD request with 3s timeout
            cmd = 'curl -s -o /dev/null -w "%{http_code}" --max-time 3 -I "' + endpoint + '"'
        } else if (endpoint.startsWith("ws://")) {
            // WebSocket — try to connect with timeout via Upgrade headers
            var wsUrl = endpoint.replace("ws://", "http://")
            cmd = 'curl -s -o /dev/null -w "%{http_code}" --max-time 3 -H "Upgrade: websocket" -H "Connection: Upgrade" "' + wsUrl + '"'
        } else if (endpoint.startsWith("tcp://")) {
            // TCP — extract host:port, use bash timeout + /dev/tcp
            var stripped = endpoint.replace("tcp://", "")
            var parts = stripped.split(":")
            var host = parts[0]
            var port = parts.length > 1 ? parts[1].split("/")[0] : "80"
            cmd = 'timeout 3 bash -c "echo > /dev/tcp/' + host + '/' + port + '" 2>/dev/null && echo "200" || echo "0"'
        }

        // Launch the check process
        _launchCheck(providerKey, cmd)
    }

    // Determine if an endpoint is local
    function isLocal(endpoint) {
        if (!endpoint || typeof endpoint !== "string") return false

        var localPrefixes = [
            "http://localhost", "https://localhost",
            "ws://localhost", "tcp://localhost",
            "http://127.0.0.1", "https://127.0.0.1",
            "ws://127.0.0.1", "tcp://127.0.0.1",
            "http://10.", "https://10.",
            "ws://10.", "tcp://10.",
            "http://192.168.", "https://192.168.",
            "ws://192.168.", "tcp://192.168."
        ]

        for (var i = 0; i < localPrefixes.length; i++) {
            if (endpoint.startsWith(localPrefixes[i])) {
                return true
            }
        }
        return false
    }

    // Internal: launch a connectivity check process
    function _launchCheck(providerKey, cmd) {
        var process = checkProcessComponent.createObject(root, {
            "providerKey": providerKey,
            "command": ["bash", "-c", cmd]
        })
        process.running = true
    }

    // Dynamic Process component for connectivity checks
    Component {
        id: checkProcessComponent

        Process {
            id: checkProcess
            property string providerKey: ""
            property string _output: ""

            stdout: SplitParser {
                splitMarker: ""
                onRead: data => {
                    checkProcess._output += data.trim()
                }
            }

            onExited: (exitCode, exitStatus) => {
                var status = "unreachable"
                var message = ""

                if (exitCode === 0 && checkProcess._output) {
                    var code = parseInt(checkProcess._output)
                    if (code >= 200 && code <= 499) {
                        status = "reachable"
                    } else if (code === 0 || code >= 500) {
                        status = "unreachable"
                        message = "Server error or network failure (HTTP " + code + ")"
                    } else {
                        status = "reachable"
                    }
                } else {
                    message = "Connection failed or timed out"
                }

                var newStates = Object.assign({}, root.checkStates)
                newStates[checkProcess.providerKey] = { status: status, message: message }
                root.checkStates = newStates

                // Clean up the dynamic object
                checkProcess.destroy()
            }
        }
    }
}
