/**
 * Integration tests for Voice Dictation + Sidebar Popout.
 * Tests the pure logic functions together end-to-end, simulating the full
 * dictation flow, popout toggle lifecycle, and policy enforcement.
 *
 * Validates: Requirements 3.1, 3.2, 4.1, 7.2, 7.6, 7.10, 8.1, 8.2
 */
import { describe, it, expect } from 'vitest';
import { detectDoubleTap, routeTranscription, calculateExclusiveZone, shouldSilenceTimeout } from './dictation-logic.js';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

const KNOWN_LOCAL_PROVIDERS = ['whisper-cpp', 'faster-whisper', 'local-whisper'];

/**
 * Simulate a full dictation flow from tap detection through transcription routing.
 */
function simulateDictationFlow({ tapTimestamps, thresholdMs, sidebarOpen, transcribedText, policyAi, provider }) {
  // Step 1: Policy gates
  if (policyAi === 0) {
    return { error: 'AI is disabled by policy', state: 'error' };
  }
  if (!provider) {
    return { error: 'No provider configured', state: 'error' };
  }
  if (policyAi === 2 && KNOWN_LOCAL_PROVIDERS.indexOf(provider) === -1) {
    return { error: 'Online transcription disallowed by policy', state: 'error' };
  }

  // Step 2: Detect double-tap
  const tapResult = detectDoubleTap(tapTimestamps, thresholdMs);
  if (!tapResult.activated) {
    return { state: 'idle', activated: false };
  }

  // Step 3: Simulate recording and transcription (mocked pw-record + API)
  if (!transcribedText) {
    return { error: 'Empty transcription', state: 'error' };
  }

  // Step 4: Route the text
  const routing = routeTranscription(transcribedText, sidebarOpen);
  return { state: 'complete', activated: true, ...routing };
}

/**
 * Simulate a popout toggle and return the resulting state.
 */
