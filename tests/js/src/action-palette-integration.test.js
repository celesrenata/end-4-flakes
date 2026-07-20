/**
 * Integration tests for AI Action Palette — full request cycle with mocked LLM response.
 * Tests the pure logic functions together end-to-end (parsing → validation → display).
 *
 * Validates: Requirements 2.1, 3.1
 */
import { describe, it, expect } from 'vitest';
import { parseActionPlan, validateAction, truncateSummary, formatActionDisplay, validateDebounceMs, SUPPORTED_TYPES } from './action-palette-logic.js';

describe('Integration: Full request cycle with mocked LLM response', () => {
  // Simulate the Gemini API envelope response format
  const geminiEnvelopeResponse = JSON.stringify({
    candidates: [{
      content: {
        parts: [{
          text: JSON.stringify({
            summary: "Enable dark mode with transparency and reduce gaps",
            actions: [
              { type: "config.set", key: "appearance.transparency", value: true },
              { type: "config.set", key: "appearance.schemeIndex", value: 1 },
              { type: "shell.exec", command: "hyprctl keyword general:gaps_out 5" },
              { type: "hyprland.dispatch", dispatcher: "workspace", args: "3" },
              { type: "app.launch", id: "org.kde.dolphin" }
            ]
          })
        }]
      }
    }]
  });

  // Simulate OpenAI API envelope response format
  const openaiEnvelopeResponse = JSON.stringify({
    choices: [{
      message: {
        content: JSON.stringify({
          summary: "Switch to workspace 2 and open terminal",
          actions: [
            { type: "hyprland.dispatch", dispatcher: "workspace", args: "2" },
            { type: "app.launch", id: "org.gnome.Terminal" }
          ]
        })
      }
    }]
  });

  it('parses valid Gemini API response envelope', () => {
    // Step 1: Extract content from Gemini envelope
    const apiResp = JSON.parse(geminiEnvelopeResponse);
    const contentText = apiResp.candidates[0].content.parts[0].text;

    // Step 2: Parse the action plan
    const result = parseActionPlan(contentText);
    expect(result.valid).toBe(true);
    expect(result.plan.summary).toBe("Enable dark mode with transparency and reduce gaps");
    expect(result.plan.actions).toHaveLength(5);
  });

  it('parses valid OpenAI API response envelope', () => {
    const apiResp = JSON.parse(openaiEnvelopeResponse);
    const contentText = apiResp.choices[0].message.content;

    const result = parseActionPlan(contentText);
    expect(result.valid).toBe(true);
    expect(result.plan.summary).toBe("Switch to workspace 2 and open terminal");
    expect(result.plan.actions).toHaveLength(2);
  });

  it('validates each action in the parsed plan', () => {
    const apiResp = JSON.parse(geminiEnvelopeResponse);
    const contentText = apiResp.candidates[0].content.parts[0].text;
    const result = parseActionPlan(contentText);

    const validatedActions = result.plan.actions.map(a => validateAction(a));

    // All should be valid
    validatedActions.forEach(a => {
      expect(a.valid).toBe(true);
      expect(a.warning).toBeNull();
    });
  });

  it('produces display strings for validated actions', () => {
    const apiResp = JSON.parse(geminiEnvelopeResponse);
    const contentText = apiResp.candidates[0].content.parts[0].text;
    const result = parseActionPlan(contentText);

    const validatedActions = result.plan.actions.map(a => validateAction(a));

    // config.set action
    const display0 = formatActionDisplay(validatedActions[0]);
    expect(display0).toContain("appearance.transparency");
    expect(display0).toContain("true");

    // shell.exec action
    const display2 = formatActionDisplay(validatedActions[2]);
    expect(display2).toContain("hyprctl keyword general:gaps_out 5");

    // hyprland.dispatch action
    const display3 = formatActionDisplay(validatedActions[3]);
    expect(display3).toContain("workspace");
    expect(display3).toContain("3");

    // app.launch action
    const display4 = formatActionDisplay(validatedActions[4]);
    expect(display4).toContain("org.kde.dolphin");
  });

  it('truncates long summary for display', () => {
    const longSummary = "A".repeat(200);
    const plan = { summary: longSummary, actions: [] };
    const serialized = JSON.stringify(plan);
    const result = parseActionPlan(serialized);

    const displaySummary = truncateSummary(result.plan.summary);
    expect(displaySummary.length).toBe(121);
    expect(displaySummary.endsWith("\u2026")).toBe(true);
  });

  it('handles malformed JSON response', () => {
    const result = parseActionPlan("not valid json {{{");
    expect(result.valid).toBe(false);
    expect(result.error).toBe("Malformed JSON");
  });

  it('handles response missing summary', () => {
    const noSummary = JSON.stringify({ actions: [] });
    const result = parseActionPlan(noSummary);
    expect(result.valid).toBe(false);
    expect(result.error).toContain("summary");
  });

  it('handles response with invalid actions field', () => {
    const noActions = JSON.stringify({ summary: "Test", actions: "not an array" });
    const result = parseActionPlan(noActions);
    expect(result.valid).toBe(false);
    expect(result.error).toContain("array");
  });

  it('handles markdown-wrapped JSON from LLM', () => {
    const innerJson = JSON.stringify({ summary: "Test", actions: [] });
    const wrapped = '```json\n' + innerJson + '\n```';
    // Strip markdown fences (as parseResponse would do before calling parseActionPlan)
    const cleaned = wrapped.trim().replace(/^```json\s*\n?/, '').replace(/\n?```\s*$/, '');
    const result = parseActionPlan(cleaned);
    expect(result.valid).toBe(true);
    expect(result.plan.summary).toBe("Test");
  });

  it('end-to-end: extract → parse → validate → display for all action types', () => {
    // Simulate a complete response with all supported action types
    const fullPlan = {
      summary: "Configure workspace for coding session",
      actions: [
        { type: "config.set", key: "bar.borderless", value: false },
        { type: "shell.exec", command: "notify-send 'Ready'" },
        { type: "hyprland.dispatch", dispatcher: "moveworkspacetomonitor", args: "2 DP-1" },
        { type: "app.launch", id: "dev.zed.Zed" }
      ]
    };
    const responseText = JSON.stringify(fullPlan);

    // Step 1: Parse
    const parsed = parseActionPlan(responseText);
    expect(parsed.valid).toBe(true);
    expect(parsed.plan.actions).toHaveLength(4);

    // Step 2: Validate each action
    const validated = parsed.plan.actions.map(a => validateAction(a));
    validated.forEach(a => {
      expect(a.valid).toBe(true);
      expect(a.warning).toBeNull();
    });

    // Step 3: Display summary
    const displaySummary = truncateSummary(parsed.plan.summary);
    expect(displaySummary).toBe("Configure workspace for coding session");

    // Step 4: Display each action
    const displays = validated.map(a => formatActionDisplay(a));
    expect(displays[0]).toContain("bar.borderless");
    expect(displays[0]).toContain("false");
    expect(displays[1]).toBe("notify-send 'Ready'");
    expect(displays[2]).toContain("moveworkspacetomonitor");
    expect(displays[2]).toContain("2 DP-1");
    expect(displays[3]).toBe("dev.zed.Zed");
  });

  it('marks invalid actions while keeping valid ones intact', () => {
    const mixedPlan = {
      summary: "Mixed validity plan",
      actions: [
        { type: "config.set", key: "valid.key", value: 42 },
        { type: "unknown.type", foo: "bar" },
        { type: "shell.exec" }, // missing command
        { type: "app.launch", id: "org.mozilla.firefox" }
      ]
    };
    const responseText = JSON.stringify(mixedPlan);

    const parsed = parseActionPlan(responseText);
    expect(parsed.valid).toBe(true);

    const validated = parsed.plan.actions.map(a => validateAction(a));

    // First action: valid config.set
    expect(validated[0].valid).toBe(true);

    // Second action: unsupported type
    expect(validated[1].valid).toBe(false);
    expect(validated[1].warning).toContain("Unrecognized action type");

    // Third action: missing required param
    expect(validated[2].valid).toBe(false);
    expect(validated[2].warning).toContain("Missing required parameter");

    // Fourth action: valid app.launch
    expect(validated[3].valid).toBe(true);
  });
});


