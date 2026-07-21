/**
 * Integration tests for Context Lens — full vision request cycle, policy enforcement, and error handling.
 * Models the Context Lens state machine and logic flows in pure JavaScript
 * since QML Process/Timer cannot run in Node.js.
 *
 * Validates: Requirements 3.1, 4.3, 6.1, 6.2, 6.3, 8.1, 8.2
 */
import { describe, it, expect } from 'vitest';
import { isVisionCapable, buildOpenAiContent, buildGeminiParts, transformCropCoordinates, getPromptForAction } from './context-lens-logic.js';

// --- Shared engine factory ---

/**
 * Creates a Context Lens state machine engine modeling the full lifecycle:
 * Selecting → ActionWheel → Loading → Result (or Error)
 */
function createContextLensEngine() {
  let state = 'Selecting';
  let selectedRegion = null;
  let selectedAction = '';
  let selectedPrompt = '';
  let resultText = '';
  let resultDone = false;
  let errorMessage = '';
  let imageBase64 = '';

  function selectRegion(x, y, w, h, scale, screenshotPath) {
    selectedRegion = { x, y, w, h, scale, screenshotPath };
    state = 'ActionWheel';
  }

  function pickAction(actionId, customPrompt) {
    selectedAction = actionId;
    selectedPrompt = customPrompt || '';
    // Validate minimum size (10x10 after scale)
    const scaledW = Math.round(selectedRegion.w * selectedRegion.scale);
    const scaledH = Math.round(selectedRegion.h * selectedRegion.scale);
    if (scaledW < 10 || scaledH < 10) {
      errorMessage = 'Region too small — please select a larger area';
      state = 'Error';
      return;
    }
    state = 'Loading';
    resultText = '';
    resultDone = false;
    imageBase64 = '';
  }

  function cropComplete(base64Data) {
    imageBase64 = base64Data;
  }

  function onChunk(chunk) {
    resultText += chunk;
  }

  function onDone() {
    resultDone = true;
    state = 'Result';
  }

  function onError(msg) {
    errorMessage = msg;
    state = 'Error';
  }

  function retry() {
    state = 'Loading';
    resultText = '';
    resultDone = false;
    errorMessage = '';
  }

  function dismiss() {
    state = 'Dismissed';
  }

  return {
    selectRegion, pickAction, cropComplete, onChunk, onDone, onError, retry, dismiss,
    getState: () => state,
    getResultText: () => resultText,
    getImageBase64: () => imageBase64,
    getError: () => errorMessage,
    isResultDone: () => resultDone,
    getSelectedAction: () => selectedAction,
    getSelectedPrompt: () => selectedPrompt,
    getRegion: () => selectedRegion,
  };
}

// --- 13.1: Full vision request cycle with mocked response ---

