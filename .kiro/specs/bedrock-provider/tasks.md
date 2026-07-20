# Implementation Plan: Bedrock Provider

## Overview

Adds AWS Bedrock as a first-class AI provider, delegating all API calls to the `aws` CLI for SigV4 signing. Implementation layers: AwsCredentialReader singleton for credential/region detection → Bedrock provider config + validation/discovery in ModelDiscoveryService → BedrockApiStrategy + bedrockRequester in Ai.qml → Bedrock-specific UI in ProviderDetailView → extracted pure functions for property-based tests. Each layer builds on the previous, and the `aws` CLI subprocess pattern (Process + SplitParser) is used for validation, discovery, and chat streaming.

## Tasks

- [x] 1. Create AwsCredentialReader singleton and Bedrock provider config
  - [x] 1.1 Create AwsCredentialReader.qml singleton
    - Create `configs/quickshell/services/AwsCredentialReader.qml` with `pragma Singleton` and `pragma ComponentBehavior: Bound`
    - Define state properties: `credentialsFilePath` (string), `credentialsDetected` (bool), `region` (string, default "us-west-2"), `awsCliAvailable` (bool), `statusMessage` (string)
    - On `Component.onCompleted`: run `which aws` via Process to check CLI availability, set `awsCliAvailable` based on exit code
    - Check `~/.aws/credentials.bedrock` existence via Process (`test -f`), fall back to `~/.aws/credentials`
    - Parse `~/.aws/config` for `[default]` profile `region` value using Process + cat + JS parsing
    - Register in `services/qmldir` as `singleton AwsCredentialReader 1.0 AwsCredentialReader.qml`
    - Use indexed for loops, no spread operator, no replaceAll (use split/join)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 7.1, 7.2, 9.1, 9.2_

  - [x] 1.2 Add Bedrock provider config entry to ModelDiscoveryService.qml
    - Add `"bedrock"` key to the `providerConfigs` readonly property object
    - Set: `name: "AWS Bedrock"`, `icon: "aws-bedrock-symbolic"`, `key_id: "bedrock"`, `requires_key: false`, `auth_type: "aws_cli"`, `api_format: "bedrock"`, `supports_balance: false`
    - No `validation_endpoint` or `model_endpoint` URLs — these are handled by CLI commands
    - _Requirements: 1.1, 1.3, 1.4_

  - [x] 1.3 Extract Bedrock pure functions to testable JS module
    - Create `tests/js/src/bedrock-logic.js` as an ES module
    - Export `parseBedrockModelList(jsonString)` — parses JSON, filters for ON_DEMAND + ACTIVE models
    - Export `mapBedrockModelToAiModel(modelData)` — maps modelSummary fields to AiModel properties
    - Export `formatModelName(rawName)` — capitalizes words, replaces dashes/colons with spaces, formats param suffixes like "7b" → "(7B)", removes trailing "Latest"
    - Export `buildRequestData(messages, systemPrompt)` — converts messages to Bedrock Converse format with content blocks
    - Export `parseResponseLine(line, message)` — parses converse-stream JSON events, returns `{ finished, error }`
    - Export `parseAwsRegion(configFileContent)` — extracts region from AWS config file format
    - Ensure no QML-specific dependencies — plain JavaScript compatible with Node.js
    - _Requirements: 4.2, 4.3, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.2, 6.3, 6.5, 6.6, 7.1, 7.2_

