/**
 * Pure logic functions extracted from ActionPalette.qml for property-based testing.
 * These mirror the QML service logic but are testable in a Node.js environment.
 */

// Supported action types and their required parameters
const SUPPORTED_TYPES = {
  "config.set": ["key", "value"],
  "shell.exec": ["command"],
  "hyprland.dispatch": ["dispatcher", "args"],
  "app.launch": ["id"]
};

/**
 * Classify whether a search input represents an AI intent.
 * Returns true iff input starts with prefix + space + non-whitespace.
 */
export function classifyAiPrefix(input, aiPrefix) {
  if (!input || !aiPrefix) return false;
  if (!input.startsWith(aiPrefix)) return false;
  const afterPrefix = input.slice(aiPrefix.length);
  return afterPrefix.startsWith(" ") && afterPrefix.trim().length > 0;
}

/**
 * Validate that a prefix string is acceptable for search.prefix.ai.
 * Must be 1-3 characters and not all whitespace.
 */
export function validatePrefix(prefix) {
  if (typeof prefix !== "string") return false;
  if (prefix.length < 1 || prefix.length > 3) return false;
  if (prefix.trim().length === 0) return false;
  return true;
}

/**
 * Check local-only policy gate.
 * Returns true (blocked) if policies.ai === 2 and endpoint doesn't contain "localhost".
 */
export function checkLocalOnlyPolicy(policyValue, endpoint) {
  if (policyValue !== 2) return false; // Not blocked
  return !endpoint.includes("localhost");
}

/**
 * Parse an Action_Plan from a JSON string.
 * Returns { valid: true, plan: {...} } or { valid: false, error: "..." }
 */
export function parseActionPlan(jsonString) {
  let plan;
  try {
    plan = JSON.parse(jsonString);
  } catch (e) {
    return { valid: false, error: "Malformed JSON" };
  }

  if (typeof plan.summary !== "string") {
    return { valid: false, error: "Missing summary" };
  }
  if (plan.summary.length > 500) {
    plan.summary = plan.summary.slice(0, 500);
  }
  if (!Array.isArray(plan.actions)) {
    return { valid: false, error: "Actions is not an array" };
  }
  if (plan.actions.length > 50) {
    plan.actions = plan.actions.slice(0, 50);
  }

  return { valid: true, plan };
}

/**
 * Validate a single action object.
 * Returns { valid: true/false, warning: string|null, ...action }
 */
export function validateAction(action) {
  if (!action || typeof action !== "object") {
    return { ...action, valid: false, warning: "Action is not an object" };
  }

  const type = action.type;
  const requiredParams = SUPPORTED_TYPES[type];

  if (!requiredParams) {
    return { ...action, valid: false, warning: `Unrecognized action type: ${type || "missing"}` };
  }

  for (const param of requiredParams) {
    if (action[param] === undefined || action[param] === null) {
      return { ...action, valid: false, warning: `Missing required parameter: ${param}` };
    }
  }

  return { ...action, valid: true, warning: null };
}

/**
 * Truncate a summary string for display.
 * Returns original if ≤ 120 chars, otherwise first 120 + "…"
 */
export function truncateSummary(summary) {
  if (typeof summary !== "string") return "";
  if (summary.length <= 120) return summary;
  return summary.slice(0, 120) + "\u2026";
}

/**
 * Format a validated action for display.
 * Returns a string containing type-specific key information.
 */
export function formatActionDisplay(action) {
  if (!action || !action.type) return "Unknown action";

  switch (action.type) {
    case "config.set": {
      const current = action.currentValue !== undefined ? JSON.stringify(action.currentValue) : "?";
      return `${action.key}: ${current} \u2192 ${JSON.stringify(action.value)}`;
    }
    case "shell.exec":
      return action.command;
    case "hyprland.dispatch":
      return `${action.dispatcher} ${action.args}`;
    case "app.launch":
      return action.id;
    default:
      return action.warning || "Unknown action";
  }
}

/**
 * Validate debounce milliseconds value.
 * Returns the value if it's an integer in [100, 5000], else 600.
 */
export function validateDebounceMs(value) {
  if (typeof value !== "number") return 600;
  if (!Number.isInteger(value)) return 600;
  if (value < 100 || value > 5000) return 600;
  return value;
}

export { SUPPORTED_TYPES };
