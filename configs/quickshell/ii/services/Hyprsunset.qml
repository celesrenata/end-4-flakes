pragma Singleton

import QtQuick
import qs.modules.common
import Quickshell
import Quickshell.Io

/**
 * Hyprsunset service with automatic mode.
 * Uses the .hyprsunset.sock socket for IPC instead of hyprctl,
 * which avoids dependency on the hyprctl binary working correctly.
 */
Singleton {
    id: root
    property var manualActive
    property string from: Config.options?.light?.night?.from ?? "19:00"
    property string to: Config.options?.light?.night?.to ?? "06:30"
    property bool automatic: Config.options?.light?.night?.automatic && (Config?.ready ?? true)
    property int colorTemperature: 5000
    Component.onCompleted: {
        root.colorTemperature = Config.options?.light?.night?.colorTemperature ?? 5000;
    }
    property bool shouldBeOn
    property bool firstEvaluation: true
    property bool active: false

    property int fromHour: Number(from.split(":")[0])
    property int fromMinute: Number(from.split(":")[1])
    property int toHour: Number(to.split(":")[0])
    property int toMinute: Number(to.split(":")[1])

    property int clockHour: DateTime.clock.hours
    property int clockMinute: DateTime.clock.minutes

    // Socket path for hyprsunset IPC
    property string socketPath: {
        const xdgRuntime = Quickshell.env("XDG_RUNTIME_DIR") || `/run/user/${Quickshell.env("UID") || "1000"}`;
        const hyprSig = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "";
        return `${xdgRuntime}/hypr/${hyprSig}/.hyprsunset.sock`;
    }

    function isNoLater(hour1, minute1, hour2, minute2) {
        if (hour1 < hour2)
            return true;
        if (hour1 === hour2 && minute1 < minute2)
            return true;
        return false;
    }

    onClockMinuteChanged: reEvaluate()
    onAutomaticChanged: {
        root.manualActive = undefined;
        root.firstEvaluation = true;
        reEvaluate();
    }
    function reEvaluate() {
        const toHourIsNextDay = !isNoLater(fromHour, fromMinute, toHour, toMinute);
        const toHourWrapped = toHourIsNextDay ? toHour + 24 : toHour;
        const toMinuteWrapped = toMinute;
        root.shouldBeOn = isNoLater(fromHour, fromMinute, clockHour, clockMinute) && isNoLater(clockHour, clockMinute, toHourWrapped, toMinuteWrapped);
        if (firstEvaluation) {
            firstEvaluation = false;
            root.ensureState();
        }
    }

    onShouldBeOnChanged: ensureState()
    function ensureState() {
        if (!root.automatic || root.manualActive !== undefined)
            return;
        if (root.shouldBeOn) {
            root.enable();
        } else {
            root.disable();
        }
    }

    function load() { } // Dummy to force init

    /**
     * Sets the color temperature dynamically via the hyprsunset socket.
     * @param temp Temperature in Kelvin (2500-6500). 6500 = identity/off.
     */
    function setTemperature(temp) {
        temp = Math.round(Math.max(2500, Math.min(6500, temp)));
        if (temp >= 6500) {
            root.disable();
            return;
        }
        root.colorTemperature = temp;
        root.active = true;
        root.manualActive = true;

        // Try socket first (if hyprsunset is already running), fall back to launching
        // Note: unset LD_LIBRARY_PATH when launching because nix-ld's LD_LIBRARY_PATH
        // can override the correct RPATH in hyprsunset's binary (gcc-16 vs gcc-15 conflict)
        Quickshell.execDetached(["bash", "-c",
            `SOCK='${root.socketPath}'; ` +
            `if [ -S "$SOCK" ]; then ` +
            `  echo -n 'temperature ${temp}' | socat - UNIX-CONNECT:"$SOCK"; ` +
            `else ` +
            `  pidof hyprsunset >/dev/null 2>&1 || env -u LD_LIBRARY_PATH hyprsunset --temperature ${temp} & ` +
            `fi`
        ]);
    }

    function enable() {
        root.active = true;
        Quickshell.execDetached(["bash", "-c",
            `SOCK='${root.socketPath}'; ` +
            `if [ -S "$SOCK" ]; then ` +
            `  echo -n 'temperature ${root.colorTemperature}' | socat - UNIX-CONNECT:"$SOCK"; ` +
            `else ` +
            `  pidof hyprsunset >/dev/null 2>&1 || env -u LD_LIBRARY_PATH hyprsunset --temperature ${root.colorTemperature} & ` +
            `fi`
        ]);
    }

    function disable() {
        root.active = false;
        Quickshell.execDetached(["bash", "-c",
            `SOCK='${root.socketPath}'; ` +
            `if [ -S "$SOCK" ]; then ` +
            `  echo -n 'identity' | socat - UNIX-CONNECT:"$SOCK"; ` +
            `else ` +
            `  pidof hyprsunset && kill $(pidof hyprsunset) || true; ` +
            `fi`
        ]);
    }

    function fetchState() {
        fetchProc.running = true;
    }

    Process {
        id: fetchProc
        running: true
        command: ["bash", "-c",
            `SOCK='${root.socketPath}'; ` +
            `if [ -S "$SOCK" ]; then ` +
            `  echo -n 'temperature' | socat - UNIX-CONNECT:"$SOCK" 2>/dev/null; ` +
            `else ` +
            `  echo ''; ` +
            `fi`
        ]
        stdout: StdioCollector {
            id: stateCollector
            onStreamFinished: {
                const output = stateCollector.text.trim();
                if (output.length == 0 || output === "6500")
                    root.active = false;
                else {
                    root.active = true;
                    const parsed = parseInt(output);
                    if (!isNaN(parsed) && parsed >= 2500 && parsed <= 6500)
                        root.colorTemperature = parsed;
                }
            }
        }
    }

    function toggle() {
        if (root.manualActive === undefined)
            root.manualActive = root.active;

        root.manualActive = !root.manualActive;
        if (root.manualActive) {
            root.enable();
        } else {
            root.disable();
        }
    }
}