- [x] 2. Implement Bedrock validation and model discovery in ModelDiscoveryService
  - [x] 2.1 Add Bedrock validation process and logic to ModelDiscoveryService.qml
    - Add a `bedrockValidationProcess` Process component that runs `aws bedrock list-foundation-models --max-results 1 --region <region> --output json`
    - Set `AWS_SHARED_CREDENTIALS_FILE` environment variable from `AwsCredentialReader.credentialsFilePath`
    - Add `validateBedrock()` function: check `AwsCredentialReader.awsCliAvailable` and `credentialsDetected` first, then launch process
    - On exit code 0: set `validationStates["bedrock"] = { status: "success", message: "" }`, trigger `discoverBedrockModels()`
    - On non-zero exit: set `validationStates["bedrock"] = { status: "error", message: <stderr> }`
    - Use StdioCollector or SplitParser for stdout/stderr collection
    - Reassign `validationStates` via `Object.assign` for QML reactivity
    - _Requirements: 3.2, 3.3, 3.4, 3.5, 3.6_

  - [x] 2.2 Add Bedrock model discovery process and parsing to ModelDiscoveryService.qml
    - Add `bedrockDiscoveryProcess` Process component that runs `aws bedrock list-foundation-models --region <region> --output json`
    - Set `AWS_SHARED_CREDENTIALS_FILE` in process environment
    - On stdout complete: parse JSON, call `parseBedrockModelList` logic (filter ON_DEMAND + ACTIVE), then `mapBedrockModelToAiModel` for each
    - Store results in `discoveredModels["bedrock"]` (reassign root object for reactivity)
    - On failure: set discovered models to empty array, log error
    - Wire refresh button support: `discoverModels("bedrock")` should trigger this process
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_

- [x] 3. Implement BedrockApiStrategy and bedrockRequester in Ai.qml
  - [x] 3.1 Create BedrockApiStrategy.qml
    - Create `configs/quickshell/services/ai/BedrockApiStrategy.qml`
    - Implement ApiStrategy interface: `buildEndpoint`, `buildRequestData`, `buildAuthorizationHeader`, `parseResponseLine`, `onRequestFinished`, `reset`
    - `buildEndpoint` returns `"aws-bedrock-converse"` sentinel
    - `buildRequestData`: convert messages to `{ role, content: [{ text }] }` format, separate system prompt into `system: [{ text }]`
    - `buildAuthorizationHeader` returns `""` (auth via env var)
    - `parseResponseLine`: handle `messageStart`, `contentBlockDelta` (extract `.delta.text`), `contentBlockStop`, `messageStop`, `metadata` events
    - `onRequestFinished`: return `{}`
    - Use indexed for loops, no spread, no replaceAll
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_

  - [x] 3.2 Add bedrockRequester Process and strategy registration to Ai.qml
    - Add `property Component bedrockApiStrategy: BedrockApiStrategy {}` alongside existing strategies
    - Register `"bedrock"` in the `apiStrategies` map (or equivalent strategy lookup)
    - Add `bedrockRequester` Process component with `SplitParser` on stdout
    - Build command dynamically: `aws bedrock-runtime converse-stream --model-id <modelId> --messages '<json>' --system '<json>' --region <region> --output json`
    - Set `AWS_SHARED_CREDENTIALS_FILE` in process environment from `AwsCredentialReader.credentialsFilePath`
    - On `SplitParser.onRead`: call `BedrockApiStrategy.parseResponseLine(data, message)`
    - On `onExited`: exit code 0 → mark message complete; non-zero → append stderr as error, mark failed
    - Modify `makeRequest` (or equivalent entry point) to branch: if `api_format === "bedrock"`, use `bedrockRequester` instead of curl
    - Support cancel: on user cancel, call `bedrockRequester.signal(Process.SIGTERM)` or equivalent kill
    - _Requirements: 6.4, 6.7, 10.1, 10.2, 10.3, 10.4, 10.5_

- [x] 4. Checkpoint — Bedrock validation, discovery, and chat strategy wired
  - Ensure AwsCredentialReader detects credentials, ModelDiscoveryService can validate and discover Bedrock models, BedrockApiStrategy parses stream events, and Ai.qml dispatches to bedrockRequester for bedrock models. Ask the user if questions arise.

