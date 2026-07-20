# Requirements Document

## Introduction

The AI Action Palette integrates structured AI-powered actions directly into the shell's overview/launcher search. Rather than requiring the user to open the AI sidebar for desktop automation tasks, the user types a natural-language query with an AI prefix (e.g., `?`) in the existing search bar. The system classifies the intent, sends it to the configured LLM with a specialized action-oriented system prompt, and returns structured proposed actions rendered as normal launcher entries with preview and apply controls. This makes AI feel desktop-native — integrated into the shell workflow rather than confined to a chatbot sidebar.

## Glossary

- **Action_Palette**: The search result area within the overview/launcher that displays AI-generated structured actions when the AI prefix is detected
- **AI_Prefix**: A configurable single-character prefix (default `?`) that triggers AI intent classification in the search bar
- **Action_Plan**: A structured JSON response from the LLM containing a summary and an ordered list of proposed actions
- **Proposed_Action**: A single atomic operation within an Action_Plan (e.g., `config.set`, `shell.exec`, `hyprland.dispatch`, `app.launch`)
- **Shell_Config**: The Quickshell configuration system managed through `Config.options` and editable via `Config.setNestedValue`
- **Overview**: The full-screen workspace overview and search interface triggered by the Super key
- **LLM**: The currently selected large language model configured in the AI service (Gemini, Mistral, OpenAI-compatible, or local Ollama)
- **Action_Context**: Runtime information about the desktop state provided to the LLM for accurate action generation (open windows, active workspace, audio state, etc.)

## Requirements

### Requirement 1: AI Prefix Detection

**User Story:** As a user, I want to type a `?` prefix in the overview search bar to trigger AI-powered action generation, so that I can issue natural-language commands without leaving the launcher.

#### Acceptance Criteria

1. WHEN the search text starts with the configured AI_Prefix followed by a space and at least one non-whitespace character, THE Action_Palette SHALL classify the input as an AI intent and suppress normal search results (app, action, clipboard, emoji, math, command, web-search)
2. THE Shell_Config SHALL expose a `search.prefix.ai` configuration key with a default value of `?` that accepts a string value of 1 to 3 characters in length, excluding whitespace-only values
3. WHEN the search text matches only the AI_Prefix, or the AI_Prefix followed by only whitespace, THE Action_Palette SHALL display a placeholder hint indicating the user can type a natural-language request
4. WHEN the AI_Prefix is changed via configuration, THE Action_Palette SHALL use the updated prefix for the next keystroke evaluation without requiring a shell restart
5. IF the configured AI_Prefix value is identical to another configured search prefix (`search.prefix.action`, `search.prefix.clipboard`, or `search.prefix.emojis`), THEN THE Action_Palette SHALL prioritize the AI prefix classification over the conflicting prefix

### Requirement 2: Action-Oriented LLM Request

**User Story:** As a user, I want the shell to send my natural-language query to the LLM with desktop context and a structured-output prompt, so that I receive actionable operations instead of conversational prose.

#### Acceptance Criteria

1. WHEN an AI intent is detected, THE Action_Palette SHALL send the user's query text (the input after the AI_Prefix and space) to the currently configured LLM using the existing AI service infrastructure (API strategies, model selection, API keys)
2. WHEN an AI intent is detected, THE Action_Palette SHALL include a specialized system prompt instructing the LLM to return only a valid JSON Action_Plan containing a `summary` string (maximum 200 characters) and an `actions` array (maximum 20 Proposed_Action objects)
3. WHEN an AI intent is detected, THE Action_Palette SHALL include Action_Context in the request containing: the current Shell_Config state, the list of open windows with their app IDs and workspace positions, and the active workspace identifier
4. WHEN the `policies.ai` configuration is set to `0` (disabled), THE Action_Palette SHALL not send any requests and SHALL display a message indicating that AI functionality is disabled by the `policies.ai` configuration
5. WHEN the `policies.ai` configuration is set to `2` (local only) and the current model endpoint does not contain "localhost", THE Action_Palette SHALL not send the request and SHALL display a message indicating that online models are disallowed by the `policies.ai` configuration
6. IF the LLM request fails due to a network error or receives no response within 30 seconds, THEN THE Action_Palette SHALL cancel the request, clear the loading state, and display an error message indicating the request failed with the option to retry

