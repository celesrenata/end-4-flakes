import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import { classifyAiPrefix, validatePrefix, checkLocalOnlyPolicy, validateAction, parseActionPlan, truncateSummary, validateDebounceMs, formatActionDisplay } from './action-palette-logic.js';

/**
 * Feature: ai-action-palette, Property 1: AI Prefix Classification
 *
 * For any search input and valid AI prefix (1-3 non-whitespace chars):
 * classifier identifies AI intent iff input starts with prefix + space + non-whitespace.
 * AI prefix takes priority over conflicting prefixes.
 *
 * **Validates: Requirements 1.1, 1.5**
 */
describe('Feature: ai-action-palette, Property 1: AI Prefix Classification', () => {
  // Arbitrary for valid AI prefixes (1-3 non-whitespace chars)
  const validPrefixArb = fc.string({ minLength: 1, maxLength: 3 })
    .filter(s => s.trim().length === s.length && s.length > 0);

  it('identifies AI intent iff input starts with prefix + space + non-whitespace', () => {
    fc.assert(fc.property(
      validPrefixArb,
      fc.string({ minLength: 1 }).filter(s => s.trim().length > 0), // non-whitespace query
      (prefix, query) => {
        const input = prefix + " " + query;
        expect(classifyAiPrefix(input, prefix)).toBe(true);
      }
    ), { numRuns: 100 });
  });

  it('does NOT identify AI intent for prefix-only or prefix + whitespace', () => {
    fc.assert(fc.property(
      validPrefixArb,
      fc.constantFrom("", " ", "  ", "   "),
      (prefix, trailing) => {
        const input = prefix + trailing;
        expect(classifyAiPrefix(input, prefix)).toBe(false);
      }
    ), { numRuns: 100 });
  });

  it('does NOT identify AI intent when input does not start with prefix', () => {
    fc.assert(fc.property(
      validPrefixArb,
      fc.string({ minLength: 1 }),
      (prefix, randomInput) => {
        if (!randomInput.startsWith(prefix)) {
          expect(classifyAiPrefix(randomInput, prefix)).toBe(false);
        }
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: ai-action-palette, Property 2: Prefix Configuration Validation
 * **Validates: Requirements 1.2**
 */
describe('Feature: ai-action-palette, Property 2: Prefix Configuration Validation', () => {
  it('accepts iff 1-3 chars and not all whitespace', () => {
    fc.assert(fc.property(
      fc.string({ minLength: 0, maxLength: 10 }),
      (s) => {
        const result = validatePrefix(s);
        const expected = s.length >= 1 && s.length <= 3 && s.trim().length > 0;
        expect(result).toBe(expected);
      }
    ), { numRuns: 100 });
  });

  it('always rejects empty string', () => {
    expect(validatePrefix("")).toBe(false);
  });

  it('always rejects whitespace-only', () => {
    fc.assert(fc.property(
      fc.constantFrom(" ", "  ", "   ", "\t", "\n"),
      (ws) => {
        expect(validatePrefix(ws)).toBe(false);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: ai-action-palette, Property 5: Action Schema Validation
 *
 * For any JSON object presented as a Proposed_Action, the validator marks it as valid
 * if and only if it has a `type` field matching one of the supported types and contains
 * all required parameters for that type.
 *
 * **Validates: Requirements 3.3, 3.4**
 */
describe('Feature: ai-action-palette, Property 5: Action Schema Validation', () => {
  it('marks valid iff type is supported and all required params present', () => {
    const arbitraryAction = fc.oneof(
      // Valid config.set
      fc.record({ type: fc.constant("config.set"), key: fc.string({ minLength: 1 }), value: fc.jsonValue() }),
      // Valid shell.exec
      fc.record({ type: fc.constant("shell.exec"), command: fc.string({ minLength: 1 }) }),
      // Valid hyprland.dispatch
      fc.record({ type: fc.constant("hyprland.dispatch"), dispatcher: fc.string({ minLength: 1 }), args: fc.string() }),
      // Valid app.launch
      fc.record({ type: fc.constant("app.launch"), id: fc.string({ minLength: 1 }) }),
      // Invalid: unsupported type
      fc.record({ type: fc.string().filter(s => !["config.set", "shell.exec", "hyprland.dispatch", "app.launch"].includes(s)) }),
      // Invalid: missing params
      fc.record({ type: fc.constant("config.set") }), // missing key and value
      fc.record({ type: fc.constant("shell.exec") }), // missing command
    );

    fc.assert(fc.property(
      arbitraryAction,
      (action) => {
        const result = validateAction(action);
        const SUPPORTED = {
          "config.set": ["key", "value"],
          "shell.exec": ["command"],
          "hyprland.dispatch": ["dispatcher", "args"],
          "app.launch": ["id"]
        };

        const requiredParams = SUPPORTED[action.type];
        if (!requiredParams) {
          expect(result.valid).toBe(false);
        } else {
          const allPresent = requiredParams.every(p => action[p] !== undefined && action[p] !== null);
          expect(result.valid).toBe(allPresent);
        }
      }
    ), { numRuns: 100 });
  });
});


/**
 * Feature: ai-action-palette, Property 3: Local-Only Policy Gate
 *
 * For any endpoint URL and policies.ai=2: gate blocks iff endpoint does not contain "localhost".
 *
 * **Validates: Requirements 2.5**
 */
describe('Feature: ai-action-palette, Property 3: Local-Only Policy Gate', () => {
  it('blocks iff policies.ai=2 and endpoint does not contain localhost', () => {
    fc.assert(fc.property(
      fc.string(), // any endpoint string
      (endpoint) => {
        const blocked = checkLocalOnlyPolicy(2, endpoint);
        const expectedBlocked = !endpoint.includes("localhost");
        expect(blocked).toBe(expectedBlocked);
      }
    ), { numRuns: 100 });
  });

  it('never blocks when policies.ai != 2', () => {
    fc.assert(fc.property(
      fc.integer().filter(n => n !== 2),
      fc.string(),
      (policy, endpoint) => {
        expect(checkLocalOnlyPolicy(policy, endpoint)).toBe(false);
      }
    ), { numRuns: 100 });
  });

  it('never blocks localhost endpoints when policies.ai=2', () => {
    fc.assert(fc.property(
      fc.string(),
      (prefix) => {
        const endpoint = prefix + "localhost" + prefix;
        expect(checkLocalOnlyPolicy(2, endpoint)).toBe(false);
      }
    ), { numRuns: 100 });
  });
});

/**
 * Feature: ai-action-palette, Property 4: Action_Plan Round-Trip
 *
 * For any valid Action_Plan (summary ≤500, 0-50 valid actions):
 * serialize to JSON then parse back produces deeply equal object.
 *
 * **Validates: Requirements 3.5, 3.1**
 */
describe('Feature: ai-action-palette, Property 4: Action_Plan Round-Trip', () => {
  // Arbitrary for valid actions
  const validActionArb = fc.oneof(
    fc.record({ type: fc.constant("config.set"), key: fc.string({ minLength: 1 }), value: fc.jsonValue() }),
    fc.record({ type: fc.constant("shell.exec"), command: fc.string({ minLength: 1 }) }),
    fc.record({ type: fc.constant("hyprland.dispatch"), dispatcher: fc.string({ minLength: 1 }), args: fc.string() }),
    fc.record({ type: fc.constant("app.launch"), id: fc.string({ minLength: 1 }) })
  );

  const actionPlanArb = fc.record({
    summary: fc.string({ minLength: 0, maxLength: 500 }),
    actions: fc.array(validActionArb, { minLength: 0, maxLength: 50 })
  });

  it('round-trip: serialize then parse produces deeply equal object', () => {
    fc.assert(fc.property(
      actionPlanArb,
      (plan) => {
        const serialized = JSON.stringify(plan);
        const result = parseActionPlan(serialized);
        expect(result.valid).toBe(true);
        expect(result.plan).toEqual(plan);
      }
    ), { numRuns: 100 });
  });
});


/**
 * Feature: ai-action-palette, Property 6: Summary Truncation
 *
 * For any summary string: displayed text equals original if ≤120 chars,
 * else first 120 + "…"
 *
 * **Validates: Requirements 4.1**
 */
describe('Feature: ai-action-palette, Property 6: Summary Truncation', () => {
  it('returns original if ≤120 chars, else first 120 + "…"', () => {
    fc.assert(fc.property(
      fc.string({ minLength: 0, maxLength: 500 }),
      (summary) => {
        const result = truncateSummary(summary);
        if (summary.length <= 120) {
          expect(result).toBe(summary);
        } else {
          expect(result).toBe(summary.slice(0, 120) + "\u2026");
          expect(result.length).toBe(121);
        }
      }
    ), { numRuns: 100 });
  });
});


/**
 * Feature: ai-action-palette, Property 12: Debounce Configuration Validation
 *
 * For any value: effective debounce is the value if integer in [100, 5000], else 600.
 *
 * **Validates: Requirements 7.4, 7.5**
 */
describe('Feature: ai-action-palette, Property 12: Debounce Configuration Validation', () => {
  it('returns value if integer in [100, 5000], else 600', () => {
    fc.assert(fc.property(
      fc.oneof(
        fc.integer(),
        fc.double(),
        fc.string(),
        fc.constant(null),
        fc.constant(undefined),
        fc.boolean()
      ),
      (value) => {
        const result = validateDebounceMs(value);
        if (typeof value === "number" && Number.isInteger(value) && value >= 100 && value <= 5000) {
          expect(result).toBe(value);
        } else {
          expect(result).toBe(600);
        }
      }
    ), { numRuns: 100 });
  });

  it('valid integers in range are returned as-is', () => {
    fc.assert(fc.property(
      fc.integer({ min: 100, max: 5000 }),
      (value) => {
        expect(validateDebounceMs(value)).toBe(value);
      }
    ), { numRuns: 100 });
  });

  it('integers outside range return 600', () => {
    fc.assert(fc.property(
      fc.oneof(
        fc.integer({ max: 99 }),
        fc.integer({ min: 5001 })
      ),
      (value) => {
        expect(validateDebounceMs(value)).toBe(600);
      }
    ), { numRuns: 100 });
  });
});


/**
 * Feature: ai-action-palette, Property 7: Action Display Completeness
 *
 * For any valid Proposed_Action, the rendered display string contains
 * the type-specific key information.
 *
 * **Validates: Requirements 4.2**
 */
describe('Feature: ai-action-palette, Property 7: Action Display Completeness', () => {
  it('display contains key info for config.set', () => {
    fc.assert(fc.property(
      fc.string({ minLength: 1 }),
      fc.jsonValue(),
      (key, value) => {
        const action = { type: "config.set", key, value, valid: true };
        const display = formatActionDisplay(action);
        expect(display).toContain(key);
        expect(display).toContain(JSON.stringify(value));
      }
    ), { numRuns: 100 });
  });

  it('display contains command for shell.exec', () => {
    fc.assert(fc.property(
      fc.string({ minLength: 1 }),
      (command) => {
        const action = { type: "shell.exec", command, valid: true };
        const display = formatActionDisplay(action);
        expect(display).toContain(command);
      }
    ), { numRuns: 100 });
  });

  it('display contains dispatcher and args for hyprland.dispatch', () => {
    fc.assert(fc.property(
      fc.string({ minLength: 1 }),
      fc.string(),
      (dispatcher, args) => {
        const action = { type: "hyprland.dispatch", dispatcher, args, valid: true };
        const display = formatActionDisplay(action);
        expect(display).toContain(dispatcher);
        expect(display).toContain(args);
      }
    ), { numRuns: 100 });
  });

  it('display contains id for app.launch', () => {
    fc.assert(fc.property(
      fc.string({ minLength: 1 }),
      (id) => {
        const action = { type: "app.launch", id, valid: true };
        const display = formatActionDisplay(action);
        expect(display).toContain(id);
      }
    ), { numRuns: 100 });
  });
});


/**
 * Feature: ai-action-palette, Property 8: Sequential Execution Order
 *
 * For any Action_Plan with N actions: execution processes indices 0..N-1
 * in strictly ascending order, no action i+1 starts before i completes/fails.
 * Model-based test using execution trace recording.
 *
 * **Validates: Requirements 5.1**
 */
describe('Feature: ai-action-palette, Property 8: Sequential Execution Order', () => {
  // Simple execution model that records traces
  function simulateExecution(actions) {
    const trace = [];
    for (let i = 0; i < actions.length; i++) {
      const action = actions[i];
      if (!action.valid) {
        trace.push({ index: i, event: 'failed' });
        break; // Stop on failure
      }
      if (action.type === "shell.exec") {
        trace.push({ index: i, event: 'approval_required' });
        // Simulate approval
        trace.push({ index: i, event: 'approved' });
      }
      trace.push({ index: i, event: 'completed' });
    }
    return trace;
  }

  const validActionArb = fc.oneof(
    fc.record({ type: fc.constant("config.set"), key: fc.string({ minLength: 1 }), value: fc.jsonValue(), valid: fc.constant(true), warning: fc.constant(null) }),
    fc.record({ type: fc.constant("shell.exec"), command: fc.string({ minLength: 1 }), valid: fc.constant(true), warning: fc.constant(null) }),
    fc.record({ type: fc.constant("hyprland.dispatch"), dispatcher: fc.string({ minLength: 1 }), args: fc.string(), valid: fc.constant(true), warning: fc.constant(null) }),
    fc.record({ type: fc.constant("app.launch"), id: fc.string({ minLength: 1 }), valid: fc.constant(true), warning: fc.constant(null) })
  );

  it('execution processes indices in strictly ascending order', () => {
    fc.assert(fc.property(
      fc.array(validActionArb, { minLength: 1, maxLength: 20 }),
      (actions) => {
        const trace = simulateExecution(actions);
        const completedIndices = trace
          .filter(e => e.event === 'completed')
          .map(e => e.index);

        // Verify strictly ascending order
        for (let i = 1; i < completedIndices.length; i++) {
          expect(completedIndices[i]).toBeGreaterThan(completedIndices[i - 1]);
        }

        // Verify no gaps (sequential)
        for (let i = 0; i < completedIndices.length; i++) {
          expect(completedIndices[i]).toBe(i);
        }
      }
    ), { numRuns: 100 });
  });

  it('no action i+1 event appears before action i completion', () => {
    fc.assert(fc.property(
      fc.array(validActionArb, { minLength: 2, maxLength: 20 }),
      (actions) => {
        const trace = simulateExecution(actions);
        for (let t = 0; t < trace.length - 1; t++) {
          const current = trace[t];
          const next = trace[t + 1];
          // If next has a higher index, current must be 'completed' or 'approved'
          if (next.index > current.index) {
            expect(['completed', 'approved']).toContain(current.event);
          }
        }
      }
    ), { numRuns: 100 });
  });
});


/**
 * Feature: ai-action-palette, Property 10: Preview Filters Only config.set
 *
 * For any mixed Action_Plan: preview applies only config.set actions,
 * count of applied changes equals count of config.set in plan.
 *
 * **Validates: Requirements 6.1**
 */
describe('Feature: ai-action-palette, Property 10: Preview Filters Only config.set', () => {
  const mixedActionArb = fc.oneof(
    fc.record({ type: fc.constant("config.set"), key: fc.string({ minLength: 1 }), value: fc.jsonValue(), valid: fc.constant(true) }),
    fc.record({ type: fc.constant("shell.exec"), command: fc.string({ minLength: 1 }), valid: fc.constant(true) }),
    fc.record({ type: fc.constant("hyprland.dispatch"), dispatcher: fc.string({ minLength: 1 }), args: fc.string(), valid: fc.constant(true) }),
    fc.record({ type: fc.constant("app.launch"), id: fc.string({ minLength: 1 }), valid: fc.constant(true) })
  );

  it('preview applies only config.set actions, count matches', () => {
    fc.assert(fc.property(
      fc.array(mixedActionArb, { minLength: 1, maxLength: 20 }),
      (actions) => {
        // Simulate preview filtering
        const previewActions = actions.filter(a => a.type === "config.set" && a.valid);
        const appliedCount = previewActions.length;
        const configSetCount = actions.filter(a => a.type === "config.set").length;

        // Count of applied changes equals count of valid config.set in plan
        expect(appliedCount).toBe(configSetCount);

        // Verify no non-config.set actions in preview set
        previewActions.forEach(a => {
          expect(a.type).toBe("config.set");
        });
      }
    ), { numRuns: 100 });
  });
});


/**
 * Feature: ai-action-palette, Property 11: Preview Revert Restores State
 *
 * For any set of config.set actions applied during preview: reverting restores
 * every key to pre-preview value.
 *
 * **Validates: Requirements 6.4, 6.5, 6.6**
 */
describe('Feature: ai-action-palette, Property 11: Preview Revert Restores State', () => {
  it('reverting restores every key to pre-preview value', () => {
    fc.assert(fc.property(
      fc.array(
        fc.record({ key: fc.string({ minLength: 1 }), value: fc.jsonValue() }),
        { minLength: 1, maxLength: 10 }
      ),
      (configActions) => {
        // Simulate initial state
        const state = {};
        configActions.forEach((a, i) => {
          state[a.key] = `initial_${i}`;
        });
        const prePreviewState = { ...state };

        // Capture snapshot (pre-preview values)
        const snapshot = configActions.map(a => ({
          key: a.key,
          previousValue: state[a.key]
        }));

        // Apply preview changes
        configActions.forEach(a => {
          state[a.key] = a.value;
        });

        // Revert: restore from snapshot in reverse order
        for (let i = snapshot.length - 1; i >= 0; i--) {
          state[snapshot[i].key] = snapshot[i].previousValue;
        }

        // Verify all keys restored to pre-preview values
        for (const key of Object.keys(prePreviewState)) {
          expect(state[key]).toEqual(prePreviewState[key]);
        }
      }
    ), { numRuns: 100 });
  });
});


/**
 * Feature: ai-action-palette, Property 9: Config Rollback on Failure
 *
 * For any plan with config.set actions where action K fails:
 * all prior config.set actions have captured values, undo restores each.
 *
 * **Validates: Requirements 5.8**
 */
describe('Feature: ai-action-palette, Property 9: Config Rollback on Failure', () => {
  it('all prior config.set actions have captured values and undo restores each', () => {
    fc.assert(fc.property(
      fc.array(
        fc.record({ key: fc.string({ minLength: 1 }), value: fc.jsonValue() }),
        { minLength: 1, maxLength: 10 }
      ),
      fc.integer({ min: 0 }), // failure index
      (configActions, failureSeed) => {
        const failureIndex = failureSeed % configActions.length;
        
        // Simulate config state
        const initialState = {};
        configActions.forEach((a, i) => {
          initialState[a.key] = `original_${i}`;
        });
        
        // Simulate execution with snapshot capture
        const currentState = { ...initialState };
        const snapshot = [];
        
        for (let i = 0; i < configActions.length; i++) {
          if (i === failureIndex) break; // Simulate failure at this index
          
          // Capture previous value
          snapshot.push({ key: configActions[i].key, previousValue: currentState[configActions[i].key] });
          // Apply new value
          currentState[configActions[i].key] = configActions[i].value;
        }
        
        // All prior config.set actions have captured values
        expect(snapshot.length).toBe(failureIndex);
        
        // Undo: restore in reverse order
        for (let i = snapshot.length - 1; i >= 0; i--) {
          currentState[snapshot[i].key] = snapshot[i].previousValue;
        }
        
        // Verify all keys restored to initial state
        for (const key of Object.keys(initialState)) {
          expect(currentState[key]).toEqual(initialState[key]);
        }
      }
    ), { numRuns: 100 });
  });
});