describe('Integration: Full vision request cycle with mocked response', () => {
  it('transitions through complete state machine: Selecting → ActionWheel → Loading → Result', () => {
    const engine = createContextLensEngine();

    // Step 1: User selects a region
    expect(engine.getState()).toBe('Selecting');
    engine.selectRegion(100, 200, 300, 150, 2.0, '/tmp/screenshot.png');
    expect(engine.getState()).toBe('ActionWheel');

    // Step 2: User picks an action
    engine.pickAction('explain');
    expect(engine.getState()).toBe('Loading');
    expect(engine.getSelectedAction()).toBe('explain');

    // Step 3: Crop completes and base64 image is available
    const fakeBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    engine.cropComplete(fakeBase64);
    expect(engine.getImageBase64()).toBe(fakeBase64);

    // Step 4: Streamed response chunks arrive
    engine.onChunk('This screenshot shows ');
    engine.onChunk('a terminal window ');
    engine.onChunk('running htop.');
    expect(engine.getResultText()).toBe('This screenshot shows a terminal window running htop.');
    expect(engine.getState()).toBe('Loading'); // Still loading until done

    // Step 5: Response completes
    engine.onDone();
    expect(engine.getState()).toBe('Result');
    expect(engine.isResultDone()).toBe(true);
  });

  it('image is included in the OpenAI multimodal payload', () => {
    const fakeBase64 = 'AAAA1234BBBB';
    const promptText = getPromptForAction('explain');

    // Build the payload using the logic function
    const content = buildOpenAiContent(promptText, [fakeBase64]);

    // Verify structure matches OpenAI multimodal format (Req 3.1)
    expect(Array.isArray(content)).toBe(true);
    expect(content[0]).toEqual({ type: 'text', text: promptText });
    expect(content[1]).toEqual({
      type: 'image_url',
      image_url: { url: 'data:image/png;base64,AAAA1234BBBB' }
    });
  });

  it('image is included in the Gemini multimodal payload', () => {
    const fakeBase64 = 'GEMINI_IMAGE_DATA';
    const promptText = getPromptForAction('summarize');

    const parts = buildGeminiParts(promptText, [fakeBase64]);

    expect(parts[0]).toEqual({ text: promptText });
    expect(parts[1]).toEqual({ inlineData: { mimeType: 'image/png', data: 'GEMINI_IMAGE_DATA' } });
  });

  it('response streams chunk-by-chunk into resultText (Req 4.3)', () => {
    const engine = createContextLensEngine();
    engine.selectRegion(0, 0, 100, 100, 1.0, '/tmp/screen.png');
    engine.pickAction('extract_text');

    // Simulate streaming chunks as they arrive from curl
    const chunks = ['Hello', ' ', 'World', '\n', 'Line 2'];
    for (const chunk of chunks) {
      engine.onChunk(chunk);
    }

    expect(engine.getResultText()).toBe('Hello World\nLine 2');
    expect(engine.getState()).toBe('Loading');

    engine.onDone();
    expect(engine.getState()).toBe('Result');
    expect(engine.getResultText()).toBe('Hello World\nLine 2');
  });

  it('crop coordinates are scaled correctly before building payload', () => {
    const engine = createContextLensEngine();
    engine.selectRegion(50, 75, 200, 100, 2.0, '/tmp/screen.png');
    engine.pickAction('explain');

    const region = engine.getRegion();
    const coords = transformCropCoordinates(region.x, region.y, region.w, region.h, region.scale);

    expect(coords).toEqual({ x: 100, y: 150, width: 400, height: 200 });
  });

  it('uses correct prompt for each action type in the request', () => {
    const engine = createContextLensEngine();
    engine.selectRegion(0, 0, 50, 50, 1.0, '/tmp/s.png');

    // Test translate with target language
    engine.pickAction('translate');
    const translatePrompt = getPromptForAction('translate', 'Japanese');
    expect(translatePrompt).toContain('Japanese');

    // Test ask_question with custom prompt
    const customPrompt = getPromptForAction('ask_question', null, 'What library is this?');
    expect(customPrompt).toBe('What library is this?');
  });

  it('handles empty streamed response gracefully', () => {
    const engine = createContextLensEngine();
    engine.selectRegion(10, 10, 100, 100, 1.0, '/tmp/s.png');
    engine.pickAction('explain');
    engine.cropComplete('abc123');

    // No chunks arrive, just done
    engine.onDone();
    expect(engine.getState()).toBe('Result');
    expect(engine.getResultText()).toBe('');
    expect(engine.isResultDone()).toBe(true);
  });
});

// --- 13.2: Policy enforcement ---