### Requirement 3: Action Plan Parsing and Validation

**User Story:** As a user, I want the system to validate the LLM's response before presenting it, so that I am not shown broken or dangerous actions.

#### Acceptance Criteria

1. WHEN the LLM returns a valid JSON Action_Plan, THE Action_Palette SHALL parse the response into a structured object with a `summary` string (maximum 500 characters) and an `actions` array (1 to 50 entries) of Proposed_Action objects
2. WHEN the LLM returns a response that is not valid JSON or does not conform to the Action_Plan schema, THE Action_Palette SHALL display an error message indicating the nature of the failure (malformed JSON or schema mismatch) with the option to retry the same query
3. THE Action_Palette SHALL validate that each Proposed_Action contains a `type` field matching one of the supported action types and the required parameters for that type: `config.set` requires `key` and `value`, `shell.exec` requires `command`, `hyprland.dispatch` requires `dispatcher` and `args`, `app.launch` requires `id`
4. WHEN a Proposed_Action has an unsupported `type` field or is missing required parameters for its type, THE Action_Palette SHALL mark that action as unrecognized and display it with a warning indicator
5. THE Action_Palette SHALL guarantee that for all valid Action_Plan objects, parsing then serializing then parsing produces a deeply equal object (round-trip property)
6. WHEN the LLM returns a valid JSON Action_Plan with an empty `actions` array, THE Action_Palette SHALL display the summary with a message indicating no actions were proposed and SHALL NOT show the [Apply] or [Preview] buttons

### Requirement 4: Action Results Display

**User Story:** As a user, I want AI-generated actions displayed as familiar launcher entries with a clear summary and per-action detail, so that I can understand what will happen before committing.

#### Acceptance Criteria

1. WHEN a valid Action_Plan is received, THE Action_Palette SHALL display a summary entry at the top showing the `summary` field (truncated to 120 characters with an ellipsis if longer) with a material icon indicating AI-generated content
2. THE Action_Palette SHALL display each Proposed_Action as a sub-item beneath the summary showing: for `config.set` actions the config key, current value, and proposed new value; for `shell.exec` actions the command string; for `hyprland.dispatch` actions the dispatcher name and arguments; for `app.launch` actions the application name or identifier
3. WHEN a `config.set` action references a key that exists in Shell_Config, THE Action_Palette SHALL display the transition as `current_value → new_value`
4. IF a `config.set` action references a key that does not exist in Shell_Config, THEN THE Action_Palette SHALL display the proposed value with an indicator that the key is new (no current value available)
5. WHEN a valid Action_Plan contains an empty `actions` array, THE Action_Palette SHALL display only the summary entry with the [Apply] and [Preview] buttons disabled
6. THE Action_Palette SHALL display an [Apply] button on the summary entry that executes all actions in the plan
7. THE Action_Palette SHALL display a [Preview] button on the summary entry that temporarily applies configuration changes for visual inspection without persisting them
8. WHILE the LLM is processing the request, THE Action_Palette SHALL display a loading indicator in place of results

### Requirement 5: Action Execution

**User Story:** As a user, I want to apply AI-generated actions with a single click and have dangerous actions gated behind confirmation, so that automation is fast but safe.

#### Acceptance Criteria

