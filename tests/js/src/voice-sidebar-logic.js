/**
 * Pure logic functions extracted from voice-sidebar QML components
 * for property-based testing. These mirror the QML service logic but are
 * testable in a Node.js environment.
 *
 * Covers: VoiceProviderCheckService, DictationService debounce,
 * AiChat message ordering, ProviderPanel policy filtering.
 */

/**
 * Validates that an endpoint URL starts with a supported protocol scheme.
 *
 * Supported schemes: http://, https://, tcp://, ws://
 *
 * @param {string} url - The endpoint URL to validate
 * @returns {boolean} True if the URL starts with a supported scheme
 */
export function validateEndpointUrl(url) {
  if (typeof url !== "string") return false;
  return (
    url.startsWith("http://") ||
    url.startsWith("https://") ||
    url.startsWith("tcp://") ||
    url.startsWith("ws://")
  );
}

/**
 * Maps an HTTP connectivity check result to a CheckState object.
 *
 * - If timedOut is true → unreachable with timeout message
 * - If httpStatus is in [200, 499] → reachable
 * - If httpStatus is 0 or >= 500 → unreachable with server error message
 *
 * @param {number} httpStatus - The HTTP response status code (0 for network error)
 * @param {boolean} timedOut - Whether the request timed out
 * @returns {{ status: string, message: string }} The CheckState object
 */
export function mapConnectivityResult(httpStatus, timedOut) {
  if (timedOut) {
    return { status: "unreachable", message: "Connection timed out" };
  }
  if (httpStatus >= 200 && httpStatus <= 499) {
    return { status: "reachable", message: "" };
  }
  return { status: "unreachable", message: "Server error or network failure" };
}

/**
 * Simulates the debounce state machine for a sequence of tap events.
 *
 * Given an array of tap objects with timestamps, a debounce window in ms,
 * and an initial state ("Idle"), produces an array of state transitions.
 *
 * Behavior:
 * - First tap from Idle → activates (newState: "Listening"), starts debounce window
 * - Taps within debounceMs of activation → discarded (action: "rejected")
 * - Taps after debounceMs from activation → stops recording (newState: "Processing")
 * - If debounceMs === 0, no taps are ever discarded (all taps processed immediately)
 *
 * @param {{ timestamp: number }[]} taps - Array of tap events with timestamps
 * @param {number} debounceMs - Debounce window in milliseconds
 * @param {string} initialState - Initial state (should be "Idle")
 * @returns {{ timestamp: number, action: string, newState: string }[]} State transitions
 */
export function debounceStateMachine(taps, debounceMs, initialState) {
  const transitions = [];
  let state = initialState;
  let activationTimestamp = -1;

  for (let i = 0; i < taps.length; i++) {
    const tap = taps[i];

    if (state === "Idle") {
      // First tap from Idle → activate
      state = "Listening";
      activationTimestamp = tap.timestamp;
      transitions.push({
        timestamp: tap.timestamp,
        action: "activate",
        newState: "Listening",
      });
    } else if (state === "Listening") {
      if (debounceMs === 0) {
        // Debounce disabled — all taps process immediately
        state = "Processing";
        transitions.push({
          timestamp: tap.timestamp,
          action: "stop",
          newState: "Processing",
        });
      } else {
        const elapsed = tap.timestamp - activationTimestamp;
        if (elapsed <= debounceMs) {
          // Within debounce window — reject
          transitions.push({
            timestamp: tap.timestamp,
            action: "rejected",
            newState: "Listening",
          });
        } else {
          // After debounce window — stop recording
          state = "Processing";
          transitions.push({
            timestamp: tap.timestamp,
            action: "stop",
            newState: "Processing",
          });
        }
      }
    }
    // If state is "Processing", ignore further taps (session ended)
  }

  return transitions;
}

/**
 * Clamps an integer value to the valid debounce range [0, 2000].
 *
 * @param {number} value - The input value to clamp
 * @returns {number} The clamped value in [0, 2000]
 */
export function clampDebounceMs(value) {
  return Math.max(0, Math.min(2000, Math.round(value)));
}

/**
 * Prepares the message model array for the AiChat ListView.
 *
 * When layoutDirection is "BottomToTop", reverses the array so that
 * the newest message (last chronologically) is at index 0 (visual bottom),
 * preserving top-to-bottom chronological reading order.
 *
 * @param {string[]} ids - Array of message IDs in chronological order
 * @param {string} layoutDirection - "BottomToTop" or "TopToBottom"
 * @returns {string[]} The prepared model array (new array, does not mutate input)
 */
export function prepareMessageModel(ids, layoutDirection) {
  if (layoutDirection === "BottomToTop") {
    return ids.slice().reverse();
  }
  return ids.slice();
}

/**
 * Determines if an endpoint URL resolves to a local address.
 *
 * Returns true for endpoints matching:
 * - localhost (any supported scheme)
 * - 127.0.0.1 (any supported scheme)
 * - 10.x.x.x (private network, any supported scheme)
 * - 192.168.x.x (private network, any supported scheme)
 *
 * @param {string} endpoint - The endpoint URL to check
 * @returns {boolean} True if the endpoint is local
 */
export function isLocal(endpoint) {
  if (typeof endpoint !== "string") return false;

  const localPrefixes = [
    "http://localhost",
    "https://localhost",
    "ws://localhost",
    "tcp://localhost",
    "http://127.0.0.1",
    "https://127.0.0.1",
    "ws://127.0.0.1",
    "tcp://127.0.0.1",
    "http://10.",
    "https://10.",
    "ws://10.",
    "tcp://10.",
    "http://192.168.",
    "https://192.168.",
    "ws://192.168.",
    "tcp://192.168.",
  ];

  for (let i = 0; i < localPrefixes.length; i++) {
    if (endpoint.startsWith(localPrefixes[i])) {
      return true;
    }
  }
  return false;
}

/**
 * Filters a list of voice providers based on AI policy setting.
 *
 * - policy === 0: returns empty array (AI disabled, hide voice sections)
 * - policy === 1: returns full providers array (all allowed)
 * - policy === 2: returns only providers where isLocal(endpoint) is true
 *   OR providers that have no endpoint property defined
 *
 * @param {{ endpoint?: string }[]} providers - Array of provider config objects
 * @param {number} policy - AI policy value (0, 1, or 2)
 * @returns {{ endpoint?: string }[]} Filtered providers array
 */
export function filterProvidersByPolicy(providers, policy) {
  if (policy === 0) {
    return [];
  }
  if (policy === 1) {
    return providers.slice();
  }
  if (policy === 2) {
    const result = [];
    for (let i = 0; i < providers.length; i++) {
      const provider = providers[i];
      if (!("endpoint" in provider) || isLocal(provider.endpoint)) {
        result.push(provider);
      }
    }
    return result;
  }
  // Unknown policy — return empty for safety
  return [];
}

/**
 * Derives the set of editable field keys from a provider configuration object.
 *
 * Returns all keys present in the provider config — these correspond to the
 * fields that should be displayed in the detail view.
 *
 * @param {object} providerConfig - The provider configuration object
 * @returns {string[]} Array of field key names
 */
export function deriveDetailFields(providerConfig) {
  return Object.keys(providerConfig);
}