describe('Integration: Policy enforcement', () => {
  /**
   * Models the policy gate that runs before Context Lens launches.
   * Returns { allowed: bool, message: string }
   */
  function checkPolicyGate(policyAiValue) {
    if (policyAiValue === 0) {
      return { allowed: false, message: 'AI features are disabled by policy' };
    }
    return { allowed: true, message: '' };
  }

  /**
   * Determines if a model endpoint is allowed under a given policy level.
   * Policy 2 = local-only: only allow localhost/127.0.0.1 endpoints or ollama.
   */
  function isModelAllowedByPolicy(policyAiValue, endpoint) {
    if (policyAiValue === 1) return true; // No restrictions
    if (policyAiValue === 2) {
      const ep = (endpoint || '').toLowerCase();
      if (ep.includes('localhost')) return true;
      if (ep.includes('127.0.0.1')) return true;
      if (ep.includes('0.0.0.0')) return true;
      if (ep.includes('ollama')) return true;
      return false;
    }
    return false; // policy 0 blocks everything
  }

  /**
   * Filters a list of vision models to those allowed by the current policy.
   */
  function filterModelsByPolicy(policyAiValue, models) {
    if (policyAiValue === 1) return models;
    return models.filter(m => isModelAllowedByPolicy(policyAiValue, m.endpoint));
  }

  /**
   * Determines the best vision model given policy and available models.
   */
  function getBestVisionModel(policyAiValue, availableModels) {
    const visionModels = availableModels.filter(m => isVisionCapable(m.id));
    const policyFiltered = filterModelsByPolicy(policyAiValue, visionModels);
    return policyFiltered.length > 0 ? policyFiltered[0].id : '';
  }

  it('policies.ai=0 blocks Context Lens launch entirely (Req 8.1)', () => {
    const gate = checkPolicyGate(0);
    expect(gate.allowed).toBe(false);
    expect(gate.message).toContain('disabled');
  });

  it('policies.ai=1 allows launch with no restrictions', () => {
    const gate = checkPolicyGate(1);
    expect(gate.allowed).toBe(true);
  });

  it('policies.ai=2 allows launch but restricts to local models', () => {
    const gate = checkPolicyGate(2);
    expect(gate.allowed).toBe(true);
  });

  it('policies.ai=2 filters out online vision models (Req 8.2)', () => {
    const models = [
      { id: 'gpt-4o', endpoint: 'https://api.openai.com/v1/chat/completions' },
      { id: 'gemini-pro-vision', endpoint: 'https://generativelanguage.googleapis.com/v1' },
      { id: 'llava:7b', endpoint: 'http://localhost:11434/api/chat' },
      { id: 'claude-3-sonnet', endpoint: 'https://api.anthropic.com/v1/messages' },
    ];

    const filtered = filterModelsByPolicy(2, models);

    expect(filtered).toHaveLength(1);
    expect(filtered[0].id).toBe('llava:7b');
  });

  it('policies.ai=2 allows ollama-based endpoints', () => {
    const models = [
      { id: 'llava:13b', endpoint: 'http://localhost:11434/api/chat' },
      { id: 'pixtral-12b', endpoint: 'http://127.0.0.1:11434/api/chat' },
      { id: 'bakllava:latest', endpoint: 'http://ollama.local:11434/api/chat' },
    ];

    const filtered = filterModelsByPolicy(2, models);
    expect(filtered).toHaveLength(3);
  });

  it('policies.ai=1 allows all models regardless of endpoint', () => {
    const models = [
      { id: 'gpt-4o', endpoint: 'https://api.openai.com/v1/chat/completions' },
      { id: 'llava:7b', endpoint: 'http://localhost:11434/api/chat' },
    ];

    const filtered = filterModelsByPolicy(1, models);
    expect(filtered).toHaveLength(2);
  });

  it('getBestVisionModel returns empty string when policy blocks all available models', () => {
    const models = [
      { id: 'gpt-4o', endpoint: 'https://api.openai.com/v1/chat/completions' },
      { id: 'gpt-3.5-turbo', endpoint: 'https://api.openai.com/v1/chat/completions' },
    ];

    const best = getBestVisionModel(2, models);
    expect(best).toBe('');
  });

  it('getBestVisionModel selects local vision model under policy 2', () => {
    const models = [
      { id: 'gpt-4o', endpoint: 'https://api.openai.com/v1/chat/completions' },
      { id: 'llava:7b', endpoint: 'http://localhost:11434/api/chat' },
      { id: 'mistral:latest', endpoint: 'http://localhost:11434/api/chat' },
    ];

    const best = getBestVisionModel(2, models);
    expect(best).toBe('llava:7b');
  });

  it('full flow blocked by policy.ai=0: engine never reaches ActionWheel', () => {
    const gate = checkPolicyGate(0);
    // If policy blocks, we never create the engine
    expect(gate.allowed).toBe(false);

    // Simulate what contextlens.qml does: check policy first, exit if blocked
    let engineCreated = false;
    if (gate.allowed) {
      createContextLensEngine();
      engineCreated = true;
    }
    expect(engineCreated).toBe(false);
  });
});

// --- 13.3: Error handling ---

