import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import {
  isVisionCapable,
  buildOpenAiContent,
  buildGeminiParts,
  transformCropCoordinates,
  getPromptForAction,
} from './context-lens-logic.js';

/**
 * Feature: context-lens, Property 1: Vision Model Detection Patterns
 *
 * For known vision model IDs: isVisionCapable returns true.
 * For known non-vision model IDs: returns false.
 *
 * **Validates: Requirements 3.5**
 */
describe('Feature: context-lens, Property 1: Vision Model Detection Patterns', () => {
  const knownVisionModels = fc.constantFrom(
    "gpt-4o", "gpt-4o-mini", "gpt-4o-2024-05-13",
    "gpt-4-turbo", "gpt-4-turbo-preview",
    "gpt-4.1", "gpt-4.1-mini",
    "gemini-pro", "gemini-1.5-pro", "gemini-2.0-flash",
    "claude-3-opus", "claude-3-sonnet", "claude-3-haiku",
    "claude-4-opus", "claude-4-sonnet",
    "llava", "llava:latest", "llava-v1.6",
    "pixtral-12b", "pixtral-large",
    "some-vision-model", "custom-vision-v2"
  );

  const knownNonVisionModels = fc.constantFrom(
    "gpt-3.5-turbo", "gpt-4-0613", "gpt-4-32k",
    "claude-2", "claude-2.1", "claude-instant",
    "mistral-7b", "mixtral-8x7b", "codellama",
    "deepseek-coder", "phi-3", "qwen-72b",
    "llama-3-70b", "command-r-plus"
  );

  it('returns true for all known vision-capable model IDs', () => {
    fc.assert(fc.property(
      knownVisionModels,
      (modelId) => {
        expect(isVisionCapable(modelId)).toBe(true);
      }
    ), { numRuns: 100 });
  });

  it('returns false for all known non-vision model IDs', () => {
    fc.assert(fc.property(
      knownNonVisionModels,
      (modelId) => {
        expect(isVisionCapable(modelId)).toBe(false);
      }
    ), { numRuns: 100 });
  });

  it('is case-insensitive for model detection', () => {
    fc.assert(fc.property(
      knownVisionModels,
      (modelId) => {
        expect(isVisionCapable(modelId.toUpperCase())).toBe(true);
      }
    ), { numRuns: 100 });
  });

  it('handles null/undefined/empty gracefully (returns false)', () => {
    expect(isVisionCapable(null)).toBe(false);
    expect(isVisionCapable(undefined)).toBe(false);
    expect(isVisionCapable("")).toBe(false);
  });

  it('random strings without vision patterns return false', () => {
    fc.assert(fc.property(
      fc.string({ minLength: 1, maxLength: 30 }).filter(s => {
        const lower = s.toLowerCase();
        return !lower.startsWith("gpt-4o") &&
               !lower.startsWith("gpt-4-turbo") &&
               !lower.startsWith("gpt-4.1") &&
               !lower.startsWith("gemini-") &&
               !lower.startsWith("claude-3-") &&
               !lower.startsWith("claude-4-") &&
               !lower.startsWith("llava") &&
               !lower.startsWith("pixtral") &&
               !lower.includes("vision");
      }),
      (randomModel) => {
        expect(isVisionCapable(randomModel)).toBe(false);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: context-lens, Property 2: Multimodal Payload Construction (OpenAI format)
 *
 * For any text + base64 image: payload has correct structure with content array.
 * For empty images: result is the plain text string.
 *
 * **Validates: Requirements 3.2**
 */
describe('Feature: context-lens, Property 2: Multimodal Payload Construction (OpenAI format)', () => {
  const base64Arb = fc.base64String({ minLength: 4, maxLength: 100 });
  const textArb = fc.string({ minLength: 0, maxLength: 200 });

  it('with images: returns array starting with text part, followed by image_url parts', () => {
    fc.assert(fc.property(
      textArb,
      fc.array(base64Arb, { minLength: 1, maxLength: 5 }),
      (text, images) => {
        const result = buildOpenAiContent(text, images);
        // Result is an array
        expect(Array.isArray(result)).toBe(true);
        // First element is the text part
        expect(result[0]).toEqual({ type: "text", text: text });
        // Length is 1 (text) + number of images
        expect(result.length).toBe(1 + images.length);
        // Each subsequent element is an image_url part
        for (let i = 0; i < images.length; i++) {
          expect(result[i + 1].type).toBe("image_url");
          expect(result[i + 1].image_url.url).toBe("data:image/png;base64," + images[i]);
        }
      }
    ), { numRuns: 100 });
  });

  it('without images: returns plain text string', () => {
    fc.assert(fc.property(
      textArb,
      (text) => {
        expect(buildOpenAiContent(text, [])).toBe(text);
        expect(buildOpenAiContent(text, null)).toBe(text);
        expect(buildOpenAiContent(text, undefined)).toBe(text);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: context-lens, Property 3: Multimodal Payload Construction (Gemini format)
 *
 * For any text + base64 image: parts array has text part first, then inlineData parts.
 * Verifies mimeType is "image/png".
 *
 * **Validates: Requirements 3.3**
 */
describe('Feature: context-lens, Property 3: Multimodal Payload Construction (Gemini format)', () => {
  const base64Arb = fc.base64String({ minLength: 4, maxLength: 100 });
  const textArb = fc.string({ minLength: 0, maxLength: 200 });

  it('with images: parts has text first, then inlineData parts with image/png mimeType', () => {
    fc.assert(fc.property(
      textArb,
      fc.array(base64Arb, { minLength: 1, maxLength: 5 }),
      (text, images) => {
        const result = buildGeminiParts(text, images);
        // Result is an array
        expect(Array.isArray(result)).toBe(true);
        // First element is the text part
        expect(result[0]).toEqual({ text: text });
        // Length is 1 (text) + number of images
        expect(result.length).toBe(1 + images.length);
        // Each subsequent element is an inlineData part
        for (let i = 0; i < images.length; i++) {
          expect(result[i + 1].inlineData).toBeDefined();
          expect(result[i + 1].inlineData.mimeType).toBe("image/png");
          expect(result[i + 1].inlineData.data).toBe(images[i]);
        }
      }
    ), { numRuns: 100 });
  });

  it('without images: parts has only text element', () => {
    fc.assert(fc.property(
      textArb,
      (text) => {
        const result = buildGeminiParts(text, []);
        expect(result).toEqual([{ text: text }]);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: context-lens, Property 4: Region Crop Coordinate Transformation
 *
 * For any monitor scale and region coordinates: transformed coordinates
 * equal Math.round(original * scale). Scale range: 1.0 to 3.0.
 *
 * **Validates: Requirements 9.1**
 */
describe('Feature: context-lens, Property 4: Region Crop Coordinate Transformation', () => {
  const coordArb = fc.integer({ min: 0, max: 7680 }); // up to 8K resolution
  const scaleArb = fc.double({ min: 1.0, max: 3.0, noNaN: true });

  it('transformed coordinates equal Math.round(original * scale)', () => {
    fc.assert(fc.property(
      coordArb, coordArb, coordArb, coordArb, scaleArb,
      (x, y, w, h, scale) => {
        const result = transformCropCoordinates(x, y, w, h, scale);
        expect(result.x).toBe(Math.round(x * scale));
        expect(result.y).toBe(Math.round(y * scale));
        expect(result.width).toBe(Math.round(w * scale));
        expect(result.height).toBe(Math.round(h * scale));
      }
    ), { numRuns: 100 });
  });

  it('scale of 1.0 preserves original coordinates', () => {
    fc.assert(fc.property(
      coordArb, coordArb, coordArb, coordArb,
      (x, y, w, h) => {
        const result = transformCropCoordinates(x, y, w, h, 1.0);
        expect(result.x).toBe(x);
        expect(result.y).toBe(y);
        expect(result.width).toBe(w);
        expect(result.height).toBe(h);
      }
    ), { numRuns: 100 });
  });

  it('scale of 2.0 doubles all coordinates', () => {
    fc.assert(fc.property(
      coordArb, coordArb, coordArb, coordArb,
      (x, y, w, h) => {
        const result = transformCropCoordinates(x, y, w, h, 2.0);
        expect(result.x).toBe(x * 2);
        expect(result.y).toBe(y * 2);
        expect(result.width).toBe(w * 2);
        expect(result.height).toBe(h * 2);
      }
    ), { numRuns: 100 });
  });

  it('all transformed values are non-negative integers', () => {
    fc.assert(fc.property(
      coordArb, coordArb, coordArb, coordArb, scaleArb,
      (x, y, w, h, scale) => {
        const result = transformCropCoordinates(x, y, w, h, scale);
        expect(Number.isInteger(result.x)).toBe(true);
        expect(Number.isInteger(result.y)).toBe(true);
        expect(Number.isInteger(result.width)).toBe(true);
        expect(Number.isInteger(result.height)).toBe(true);
        expect(result.x).toBeGreaterThanOrEqual(0);
        expect(result.y).toBeGreaterThanOrEqual(0);
        expect(result.width).toBeGreaterThanOrEqual(0);
        expect(result.height).toBeGreaterThanOrEqual(0);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: context-lens, Property 5: Action Prompt Construction
 *
 * For each action ID: prompt template is non-empty and contains action-relevant keywords.
 * For "translate": contains the target language.
 * For "ask_question": returns the custom prompt.
 *
 * **Validates: Requirements 2.2**
 */
describe('Feature: context-lens, Property 5: Action Prompt Construction', () => {
  const knownActions = ["explain", "extract_text", "translate", "summarize",
                        "explain_error", "generate_command", "ask_question", "identify_ui"];

  const actionKeywords = {
    explain: ["describe", "screenshot"],
    extract_text: ["extract", "text"],
    translate: ["translate"],
    summarize: ["summarize"],
    explain_error: ["error", "fix"],
    generate_command: ["command", "screenshot"],
    ask_question: [], // special case: uses custom prompt
    identify_ui: ["identify", "ui"],
  };

  it('every known action ID produces a non-empty prompt', () => {
    fc.assert(fc.property(
      fc.constantFrom(...knownActions.filter(a => a !== "ask_question")),
      (actionId) => {
        const prompt = getPromptForAction(actionId, "English", "");
        expect(prompt.length).toBeGreaterThan(0);
      }
    ), { numRuns: 100 });
  });

  it('each action prompt contains action-relevant keywords', () => {
    fc.assert(fc.property(
      fc.constantFrom(...knownActions.filter(a => a !== "ask_question")),
      (actionId) => {
        const prompt = getPromptForAction(actionId, "English", "").toLowerCase();
        const keywords = actionKeywords[actionId];
        const hasAtLeastOne = keywords.some(kw => prompt.includes(kw));
        expect(hasAtLeastOne).toBe(true);
      }
    ), { numRuns: 100 });
  });

  it('translate action contains the target language', () => {
    fc.assert(fc.property(
      fc.constantFrom("English", "Spanish", "French", "Japanese", "German", "Korean"),
      (lang) => {
        const prompt = getPromptForAction("translate", lang, "");
        expect(prompt).toContain(lang);
      }
    ), { numRuns: 100 });
  });

  it('ask_question returns the custom prompt', () => {
    fc.assert(fc.property(
      fc.string({ minLength: 1, maxLength: 200 }),
      (customPrompt) => {
        const result = getPromptForAction("ask_question", "English", customPrompt);
        expect(result).toBe(customPrompt);
      }
    ), { numRuns: 100 });
  });

  it('ask_question with empty custom prompt returns empty string', () => {
    expect(getPromptForAction("ask_question", "English", "")).toBe("");
    expect(getPromptForAction("ask_question", "English", null)).toBe("");
    expect(getPromptForAction("ask_question", "English", undefined)).toBe("");
  });

  it('unknown action IDs produce a non-empty fallback prompt', () => {
    fc.assert(fc.property(
      fc.string({ minLength: 1, maxLength: 30 }).filter(s =>
        !knownActions.includes(s)
      ),
      (unknownAction) => {
        const prompt = getPromptForAction(unknownAction, "English", "");
        expect(prompt.length).toBeGreaterThan(0);
      }
    ), { numRuns: 100 });
  });
});
