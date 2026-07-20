# Implementation Plan: AI Provider Sign-in and Model Discovery

## Overview

Implements a dedicated AI Provider Sign-in panel as a new tab in the left sidebar, replacing the hardcoded model list in Ai.qml with dynamic model discovery. The implementation proceeds in layers: service singleton with pure logic functions → sidebar tab integration → provider list UI → per-provider detail view (key input, validation, models) → custom provider form (add/edit/delete OpenAI-compatible endpoints) → Ai.qml refactor to remove hardcoded models → property-based tests for pure logic. Each layer builds on the previous, ensuring incremental integration.

## Tasks

- [x] 1. Create ModelDiscoveryService singleton with provider configs and pure logic
  - [x] 1.1 Create ModelDiscoveryService.qml with provider configuration registry
    - Create `services/ModelDiscoveryService.qml` as a `pragma Singleton` with `pragma ComponentBehavior: Bound`
    - Define the `providerConfigs` readonly property with all 6 built-in provider entries (openai, anthropic, gemini, mistral, openrouter, ollama) including endpoints, auth_type, api_format, icons, supports_balance
    - Declare state properties: `validationStates` (object), `discoveredModels` (object), `balances` (object)
    - Add `customProviders` property bound to `Config.options.ai.customProviders || []`
    - Register in `services/qmldir` as `singleton ModelDiscoveryService 1.0 ModelDiscoveryService.qml`
    - Use indexed for loops, no spread operator, no replaceAll
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 1.7_

  - [x] 1.2 Implement buildValidationCommand pure function
    - Takes `providerId` and `apiKey`, returns `{endpoint, auth, command}` or `null`
    - Handle auth_type "bearer" → `-H "Authorization: Bearer <key>"`
    - Handle auth_type "x-api-key" → `-H "x-api-key: <key>" -H "anthropic-version: 2023-06-01"`
    - Handle auth_type "query_param" → append `?key=<key>` to endpoint
    - Handle auth_type "none" → no auth headers (Ollama)
    - Build command as `["bash", "-c", 'curl -s -w "\\n%{http_code}" "<endpoint>" <authPart>']`
    - Support custom providers: look up in customProviders array if not in providerConfigs
    - File: `services/ModelDiscoveryService.qml`
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 1.7_

  - [x] 1.3 Implement mapErrorResponse pure function
    - Takes `httpStatus` (int) and `responseBody` (string)
    - Return "Invalid or revoked API key" for 401/403
    - Return "Rate limited — try again later" for 429
    - Return "Insufficient credits or quota exceeded" for 402 or body containing quota/credit/billing/insufficient
    - Return "Key lacks required permissions" for body containing permission/scope
    - Return "Network error — check your connection" for status 0
    - Return "Error {status}: {body}" for all other cases
    - Use `indexOf` for string matching (no includes)
    - File: `services/ModelDiscoveryService.qml`
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_

  - [x] 1.4 Implement formatModelName pure function
    - Takes `modelId` string, returns human-friendly display name
    - Replace hyphens and colons with spaces using `.replace(/-/g, " ").replace(/:/g, " ")`
    - Capitalize each word (first char uppercase)
    - Format parameter-count suffixes like "7b" → "(7B)"
    - Remove "Latest" trailing word
    - Use indexed for loop over words array
    - File: `services/ModelDiscoveryService.qml`
    - _Requirements: 11.7_

  - [x] 1.5 Implement parseModelListResponse pure function
    - Takes `providerId` and `responseBody`, returns array of raw model data objects
    - For ollama: return `json.models || []`
    - For gemini: return `json.models || []`
    - For openai/anthropic/mistral/openrouter and custom providers: return `json.data || []`
    - Wrap in try/catch, return `[]` on parse failure
    - File: `services/ModelDiscoveryService.qml`
    - _Requirements: 6.1, 6.2, 1.7_

  - [x] 1.6 Implement mapModelToAiModel pure function
    - Takes `providerId` and `modelData` object, returns AiModel-compatible property object
    - Extract model ID: ollama uses `modelData.name || modelData.model`, gemini strips "models/" prefix, others use `modelData.id`
    - Set `api_format`, `endpoint`, `key_id`, `requires_key` from provider config
    - For gemini: substitute `{model}` in `chat_endpoint_template`
    - For custom providers: use their stored base URL + `/v1/chat/completions`
    - Set `name` via `formatModelName(modelId)`, `icon` from config, `description` as "Provider | modelId"
    - File: `services/ModelDiscoveryService.qml`
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.8, 1.7_

  - [x] 1.7 Implement getEffectiveProviderConfig helper function
    - Takes `providerId`, returns the config object from `providerConfigs` or from `customProviders` array
    - For built-in providers: return `providerConfigs[providerId]`
    - For custom providers: find in `Config.options.ai.customProviders` by id, construct config object with auth_type "bearer" (if key provided) or "none", api_format "openai", model_endpoint as `baseUrl + "/models"`, chat_endpoint as `baseUrl + "/chat/completions"`
    - File: `services/ModelDiscoveryService.qml`
    - _Requirements: 1.7_