function simulatePopoutToggle(currentPoppedOut, sidebarWidth, visible) {
  const newPoppedOut = !currentPoppedOut;
  return {
    poppedOut: newPoppedOut,
    exclusiveZone: calculateExclusiveZone(newPoppedOut, sidebarWidth),
    focusGrabActive: visible && !newPoppedOut,
    visible: newPoppedOut || visible,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// 13.1 — Full dictation with mocked audio and transcription
// ─────────────────────────────────────────────────────────────────────────────

describe('Integration: Full dictation flow with mocked audio and transcription', () => {
  it('double-tap activates recording and routes to action palette when sidebar closed', () => {
    const result = simulateDictationFlow({
      tapTimestamps: [1000, 1200],
      thresholdMs: 400,
      sidebarOpen: false,
      transcribedText: 'make it dark mode',
      policyAi: 1,
      provider: 'openai',
    });

    expect(result.state).toBe('complete');
    expect(result.activated).toBe(true);
    expect(result.target).toBe('palette');
    expect(result.text).toBe('? make it dark mode');
  });

  it('double-tap activates and routes to sidebar chat when sidebar open', () => {
    const result = simulateDictationFlow({
      tapTimestamps: [500, 800],
      thresholdMs: 400,
      sidebarOpen: true,
      transcribedText: 'explain this error message',
      policyAi: 1,
      provider: 'whisper-cpp',
    });

    expect(result.state).toBe('complete');
    expect(result.activated).toBe(true);
    expect(result.target).toBe('chat');
    expect(result.text).toBe('explain this error message');
  });

  it('single tap does not activate dictation', () => {
    const result = simulateDictationFlow({
      tapTimestamps: [1000],
      thresholdMs: 400,
      sidebarOpen: false,
      transcribedText: 'should not matter',
      policyAi: 1,
      provider: 'openai',
    });

    expect(result.state).toBe('idle');
    expect(result.activated).toBe(false);
  });

  it('taps outside threshold do not activate dictation', () => {
    const result = simulateDictationFlow({
      tapTimestamps: [1000, 1500],
      thresholdMs: 400,
      sidebarOpen: false,
      transcribedText: 'irrelevant',
      policyAi: 1,
      provider: 'openai',
    });

    expect(result.state).toBe('idle');
    expect(result.activated).toBe(false);
  });

  it('empty transcription returns an error state', () => {
    const result = simulateDictationFlow({
      tapTimestamps: [100, 300],
      thresholdMs: 400,
      sidebarOpen: false,
      transcribedText: '',
      policyAi: 1,
      provider: 'openai',
    });

    expect(result.state).toBe('error');
    expect(result.error).toBe('Empty transcription');
  });

  it('simulates full lifecycle: activate → record → silence timeout → transcribe → route', () => {
    // Simulate time-based events
    const now = Date.now();
    const tapTimestamps = [now, now + 150]; // Double-tap within 400ms

    const result = simulateDictationFlow({
      tapTimestamps,
      thresholdMs: 400,
      sidebarOpen: false,
      transcribedText: 'open a terminal',
      policyAi: 1,
      provider: 'faster-whisper',
    });

    expect(result.state).toBe('complete');
    expect(result.target).toBe('palette');
    expect(result.text).toBe('? open a terminal');

    // Verify silence timeout would fire after 3s of silence
    const lastAudio = now + 2000;
    const checkAt = lastAudio + 3000;
    expect(shouldSilenceTimeout(lastAudio, checkAt, 3000)).toBe(true);
  });

  it('recording with local provider works end-to-end', () => {
    const result = simulateDictationFlow({
      tapTimestamps: [0, 200],
      thresholdMs: 400,
      sidebarOpen: true,
      transcribedText: 'what is the weather today',
      policyAi: 2, // Local-only policy
      provider: 'whisper-cpp', // Known local provider
    });

    expect(result.state).toBe('complete');
    expect(result.target).toBe('chat');
    expect(result.text).toBe('what is the weather today');
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 13.2 — Sidebar popout exclusive zone
// ─────────────────────────────────────────────────────────────────────────────

describe('Integration: Sidebar popout exclusive zone', () => {
  it('toggling from overlay to popout sets exclusiveZone to sidebarWidth', () => {
    const result = simulatePopoutToggle(false, 400, true);

    expect(result.poppedOut).toBe(true);
    expect(result.exclusiveZone).toBe(400);
  });

  it('toggling from popout to overlay sets exclusiveZone to 0', () => {
    const result = simulatePopoutToggle(true, 400, true);

    expect(result.poppedOut).toBe(false);
    expect(result.exclusiveZone).toBe(0);
  });

  it('focusGrab is disabled when popped out', () => {
    const result = simulatePopoutToggle(false, 350, true);

    expect(result.poppedOut).toBe(true);
    expect(result.focusGrabActive).toBe(false);
  });

  it('focusGrab is enabled when not popped out and sidebar visible', () => {
    const result = simulatePopoutToggle(true, 350, true);

    expect(result.poppedOut).toBe(false);
    expect(result.focusGrabActive).toBe(true);
  });

  it('focusGrab is disabled when sidebar not visible (regardless of popout state)', () => {
    const result = simulatePopoutToggle(true, 350, false);

    expect(result.poppedOut).toBe(false);
    expect(result.focusGrabActive).toBe(false);
  });

  it('popout forces visibility to true', () => {
    // Even if sidebar was not visible, popping out makes it visible
    const result = simulatePopoutToggle(false, 400, false);

    expect(result.poppedOut).toBe(true);
    expect(result.visible).toBe(true);
  });

  it('un-popping respects prior visibility state', () => {
    // If sidebar was visible before un-popping, stays visible
    const resultVisible = simulatePopoutToggle(true, 400, true);
    expect(resultVisible.visible).toBe(true);

    // If sidebar was not visible before un-popping, goes invisible
    const resultHidden = simulatePopoutToggle(true, 400, false);
    expect(resultHidden.visible).toBe(false);
  });

  it('exclusiveZone tracks width changes while popped out', () => {
    // Simulate resizing while in popout mode
    const widths = [300, 350, 400, 450, 500];
    for (const width of widths) {
      const zone = calculateExclusiveZone(true, width);
      expect(zone).toBe(width);
    }
  });

  it('exclusiveZone stays 0 when not popped out regardless of width', () => {
    const widths = [300, 350, 400, 450, 500];
    for (const width of widths) {
      const zone = calculateExclusiveZone(false, width);
      expect(zone).toBe(0);
    }
  });

  it('full toggle cycle: overlay → popout → overlay preserves correct states', () => {
    const width = 380;

    // Start as overlay (not popped out, visible)
    let state = { poppedOut: false, visible: true };

    // Toggle to popout
    const afterPopout = simulatePopoutToggle(state.poppedOut, width, state.visible);
    expect(afterPopout.poppedOut).toBe(true);
    expect(afterPopout.exclusiveZone).toBe(380);
    expect(afterPopout.focusGrabActive).toBe(false);
    expect(afterPopout.visible).toBe(true);

    // Toggle back to overlay
    const afterOverlay = simulatePopoutToggle(afterPopout.poppedOut, width, afterPopout.visible);
    expect(afterOverlay.poppedOut).toBe(false);
    expect(afterOverlay.exclusiveZone).toBe(0);
    expect(afterOverlay.focusGrabActive).toBe(true);
    expect(afterOverlay.visible).toBe(true);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 13.3 — Policy enforcement
// ─────────────────────────────────────────────────────────────────────────────

describe('Integration: Policy enforcement', () => {
  it('policies.ai=0 blocks dictation activation entirely', () => {
    const result = simulateDictationFlow({
      tapTimestamps: [100, 250],
      thresholdMs: 400,
      sidebarOpen: false,
      transcribedText: 'this should not work',
      policyAi: 0,
      provider: 'openai',
    });

    expect(result.state).toBe('error');
    expect(result.error).toBe('AI is disabled by policy');
  });

  it('policies.ai=0 blocks even with local provider', () => {
    const result = simulateDictationFlow({
      tapTimestamps: [100, 250],
      thresholdMs: 400,
      sidebarOpen: true,
      transcribedText: 'local should also be blocked',
      policyAi: 0,
      provider: 'whisper-cpp',
    });

    expect(result.state).toBe('error');
    expect(result.error).toBe('AI is disabled by policy');
  });

  it('policies.ai=2 with remote provider shows error', () => {
    const result = simulateDictationFlow({
      tapTimestamps: [100, 250],
      thresholdMs: 400,
      sidebarOpen: false,
      transcribedText: 'remote should fail',
      policyAi: 2,
      provider: 'openai',
    });

    expect(result.state).toBe('error');
    expect(result.error).toBe('Online transcription disallowed by policy');
  });

  it('policies.ai=2 blocks all non-local providers', () => {
    const remoteProviders = ['openai', 'azure-whisper', 'groq-whisper', 'deepgram'];

    for (const provider of remoteProviders) {
      const result = simulateDictationFlow({
        tapTimestamps: [100, 250],
        thresholdMs: 400,
        sidebarOpen: false,
        transcribedText: 'should fail',
        policyAi: 2,
        provider,
      });

      expect(result.state).toBe('error');
      expect(result.error).toBe('Online transcription disallowed by policy');
    }
  });

  it('policies.ai=2 allows known local providers', () => {
    const localProviders = ['whisper-cpp', 'faster-whisper', 'local-whisper'];

    for (const provider of localProviders) {
      const result = simulateDictationFlow({
        tapTimestamps: [100, 250],
        thresholdMs: 400,
        sidebarOpen: false,
        transcribedText: 'local is fine',
        policyAi: 2,
        provider,
      });

      expect(result.state).toBe('complete');
      expect(result.activated).toBe(true);
      expect(result.target).toBe('palette');
    }
  });

  it('policies.ai=1 allows any provider (no restriction)', () => {
    const providers = ['openai', 'whisper-cpp', 'azure-whisper', 'faster-whisper'];

    for (const provider of providers) {
      const result = simulateDictationFlow({
        tapTimestamps: [100, 250],
        thresholdMs: 400,
        sidebarOpen: true,
        transcribedText: 'all providers allowed',
        policyAi: 1,
        provider,
      });

      expect(result.state).toBe('complete');
      expect(result.target).toBe('chat');
    }
  });

  it('no provider configured shows error regardless of policy', () => {
    const result = simulateDictationFlow({
      tapTimestamps: [100, 250],
      thresholdMs: 400,
      sidebarOpen: false,
      transcribedText: 'no provider',
      policyAi: 1,
      provider: '',
    });

    expect(result.state).toBe('error');
    expect(result.error).toBe('No provider configured');
  });

  it('null provider treated as unconfigured', () => {
    const result = simulateDictationFlow({
      tapTimestamps: [100, 250],
      thresholdMs: 400,
      sidebarOpen: false,
      transcribedText: 'null provider',
      policyAi: 1,
      provider: null,
    });

    expect(result.state).toBe('error');
    expect(result.error).toBe('No provider configured');
  });

  it('policy check runs before double-tap detection (early exit)', () => {
    // Even with invalid tap data, policy check returns error first
    const result = simulateDictationFlow({
      tapTimestamps: [],
      thresholdMs: 400,
      sidebarOpen: false,
      transcribedText: 'irrelevant',
      policyAi: 0,
      provider: 'openai',
    });

    expect(result.state).toBe('error');
    expect(result.error).toBe('AI is disabled by policy');
  });
});