/**
 * Integration: Debounce timer and cancellation
 *
 * Since QML Timer behavior can't be tested directly in Node.js, we test the
 * pure logic of debounce validation and state transitions that govern the
 * debounce/cancellation flow.
 *
 * _Requirements: 7.1, 7.2, 7.3_
 */
describe('Integration: Debounce timer and cancellation', () => {
  it('validateDebounceMs returns valid values in range', () => {
    expect(validateDebounceMs(100)).toBe(100);
    expect(validateDebounceMs(600)).toBe(600);
    expect(validateDebounceMs(5000)).toBe(5000);
  });

  it('validateDebounceMs falls back to 600 for invalid values', () => {
    expect(validateDebounceMs(99)).toBe(600);
    expect(validateDebounceMs(5001)).toBe(600);
    expect(validateDebounceMs(3.14)).toBe(600);
    expect(validateDebounceMs("600")).toBe(600);
    expect(validateDebounceMs(null)).toBe(600);
    expect(validateDebounceMs(undefined)).toBe(600);
  });

  it('simulates debounce → request → cancel flow via state model', () => {
    // Model the state machine transitions
    let state = 'Idle';
    let lastQuery = '';

    // submitQuery transitions to Debouncing
    function submitQuery(query) {
      lastQuery = query;
      state = 'Debouncing';
    }

    // Timer fires → transitions to Loading
    function timerFired() {
      if (state === 'Debouncing') {
        state = 'Loading';
      }
    }

    // cancelRequest → resets to Idle
    function cancelRequest() {
      state = 'Idle';
      lastQuery = '';
    }

    // Scenario 1: Normal flow — debounce fires after idle period (Req 7.1)
    submitQuery("make it dark");
    expect(state).toBe('Debouncing');
    expect(lastQuery).toBe("make it dark");

    timerFired();
    expect(state).toBe('Loading');

    // Scenario 2: Cancel during debounce — text changed (Req 7.2)
    submitQuery("make it");
    expect(state).toBe('Debouncing');

    submitQuery("make it light");
    expect(state).toBe('Debouncing'); // Restarted timer
    expect(lastQuery).toBe("make it light");

    // Scenario 3: Cancel on prefix removal (Req 7.3)
    cancelRequest();
    expect(state).toBe('Idle');
    expect(lastQuery).toBe('');

    // Scenario 4: Cancel during loading — text change while request in-flight
    submitQuery("enable transparency");
    timerFired();
    expect(state).toBe('Loading');
    cancelRequest(); // User changed text
    expect(state).toBe('Idle');
  });

  it('simulates retry re-submits last query', () => {
    let state = 'Idle';
    let lastQuery = '';

    function submitQuery(query) {
      lastQuery = query;
      state = 'Debouncing';
    }

    function retry() {
      if (lastQuery.length > 0) {
        submitQuery(lastQuery);
      }
    }

    // Initial request
    submitQuery("make it dark");

    // Simulate error
    state = 'Error';

    // Retry
    retry();
    expect(state).toBe('Debouncing');
    expect(lastQuery).toBe("make it dark");
  });
});