- [x] 2. Implement ModelDiscoveryService side-effect functions (validation, discovery, balance)
  - [x] 2.1 Implement validateKey with Process-based curl execution
    - Create Process component for validation requests
    - On call: set `validationStates[providerId] = { status: "loading", message: "" }` (reassign via Object.assign for reactivity)
    - Build command via `buildValidationCommand`, launch Process
    - On stdout: split body from last-line HTTP status code
    - On success (2xx): set status "success", store key via `KeyringStorage.setNestedField(["apiKeys", config.key_id], apiKey)`, trigger `discoverModels(providerId)`
    - On failure: set status "error" with message from `mapErrorResponse`
    - Support custom provider IDs (look up via getEffectiveProviderConfig)
    - File: `services/ModelDiscoveryService.qml`
    - _Requirements: 2.2, 3.2, 3.3, 3.4, 1.7_

  - [x] 2.2 Implement discoverModels with Process-based curl execution
    - Create Process component for model listing requests
    - Build curl command targeting `model_endpoint` with same auth as validation
    - On stdout: parse via `parseModelListResponse`, map each entry via `mapModelToAiModel`
    - Store results in `discoveredModels[providerId]` (reassign root object for reactivity)
    - Add `isRefreshing(providerId)` helper function
    - Support custom provider IDs
    - File: `services/ModelDiscoveryService.qml`
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 8.2, 1.7_

  - [x] 2.3 Implement fetchBalance for supported providers
    - Only execute for providers where `supports_balance` is true (OpenAI, OpenRouter)
    - Curl GET to `balance_endpoint` with auth headers
    - Parse response and store in `balances[providerId]`
    - Call on successful validation and on model refresh
    - File: `services/ModelDiscoveryService.qml`
    - _Requirements: 9.1, 9.2, 9.3_

- [x] 3. Checkpoint — ModelDiscoveryService verified
  - Ensure ModelDiscoveryService.qml loads without errors, qmldir is correct, pure functions can be called. Ask the user if questions arise.

