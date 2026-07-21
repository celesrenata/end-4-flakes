/**
 * Pure logic functions extracted from DictationService.qml and SidebarLeft.qml
 * for property-based testing. These mirror the QML service logic but are
 * testable in a Node.js environment.
 */

/**
 * Simulates double-tap detection state machine.
 *
 * Given an array of tap timestamps (in ms) and a threshold (max interval between
 * taps to count as a double-tap), returns the number of activations that would
 * occur. After an activation, subsequent taps within the threshold are debounced
 * (ignored) until the threshold window passes.
 *
 * State machine:
 *   Idle → WaitingForSecond (first tap starts timer)
 *   WaitingForSecond + tap within threshold → Activated (debounce until threshold passes)
 *   WaitingForSecond + timer expires → Idle (no activation)
 *
 * @param {number[]} tapTimestamps - Sorted array of tap timestamps in ms
 * @param {number} thresholdMs - Maximum interval between taps for double-tap detection
 * @returns {{ activated: boolean, activationCount: number }}
 */
export function detectDoubleTap(tapTimestamps, thresholdMs) {
  if (!tapTimestamps || tapTimestamps.length < 2) {
    return { activated: false, activationCount: 0 };
  }

  let activationCount = 0;
  let i = 0;

  while (i < tapTimestamps.length) {
    // First tap — look for second tap within threshold
    const firstTap = tapTimestamps[i];
    i++;

    if (i < tapTimestamps.length) {
      const secondTap = tapTimestamps[i];
      const interval = secondTap - firstTap;

      if (interval <= thresholdMs) {
        // Double-tap detected — activate
        activationCount++;
        i++;

        // Debounce: skip any taps that arrive within thresholdMs of the activation
        while (i < tapTimestamps.length && (tapTimestamps[i] - secondTap) <= thresholdMs) {
          i++;
        }
      }
      // If interval > threshold, the first tap expired. The loop continues and
      // treats tapTimestamps[i] (the "second" tap) as a new first tap.
    }
  }

  return { activated: activationCount > 0, activationCount };
}

/**
 * Routes transcribed text based on sidebar state.
 *
 * - Sidebar open → text goes to the AI chat (target: 'chat')
 * - Sidebar closed → text goes to AI Action Palette with '? ' prefix (target: 'palette')
 *
 * @param {string} text - Transcribed text
 * @param {boolean} sidebarOpen - Whether the left sidebar is currently open
 * @returns {{ target: 'chat' | 'palette', text: string }}
 */
export function routeTranscription(text, sidebarOpen) {
  if (sidebarOpen) {
    return { target: 'chat', text: text };
  } else {
    return { target: 'palette', text: '? ' + text };
  }
}

/**
 * Calculates exclusive zone for popout mode.
 *
 * When the sidebar is popped out, it claims exclusive zone equal to its width,
 * causing Hyprland to compress tiled windows to the right. When not popped out,
 * exclusive zone is 0 (overlay mode).
 *
 * @param {boolean} poppedOut - Whether the sidebar is in popout mode
 * @param {number} sidebarWidth - Current width of the sidebar in pixels
 * @returns {number} The exclusive zone value
 */
export function calculateExclusiveZone(poppedOut, sidebarWidth) {
  return poppedOut ? sidebarWidth : 0;
}

/**
 * Determines if silence timeout should fire.
 *
 * Returns true if the duration since the last audio activity exceeds the
 * configured silence timeout, indicating recording should auto-stop.
 *
 * @param {number} lastAudioTimestamp - Timestamp (ms) of last detected audio activity
 * @param {number} currentTimestamp - Current timestamp (ms)
 * @param {number} silenceTimeoutMs - Configured silence timeout duration (ms)
 * @returns {boolean} Whether the silence timeout condition is met
 */
export function shouldSilenceTimeout(lastAudioTimestamp, currentTimestamp, silenceTimeoutMs) {
  return (currentTimestamp - lastAudioTimestamp) >= silenceTimeoutMs;
}