/**
 * Integration tests for AI Action Palette — Preview mode lifecycle.
 * Models the preview state machine without QML runtime.
 *
 * Validates: Requirements 6.1, 6.3, 6.4, 6.5
 */
describe('Integration: Preview mode lifecycle', () => {
  function createPreviewEngine() {
    const config = {};
    let previewActive = false;
    let snapshot = null;
    let persisted = false;
    let overviewOpen = true;

    function getNestedValue(key) { return config[key]; }
    function setNestedValue(key, value) { config[key] = value; }

    function previewPlan(actions) {
      const configActions = actions.filter(a => a.type === "config.set" && a.valid);
      if (configActions.length === 0) return false;

      // Capture snapshot
      snapshot = { entries: configActions.map(a => ({ key: a.key, previousValue: getNestedValue(a.key) })) };

      // Apply only config.set actions
      configActions.forEach(a => setNestedValue(a.key, a.value));
      previewActive = true;
      return true;
    }

    function commitPreview() {
      if (!previewActive) return;
      persisted = true;
      previewActive = false;
      snapshot = null;
      overviewOpen = false;
    }

    function revertPreview() {
      if (!previewActive) return;
      if (snapshot) {
        for (let i = snapshot.entries.length - 1; i >= 0; i--) {
          setNestedValue(snapshot.entries[i].key, snapshot.entries[i].previousValue);
        }
      }
      previewActive = false;
      snapshot = null;
    }

    function closeOverview() {
      overviewOpen = false;
      if (previewActive) {
        revertPreview();
      }
    }

    return { config, previewPlan, commitPreview, revertPreview, closeOverview,
             isPreviewActive: () => previewActive, isPersisted: () => persisted,
             isOverviewOpen: () => overviewOpen };
  }

  it('preview applies only config.set actions from mixed plan', () => {
    const engine = createPreviewEngine();
    engine.config["existing"] = "old";

    const actions = [
      { type: "config.set", key: "existing", value: "new", valid: true },
      { type: "shell.exec", command: "echo hi", valid: true },
      { type: "hyprland.dispatch", dispatcher: "workspace", args: "2", valid: true },
      { type: "config.set", key: "another", value: true, valid: true },
      { type: "app.launch", id: "firefox", valid: true }
    ];

    engine.previewPlan(actions);

    expect(engine.config["existing"]).toBe("new");
    expect(engine.config["another"]).toBe(true);
    expect(engine.isPreviewActive()).toBe(true);
  });

  it('commit persists changes and closes overview', () => {
    const engine = createPreviewEngine();
    const actions = [
      { type: "config.set", key: "theme", value: "dark", valid: true }
    ];

    engine.previewPlan(actions);
    engine.commitPreview();

    expect(engine.config["theme"]).toBe("dark");
    expect(engine.isPersisted()).toBe(true);
    expect(engine.isPreviewActive()).toBe(false);
    expect(engine.isOverviewOpen()).toBe(false);
  });

  it('revert restores all values to pre-preview state', () => {
    const engine = createPreviewEngine();
    engine.config["a"] = "original_a";
    engine.config["b"] = "original_b";

    const actions = [
      { type: "config.set", key: "a", value: "changed_a", valid: true },
      { type: "config.set", key: "b", value: "changed_b", valid: true }
    ];

    engine.previewPlan(actions);
    expect(engine.config["a"]).toBe("changed_a");

    engine.revertPreview();
    expect(engine.config["a"]).toBe("original_a");
    expect(engine.config["b"]).toBe("original_b");
    expect(engine.isPreviewActive()).toBe(false);
  });

  it('closing overview auto-reverts preview', () => {
    const engine = createPreviewEngine();
    engine.config["x"] = 10;

    const actions = [
      { type: "config.set", key: "x", value: 99, valid: true }
    ];

    engine.previewPlan(actions);
    expect(engine.config["x"]).toBe(99);

    engine.closeOverview();
    expect(engine.config["x"]).toBe(10);
    expect(engine.isPreviewActive()).toBe(false);
  });

  it('returns false when no config.set actions to preview', () => {
    const engine = createPreviewEngine();
    const actions = [
      { type: "shell.exec", command: "echo hi", valid: true },
      { type: "app.launch", id: "firefox", valid: true }
    ];

    const result = engine.previewPlan(actions);
    expect(result).toBe(false);
    expect(engine.isPreviewActive()).toBe(false);
  });
});