- [x] 4. Provider Panel UI components
  - [x] 4.1 Create ProviderPanel.qml main tab component
    - Create `modules/sidebarLeft/ProviderPanel.qml`
    - Define `selectedProvider` string property and `providerList` computed from `Config.options.policies.ai`
    - When `policies.ai === 2`: show `["ollama"]` plus custom providers with localhost base URLs
    - Otherwise: show all 6 built-in providers plus all custom providers
    - Add "Add Custom" button at the bottom of the provider list
    - Layout: ListView of providers when none selected, ProviderDetailView when one is selected, CustomProviderForm when adding/editing
    - File: `modules/sidebarLeft/ProviderPanel.qml`
    - _Requirements: 1.1, 1.2, 1.4, 1.5, 1.6_

  - [x] 4.2 Create ProviderListItem.qml delegate
    - Create `modules/sidebarLeft/ProviderListItem.qml`
    - Display provider icon (from `ModelDiscoveryService.providerConfigs[providerId].icon`) and name
    - Show validation status indicator (green dot for success, nothing for idle)
    - Emit `clicked` signal for navigation to detail view
    - Support custom provider entries (icon defaults to "ai-openai-symbolic" for custom)
    - File: `modules/sidebarLeft/ProviderListItem.qml`
    - _Requirements: 1.2_

  - [x] 4.3 Create ProviderDetailView.qml with key input and debounce
    - Create `modules/sidebarLeft/ProviderDetailView.qml`
    - Required property `providerId`, signal `back()`
    - Back button + provider name + icon header row
    - API key TextField with `echoMode: TextInput.Password` (hidden for Ollama and custom providers with no key via `visible: config.requires_key`)
    - Pre-populate key from `KeyringStorage.keyringData` if stored
    - Timer component with 1000ms interval for debounce; restart on `onTextChanged`
    - On timer triggered: call `ModelDiscoveryService.validateKey(providerId, keyInput.text)`
    - Clear/remove button when key exists
    - For custom providers: add edit and delete buttons in the header
    - File: `modules/sidebarLeft/ProviderDetailView.qml`
    - _Requirements: 1.3, 2.1, 2.2, 2.3, 2.4, 2.5, 3.1_

  - [x] 4.4 Add validation status indicators and re-test button
    - BusyIndicator visible when `validationState.status === "loading"`
    - Green checkmark icon when status is "success"
    - Red error icon when status is "error"
    - Error message Label below key input (visible on error, shows `validationState.message`)
    - Re-test IconButton: visible when key exists, disabled during loading, calls `validateKey` directly (bypasses debounce)
    - File: `modules/sidebarLeft/ProviderDetailView.qml`
    - _Requirements: 3.3, 3.4, 3.5, 4.1, 4.2, 4.3, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_

  - [x] 4.5 Add model list section and refresh button to ProviderDetailView
    - Models header with refresh IconButton (visible when validated or no key required)
    - BusyIndicator on refresh button while `isRefreshing(providerId)`
    - ListView bound to `ModelDiscoveryService.discoveredModels[providerId] || []`
    - File: `modules/sidebarLeft/ProviderDetailView.qml`
    - _Requirements: 6.1, 6.2, 8.1, 8.2, 8.3, 8.4_

  - [x] 4.6 Create ModelListItem.qml delegate
    - Create `modules/sidebarLeft/ModelListItem.qml`
    - Display model name and model ID (smaller text)
    - Show provider icon
    - File: `modules/sidebarLeft/ModelListItem.qml`
    - _Requirements: 6.2_

  - [x] 4.7 Add balance display to ProviderDetailView
    - RowLayout visible when `config.supports_balance && validationState.status === "success"`
    - Display "Balance:" label and value from `ModelDiscoveryService.balances[providerId]`
    - Omit entirely for providers that don't support it
    - File: `modules/sidebarLeft/ProviderDetailView.qml`
    - _Requirements: 9.1, 9.2, 9.3_

- [x] 5. Integrate Provider Panel into sidebar and modify SidebarLeftContent
  - [x] 5.1 Add Providers tab to SidebarLeftContent.qml tabButtonList
    - Add `{"icon": "key", "name": Translation.tr("Providers")}` entry to `tabButtonList` when `policies.ai !== 0`
    - Position after the Intelligence tab
    - Use `Object.assign` or `concat` for array composition (no spread)
    - File: `modules/sidebarLeft/SidebarLeftContent.qml`
    - _Requirements: 1.1, 1.4_

  - [x] 5.2 Add ProviderPanel to contentChildren in SidebarLeftContent.qml
    - Create `Component { id: providerPanel; ProviderPanel {} }`
    - Add to contentChildren array in the correct position (after aiChat)
    - File: `modules/sidebarLeft/SidebarLeftContent.qml`
    - _Requirements: 1.1_

- [x] 6. Checkpoint — Provider Panel UI loads and navigates
  - Ensure the Providers tab appears in the sidebar, clicking a provider shows the detail view, back button works, key input is masked. Ask the user if questions arise.

