import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root

    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource

    signal sinkProtectionTriggered(string reason);

    PwObjectTracker {
        objects: [sink, source]
    }

    // Grace period after node changes (Bluetooth codec swaps, device switches)
    // During this window, protection is disabled so the user can set volume freely
    Timer {
        id: graceTimer
        interval: 2000  // 2 seconds after device change
        repeat: false
    }

    // Reset protection state when the sink node itself changes
    onSinkChanged: {
        sinkProtection.lastReady = false;
        sinkProtection.lastVolume = 0;
        graceTimer.restart();
    }

    Connections { // Protection against sudden volume changes
        id: sinkProtection
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (!Config.options.audio.protection.enable) return;

            // Skip invalid/transitional readings
            if (!sink?.ready || isNaN(sink.audio.volume) || sink.audio.volume === undefined || sink.audio.volume === null) {
                lastReady = false;
                return;
            }

            const newVolume = sink.audio.volume;

            // During grace period after node change — accept everything, just track
            if (graceTimer.running) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }

            // First valid reading after grace — accept as baseline
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }

            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100; 
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered("Illegal increment");
            } else if (newVolume > maxAllowed) {
                root.sinkProtectionTriggered("Exceeded max allowed");
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
    }

}