/**
 * Integration tests for AI Action Palette — execution flow with approval gate.
 * Models the execution engine logic (sequential execution, approval gate, rejection, timeout)
 * without QML runtime.
 *
 * Validates: Requirements 5.2, 5.3, 5.4, 5.9
 */
describe('Integration: Execution flow with approval gate', () => {
  // Mock config state and execution engine
  function createExecutionEngine() {
    const config = {};
    const trace = [];
    let executionIndex = 0;
    let state = 'Idle';
    let waitingForApproval = false;
    const snapshot = [];

    function getNestedValue(key) { return config[key]; }
    function setNestedValue(key, value) { config[key] = value; }

    function applyPlan(actions) {
      state = 'Executing';
      executionIndex = 0;
      // Capture snapshot for config.set actions
      actions.forEach(a => {
        if (a.type === "config.set") {
          snapshot.push({ key: a.key, previousValue: getNestedValue(a.key) });
        }
      });
      executeNext(actions);
    }

    function executeNext(actions) {
      if (executionIndex >= actions.length) {
        state = 'Complete';
        trace.push({ event: 'all_complete' });
        return;
      }
      const action = actions[executionIndex];
      switch (action.type) {
        case "config.set":
          setNestedValue(action.key, action.value);
          trace.push({ event: 'config_set', key: action.key, value: action.value });
          executionIndex++;
          executeNext(actions);
          break;
        case "shell.exec":
          waitingForApproval = true;
          trace.push({ event: 'approval_required', command: action.command });
          break;
        case "hyprland.dispatch":
          trace.push({ event: 'dispatch', dispatcher: action.dispatcher, args: action.args });
          executionIndex++;
          executeNext(actions);
          break;
        case "app.launch":
          trace.push({ event: 'app_launch', id: action.id });
          executionIndex++;
          executeNext(actions);
          break;
      }
    }

    function approve(actions) {
      if (!waitingForApproval) return;
      waitingForApproval = false;
      trace.push({ event: 'approved' });
      executionIndex++;
      executeNext(actions);
    }

    function reject() {
      waitingForApproval = false;
      state = 'Error';
      trace.push({ event: 'rejected' });
    }

    function timeout() {
      waitingForApproval = false;
      state = 'Error';
      trace.push({ event: 'timeout' });
    }

    function rollback() {
      for (let i = snapshot.length - 1; i >= 0; i--) {
        setNestedValue(snapshot[i].key, snapshot[i].previousValue);
      }
      trace.push({ event: 'rollback' });
    }

    return {
      config, trace, applyPlan, approve, reject, timeout, rollback,
      getState: () => state,
      isWaitingForApproval: () => waitingForApproval
    };
  }

  it('config.set applies values sequentially via setNestedValue', () => {
    const engine = createExecutionEngine();
    const actions = [
      { type: "config.set", key: "a.b", value: true, valid: true },
      { type: "config.set", key: "c.d", value: 42, valid: true }
    ];
    engine.applyPlan(actions);

    expect(engine.config["a.b"]).toBe(true);
    expect(engine.config["c.d"]).toBe(42);
    expect(engine.getState()).toBe('Complete');
    expect(engine.trace.some(e => e.event === 'all_complete')).toBe(true);

    // Verify sequential ordering in trace
    const setEvents = engine.trace.filter(e => e.event === 'config_set');
    expect(setEvents).toHaveLength(2);
    expect(setEvents[0].key).toBe("a.b");
    expect(setEvents[1].key).toBe("c.d");
  });

  it('shell.exec triggers approval and pauses execution', () => {
    const engine = createExecutionEngine();
    const actions = [
      { type: "config.set", key: "a", value: 1, valid: true },
      { type: "shell.exec", command: "echo hello", valid: true },
      { type: "config.set", key: "b", value: 2, valid: true }
    ];
    engine.applyPlan(actions);

    // config.set before shell.exec should have applied
    expect(engine.config["a"]).toBe(1);
    // Execution should be paused at shell.exec
    expect(engine.config["b"]).toBeUndefined();
    expect(engine.isWaitingForApproval()).toBe(true);
    expect(engine.trace.some(e => e.event === 'approval_required')).toBe(true);

    // Approve and continue — remaining actions execute
    engine.approve(actions);
    expect(engine.config["b"]).toBe(2);
    expect(engine.getState()).toBe('Complete');
    expect(engine.isWaitingForApproval()).toBe(false);
  });

  it('rejection stops execution of remaining actions', () => {
    const engine = createExecutionEngine();
    const actions = [
      { type: "shell.exec", command: "rm -rf /", valid: true },
      { type: "config.set", key: "x", value: "never", valid: true }
    ];
    engine.applyPlan(actions);

    // Should be waiting for approval
    expect(engine.isWaitingForApproval()).toBe(true);
    engine.reject();

    expect(engine.getState()).toBe('Error');
    expect(engine.config["x"]).toBeUndefined(); // Never executed
    expect(engine.trace.some(e => e.event === 'rejected')).toBe(true);
    expect(engine.trace.some(e => e.event === 'all_complete')).toBe(false);
  });

  it('timeout kills process and stops execution', () => {
    const engine = createExecutionEngine();
    const actions = [
      { type: "config.set", key: "applied", value: "yes", valid: true },
      { type: "shell.exec", command: "sleep 60", valid: true },
      { type: "config.set", key: "after_shell", value: "nope", valid: true }
    ];
    engine.applyPlan(actions);

    // First config.set applied, now waiting at shell.exec
    expect(engine.config["applied"]).toBe("yes");
    expect(engine.isWaitingForApproval()).toBe(true);

    // Simulate 30s timeout
    engine.timeout();

    expect(engine.getState()).toBe('Error');
    expect(engine.config["after_shell"]).toBeUndefined();
    expect(engine.trace.some(e => e.event === 'timeout')).toBe(true);
    expect(engine.trace.some(e => e.event === 'all_complete')).toBe(false);
  });

  it('rollback restores previous config values after failure', () => {
    const engine = createExecutionEngine();
    engine.config["a"] = "original";

    const actions = [
      { type: "config.set", key: "a", value: "changed", valid: true },
      { type: "config.set", key: "b", value: "new", valid: true }
    ];
    engine.applyPlan(actions);

    expect(engine.config["a"]).toBe("changed");
    expect(engine.config["b"]).toBe("new");

    engine.rollback();

    expect(engine.config["a"]).toBe("original");
    expect(engine.config["b"]).toBeUndefined(); // Was undefined before
    expect(engine.trace.some(e => e.event === 'rollback')).toBe(true);
  });

  it('mixed action types execute in correct order with approval gate', () => {
    const engine = createExecutionEngine();
    const actions = [
      { type: "config.set", key: "theme", value: "dark", valid: true },
      { type: "hyprland.dispatch", dispatcher: "workspace", args: "2", valid: true },
      { type: "shell.exec", command: "notify-send 'done'", valid: true },
      { type: "app.launch", id: "org.kde.dolphin", valid: true }
    ];
    engine.applyPlan(actions);

    // config.set and hyprland.dispatch should execute immediately
    expect(engine.config["theme"]).toBe("dark");
    expect(engine.trace.some(e => e.event === 'dispatch' && e.dispatcher === 'workspace')).toBe(true);

    // Paused at shell.exec
    expect(engine.isWaitingForApproval()).toBe(true);
    expect(engine.trace.filter(e => e.event === 'app_launch')).toHaveLength(0);

    // Approve — app.launch should follow
    engine.approve(actions);
    expect(engine.trace.some(e => e.event === 'app_launch' && e.id === 'org.kde.dolphin')).toBe(true);
    expect(engine.getState()).toBe('Complete');
  });
});