- [x] 7. Custom Provider UI and Persistence
  - [x] 7.1 Create CustomProviderForm.qml component
    - Create `modules/sidebarLeft/CustomProviderForm.qml`
    - Signal `back()`, optional property `editingProvider` (null for add, object for edit)
    - TextField for display name (required, placeholder: "My vLLM Server")
    - TextField for base URL (required, placeholder: "http://localhost:5000/v1")
    - TextField for optional API key (`echoMode: TextInput.Password`)
    - "Save" button: validates fields (name non-empty, URL non-empty and starts with http), then calls save function
    - "Cancel" button: emits `back()` signal
    - When editing: pre-populate fields from `editingProvider`, show "Delete" button
    - File: `modules/sidebarLeft/CustomProviderForm.qml`
    - _Requirements: 1.6_

  - [x] 7.2 Implement custom provider persistence functions
    - Add `addCustomProvider(name, baseUrl, apiKey)` to ModelDiscoveryService
    - Generate unique ID: `"custom-" + Date.now()` (or sanitized name)
    - Build provider entry: `{ id, name, baseUrl, apiKey, icon: "ai-openai-symbolic", auth_type: apiKey ? "bearer" : "none", api_format: "openai", requires_key: apiKey !== "" }`
    - Read current array from `Config.options.ai.customProviders || []`
    - Append new entry and write back via `Config.setNestedField(["ai", "customProviders"], newArray)`
    - If apiKey provided, store in KeyringStorage: `KeyringStorage.setNestedField(["apiKeys", id], apiKey)`
    - Trigger `discoverModels(id)` after save
    - File: `services/ModelDiscoveryService.qml`
    - _Requirements: 1.6, 1.7_

  - [x] 7.3 Implement custom provider edit and delete functions
    - Add `updateCustomProvider(id, name, baseUrl, apiKey)` to ModelDiscoveryService
    - Find provider in `Config.options.ai.customProviders` by id, update fields
    - Write updated array back to Config
    - Update KeyringStorage key if changed
    - Re-trigger `discoverModels(id)` after edit
    - Add `deleteCustomProvider(id)` to ModelDiscoveryService
    - Remove from `Config.options.ai.customProviders` array
    - Remove from `KeyringStorage.keyringData.apiKeys` if present
    - Remove from `discoveredModels[id]` and `validationStates[id]`
    - Reassign objects via Object.assign for reactivity
    - File: `services/ModelDiscoveryService.qml`
    - _Requirements: 1.7_

  - [x] 7.4 Implement custom provider validation and model discovery
    - Custom providers use OpenAI-compatible endpoint conventions
    - Validation: GET `baseUrl + "/models"` with bearer auth (if key) or no auth
    - Model discovery: same endpoint, parse `json.data || []` (OpenAI format)
    - Map models via `mapModelToAiModel` using the custom provider's config
    - Chat endpoint: `baseUrl + "/chat/completions"`
    - Handle connection refused gracefully (localhost servers may be offline)
    - File: `services/ModelDiscoveryService.qml`
    - _Requirements: 1.7_

  - [x] 7.5 Wire CustomProviderForm into ProviderPanel navigation
    - Add `showCustomForm` boolean state and `editingCustomProvider` property to ProviderPanel
    - "Add Custom" button sets `showCustomForm = true, editingCustomProvider = null`
    - Edit button in ProviderDetailView (for custom providers) sets `showCustomForm = true, editingCustomProvider = currentProvider`
    - CustomProviderForm `back()` signal resets to provider list
    - On successful save, reset to provider list and auto-select the new provider
    - File: `modules/sidebarLeft/ProviderPanel.qml`
    - _Requirements: 1.6_

- [x] 8. Checkpoint — Custom providers work end-to-end
  - Ensure "Add Custom" opens the form, saving persists to Config.options.ai.customProviders, custom provider appears in list, validation and model discovery work against OpenAI-compatible endpoints, editing and deleting work. Ask the user if questions arise.

- [x] 9. Refactor Ai.qml to remove hardcoded models
  - [x] 9.1 Remove hardcoded models property from Ai.qml
    - Delete the entire `property var models: { ... }` object literal containing hardcoded model entries (gemini-2.0-flash, gpt-4.1-mini, etc.)
    - Replace with a computed `models` property that merges `ModelDiscoveryService.discoveredModels` (built-in + custom providers) and `Config.options.ai.extraModels`
    - Use indexed for loops to iterate provider keys and model arrays
    - Use `Object.assign({}, ...)` for object reactivity
    - Keep `modelList: Object.keys(root.models)` binding
    - File: `services/Ai.qml`
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [x] 9.2 Remove getOllamaModels Process from Ai.qml
    - Delete the existing `Process` component that queries `http://localhost:11434/api/tags`
    - Delete associated Ollama model parsing logic
    - Ollama discovery is now handled by ModelDiscoveryService
    - File: `services/Ai.qml`
    - _Requirements: 6.3, 7.1_

  - [x] 9.3 Add safeModelName helper if not already present
    - Ensure a `safeModelName(modelId)` function exists that sanitizes model IDs for use as object keys (replace special chars)
    - Used when building the `models` registry from discovered models
    - File: `services/Ai.qml`
    - _Requirements: 7.2_

- [x] 10. Checkpoint — Dynamic model registry works end-to-end
  - Ensure Ai.qml loads, model registry is empty when no providers are authenticated, extraModels from config appear, validating a key triggers model discovery that populates the registry, custom provider models also appear in registry. Ask the user if questions arise.

