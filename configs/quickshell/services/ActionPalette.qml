pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions as CF
import qs.modules.common
import qs
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

/**
 * AI Action Palette service — orchestrates request lifecycle, parsing,
 * validation, execution, and preview state management for the
 * natural-language action palette integrated into the overview search.
 */
Singleton {
    id: root

    // === State ===
    enum State { Idle, Debouncing, Loading, Ready, Executing, Previewing, Error }
    property int state: ActionPalette.Idle

    property var actionPlan: null        // Parsed Action_Plan object or null
    property string errorMessage: ""     // Human-readable error
    property bool canRetry: false        // Whether retry is available
    property string lastQuery: ""        // Last submitted query text
    property var configSnapshot: null    // Captured config state before preview
    property bool previewActive: false   // Whether preview mode is active
    property var currentResults: {
        // Loading state
        if (root.state === ActionPalette.Loading || root.state === ActionPalette.Debouncing) {
            return [{
                name: Translation.tr("Thinking..."),
                type: Translation.tr("AI Action"),
                materialSymbol: "hourglass_top",
                execute: function() {}
            }];
        }

        // Error state
        if (root.state === ActionPalette.Error) {
            let errorActions = [];
            if (root.canRetry) {
                errorActions.push({
                    name: Translation.tr("Retry"),
                    icon: "",
                    execute: function() { ActionPalette.retry(); }
                });
            }
            return [{
                name: root.errorMessage,
                type: Translation.tr("AI Action"),
                materialSymbol: "error",
                execute: function() {},
                actions: errorActions
            }];
        }

        // Ready state with action plan
        if (root.state === ActionPalette.Ready && root.actionPlan) {
            const plan = root.actionPlan;
            const displaySummary = plan.summary.length > 120
                ? plan.summary.slice(0, 120) + "…"
                : plan.summary;

            let results = [];

            // Summary entry — clicking it applies the full plan
            const hasActions = plan.actions.length > 0;
            results.push({
                name: displaySummary,
                type: Translation.tr("AI Action Plan"),
                materialSymbol: "auto_awesome",
                clickActionName: "",
                execute: function() { ActionPalette.applyPlan(); },
                actions: hasActions ? [
                    { name: Translation.tr("Apply"), icon: "", execute: function() { ActionPalette.applyPlan(); } },
                    { name: Translation.tr("Preview"), icon: "", execute: function() { ActionPalette.previewPlan(); } }
                ] : []
            });

            // Per-action entries — clicking executes just that action
            for (var idx = 0; idx < plan.actions.length; idx++) {
                const action = plan.actions[idx];
                let name = "";
                let icon = "";

                switch (action.type) {
                    case "config.set":
                        const current = action.currentValue !== undefined
                            ? JSON.stringify(action.currentValue)
                            : "?";
                        name = `${action.key}: ${current} → ${JSON.stringify(action.value)}`;
                        icon = "settings";
                        break;
                    case "shell.exec":
                        name = action.command;
                        icon = "terminal";
                        break;
                    case "hyprland.dispatch":
                        name = `${action.dispatcher} ${action.args}`;
                        icon = "open_with";
                        break;
                    case "app.launch":
                        name = action.id;
                        icon = "apps";
                        break;
                    default:
                        name = action.warning || "Unknown action";
                        icon = "warning";
                        break;
                }

                const actionIdx = idx;
                results.push({
                    name: name,
                    type: action.type || "unknown",
                    materialSymbol: action.valid === false ? "warning" : icon,
                    execute: function() { ActionPalette.executeSingleAction(actionIdx); }
                });
            }

            return results;
        }

        // Idle or other states — no results
        return [];
    }

    // === Signals ===
    signal actionPlanReady()
    signal executionComplete()
    signal executionFailed(string actionType, int index, string reason)
    signal previewStarted()
    signal previewEnded()
    signal approvalRequired(string command, int actionIndex)

    // === Supported action types and their required parameters ===
    readonly property var supportedActionTypes: ({
        "config.set": ["key", "value"],
        "shell.exec": ["command"],
        "hyprland.dispatch": ["dispatcher", "args"],
        "app.launch": ["id"]
    })

    // === Internal: Execution state (used by applyPlan, approveCommand) ===
    property int _executionIndex: 0
    property var _configUndoSnapshot: null  // ConfigSnapshot for rollback on failure

    /**
     * Internal: Advance execution to the next action in the plan.
     * Processes actions sequentially (index 0 to N-1). Each action type
     * is handled differently:
     * - config.set: synchronous via Config.setNestedValue
     * - hyprland.dispatch: synchronous via Hyprland.dispatch
     * - app.launch: synchronous via DesktopEntries.byId + execute
     * - shell.exec: pauses for user approval (async)
     *
     * Requirements: 5.1, 5.2, 5.5, 5.6, 5.7, 5.8, 5.10
     */
    function _executeNext() {
        if (!root.actionPlan || root._executionIndex >= root.actionPlan.actions.length) {
            // All actions completed successfully
            root.state = ActionPalette.Idle;
            root.executionComplete();
            GlobalStates.overviewOpen = false;
            return;
        }

        const action = root.actionPlan.actions[root._executionIndex];

        if (!action.valid) {
            root._executionFailed(action.type || "unknown", root._executionIndex, action.warning || "Invalid action");
            return;
        }

        switch (action.type) {
            case "config.set":
                root._executeConfigSet(action);
                break;
            case "shell.exec":
                // Pause execution — emit approval signal, wait for approve/reject
                root.approvalRequired(action.command, root._executionIndex);
                break;
            case "hyprland.dispatch":
                root._executeHyprlandDispatch(action);
                break;
            case "app.launch":
                root._executeAppLaunch(action);
                break;
            default:
                root._executionFailed(action.type || "unknown", root._executionIndex, "Unsupported action type");
                break;
        }
    }

    /**
     * Internal: Execute a config.set action.
     * Calls Config.setNestedValue with the specified key and value.
     * Previous values are already captured in _configUndoSnapshot by applyPlan().
     */
    function _executeConfigSet(action) {
        try {
            Config.setNestedValue(action.key, action.value);
        } catch (e) {
            root._executionFailed("config.set", root._executionIndex, `Failed to set ${action.key}: ${e}`);
            return;
        }
        root._executionIndex++;
        root._executeNext();
    }

    /**
     * Internal: Execute a hyprland.dispatch action.
     * Uses the native Hyprland.dispatch() call for consistency with the rest
     * of the shell (synchronous, no process spawn needed).
     */
    function _executeHyprlandDispatch(action) {
        try {
            Hyprland.dispatch(`${action.dispatcher} ${action.args}`);
        } catch (e) {
            root._executionFailed("hyprland.dispatch", root._executionIndex, `Dispatch failed: ${e}`);
            return;
        }
        root._executionIndex++;
        root._executeNext();
    }

    /**
     * Internal: Execute an app.launch action.
     * Looks up the desktop entry by ID via DesktopEntries.byId(), then calls
     * execute() on it. Fails if no matching desktop entry is found.
     */
    function _executeAppLaunch(action) {
        const entry = DesktopEntries.byId(action.id);
        if (!entry) {
            root._executionFailed("app.launch", root._executionIndex, `Application not found: ${action.id}`);
            return;
        }
        try {
            entry.execute();
        } catch (e) {
            root._executionFailed("app.launch", root._executionIndex, `Failed to launch ${action.id}: ${e}`);
            return;
        }
        root._executionIndex++;
        root._executeNext();
    }

    /**
     * Internal: Handle execution failure — stop remaining actions, offer undo.
     * Sets error state with a descriptive message and emits executionFailed signal.
     * The user can call rollbackConfig() to undo applied config.set actions.
     */
    function _executionFailed(actionType, index, reason) {
        root.state = ActionPalette.Error;
        root.errorMessage = reason;
        root.canRetry = false;
        root.executionFailed(actionType, index, reason);
    }

    /**
     * Rollback applied config.set changes using the captured undo snapshot.
     * Iterates snapshot entries in reverse order and restores each key to its
     * previous value. Reverse order ensures dependent changes are undone correctly.
     */
    function rollbackConfig() {
        if (!root._configUndoSnapshot || !root._configUndoSnapshot.entries
            || root._configUndoSnapshot.entries.length === 0) return;

        // Restore in reverse order to handle dependent changes correctly
        for (let i = root._configUndoSnapshot.entries.length - 1; i >= 0; i--) {
            const entry = root._configUndoSnapshot.entries[i];
            try {
                Config.setNestedValue(entry.key, entry.previousValue);
            } catch (e) {
                console.warn(`[ActionPalette] Failed to rollback ${entry.key}: ${e}`);
            }
        }

        root._configUndoSnapshot = null;
        root.state = ActionPalette.Idle;
        root.errorMessage = "";
    }

    // === Internal: Effective debounce duration ===
    // Validates that aiDebounceMs is an integer in [100, 5000]; otherwise uses default 600
    readonly property int effectiveDebounceMs: {
        const raw = Config.options.search.aiDebounceMs;
        if (typeof raw === "number" && Number.isInteger(raw) && raw >= 100 && raw <= 5000) {
            return raw;
        }
        return 600;
    }

    // === Debounce Timer ===
    Timer {
        id: debounceTimer
        interval: root.effectiveDebounceMs
        repeat: false
        onTriggered: () => {
            root.sendRequest();
        }
    }

    // === 30-second request timeout timer ===
    Timer {
        id: requestTimeoutTimer
        interval: 30000
        repeat: false
        onTriggered: () => {
            llmProcess.running = false;  // Kill process
            root.state = ActionPalette.Error;
            root.errorMessage = "Request timed out";
            root.canRetry = true;
        }
    }

    // === Auto-revert preview when overview closes ===
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (!GlobalStates.overviewOpen && root.previewActive) {
                root.revertPreview();
            }
        }
    }

    // === Shell command execution process (for shell.exec actions) ===
    Process {
        id: shellExecProcess
        property list<string> baseCommand: ["bash", "-c"]
        stdout: StdioCollector {
            onStreamFinished: {
                shellExecTimeout.stop();
                // Exit handled in onExited
            }
        }
        onExited: (exitCode, exitStatus) => {
            shellExecTimeout.stop();
            if (exitCode !== 0) {
                root._executionFailed("shell.exec", root._executionIndex,
                    `Command exited with code ${exitCode}`);
            } else {
                // Success — advance to next action
                root._executionIndex++;
                root._executeNext();
            }
        }
    }

    // === 30-second shell command timeout timer ===
    Timer {
        id: shellExecTimeout
        interval: 30000
        repeat: false
        onTriggered: () => {
            shellExecProcess.running = false;
            root._executionFailed("shell.exec", root._executionIndex, "Command timed out (30s)");
        }
    }

    // === LLM request process (separate from Ai.qml's requester) ===
    Process {
        id: llmProcess
        property list<string> baseCommand: ["bash", "-c"]
        stdout: StdioCollector {
            onStreamFinished: {
                requestTimeoutTimer.stop();
                if (text.length === 0) {
                    root.state = ActionPalette.Error;
                    root.errorMessage = "Request failed — check your network connection";
                    root.canRetry = true;
                    return;
                }
                root.parseResponse(text);
            }
        }
        onExited: (exitCode, exitStatus) => {
            requestTimeoutTimer.stop();
            if (exitCode !== 0) {
                root.state = ActionPalette.Error;
                root.errorMessage = "Request failed — check your network connection";
                root.canRetry = true;
            }
        }
    }

    // === Public API ===
    function submitQuery(queryText) {
        root.lastQuery = queryText;
        root.state = ActionPalette.Debouncing;
        debounceTimer.restart();
    }

    function cancelRequest() {
        debounceTimer.stop();
        // Stop request timeout timer if it exists
        if (typeof requestTimeoutTimer !== "undefined" && requestTimeoutTimer) {
            requestTimeoutTimer.stop();
        }
        // Kill in-flight LLM process if it's running
        if (typeof llmProcess !== "undefined" && llmProcess && llmProcess.running) {
            llmProcess.running = false;
        }
        root.state = ActionPalette.Idle;
        root.actionPlan = null;
        root.errorMessage = "";
        root.canRetry = false;
    }

    function retry() {
        if (root.lastQuery.length > 0) {
            root.submitQuery(root.lastQuery);
        }
    }

    function applyPlan() {
        console.log("[ActionPalette] applyPlan called. actionPlan=" + JSON.stringify(root.actionPlan ? {summary: root.actionPlan.summary, actionsCount: root.actionPlan.actions.length} : null));
        if (!root.actionPlan || root.actionPlan.actions.length === 0) {
            console.log("[ActionPalette] applyPlan: no actionPlan or empty actions, returning");
            return;
        }

        // Execute all actions directly — user triggered from action palette (implicit approval)
        for (var i = 0; i < root.actionPlan.actions.length; i++) {
            var action = root.actionPlan.actions[i];
            console.log("[ActionPalette] processing action " + i + ": type=" + (action ? action.type : "null") + " valid=" + (action ? action.valid : "n/a") + " command=" + (action ? action.command : ""));
            if (!action || action.valid === false) continue;

            switch (action.type) {
                case "config.set":
                    try { Config.setNestedValue(action.key, action.value); } catch (e) { console.log("[ActionPalette] config.set error: " + e); }
                    break;
                case "shell.exec":
                    console.log("[ActionPalette] executing shell: " + action.command);
                    // Run in a visible terminal so the user sees output
                    var termCmd = "foot -e bash -c '" + action.command.replace(/'/g, "'\\''") + "; echo; echo Press Enter to close...; read'";
                    Hyprland.dispatch("exec " + termCmd);
                    break;
                case "hyprland.dispatch":
                    try { Hyprland.dispatch(action.dispatcher + " " + action.args); } catch (e) { console.log("[ActionPalette] dispatch error: " + e); }
                    break;
                case "app.launch":
                    var entry = DesktopEntries.byId(action.id);
                    if (entry) { try { entry.execute(); } catch (e) {} }
                    break;
                default:
                    console.log("[ActionPalette] unknown action type: " + action.type);
                    break;
            }
        }

        root.state = ActionPalette.Idle;
        GlobalStates.overviewOpen = false;
    }

    /**
     * Preview only the config.set actions from the action plan.
     * Applies changes in memory (runtime-only, no persistence) so the user
     * can visually inspect the result before committing.
     *
     * On failure: reverts already-applied changes, exits preview, shows error.
     *
     * Requirements: 6.1, 6.6
     */

    /**
     * Execute a single action by index. Used when the user clicks a specific
     * action row in the results list rather than applying the entire plan.
     * For shell.exec: runs directly (user click is implicit approval).
     * For config.set: applies immediately.
     * For hyprland.dispatch: dispatches immediately.
     * For app.launch: launches immediately.
     */
    function executeSingleAction(actionIndex) {
        console.log("[ActionPalette] executeSingleAction called. index=" + actionIndex + " actionPlan=" + (root.actionPlan ? "exists, actions=" + root.actionPlan.actions.length : "null"));
        if (!root.actionPlan || actionIndex >= root.actionPlan.actions.length) {
            console.log("[ActionPalette] executeSingleAction: guard failed, returning");
            return;
        }

        const action = root.actionPlan.actions[actionIndex];
        if (!action || action.valid === false) return;

        switch (action.type) {
            case "config.set":
                try {
                    Config.setNestedValue(action.key, action.value);
                } catch (e) {
                    console.error("[ActionPalette] config.set failed:", e);
                }
                GlobalStates.overviewOpen = false;
                break;
            case "shell.exec":
                // Run in a visible terminal so the user sees output
                var termCmd2 = "foot -e bash -c '" + action.command.replace(/'/g, "'\\''") + "; echo; echo Press Enter to close...; read'";
                Hyprland.dispatch("exec " + termCmd2);
                GlobalStates.overviewOpen = false;
                break;
            case "hyprland.dispatch":
                try {
                    Hyprland.dispatch(`${action.dispatcher} ${action.args}`);
                } catch (e) {
                    console.error("[ActionPalette] hyprland.dispatch failed:", e);
                }
                GlobalStates.overviewOpen = false;
                break;
            case "app.launch":
                const entry = DesktopEntries.byId(action.id);
                if (entry) {
                    try { entry.execute(); } catch (e) {}
                }
                GlobalStates.overviewOpen = false;
                break;
        }
    }

    function previewPlan() {
        if (!root.actionPlan || root.actionPlan.actions.length === 0) return;

        // Filter to only valid config.set actions
        const configActions = root.actionPlan.actions.filter(a => a.type === "config.set" && a.valid);
        if (configActions.length === 0) {
            root.errorMessage = "No config changes to preview";
            root.state = ActionPalette.Error;
            root.canRetry = false;
            return;
        }

        // Capture snapshot before applying (for revert)
        root.configSnapshot = {
            entries: configActions.map(a => ({
                key: a.key,
                previousValue: root.getNestedValue(a.key)
            }))
        };

        // Apply each config.set (runtime-only, no persistence via FileView.writeAdapter)
        for (let i = 0; i < configActions.length; i++) {
            try {
                Config.setNestedValue(configActions[i].key, configActions[i].value);
            } catch (e) {
                // Revert already-applied changes in reverse order
                for (let j = i - 1; j >= 0; j--) {
                    try {
                        Config.setNestedValue(root.configSnapshot.entries[j].key, root.configSnapshot.entries[j].previousValue);
                    } catch (revertError) {
                        console.warn("[ActionPalette] Failed to revert preview change:", revertError);
                    }
                }
                root.configSnapshot = null;
                root.state = ActionPalette.Error;
                root.errorMessage = `Preview failed on ${configActions[i].key}: ${e}`;
                root.canRetry = false;
                return;
            }
        }

        root.state = ActionPalette.Previewing;
        root.previewActive = true;
        root.previewStarted();
    }

    /**
     * Persist previewed configuration changes and close the overview.
     * Since Config.qml auto-persists via onAdapterUpdated → writeAdapter(),
     * the changes applied during previewPlan() are already written to disk.
     * This function cleans up preview state and closes the overview.
     *
     * Requirements: 6.3
     */
    function commitPreview() {
        if (!root.previewActive) return;

        // Changes are already persisted by Config.qml's FileView (onAdapterUpdated → writeAdapter())
        // Clean up preview state
        root.previewActive = false;
        root.configSnapshot = null;
        root.state = ActionPalette.Idle;
        root.previewEnded();

        // Close the overview
        GlobalStates.overviewOpen = false;
    }

    /**
     * Revert all previewed configuration changes by restoring pre-preview values.
     * Iterates snapshot entries in reverse order to handle dependent changes correctly.
     * Transitions back to Ready so the action plan remains visible for re-preview or apply.
     *
     * Requirements: 6.4
     */
    function revertPreview() {
        if (!root.previewActive) return;

        // Restore all keys from snapshot in reverse order
        if (root.configSnapshot && root.configSnapshot.entries) {
            for (let i = root.configSnapshot.entries.length - 1; i >= 0; i--) {
                const entry = root.configSnapshot.entries[i];
                try {
                    Config.setNestedValue(entry.key, entry.previousValue);
                } catch (e) {
                    console.warn("[ActionPalette] Failed to revert preview:", entry.key, e);
                }
            }
        }

        root.previewActive = false;
        root.configSnapshot = null;
        root.state = ActionPalette.Ready;  // Back to Ready so user can re-try
        root.previewEnded();
    }

    function approveCommand(actionIndex) {
        const action = root.actionPlan.actions[actionIndex];
        shellExecProcess.command = shellExecProcess.baseCommand.concat([action.command]);
        shellExecProcess.running = true;
        shellExecTimeout.start();
    }

    function rejectCommand() {
        root.state = ActionPalette.Error;
        root.errorMessage = Translation.tr("Execution cancelled by user");
        root.canRetry = false;
    }

    // === Internal: Build system prompt for LLM ===
    function buildSystemPrompt() {
        return `You are a desktop automation assistant for a Quickshell-based Linux desktop environment.
You MUST respond with ONLY a valid JSON object following this exact schema:

{
  "summary": "Brief description of what the actions will do (max 200 characters)",
  "actions": [
    // Array of action objects (max 20 items)
  ]
}

Supported action types:

1. config.set — Change a shell configuration value
   Required parameters: "key" (dot-notation path), "value" (any JSON value)
   Example: {"type": "config.set", "key": "appearance.transparency", "value": true}

2. shell.exec — Execute a shell command (requires user approval)
   Required parameters: "command" (string)
   Example: {"type": "shell.exec", "command": "hyprctl keyword general:gaps_out 5"}

3. hyprland.dispatch — Send a Hyprland dispatcher command
   Required parameters: "dispatcher" (string), "args" (string)
   Example: {"type": "hyprland.dispatch", "dispatcher": "workspace", "args": "3"}

4. app.launch — Launch an application by desktop entry ID
   Required parameters: "id" (string - desktop entry app ID)
   Example: {"type": "app.launch", "id": "org.kde.dolphin"}

Configuration key namespaces (use with config.set):
- appearance.* — Visual settings (transparency, borderless, schemeIndex, etc.)
- bar.* — Status bar configuration
- search.* — Search/launcher settings
- apps.* — Default application settings
- ai.* — AI model configuration
- policies.* — Policy settings

Rules:
- Return ONLY valid JSON, no markdown, no explanation text
- summary must be ≤ 200 characters
- actions array must have ≤ 20 items
- Each action must have a "type" field and all required parameters for that type
- Prefer config.set over shell.exec when possible (safer, reversible)
- Use hyprland.dispatch for window/workspace management
- Use app.launch for opening applications`;
    }

    // === Internal: Policy gates ===
    /**
     * Checks policy gates before sending a request. Returns true if the request
     * should proceed, false if blocked (after setting error state).
     *
     * Checks in order:
     * 1. policies.ai === 0 → AI disabled
     * 2. Invalid/missing model
     * 3. policies.ai === 2 and endpoint not localhost → online models disallowed
     * 4. Missing API key for model that requires one
     */
    function checkPolicyGates() {
        // 1. AI completely disabled
        if (Config.options.policies.ai === 0) {
            root.errorMessage = "AI is disabled by policies.ai configuration";
            root.state = ActionPalette.Error;
            root.canRetry = false;
            return false;
        }

        // 2. No valid model selected
        if (!Ai.currentModelId || !Ai.models[Ai.currentModelId]) {
            root.errorMessage = "Select a model in the AI sidebar";
            root.state = ActionPalette.Error;
            root.canRetry = false;
            return false;
        }

        // 3. Local-only policy with online model
        const endpoint = Ai.models[Ai.currentModelId]?.endpoint || "";
        if (Config.options.policies.ai === 2 && !endpoint.includes("localhost")) {
            root.errorMessage = "Online models are disallowed by policies.ai configuration";
            root.state = ActionPalette.Error;
            root.canRetry = false;
            return false;
        }

        // 4. Missing API key
        if (!Ai.currentModelHasApiKey) {
            root.errorMessage = "Set an API key via /key in the AI sidebar";
            root.state = ActionPalette.Error;
            root.canRetry = false;
            return false;
        }

        return true;
    }

    // === Internal: Send request to LLM ===
    function sendRequest() {
        if (!root.checkPolicyGates()) {
            return;
        }

        root.state = ActionPalette.Loading;

        const model = Ai.models[Ai.currentModelId];
        const strategy = Ai.currentApiStrategy;

        /* Build endpoint — for Gemini, replace streaming with non-streaming */
        let endpoint = strategy.buildEndpoint(model);
        if (model.api_format === "gemini") {
            endpoint = endpoint.replace(":streamGenerateContent", ":generateContent");
        }

        /* Build messages: system prompt + single user message (no chat history) */
        const context = root.buildActionContext();
        const userContent = root.lastQuery + "\n\nCurrent desktop context:\n" + JSON.stringify(context, null, 2);
        const systemPrompt = root.buildSystemPrompt();

        /* Build request data via the strategy pattern */
        const fakeMessages = [{
            role: "user",
            rawContent: userContent,
            functionCall: undefined,
            functionName: "",
            functionResponse: undefined,
        }];
        let data = strategy.buildRequestData(model, fakeMessages, systemPrompt, Ai.temperature, []);

        /* For OpenAI/Mistral: disable streaming since we want full response at once */
        if (data.stream !== undefined) {
            data.stream = false;
        }

        /* Set API key in environment variable */
        if (model.requires_key) {
            llmProcess.environment[`${Ai.apiKeyEnvVarName}`] = Ai.apiKeys ? (Ai.apiKeys[model.key_id] ?? "") : "";
        }

        /* Build curl header string */
        let requestHeaders = {
            "Content-Type": "application/json",
        };
        let headerString = Object.entries(requestHeaders)
            .filter(([k, v]) => v && v.length > 0)
            .map(([k, v]) => `-H '${k}: ${v}'`)
            .join(' ');

        /* Get authorization header from strategy */
        const authHeader = strategy.buildAuthorizationHeader(Ai.apiKeyEnvVarName);

        /* Create curl command string (non-streaming, no --no-buffer) */
        const requestCommandString = `curl "${endpoint}"`
            + ` ${headerString}`
            + (authHeader ? ` ${authHeader}` : "")
            + ` -d '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`;

        /* Send the request */
        llmProcess.command = llmProcess.baseCommand.concat([requestCommandString]);
        llmProcess.running = true;
        requestTimeoutTimer.start();
    }

    /**
     * Parses the LLM response text into an Action_Plan.
     *
     * Handles multiple response formats:
     * - Raw Action_Plan JSON (direct)
     * - Gemini API envelope: { candidates: [{ content: { parts: [{ text }] } }] }
     * - OpenAI/Mistral API envelope: { choices: [{ message: { content } }] }
     * - Markdown code-fence wrapped JSON (```json ... ```)
     *
     * Validates:
     * - summary is a string, truncated to 500 chars if longer
     * - actions is an array, truncated to 50 items if longer
     * - On any schema mismatch: sets error state with descriptive message and retry
     *
     * Requirements: 3.1, 3.2
     */
    function parseResponse(responseText) {
        // Step 1: Extract the content text from the API envelope (if any)
        let contentText = responseText;
        try {
            const apiResp = JSON.parse(responseText);
            // Try Gemini format
            if (apiResp.candidates && apiResp.candidates[0]
                && apiResp.candidates[0].content
                && apiResp.candidates[0].content.parts
                && apiResp.candidates[0].content.parts[0]
                && typeof apiResp.candidates[0].content.parts[0].text === "string") {
                contentText = apiResp.candidates[0].content.parts[0].text;
            }
            // Try OpenAI/Mistral format
            else if (apiResp.choices && apiResp.choices[0]
                     && apiResp.choices[0].message
                     && typeof apiResp.choices[0].message.content === "string") {
                contentText = apiResp.choices[0].message.content;
            }
            // Otherwise: responseText itself might be the Action_Plan JSON directly
        } catch (e) {
            // responseText is not valid JSON at all at the top level —
            // it might still be raw text we can try to parse below
        }

        // Step 2: Strip markdown code fences if the LLM wrapped JSON in them
        contentText = contentText.trim()
            .replace(/^```json\s*\n?/, '')
            .replace(/^```\s*\n?/, '')
            .replace(/\n?```\s*$/, '');

        // Step 3: Parse the action plan JSON
        let plan;
        try {
            plan = JSON.parse(contentText);
        } catch (e) {
            root.state = ActionPalette.Error;
            root.errorMessage = "LLM returned malformed response";
            root.canRetry = true;
            return;
        }

        // Step 4: Validate schema — summary must be a string
        if (typeof plan.summary !== "string") {
            root.state = ActionPalette.Error;
            root.errorMessage = "Response doesn't match expected format (missing summary)";
            root.canRetry = true;
            return;
        }

        // Truncate summary to 500 chars if it exceeds the limit
        if (plan.summary.length > 500) {
            plan.summary = plan.summary.slice(0, 500);
        }

        // Step 5: Validate schema — actions must be an array
        if (!Array.isArray(plan.actions)) {
            root.state = ActionPalette.Error;
            root.errorMessage = "Response doesn't match expected format (actions is not an array)";
            root.canRetry = true;
            return;
        }

        // Truncate actions array to 50 items if it exceeds the limit
        if (plan.actions.length > 50) {
            plan.actions = plan.actions.slice(0, 50);
        }

        // Step 6: Validate individual actions (delegates to validateActionPlan)
        root.actionPlan = root.validateActionPlan(plan);
        root.state = ActionPalette.Ready;
        root.canRetry = false;
        root.errorMessage = "";
        root.actionPlanReady();
    }

    /**
     * Gathers current desktop context for the LLM request:
     * - Shell_Config state (full config object)
     * - Open windows with app IDs and workspace positions
     * - Active workspace identifier
     */
    function buildActionContext() {
        const config = JSON.parse(JSON.stringify(Config.options));
        const windows = HyprlandData.windowList.map(w => ({
            appId: w.class || "",
            title: w.title || "",
            workspace: w.workspace?.id ?? -1
        }));
        const activeWorkspace = HyprlandData.activeWorkspace?.id ?? 1;
        return {
            config: config,
            windows: windows,
            activeWorkspace: activeWorkspace
        };
    }

    /**
     * Get a nested value from Config.options using dot notation.
     * Returns undefined if the path doesn't exist.
     */
    function getNestedValue(key) {
        const parts = key.split(".");
        let obj = Config.options;
        for (const part of parts) {
            if (obj === undefined || obj === null) return undefined;
            obj = obj[part];
        }
        return obj;
    }

    /**
     * Validate a single action object.
     * Checks that the type is supported and all required parameters are present.
     * For config.set actions, looks up the current value.
     * Returns an enriched copy with `valid` and `warning` fields.
     */
    function validateAction(action) {
        if (!action || typeof action !== "object") {
            return Object.assign({}, action, { valid: false, warning: "Action is not an object" });
        }

        const type = action.type;
        const requiredParams = root.supportedActionTypes[type];

        if (!requiredParams) {
            return Object.assign({}, action, { valid: false, warning: `Unrecognized action type: ${type || "missing"}` });
        }

        // Check required parameters
        for (const param of requiredParams) {
            if (action[param] === undefined || action[param] === null) {
                return Object.assign({}, action, { valid: false, warning: `Missing required parameter: ${param}` });
            }
        }

        // Valid action — enrich with metadata
        let result = Object.assign({}, action, { valid: true, warning: null });

        // For config.set: look up current value
        if (type === "config.set") {
            result.currentValue = root.getNestedValue(action.key);
        }

        return result;
    }

    /**
     * Validate the entire action plan.
     * Runs validateAction on each action in the plan and returns a structured
     * result with the summary, validated actions, and the raw JSON string.
     */
    function validateActionPlan(plan) {
        return {
            summary: plan.summary,
            actions: plan.actions.map(action => root.validateAction(action)),
            raw: JSON.stringify(plan)
        };
    }
}