1. WHEN the user activates the [Apply] button, THE Action_Palette SHALL execute each Proposed_Action in the plan sequentially in the order specified by the `actions` array
2. WHEN a `config.set` action is executed, THE Action_Palette SHALL call `Config.setNestedValue` with the specified key and value
3. WHEN a `shell.exec` action is executed, THE Action_Palette SHALL display an approval prompt showing the full command text with [Approve] and [Reject] buttons, consistent with the existing command approval gate in the AI sidebar
4. IF the user rejects a `shell.exec` approval prompt, THEN THE Action_Palette SHALL stop execution of remaining actions and display a message indicating the plan was cancelled by the user
5. WHEN a `hyprland.dispatch` action is executed, THE Action_Palette SHALL call `hyprctl dispatch` with the specified dispatcher and arguments
6. WHEN an `app.launch` action is executed, THE Action_Palette SHALL launch the application using the desktop entry matching the specified app identifier
7. IF an `app.launch` action references an app identifier with no matching desktop entry, THEN THE Action_Palette SHALL treat the action as failed
8. WHEN any action in the plan fails, THE Action_Palette SHALL stop execution of remaining actions, display a message indicating which action failed and the reason, and offer to undo already-applied `config.set` changes by restoring their previous values
9. IF a `shell.exec` command does not complete within 30 seconds, THEN THE Action_Palette SHALL terminate the process and treat the action as failed
10. WHEN all actions complete successfully, THE Action_Palette SHALL close the overview

### Requirement 6: Preview Mode

**User Story:** As a user, I want to preview configuration changes before committing them, so that I can verify the visual result of AI-suggested modifications.

#### Acceptance Criteria

1. WHEN the user activates the [Preview] button, THE Action_Palette SHALL temporarily apply only the `config.set` actions from the Action_Plan without writing changes to persistent storage, skipping any `shell.exec`, `hyprland.dispatch`, or `app.launch` actions
2. WHILE preview mode is active, THE Action_Palette SHALL display a floating indicator showing "Previewing changes" with [Commit] and [Revert] buttons
3. WHEN the user activates [Commit] during preview, THE Action_Palette SHALL persist all previewed changes to the Shell_Config file and close the overview
4. WHEN the user activates [Revert] during preview, THE Action_Palette SHALL restore all configuration values to their pre-preview state
5. IF the user closes the overview while preview mode is active, THEN THE Action_Palette SHALL automatically revert all previewed changes
6. IF a `config.set` action fails during preview application (invalid key or rejected value), THEN THE Action_Palette SHALL revert any already-applied preview changes, exit preview mode, and display an error message indicating which action failed

### Requirement 7: Debounced Input and Cancellation

**User Story:** As a user, I want the system to wait briefly before sending my query and allow me to cancel in-flight requests, so that I am not rate-limited by typing speed.

#### Acceptance Criteria

1. WHEN the user is typing an AI query, THE Action_Palette SHALL wait until no keystroke has occurred for the duration specified by `search.aiDebounceMs` before sending the request to the LLM
2. WHEN the user modifies the search text while a request is in-flight, THE Action_Palette SHALL cancel the pending request, remove the loading indicator, and restart the debounce timer
3. WHEN the user clears the search bar or removes the AI_Prefix, THE Action_Palette SHALL cancel any in-flight request, remove the loading indicator, and clear the results area
4. THE Shell_Config SHALL expose a `search.aiDebounceMs` configuration key for the debounce duration with a default value of 600, accepting integer values between 100 and 5000 milliseconds inclusive
5. IF `search.aiDebounceMs` is set to a value outside the range of 100 to 5000 or is not a valid integer, THEN THE Shell_Config SHALL use the default value of 600

### Requirement 8: Integration with Existing AI Configuration

**User Story:** As a user, I want the Action Palette to use my existing AI model, API keys, and tool configuration, so that I do not need to configure AI separately for the launcher.

#### Acceptance Criteria

1. THE Action_Palette SHALL use the model specified by `Ai.currentModelId` for all AI requests
2. THE Action_Palette SHALL use the API key stored in `KeyringStorage` for the current model's `key_id`
3. IF no API key is configured for the current model and the model requires one, THEN THE Action_Palette SHALL display a message directing the user to set an API key via the AI sidebar `/key` command
4. THE Action_Palette SHALL apply the value of `Ai.temperature` (within the range 0.0 to 2.0) as the temperature parameter for AI request generation
5. WHEN the current model is changed in the AI sidebar, THE Action_Palette SHALL use the newly selected model for the next request issued after the change, without requiring the Action Palette to be reopened
6. IF `Ai.currentModelId` is not set or references a model that is unavailable, THEN THE Action_Palette SHALL display a message directing the user to select a model via the AI sidebar