- [x] 11. Extract pure logic to testable JS module and write property-based tests
  - [x] 11.1 Extract ModelDiscoveryService pure functions to testable JS module
    - Create `tests/js/src/model-discovery-logic.js`
    - Port `buildValidationCommand`, `mapErrorResponse`, `formatModelName`, `mapModelToAiModel`, `parseModelListResponse`, `getEffectiveProviderConfig` as ES module exports
    - Include the `providerConfigs` constant for test reference
    - Include a sample custom provider config for testing custom provider paths
    - Ensure no QML-specific dependencies — plain JavaScript compatible with Node.js
    - Maintain identical logic to the QML implementations
    - _Requirements: Design Testing Strategy_

  - [x] 11.2 Write property test: Validation Endpoint Construction (Property 3)
    - **Property 3: Validation Endpoint Construction**
    - For any provider ID in {openai, anthropic, gemini, mistral, openrouter, ollama} and any non-empty API key: `buildValidationCommand` produces correct endpoint and auth scheme per provider config
    - Bearer token for openai/mistral/openrouter, x-api-key header for anthropic, query param for gemini, no auth for ollama
    - File: `tests/js/src/model-discovery-logic.test.js`
    - **Validates: Requirements 10.1, 10.2, 10.3, 10.4, 10.5, 10.6**

  - [x] 11.3 Write property test: Error Response Mapping Completeness (Property 4)
    - **Property 4: Error Response Mapping Completeness**
    - For any HTTP status code (0–599) and any response body string: `mapErrorResponse` returns a non-empty string
    - 401/403 → "Invalid or revoked API key", 429 → "Rate limited — try again later", 402 or quota keywords → "Insufficient credits or quota exceeded", permission keywords → "Key lacks required permissions", 0 → "Network error — check your connection"
    - File: `tests/js/src/model-discovery-logic.test.js`
    - **Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.6**

  - [x] 11.4 Write property test: Model Registry Composition (Property 5)
    - **Property 5: Model Registry Composition**
    - For any combination of discovered model sets (including custom providers) and extraModels config array: registry contains exactly the union, extraModels always present regardless of auth state
    - File: `tests/js/src/model-discovery-logic.test.js`
    - **Validates: Requirements 7.2, 7.4**

  - [x] 11.5 Write property test: Model Metadata Mapping Correctness (Property 6)
    - **Property 6: Model Metadata Mapping Correctness**
    - For any provider ID (built-in or custom) and valid model data: `mapModelToAiModel` produces correct `api_format`, `endpoint`, `key_id`, `requires_key` per provider config
    - Ollama: requires_key=false, key_id=""
    - Gemini: endpoint uses template with model substitution
    - Custom: api_format="openai", endpoint=baseUrl+"/chat/completions"
    - File: `tests/js/src/model-discovery-logic.test.js`
    - **Validates: Requirements 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 1.7**

  - [x] 11.6 Write property test: Discovery and Validation Share Endpoints (Property 7)
    - **Property 7: Discovery and Validation Share Endpoints**
    - For every built-in provider ID: `providerConfigs[id].validation_endpoint === providerConfigs[id].model_endpoint`
    - For custom providers: validation and model discovery both use `baseUrl + "/models"`
    - File: `tests/js/src/model-discovery-logic.test.js`
    - **Validates: Requirements 10.7**

  - [x] 11.7 Write property test: Model Name Formatting (Property 8)
    - **Property 8: Model Name Formatting**
    - For any model ID string (non-empty, alphanumeric + hyphens/colons/dots): `formatModelName` returns a string with capitalized word-segments, hyphens→spaces, param suffixes like "7b" → "(7B)"
    - File: `tests/js/src/model-discovery-logic.test.js`
    - **Validates: Requirements 11.7**

  - [x] 11.8 Write property test: API Key Storage Round-Trip (Property 1)
    - **Property 1: API Key Storage Round-Trip**
    - For any provider key_id and non-empty key string: storing then reading from a mock KeyringStorage returns the exact same key
    - File: `tests/js/src/model-discovery-logic.test.js`
    - **Validates: Requirements 2.2**

  - [x] 11.9 Write property test: Custom Provider Config Construction
    - **Property 9: Custom Provider Config Construction**
    - For any non-empty name, valid URL string, and optional API key: `getEffectiveProviderConfig` for a custom provider returns api_format "openai", model_endpoint ending in "/models", chat_endpoint ending in "/chat/completions", and auth_type "bearer" iff apiKey is non-empty
    - File: `tests/js/src/model-discovery-logic.test.js`
    - **Validates: Requirements 1.7**