describe('Integration: Error handling', () => {
  it('timeout shows error with retry option (Req 6.1)', () => {
    const engine = createContextLensEngine();
    engine.selectRegion(50, 50, 200, 200, 1.0, '/tmp/s.png');
    engine.pickAction('explain');
    engine.cropComplete('base64data');

    // Simulate 30s timeout firing
    engine.onError('Request timed out after 30 seconds');

    expect(engine.getState()).toBe('Error');
    expect(engine.getError()).toContain('timed out');

    // User clicks retry
    engine.retry();
    expect(engine.getState()).toBe('Loading');
    expect(engine.getResultText()).toBe('');
    expect(engine.getError()).toBe('');
  });

  it('retry resets state and allows new response to stream', () => {
    const engine = createContextLensEngine();
    engine.selectRegion(0, 0, 100, 100, 1.0, '/tmp/s.png');
    engine.pickAction('summarize');
    engine.cropComplete('img');

    // First attempt times out
    engine.onError('Request timed out after 30 seconds');
    expect(engine.getState()).toBe('Error');

    // Retry
    engine.retry();
    expect(engine.getState()).toBe('Loading');

    // Second attempt succeeds
    engine.onChunk('Summary: This is a desktop screenshot.');
    engine.onDone();
    expect(engine.getState()).toBe('Result');
    expect(engine.getResultText()).toBe('Summary: This is a desktop screenshot.');
  });

  it('no vision model shows setup guidance (Req 6.3)', () => {
    // Model the "no vision model" check that happens before sending the request
    function validateVisionModel(bestVisionModel) {
      if (!bestVisionModel || bestVisionModel === '') {
        return {
          valid: false,
          error: 'No vision-capable model configured. Please set up a vision model in the Providers panel.'
        };
      }
      return { valid: true, error: '' };
    }

    const result = validateVisionModel('');
    expect(result.valid).toBe(false);
    expect(result.error).toContain('No vision-capable model');
    expect(result.error).toContain('Providers');

    // With a valid model
    const validResult = validateVisionModel('gpt-4o');
    expect(validResult.valid).toBe(true);
  });

  it('no vision model transitions engine to Error state', () => {
    const engine = createContextLensEngine();
    engine.selectRegion(10, 10, 100, 100, 1.0, '/tmp/s.png');
    engine.pickAction('explain');

    // Simulate the vision model check failing
    engine.onError('No vision-capable model configured. Please set up a vision model in the Providers panel.');

    expect(engine.getState()).toBe('Error');
    expect(engine.getError()).toContain('No vision-capable model');
  });

  it('too-small region shows hint (Req 6.2)', () => {
    const engine = createContextLensEngine();

    // Select a tiny region: 4x4 at scale 2.0 = 8x8 pixels (< 10x10 minimum)
    engine.selectRegion(100, 100, 4, 4, 2.0, '/tmp/s.png');
    expect(engine.getState()).toBe('ActionWheel');

    // Picking action validates size
    engine.pickAction('explain');
    expect(engine.getState()).toBe('Error');
    expect(engine.getError()).toContain('too small');
  });

  it('region exactly at minimum size (10x10 after scale) is accepted', () => {
    const engine = createContextLensEngine();

    // 5x5 at scale 2.0 = 10x10 — exactly the minimum
    engine.selectRegion(50, 50, 5, 5, 2.0, '/tmp/s.png');
    engine.pickAction('explain');
    expect(engine.getState()).toBe('Loading');
  });

  it('region just below minimum (9x10 after scale) is rejected', () => {
    const engine = createContextLensEngine();

    // 9x10 at scale 1.0 = 9x10 — width is too small
    engine.selectRegion(50, 50, 9, 10, 1.0, '/tmp/s.png');
    engine.pickAction('explain');
    expect(engine.getState()).toBe('Error');
    expect(engine.getError()).toContain('too small');
  });

  it('region just below minimum (10x9 after scale) is rejected', () => {
    const engine = createContextLensEngine();

    // 10x9 at scale 1.0 = 10x9 — height is too small
    engine.selectRegion(50, 50, 10, 9, 1.0, '/tmp/s.png');
    engine.pickAction('explain');
    expect(engine.getState()).toBe('Error');
    expect(engine.getError()).toContain('too small');
  });

  it('network error transitions to Error with message', () => {
    const engine = createContextLensEngine();
    engine.selectRegion(0, 0, 200, 200, 1.0, '/tmp/s.png');
    engine.pickAction('explain');
    engine.cropComplete('imagedata');

    engine.onError('Network error: connection refused');
    expect(engine.getState()).toBe('Error');
    expect(engine.getError()).toContain('Network error');
  });

  it('error after partial streaming preserves no partial text on retry', () => {
    const engine = createContextLensEngine();
    engine.selectRegion(0, 0, 200, 200, 1.0, '/tmp/s.png');
    engine.pickAction('explain');
    engine.cropComplete('img');

    // Partial streaming then error
    engine.onChunk('This is a partial...');
    expect(engine.getResultText()).toBe('This is a partial...');

    engine.onError('Connection reset');
    expect(engine.getState()).toBe('Error');

    // Retry clears the partial text
    engine.retry();
    expect(engine.getResultText()).toBe('');
    expect(engine.getState()).toBe('Loading');
  });
});