- [x] 5. Add Bedrock UI section to ProviderDetailView and update ProviderPanel
  - [x] 5.1 Add Bedrock-specific section to ProviderDetailView.qml
    - Add a `ColumnLayout` visible when `config.auth_type === "aws_cli"` (after the existing API key section)
    - Show credential status: file path (read-only StyledText) from `AwsCredentialReader.credentialsFilePath`, or "No credentials found" message with instructions
    - Show region display: read-only StyledText from `AwsCredentialReader.region`
    - Show AWS CLI availability status: error message "AWS CLI not found. Install the aws-cli package to use Bedrock." when `!AwsCredentialReader.awsCliAvailable`
    - Add "Test Connection" button (RippleButton): visible when credentials detected AND CLI available, disabled during loading, calls `ModelDiscoveryService.validateBedrock()`
    - Show validation status indicators (BusyIndicator, success/error icons) consistent with existing pattern
    - Hide the API key input section for Bedrock (already handled by `requires_key: false`)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.3, 3.4, 3.5, 7.3, 9.2, 9.3_

  - [x] 5.2 Ensure Bedrock appears in ProviderPanel with correct policy filtering
    - Add `"bedrock"` to the `builtIn` array in `ProviderPanel.qml` in the `else` branch (full mode, policies.ai !== 2)
    - Do NOT add to local-only list (Bedrock is a remote cloud service)
    - Verify it does not appear when `policies.ai === 0` (entire panel hidden) or `policies.ai === 2`
    - _Requirements: 1.2, 8.1, 8.2, 8.3_

- [x] 6. Checkpoint — Bedrock UI complete and policy-filtered
  - Ensure Bedrock appears in provider list (full mode only), detail view shows credential status/region/test connection, hiding when policies restrict. Ask the user if questions arise.

- [x] 7. Property-based tests for Bedrock pure functions
  - [x] 7.1 Write property test: Model list parsing preserves model identity (Property 1)
    - **Property 1: Model list parsing preserves model identity**
    - For any valid `modelSummaries` JSON array where each entry has `modelId`, `modelName`, `inferenceTypesSupported` containing "ON_DEMAND", and `modelLifecycle.status` "ACTIVE": parsed AiModel objects have `model` === source `modelId`, `api_format` === "bedrock", `icon` === "aws-bedrock-symbolic", `endpoint` === "aws-bedrock-converse"
    - File: `tests/js/src/bedrock-logic.test.js`
    - **Validates: Requirements 4.2, 5.1, 5.2, 5.3, 5.5, 5.6**

  - [x] 7.2 Write property test: Model list filtering retains only ON_DEMAND ACTIVE models (Property 2)
    - **Property 2: Model list filtering retains only ON_DEMAND ACTIVE models**
    - For any array of model summary objects with arbitrary `inferenceTypesSupported` arrays and `modelLifecycle.status` values: filtered output contains only models where inferenceTypesSupported includes "ON_DEMAND" AND status === "ACTIVE", and no qualifying model is excluded
    - File: `tests/js/src/bedrock-logic.test.js`
    - **Validates: Requirements 4.3**

  - [x] 7.3 Write property test: Model name formatting (Property 3)
    - **Property 3: Model name formatting produces capitalized human-friendly names**
    - For any string with dashes, colons, or spaces: `formatModelName` produces output where each word is capitalized, dashes/colons replaced with spaces, trailing "Latest" removed, param suffixes like "7b" formatted as "(7B)"
    - File: `tests/js/src/bedrock-logic.test.js`
    - **Validates: Requirements 5.4**

  - [x] 7.4 Write property test: buildRequestData produces valid Bedrock Converse format (Property 4)
    - **Property 4: buildRequestData produces valid Bedrock Converse message format**
    - For any array of messages with role ("user" or "assistant") and non-empty rawContent: output has each message with matching role and `content` array containing exactly one `{"text": <rawContent>}` object
    - File: `tests/js/src/bedrock-logic.test.js`
    - **Validates: Requirements 6.2**

  - [x] 7.5 Write property test: System prompt separation (Property 5)
    - **Property 5: System prompt is separated from message array**
    - For any non-empty system prompt and any messages array: `buildRequestData` returns system prompt in `system` field as `[{"text": <systemPrompt>}]`, and no element in returned `messages` array has role "system"
    - File: `tests/js/src/bedrock-logic.test.js`
    - **Validates: Requirements 6.3**

  - [x] 7.6 Write property test: Stream event parsing concatenation (Property 6)
    - **Property 6: Stream event parsing concatenates all delta text**
    - For any sequence of valid converse-stream event lines (messageStart, contentBlockDelta, messageStop): calling `parseResponseLine` for each line results in `message.content` equaling the exact concatenation of all `contentBlockDelta.delta.text` values in order
    - File: `tests/js/src/bedrock-logic.test.js`
    - **Validates: Requirements 6.5, 10.2**

  - [x] 7.7 Write property test: AWS region parsing from config file (Property 7)
    - **Property 7: AWS region parsing from config file**
    - For any string representing an AWS config file with a `[default]` section containing `region = <value>`: parser extracts exactly `<value>` (trimmed). If no `[default]` section or no `region` line exists, result is "us-west-2"
    - File: `tests/js/src/bedrock-logic.test.js`
    - **Validates: Requirements 7.1, 7.2**