- [x] 12. Checkpoint — All property tests pass
  - Ensure all property tests pass with `vitest run` in `tests/js/`. Ask the user if questions arise.

- [x] 13. Integration tests
  - [x] 13.1 Write integration test: validation flow with mocked curl responses
    - Mock Process output for success (200 + model list JSON) and failure (401, 429, 0) scenarios
    - Verify validation state transitions: idle → loading → success/error
    - Verify successful validation triggers model discovery
    - Verify key is stored in KeyringStorage on success
    - File: `tests/js/src/model-discovery-integration.test.js`
    - _Requirements: 2.2, 3.2, 3.3, 3.4, 3.5_

  - [x] 13.2 Write integration test: model discovery and registry population
    - Mock model list responses for each provider format (ollama models[], gemini models[], openai data[])
    - Verify parsed models are correctly mapped to AiModel properties
    - Verify Ai.models registry contains discovered + extraModels
    - Include custom provider mock responses (OpenAI-compatible data[] format)
    - File: `tests/js/src/model-discovery-integration.test.js`
    - _Requirements: 6.1, 6.2, 7.2, 7.4, 1.7_

  - [x] 13.3 Write integration test: policy enforcement and provider visibility
    - Verify policies.ai=0 hides provider tab entirely
    - Verify policies.ai=2 shows only Ollama and custom providers with localhost URLs
    - Verify policies.ai=1 shows all built-in providers and all custom providers
    - File: `tests/js/src/model-discovery-integration.test.js`
    - _Requirements: 1.1, 1.4, 1.5_

  - [x] 13.4 Write integration test: custom provider CRUD operations
    - Verify addCustomProvider persists to Config.options.ai.customProviders
    - Verify updateCustomProvider updates the correct entry
    - Verify deleteCustomProvider removes entry and cleans up discoveredModels/validationStates
    - Verify custom provider appears in provider list after add
    - File: `tests/js/src/model-discovery-integration.test.js`
    - _Requirements: 1.6, 1.7_

- [x] 14. Final checkpoint — All tests pass, feature complete
  - Ensure all property tests and integration tests pass, all QML files load without errors, Provider Panel navigates correctly, validation triggers model discovery, Ai.models reflects discovered models, custom providers can be added/edited/deleted and their models appear in the registry. Ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation between phases
- Property tests use fast-check + vitest (existing infrastructure at `tests/js/`)
- Pure logic functions are extracted from ModelDiscoveryService.qml into a testable JS module
- QML constraints: no spread operator (use Object.assign), no replaceAll (use split/join), indexed for loops, Process for curl, pragma Singleton + ComponentBehavior: Bound
- Object reactivity in QML requires reassigning root objects — use `Object.assign({}, oldObj)` pattern to trigger change notifications
- The debounce timer (1000ms) ensures validation only fires after the user stops typing
- ModelDiscoveryService uses the same endpoint for both validation and model listing (Property 7)
- Balance display is only shown for OpenAI and OpenRouter (providers with `supports_balance: true`)
- Custom providers use OpenAI-compatible endpoint conventions: `/v1/models` for discovery, `/v1/chat/completions` for chat
- Custom providers are stored in `Config.options.ai.customProviders` as an array of objects with `{id, name, baseUrl, apiKey, icon}`
- In local-only mode (policies.ai=2), custom providers with localhost/127.0.0.1 base URLs are shown alongside Ollama

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7"] },
    { "id": 1, "tasks": ["2.1", "2.2", "2.3"] },
    { "id": 2, "tasks": ["4.1", "4.2", "4.6"] },
    { "id": 3, "tasks": ["4.3", "4.4", "4.5", "4.7"] },
    { "id": 4, "tasks": ["5.1", "5.2"] },
    { "id": 5, "tasks": ["7.1", "7.2", "7.3"] },
    { "id": 6, "tasks": ["7.4", "7.5"] },
    { "id": 7, "tasks": ["9.1", "9.2", "9.3"] },
    { "id": 8, "tasks": ["11.1"] },
    { "id": 9, "tasks": ["11.2", "11.3", "11.4", "11.5", "11.6", "11.7", "11.8", "11.9"] },
    { "id": 10, "tasks": ["13.1", "13.2", "13.3", "13.4"] }
  ]
}
```
