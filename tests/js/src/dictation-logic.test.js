import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import { detectDoubleTap, routeTranscription, calculateExclusiveZone, shouldSilenceTimeout } from './dictation-logic.js';

/**
 * Feature: voice-dictation, Property 1: Double-Tap Timing Detection
 *
 * The double-tap state machine activates iff two taps arrive within the
 * configured threshold. Single taps pass through, and rapid multi-taps
 * (triple+) produce at most one activation due to debounce.
 *
 * **Validates: Requirements 1.1, 1.2, 1.3**
 */
describe('Feature: voice-dictation, Property 1: Double-Tap Timing Detection', () => {
  it('two taps within threshold → activates exactly once', () => {
    fc.assert(fc.property(
      fc.integer({ min: 0, max: 100000 }),           // firstTap timestamp
      fc.integer({ min: 100, max: 1000 }),            // thresholdMs
      fc.integer({ min: 1 }),                         // interval (will be clamped to threshold)
      (firstTap, thresholdMs, intervalSeed) => {
        const interval = (intervalSeed % thresholdMs) + 1; // 1..thresholdMs (within threshold)
        const secondTap = firstTap + interval;
        const result = detectDoubleTap([firstTap, secondTap], thresholdMs);
        expect(result.activated).toBe(true);
        expect(result.activationCount).toBe(1);
      }
    ), { numRuns: 100 });
  });

  it('two taps outside threshold → no activation', () => {
    fc.assert(fc.property(
      fc.integer({ min: 0, max: 100000 }),           // firstTap timestamp
      fc.integer({ min: 100, max: 1000 }),            // thresholdMs
      fc.integer({ min: 1, max: 10000 }),             // extra delay beyond threshold
      (firstTap, thresholdMs, extraDelay) => {
        const secondTap = firstTap + thresholdMs + extraDelay; // strictly beyond threshold
        const result = detectDoubleTap([firstTap, secondTap], thresholdMs);
        expect(result.activated).toBe(false);
        expect(result.activationCount).toBe(0);
      }
    ), { numRuns: 100 });
  });

  it('three rapid taps → only one activation (debounce)', () => {
    fc.assert(fc.property(
      fc.integer({ min: 0, max: 100000 }),           // firstTap timestamp
      fc.integer({ min: 100, max: 1000 }),            // thresholdMs
      fc.integer({ min: 1 }),                         // interval1 seed
      fc.integer({ min: 1 }),                         // interval2 seed
      (firstTap, thresholdMs, interval1Seed, interval2Seed) => {
        // All three taps within the threshold window
        const interval1 = (interval1Seed % Math.max(1, thresholdMs / 2)) + 1;
        const interval2 = (interval2Seed % Math.max(1, thresholdMs / 2)) + 1;
        const secondTap = firstTap + interval1;
        const thirdTap = secondTap + interval2;

        const result = detectDoubleTap([firstTap, secondTap, thirdTap], thresholdMs);
        // Third tap is debounced — only one activation
        expect(result.activationCount).toBe(1);
      }
    ), { numRuns: 100 });
  });

  it('single tap → no activation', () => {
    fc.assert(fc.property(
      fc.integer({ min: 0, max: 100000 }),
      fc.integer({ min: 100, max: 1000 }),
      (timestamp, thresholdMs) => {
        const result = detectDoubleTap([timestamp], thresholdMs);
        expect(result.activated).toBe(false);
        expect(result.activationCount).toBe(0);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: voice-dictation, Property 2: Routing Logic
 *
 * Transcribed text is routed based on sidebar state:
 * - Sidebar open → text goes to the AI chat unchanged
 * - Sidebar closed → text goes to action palette with '? ' prefix
 *
 * **Validates: Requirements 3.1, 3.2**
 */
describe('Feature: voice-dictation, Property 2: Routing Logic', () => {
  it('sidebar open → text goes to chat, unchanged', () => {
    fc.assert(fc.property(
      fc.string({ minLength: 1 }),
      (text) => {
        const result = routeTranscription(text, true);
        expect(result.target).toBe('chat');
        expect(result.text).toBe(text);
      }
    ), { numRuns: 100 });
  });

  it('sidebar closed → text goes to palette with "? " prefix', () => {
    fc.assert(fc.property(
      fc.string({ minLength: 1 }),
      (text) => {
        const result = routeTranscription(text, false);
        expect(result.target).toBe('palette');
        expect(result.text).toBe('? ' + text);
      }
    ), { numRuns: 100 });
  });

  it('routing is deterministic — same inputs always produce same output', () => {
    fc.assert(fc.property(
      fc.string(),
      fc.boolean(),
      (text, sidebarOpen) => {
        const result1 = routeTranscription(text, sidebarOpen);
        const result2 = routeTranscription(text, sidebarOpen);
        expect(result1).toEqual(result2);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: voice-dictation, Property 3: Exclusive Zone Matches Sidebar Width
 *
 * In popout mode, the exclusive zone must equal the sidebar width so that
 * Hyprland compresses tiled windows by exactly the sidebar's width. When not
 * popped out, exclusive zone is always 0.
 *
 * **Validates: Requirements 7.2, 7.5**
 */
describe('Feature: voice-dictation, Property 3: Exclusive Zone Matches Sidebar Width', () => {
  const MIN_WIDTH = 300;
  const MAX_WIDTH = 800;

  it('popout mode → exclusiveZone equals sidebar width for any valid width', () => {
    fc.assert(fc.property(
      fc.integer({ min: MIN_WIDTH, max: MAX_WIDTH }),
      (sidebarWidth) => {
        const zone = calculateExclusiveZone(true, sidebarWidth);
        expect(zone).toBe(sidebarWidth);
      }
    ), { numRuns: 100 });
  });

  it('non-popout mode → exclusiveZone is always 0 regardless of width', () => {
    fc.assert(fc.property(
      fc.integer({ min: MIN_WIDTH, max: MAX_WIDTH }),
      (sidebarWidth) => {
        const zone = calculateExclusiveZone(false, sidebarWidth);
        expect(zone).toBe(0);
      }
    ), { numRuns: 100 });
  });

  it('exclusiveZone updates correctly when width changes during popout', () => {
    fc.assert(fc.property(
      fc.integer({ min: MIN_WIDTH, max: MAX_WIDTH }),
      fc.integer({ min: MIN_WIDTH, max: MAX_WIDTH }),
      (width1, width2) => {
        const zone1 = calculateExclusiveZone(true, width1);
        const zone2 = calculateExclusiveZone(true, width2);
        expect(zone1).toBe(width1);
        expect(zone2).toBe(width2);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: voice-dictation, Property 4: Silence Timeout Fires After Configured Duration
 *
 * The silence timeout should fire (return true) when the elapsed time since
 * last audio activity meets or exceeds the configured timeout. It should NOT
 * fire when less time has elapsed.
 *
 * **Validates: Requirements 1.6, 6.4**
 */
describe('Feature: voice-dictation, Property 4: Silence Timeout Fires After Configured Duration', () => {
  it('fires when elapsed time >= silenceTimeoutMs', () => {
    fc.assert(fc.property(
      fc.integer({ min: 0, max: 100000 }),           // lastAudioTimestamp
      fc.integer({ min: 1000, max: 10000 }),          // silenceTimeoutMs
      fc.integer({ min: 0, max: 5000 }),              // extra time beyond timeout
      (lastAudio, timeoutMs, extra) => {
        const current = lastAudio + timeoutMs + extra;
        expect(shouldSilenceTimeout(lastAudio, current, timeoutMs)).toBe(true);
      }
    ), { numRuns: 100 });
  });

  it('does NOT fire when elapsed time < silenceTimeoutMs', () => {
    fc.assert(fc.property(
      fc.integer({ min: 0, max: 100000 }),           // lastAudioTimestamp
      fc.integer({ min: 1000, max: 10000 }),          // silenceTimeoutMs
      fc.integer({ min: 1 }),                         // shortfall seed
      (lastAudio, timeoutMs, shortfallSeed) => {
        // Ensure elapsed is strictly less than timeout
        const shortfall = (shortfallSeed % (timeoutMs - 1)) + 1; // 1..(timeoutMs-1)
        const current = lastAudio + timeoutMs - shortfall;
        expect(shouldSilenceTimeout(lastAudio, current, timeoutMs)).toBe(false);
      }
    ), { numRuns: 100 });
  });

  it('fires at exactly the timeout boundary', () => {
    fc.assert(fc.property(
      fc.integer({ min: 0, max: 100000 }),
      fc.integer({ min: 1000, max: 10000 }),
      (lastAudio, timeoutMs) => {
        const current = lastAudio + timeoutMs; // exactly at boundary
        expect(shouldSilenceTimeout(lastAudio, current, timeoutMs)).toBe(true);
      }
    ), { numRuns: 100 });
  });
});