- [x] 8. Integration and edge case tests
  - [x] 8.1 Write unit tests for Bedrock provider config and policy filtering
    - Test that `providerConfigs["bedrock"]` has correct static fields (name, icon, key_id, requires_key, auth_type, api_format, supports_balance)
    - Test policy filtering: bedrock hidden when policies.ai is 0 or 2, visible when 1
    - Test `buildAuthorizationHeader` returns empty string
    - File: `tests/js/src/bedrock-logic.test.js`
    - _Requirements: 1.1, 1.3, 1.4, 8.1, 8.2, 8.3_

  - [x] 8.2 Write integration tests for credential detection and validation flow
    - Test: both credential files missing → statusMessage contains instructions (Requirement 2.4)
    - Test: AWS CLI not on PATH → awsCliAvailable false, statusMessage contains "AWS CLI not found" (Requirements 9.1, 9.2, 9.3)
    - Test: validation command construction includes `--max-results 1 --region <region>` (Requirement 3.2)
    - Test: exit code 0 → success state, non-zero → error with stderr (Requirements 3.3, 3.4)
    - Test: `parseResponseLine` with `messageStop` → returns `{ finished: true }` (Requirement 6.6)
    - Test: malformed JSON line → skipped without crashing (Design: Malformed Stream Output handling)
    - File: `tests/js/src/bedrock-logic.test.js`
    - _Requirements: 2.4, 3.2, 3.3, 3.4, 6.6, 9.1, 9.2, 9.3_

- [x] 9. Final checkpoint — All tests pass, feature complete
  - Ensure all property tests and unit tests pass with `vitest run` in `tests/js/`, all QML files load without errors, Bedrock appears in provider list under correct policy, credential detection works, validation triggers discovery, chat routing uses bedrockRequester. Ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation between phases
- Property tests use fast-check + vitest (existing infrastructure at `tests/js/`)
- Pure logic functions are extracted from QML into `tests/js/src/bedrock-logic.js` for testability
- QML constraints: no spread operator (use Object.assign), no replaceAll (use split/join), indexed for loops, Process + SplitParser/StdioCollector for subprocess stdout, pragma Singleton + ComponentBehavior: Bound
- Object reactivity in QML requires reassigning root objects — use `Object.assign({}, oldObj)` pattern
- The `aws` CLI handles SigV4 signing internally — no need to implement signing in QML/JS
- `AWS_SHARED_CREDENTIALS_FILE` env var injection lets the CLI use the detected credentials file without modifying user config
- Bedrock Converse API stream format is newline-delimited JSON (not SSE like OpenAI)
- The `"aws-bedrock-converse"` sentinel endpoint value signals CLI-based invocation in Ai.qml routing

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.3"] },
    { "id": 1, "tasks": ["2.1", "2.2"] },
    { "id": 2, "tasks": ["3.1", "3.2", "5.1"] },
    { "id": 3, "tasks": ["5.2", "7.1", "7.2", "7.3", "7.4", "7.5", "7.6", "7.7"] },
    { "id": 4, "tasks": ["8.1", "8.2"] }
  ]
}
```
