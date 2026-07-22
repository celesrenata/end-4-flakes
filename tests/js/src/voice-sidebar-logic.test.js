import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import { validateEndpointUrl, mapConnectivityResult, debounceStateMachine, clampDebounceMs, prepareMessageModel, filterProvidersByPolicy, isLocal, deriveDetailFields } from './voice-sidebar-logic.js';

/**
 * Feature: voice-sidebar-fixes, Property 1: Endpoint URL Validation
 *
 * For any string input, validateEndpointUrl returns true iff the string begins
 * with one of http://, https://, tcp://, or ws://. All other strings return false.
 *
 * **Validates: Requirements 2.5**
 */
describe('Feature: voice-sidebar-fixes, Property 1: Endpoint URL Validation', () => {
  it('returns true for strings starting with valid schemes', () => {
    const schemes = ['http://', 'https://', 'tcp://', 'ws://'];
    fc.assert(fc.property(
      fc.constantFrom(...schemes),
      fc.string(),
      (scheme, rest) => {
        expect(validateEndpointUrl(scheme + rest)).toBe(true);
      }
    ), { numRuns: 100 });
  });

  it('returns false for strings not starting with valid schemes', () => {
    fc.assert(fc.property(
      fc.string().filter(s => 
        !s.startsWith('http://') && !s.startsWith('https://') &&
        !s.startsWith('tcp://') && !s.startsWith('ws://')
      ),
      (url) => {
        expect(validateEndpointUrl(url)).toBe(false);
      }
    ), { numRuns: 100 });
  });

  it('returns false for non-string inputs', () => {
    fc.assert(fc.property(
      fc.oneof(fc.integer(), fc.constant(null), fc.constant(undefined), fc.boolean()),
      (input) => {
        expect(validateEndpointUrl(input)).toBe(false);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: voice-sidebar-fixes, Property 2: Connectivity Status Mapping
 *
 * For any HTTP status code, if code is in [200, 499] the result is "reachable".
 * For status 0, codes >= 500, or timeout, the result is "unreachable".
 *
 * **Validates: Requirements 3.3, 3.4**
 */
describe('Feature: voice-sidebar-fixes, Property 2: Connectivity Status Mapping', () => {
  it('status 200-499 maps to reachable', () => {
    fc.assert(fc.property(
      fc.integer({ min: 200, max: 499 }),
      (status) => {
        const result = mapConnectivityResult(status, false);
        expect(result.status).toBe("reachable");
        expect(result.message).toBe("");
      }
    ), { numRuns: 100 });
  });

  it('status 0 or >=500 maps to unreachable', () => {
    fc.assert(fc.property(
      fc.oneof(fc.constant(0), fc.integer({ min: 500, max: 599 })),
      (status) => {
        const result = mapConnectivityResult(status, false);
        expect(result.status).toBe("unreachable");
        expect(result.message).not.toBe("");
      }
    ), { numRuns: 100 });
  });

  it('timeout always maps to unreachable regardless of status', () => {
    fc.assert(fc.property(
      fc.integer({ min: 0, max: 599 }),
      (status) => {
        const result = mapConnectivityResult(status, true);
        expect(result.status).toBe("unreachable");
        expect(result.message).toBe("Connection timed out");
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: voice-sidebar-fixes, Property 3: Debounce State Machine
 *
 * For any sequence of tap events with debounceMs > 0 and initial state Idle:
 * first tap activates, taps within debounceMs are discarded, taps after
 * debounceMs stop recording.
 *
 * **Validates: Requirements 4.1, 4.2, 4.3, 4.4**
 */
describe('Feature: voice-sidebar-fixes, Property 3: Debounce State Machine', () => {
  it('first tap from Idle activates', () => {
    fc.assert(fc.property(
      fc.integer({ min: 0, max: 100000 }),  // timestamp
      fc.integer({ min: 1, max: 2000 }),     // debounceMs
      (timestamp, debounceMs) => {
        const taps = [{ timestamp }];
        const transitions = debounceStateMachine(taps, debounceMs, "Idle");
        expect(transitions.length).toBe(1);
        expect(transitions[0].action).toBe("activate");
        expect(transitions[0].newState).toBe("Listening");
      }
    ), { numRuns: 100 });
  });

  it('taps within debounceMs are rejected', () => {
    fc.assert(fc.property(
      fc.integer({ min: 0, max: 100000 }),   // firstTap
      fc.integer({ min: 100, max: 2000 }),    // debounceMs
      fc.integer({ min: 1 }),                  // offsetSeed
      (firstTap, debounceMs, offsetSeed) => {
        const offset = (Math.abs(offsetSeed) % debounceMs) + 1; // 1..debounceMs (within window)
        const taps = [{ timestamp: firstTap }, { timestamp: firstTap + offset }];
        const transitions = debounceStateMachine(taps, debounceMs, "Idle");
        expect(transitions.length).toBe(2);
        expect(transitions[0].action).toBe("activate");
        expect(transitions[1].action).toBe("rejected");
        expect(transitions[1].newState).toBe("Listening");
      }
    ), { numRuns: 100 });
  });

  it('taps after debounceMs stop recording', () => {
    fc.assert(fc.property(
      fc.integer({ min: 0, max: 100000 }),   // firstTap
      fc.integer({ min: 100, max: 2000 }),    // debounceMs
      fc.integer({ min: 1, max: 10000 }),     // extra
      (firstTap, debounceMs, extra) => {
        const secondTap = firstTap + debounceMs + extra; // strictly after window
        const taps = [{ timestamp: firstTap }, { timestamp: secondTap }];
        const transitions = debounceStateMachine(taps, debounceMs, "Idle");
        expect(transitions.length).toBe(2);
        expect(transitions[0].action).toBe("activate");
        expect(transitions[1].action).toBe("stop");
        expect(transitions[1].newState).toBe("Processing");
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: voice-sidebar-fixes, Property 4: Debounce Idle Invariant
 *
 * For any DictationService state snapshot, if state is Idle then debounce
 * is not active and the debounce timer is not running.
 *
 * **Validates: Requirements 4.5**
 */
describe('Feature: voice-sidebar-fixes, Property 4: Debounce Idle Invariant', () => {
  it('debounce state machine starting from Idle has no active debounce before first tap', () => {
    fc.assert(fc.property(
      fc.integer({ min: 1, max: 2000 }),  // debounceMs
      (debounceMs) => {
        // With zero taps, no transitions occur — debounce is never activated
        const transitions = debounceStateMachine([], debounceMs, "Idle");
        expect(transitions.length).toBe(0);
      }
    ), { numRuns: 100 });
  });

  it('after processing completes (session ends), no further transitions occur', () => {
    fc.assert(fc.property(
      fc.integer({ min: 0, max: 100000 }),
      fc.integer({ min: 100, max: 2000 }),
      fc.integer({ min: 1, max: 10000 }),
      fc.integer({ min: 1, max: 10000 }),
      (firstTap, debounceMs, afterWindow, extraTap) => {
        const secondTap = firstTap + debounceMs + afterWindow;
        const thirdTap = secondTap + extraTap;
        const taps = [
          { timestamp: firstTap },
          { timestamp: secondTap },
          { timestamp: thirdTap }
        ];
        const transitions = debounceStateMachine(taps, debounceMs, "Idle");
        // Third tap is ignored because state is "Processing"
        expect(transitions.length).toBe(2);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: voice-sidebar-fixes, Property 5: Debounce Disabled at Zero
 *
 * For any sequence of tap events with debounceMs === 0, no tap is ever
 * discarded due to debounce. Every tap from Idle activates, every tap from
 * Listening stops recording.
 *
 * **Validates: Requirements 5.3**
 */
describe('Feature: voice-sidebar-fixes, Property 5: Debounce Disabled at Zero', () => {
  it('with debounceMs=0, second tap from Listening immediately stops', () => {
    fc.assert(fc.property(
      fc.integer({ min: 0, max: 100000 }),   // firstTap
      fc.integer({ min: 1, max: 10000 }),     // interval (any)
      (firstTap, interval) => {
        const taps = [{ timestamp: firstTap }, { timestamp: firstTap + interval }];
        const transitions = debounceStateMachine(taps, 0, "Idle");
        expect(transitions.length).toBe(2);
        expect(transitions[0].action).toBe("activate");
        expect(transitions[1].action).toBe("stop");
        // No tap is ever "rejected" when debounceMs=0
      }
    ), { numRuns: 100 });
  });

  it('with debounceMs=0, no tap is ever rejected regardless of timing', () => {
    fc.assert(fc.property(
      fc.array(fc.integer({ min: 0, max: 100000 }), { minLength: 1, maxLength: 5 }),
      (timestamps) => {
        // Sort timestamps to simulate chronological order
        const sorted = timestamps.slice().sort((a, b) => a - b);
        const taps = sorted.map(t => ({ timestamp: t }));
        const transitions = debounceStateMachine(taps, 0, "Idle");
        const rejected = transitions.filter(t => t.action === "rejected");
        expect(rejected.length).toBe(0);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: voice-sidebar-fixes, Property 6: Debounce Value Clamping
 *
 * For any integer value x, the clamped result equals Math.max(0, Math.min(2000, x)).
 *
 * **Validates: Requirements 5.4**
 */
describe('Feature: voice-sidebar-fixes, Property 6: Debounce Value Clamping', () => {
  it('clampDebounceMs equals Math.max(0, Math.min(2000, Math.round(x)))', () => {
    fc.assert(fc.property(
      fc.integer({ min: -10000, max: 10000 }),
      (x) => {
        const result = clampDebounceMs(x);
        const expected = Math.max(0, Math.min(2000, Math.round(x)));
        expect(result).toBe(expected);
      }
    ), { numRuns: 100 });
  });

  it('result is always in [0, 2000]', () => {
    fc.assert(fc.property(
      fc.double({ min: -1e9, max: 1e9, noNaN: true }),
      (x) => {
        const result = clampDebounceMs(x);
        expect(result).toBeGreaterThanOrEqual(0);
        expect(result).toBeLessThanOrEqual(2000);
      }
    ), { numRuns: 100 });
  });

  it('values within range are unchanged after rounding', () => {
    fc.assert(fc.property(
      fc.integer({ min: 0, max: 2000 }),
      (x) => {
        expect(clampDebounceMs(x)).toBe(x);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: voice-sidebar-fixes, Property 7: Message Chronological Ordering
 *
 * For any array of message IDs in chronological order, the BottomToTop model
 * transformation produces the reverse — newest at index 0 (visual bottom),
 * oldest at last index (visual top).
 *
 * **Validates: Requirements 6.1, 6.2**
 */
describe('Feature: voice-sidebar-fixes, Property 7: Message Chronological Ordering', () => {
  it('BottomToTop reverses any array of message IDs', () => {
    fc.assert(fc.property(
      fc.array(fc.string({ minLength: 1, maxLength: 20 })),
      (ids) => {
        const result = prepareMessageModel(ids, "BottomToTop");
        const expected = ids.slice().reverse();
        expect(result).toEqual(expected);
      }
    ), { numRuns: 100 });
  });

  it('TopToBottom preserves original order', () => {
    fc.assert(fc.property(
      fc.array(fc.string({ minLength: 1, maxLength: 20 })),
      (ids) => {
        const result = prepareMessageModel(ids, "TopToBottom");
        expect(result).toEqual(ids);
      }
    ), { numRuns: 100 });
  });

  it('does not mutate the input array', () => {
    fc.assert(fc.property(
      fc.array(fc.string({ minLength: 1, maxLength: 20 }), { minLength: 1 }),
      (ids) => {
        const original = ids.slice();
        prepareMessageModel(ids, "BottomToTop");
        expect(ids).toEqual(original);
      }
    ), { numRuns: 100 });
  });

  it('BottomToTop result has same length as input', () => {
    fc.assert(fc.property(
      fc.array(fc.string({ minLength: 1, maxLength: 20 })),
      (ids) => {
        const result = prepareMessageModel(ids, "BottomToTop");
        expect(result.length).toBe(ids.length);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: voice-sidebar-fixes, Property 8: Voice Provider Policy Filtering
 *
 * For any list of providers: policy 1 returns all, policy 2 returns only local
 * or endpoint-less providers, policy 0 returns empty.
 *
 * **Validates: Requirements 7.1, 7.4, 7.2**
 */
describe('Feature: voice-sidebar-fixes, Property 8: Voice Provider Policy Filtering', () => {
  it('policy=1 returns all providers unchanged', () => {
    fc.assert(fc.property(
      fc.array(fc.record({
        endpoint: fc.oneof(fc.constant("http://localhost:8080"), fc.constant("http://remote.com:5000"))
      }), { minLength: 0, maxLength: 10 }),
      (providers) => {
        const result = filterProvidersByPolicy(providers, 1);
        expect(result).toEqual(providers);
      }
    ), { numRuns: 100 });
  });

  it('policy=0 always returns empty array', () => {
    fc.assert(fc.property(
      fc.array(fc.record({
        endpoint: fc.string()
      }), { minLength: 0, maxLength: 10 }),
      (providers) => {
        const result = filterProvidersByPolicy(providers, 0);
        expect(result).toEqual([]);
      }
    ), { numRuns: 100 });
  });

  it('policy=2 returns only local providers', () => {
    const localProvider = { endpoint: "http://localhost:8080" };
    const remoteProvider = { endpoint: "http://remote.example.com:5000" };
    const noEndpointProvider = { voice: "en", speed: 175 };
    
    fc.assert(fc.property(
      fc.array(fc.constantFrom(localProvider, remoteProvider, noEndpointProvider), { minLength: 1, maxLength: 10 }),
      (providers) => {
        const result = filterProvidersByPolicy(providers, 2);
        // Every provider in the result must be local or have no endpoint
        for (let i = 0; i < result.length; i++) {
          const p = result[i];
          if ("endpoint" in p) {
            expect(isLocal(p.endpoint)).toBe(true);
          }
        }
        // Remote providers must NOT be in the result
        const remoteCount = providers.filter(p => "endpoint" in p && !isLocal(p.endpoint)).length;
        const resultRemoteCount = result.filter(p => "endpoint" in p && !isLocal(p.endpoint)).length;
        expect(resultRemoteCount).toBe(0);
      }
    ), { numRuns: 100 });
  });

  it('policy=2 preserves providers without endpoint property', () => {
    fc.assert(fc.property(
      fc.array(fc.record({
        voice: fc.string({ minLength: 1 }),
        speed: fc.integer({ min: 50, max: 300 })
      }), { minLength: 1, maxLength: 5 }),
      (providers) => {
        // None have "endpoint" property → all should pass through with policy=2
        const result = filterProvidersByPolicy(providers, 2);
        expect(result.length).toBe(providers.length);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: voice-sidebar-fixes, Property 9: TTS Detail View Field Derivation
 *
 * For any provider configuration object, the derived editable fields are exactly
 * the set of keys present in that configuration object.
 *
 * **Validates: Requirements 2.2**
 */
describe('Feature: voice-sidebar-fixes, Property 9: TTS Detail View Field Derivation', () => {
  it('returns exactly the keys of the config object', () => {
    fc.assert(fc.property(
      fc.dictionary(
        fc.string({ minLength: 1, maxLength: 20 }).filter(s => /^[a-zA-Z]/.test(s)),
        fc.oneof(fc.string(), fc.integer(), fc.boolean())
      ),
      (config) => {
        const result = deriveDetailFields(config);
        const expected = Object.keys(config);
        expect(result.sort()).toEqual(expected.sort());
      }
    ), { numRuns: 100 });
  });

  it('returns empty array for empty config', () => {
    expect(deriveDetailFields({})).toEqual([]);
  });

  it('includes all fields for known TTS provider shapes', () => {
    const piperConfig = { endpoint: "tcp://localhost:10200", protocol: "wyoming", voice: "en_US-lessac-medium", model: "" };
    const espeakConfig = { voice: "en", speed: 175, pitch: 50 };
    
    expect(deriveDetailFields(piperConfig).sort()).toEqual(["endpoint", "model", "protocol", "voice"]);
    expect(deriveDetailFields(espeakConfig).sort()).toEqual(["pitch", "speed", "voice"]);
  });
});
