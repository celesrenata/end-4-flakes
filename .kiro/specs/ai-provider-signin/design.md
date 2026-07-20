# Design Document: AI Provider Sign-in and Model Discovery

## Overview

This feature adds a dedicated AI Provider Sign-in and Model Discovery panel to the left sidebar. It replaces the existing hardcoded model list in `Ai.qml` with a dynamic model discovery system that queries provider APIs after successful key validation. The implementation uses QML singletons, Process-based curl execution, and the existing KeyringStorage service for secure credential persistence.

## Architecture

This feature introduces a provider management layer between the user and the AI service. Instead of a hardcoded model list in `Ai.qml`, models are discovered dynamically by querying provider APIs after successful key validation. The architecture follows the existing Quickshell singleton/service pattern with Process-based curl execution for HTTP requests.

### Component Diagram

```
┌─────────────────────────────────────────────────────────┐
│  SidebarLeftContent.qml                                 │
│  ┌───────────────────────────────────────────────────┐  │
│  │ SwipeView                                         │  │
│  │  ┌─────────┐ ┌──────────┐ ┌───────┐ ┌────────┐  │  │
│  │  │ AiChat  │ │Providers │ │Transl.│ │ Anime  │  │  │
│  │  └─────────┘ └──────────┘ └───────┘ └────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
         │                │
         ▼                ▼
┌─────────────────┐  ┌───────────────────────────────────┐
│   Ai.qml        │  │  ProviderPanel.qml                │
│  (Singleton)    │◄─┤   ├─ ProviderListView             │
│  - models: {}   │  │   ├─ ProviderDetailView           │
│  - modelList: []│  │   │    ├─ KeyInput + Validator     │
│  - registry ops │  │   │    ├─ ValidationStatus         │
└────────┬────────┘  │   │    ├─ ModelListSection          │
         │           │   │    └─ BalanceDisplay            │
         │           └───────────────────────────────────┘
         │                          │
         ▼                          ▼
┌─────────────────┐  ┌───────────────────────────────────┐
│ KeyringStorage  │  │  ModelDiscoveryService.qml         │
│  (Singleton)    │  │   (Singleton)                      │
│  - apiKeys      │  │   - providerConfigs                │
│  - setNestedField│  │   - validateKey(provider, key)    │
│  - fetchKeyring │  │   - discoverModels(provider)      │
└─────────────────┘  │   - buildValidationRequest()      │
                     │   - parseModelResponse()           │
                     │   - mapErrorResponse()             │
                     │   - formatModelName()              │
                     └───────────────────────────────────┘
```

## Components and Interfaces

### 1. ModelDiscoveryService.qml (New Singleton)

The core logic service responsible for API key validation, model discovery, error mapping, and model name formatting. This is the primary pure-logic component and the main target for property-based testing.

```qml
pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Provider configuration registry
    readonly property var providerConfigs: ({
        "openai": {
            name: "OpenAI",
            icon: "ai-openai-symbolic",
            key_id: "openai",
            requires_key: true,
            validation_endpoint: "https://api.openai.com/v1/models",
            model_endpoint: "https://api.openai.com/v1/models",
            chat_endpoint: "https://api.openai.com/v1/chat/completions",
            auth_type: "bearer",  // Authorization: Bearer <key>
            api_format: "openai",
            supports_balance: true,
            balance_endpoint: "https://api.openai.com/v1/organization/usage"
        },
        "anthropic": {
            name: "Anthropic",
            icon: "anthropic-symbolic",
            key_id: "anthropic",
            requires_key: true,
            validation_endpoint: "https://api.anthropic.com/v1/models",
            model_endpoint: "https://api.anthropic.com/v1/models",
            chat_endpoint: "https://api.anthropic.com/v1/messages",
            auth_type: "x-api-key",  // x-api-key: <key>
            api_format: "openai",
            supports_balance: false
        },
        "gemini": {
            name: "Gemini",
            icon: "google-gemini-symbolic",
            key_id: "gemini",
            requires_key: true,
            validation_endpoint: "https://generativelanguage.googleapis.com/v1beta/models",
            model_endpoint: "https://generativelanguage.googleapis.com/v1beta/models",
            chat_endpoint_template: "https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent",
            auth_type: "query_param",  // ?key=<key>
            api_format: "gemini",
            supports_balance: false
        },
        "mistral": {
            name: "Mistral",
            icon: "mistral-symbolic",
            key_id: "mistral",
            requires_key: true,
            validation_endpoint: "https://api.mistral.ai/v1/models",
            model_endpoint: "https://api.mistral.ai/v1/models",
            chat_endpoint: "https://api.mistral.ai/v1/chat/completions",
            auth_type: "bearer",
            api_format: "mistral",
            supports_balance: false
        },
        "openrouter": {
            name: "OpenRouter",
            icon: "openrouter-symbolic",
            key_id: "openrouter",
            requires_key: true,
            validation_endpoint: "https://openrouter.ai/api/v1/models",
            model_endpoint: "https://openrouter.ai/api/v1/models",
            chat_endpoint: "https://openrouter.ai/api/v1/chat/completions",
            auth_type: "bearer",
            api_format: "openai",
            supports_balance: true,
            balance_endpoint: "https://openrouter.ai/api/v1/auth/key"
        },
        "ollama": {
            name: "Ollama",
            icon: "ollama-symbolic",
            key_id: "",
            requires_key: false,
            validation_endpoint: "http://localhost:11434/api/tags",
            model_endpoint: "http://localhost:11434/api/tags",
            chat_endpoint: "http://localhost:11434/v1/chat/completions",
            auth_type: "none",
            api_format: "openai",
            supports_balance: false
        }
    })

    // Validation state per provider: { status: "idle"|"loading"|"success"|"error", message: "" }
    property var validationStates: ({})
    // Discovered models per provider: { "openai": [...], "gemini": [...] }
    property var discoveredModels: ({})

    // --- Pure functions (testable) ---

    function buildValidationCommand(providerId, apiKey) {
        var config = providerConfigs[providerId];
        if (!config) return null;
        var endpoint = config.validation_endpoint;
        var authPart = "";
        if (config.auth_type === "bearer") {
            authPart = '-H "Authorization: Bearer ' + apiKey + '"';
        } else if (config.auth_type === "x-api-key") {
            authPart = '-H "x-api-key: ' + apiKey + '" -H "anthropic-version: 2023-06-01"';
        } else if (config.auth_type === "query_param") {
            endpoint = endpoint + "?key=" + apiKey;
        }
        // auth_type === "none" → no auth needed
        return {
            endpoint: endpoint,
            auth: authPart,
            command: ["bash", "-c", 'curl -s -w "\\n%{http_code}" "' + endpoint + '" ' + authPart]
        };
    }

    function mapErrorResponse(httpStatus, responseBody) {
        if (httpStatus === 401 || httpStatus === 403) {
            return "Invalid or revoked API key";
        }
        if (httpStatus === 429) {
            return "Rate limited — try again later";
        }
        // Check for credit/quota errors (varies by provider)
        if (httpStatus === 402) {
            return "Insufficient credits or quota exceeded";
        }
        var bodyLower = (responseBody || "").toLowerCase();
        if (bodyLower.indexOf("quota") !== -1 || bodyLower.indexOf("insufficient") !== -1 ||
            bodyLower.indexOf("credit") !== -1 || bodyLower.indexOf("billing") !== -1) {
            return "Insufficient credits or quota exceeded";
        }
        if (bodyLower.indexOf("permission") !== -1 || bodyLower.indexOf("scope") !== -1) {
            return "Key lacks required permissions";
        }
        // Network errors (status 0 or no response)
        if (httpStatus === 0) {
            return "Network error — check your connection";
        }
        // Fallback: show raw status and body
        return "Error " + httpStatus + ": " + (responseBody || "Unknown error");
    }

    function formatModelName(modelId) {
        // "gpt-4.1-mini" → "GPT 4.1 Mini"
        // "gemini-2.5-flash" → "Gemini 2.5 Flash"
        // "llama3.2:7b" → "Llama3.2 (7B)"
        var replaced = modelId.replace(/-/g, " ").replace(/:/g, " ");
        var words = replaced.split(" ");
        // Format last word if it's a param count like "7b"
        var lastWord = words[words.length - 1];
        if (/^\d+b$/i.test(lastWord)) {
            words[words.length - 1] = lastWord.replace(/(\d+)b/i, function(_, num) {
                return num + "B";
            });
            words[words.length - 1] = "(" + words[words.length - 1] + ")";
        }
        // Capitalize each word
        words = words.map(function(word) {
            return word.charAt(0).toUpperCase() + word.slice(1);
        });
        // Remove "Latest" tag
        if (words[words.length - 1] === "Latest") words.pop();
        return words.join(" ");
    }

    function mapModelToAiModel(providerId, modelData) {
        var config = providerConfigs[providerId];
        if (!config) return null;
        var modelId = "";
        var displayName = "";

        // Extract model ID from provider-specific response format
        if (providerId === "ollama") {
            modelId = modelData.name || modelData.model || "";
        } else if (providerId === "gemini") {
            // Gemini returns "models/gemini-2.5-flash" → extract after "models/"
            modelId = (modelData.name || "").replace("models/", "");
        } else {
            modelId = modelData.id || modelData.name || "";
        }

        displayName = formatModelName(modelId);

        // Build endpoint
        var endpoint = config.chat_endpoint || "";
        if (providerId === "gemini" && config.chat_endpoint_template) {
            endpoint = config.chat_endpoint_template.replace("{model}", modelId);
        }

        return {
            name: displayName,
            icon: config.icon,
            description: config.name + " | " + modelId,
            endpoint: endpoint,
            model: modelId,
            requires_key: config.requires_key,
            key_id: config.key_id,
            api_format: config.api_format
        };
    }

    function parseModelListResponse(providerId, responseBody) {
        // Returns an array of raw model data objects from the API response
        try {
            var json = JSON.parse(responseBody);
            if (providerId === "ollama") {
                return json.models || [];
            } else if (providerId === "gemini") {
                return json.models || [];
            } else {
                // OpenAI, Anthropic, Mistral, OpenRouter all use { data: [...] }
                return json.data || [];
            }
        } catch (e) {
            console.error("[ModelDiscovery] Failed to parse response for", providerId, e);
            return [];
        }
    }

    // --- Imperative side-effect functions ---

    function validateKey(providerId, apiKey) { /* triggers Process curl */ }
    function discoverModels(providerId) { /* triggers Process curl */ }
    function fetchBalance(providerId) { /* triggers Process curl */ }
}
```

### 2. ProviderPanel.qml (New UI Component)

The new sidebar tab component that provides the provider management interface.

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string selectedProvider: ""
    property var providerList: {
        if (Config.options.policies.ai === 2) {
            return ["ollama"];  // Local-only mode
        }
        return ["openai", "anthropic", "gemini", "mistral", "openrouter", "ollama"];
    }

    ColumnLayout {
        anchors.fill: parent

        // Provider list (when no provider selected)
        ListView {
            id: providerListView
            visible: root.selectedProvider === ""
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.providerList
            delegate: ProviderListItem {
                required property string modelData
                providerId: modelData
                onClicked: root.selectedProvider = providerId
            }
        }

        // Provider detail view (when provider selected)
        ProviderDetailView {
            visible: root.selectedProvider !== ""
            Layout.fillWidth: true
            Layout.fillHeight: true
            providerId: root.selectedProvider
            onBack: root.selectedProvider = ""
        }
    }
}
```

### 3. ProviderDetailView.qml (New UI Component)

Per-provider detail view with key input, validation, and model list.

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services

Item {
    id: root
    required property string providerId
    signal back()

    property var config: ModelDiscoveryService.providerConfigs[providerId]
    property var validationState: ModelDiscoveryService.validationStates[providerId] || { status: "idle", message: "" }

    // Debounce timer for auto-validation
    Timer {
        id: debounceTimer
        interval: 1000
        repeat: false
        onTriggered: {
            ModelDiscoveryService.validateKey(root.providerId, keyInput.text)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Back button + provider name
        RowLayout {
            IconButton { icon: "arrow_back"; onClicked: root.back() }
            Label { text: config.name; font.bold: true }
            Image { source: "qrc:///icons/" + config.icon + ".svg" }
        }

        // API Key input (hidden for Ollama)
        ColumnLayout {
            visible: config.requires_key
            Label { text: Translation.tr("API Key") }
            RowLayout {
                TextField {
                    id: keyInput
                    echoMode: TextInput.Password
                    placeholderText: Translation.tr("Enter API key...")
                    text: KeyringStorage.keyringData?.apiKeys?.[config.key_id] ?? ""
                    onTextChanged: {
                        debounceTimer.restart()
                    }
                }
                // Validation status indicator
                BusyIndicator { visible: validationState.status === "loading"; width: 24; height: 24 }
                IconButton {
                    icon: "check_circle"
                    visible: validationState.status === "success"
                    iconColor: "green"
                }
                IconButton {
                    icon: "error"
                    visible: validationState.status === "error"
                    iconColor: "red"
                }
                // Re-test button
                IconButton {
                    icon: "refresh"
                    visible: keyInput.text.length > 0
                    enabled: validationState.status !== "loading"
                    onClicked: ModelDiscoveryService.validateKey(root.providerId, keyInput.text)
                }
            }
            // Error message
            Label {
                visible: validationState.status === "error"
                text: validationState.message
                color: "red"
                wrapMode: Text.Wrap
            }
        }

        // Balance display (only for providers that support it)
        RowLayout {
            visible: config.supports_balance && validationState.status === "success"
            Label { text: Translation.tr("Balance:") }
            Label { text: ModelDiscoveryService.balances[root.providerId] || "—" }
        }

        // Model list section
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
                Label { text: Translation.tr("Models"); font.bold: true }
                IconButton {
                    icon: "refresh"
                    visible: validationState.status === "success" || !config.requires_key
                    enabled: !ModelDiscoveryService.isRefreshing(root.providerId)
                    onClicked: ModelDiscoveryService.discoverModels(root.providerId)
                }
                BusyIndicator {
                    visible: ModelDiscoveryService.isRefreshing(root.providerId)
                    width: 20; height: 20
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: ModelDiscoveryService.discoveredModels[root.providerId] || []
                delegate: ModelListItem {
                    required property var modelData
                    modelName: modelData.name
                    modelId: modelData.model
                }
            }
        }
    }
}
```

### 4. Modified Ai.qml (Singleton — Refactored)

The existing `Ai.qml` is refactored to remove the hardcoded `models` property and instead derive its model registry from `ModelDiscoveryService.discoveredModels` and `Config.options.ai.extraModels`.

Key changes:
- Remove the hardcoded `models` object literal (all the `gemini-2.0-flash`, `gemini-2.5-flash`, etc. entries)
- Replace with a computed property that merges discovered models + extraModels
- Remove the `getOllamaModels` Process (Ollama discovery moves to ModelDiscoveryService)
- Keep the existing `apiStrategies`, `currentApiStrategy`, messaging, and tool infrastructure unchanged

```qml
// In Ai.qml — replace the hardcoded models property:
property var models: {
    var result = {};
    // Add all discovered models from ModelDiscoveryService
    var providers = Object.keys(ModelDiscoveryService.discoveredModels);
    for (var i = 0; i < providers.length; i++) {
        var providerModels = ModelDiscoveryService.discoveredModels[providers[i]];
        for (var j = 0; j < providerModels.length; j++) {
            var m = providerModels[j];
            var safeId = root.safeModelName(m.model);
            result[safeId] = aiModelComponent.createObject(root, m);
        }
    }
    // Add extraModels from config
    var extras = Config.options?.ai?.extraModels ?? [];
    for (var k = 0; k < extras.length; k++) {
        var safeExtra = root.safeModelName(extras[k].model);
        result[safeExtra] = aiModelComponent.createObject(root, extras[k]);
    }
    return result;
}
property var modelList: Object.keys(root.models)
```

### 5. Modified SidebarLeftContent.qml

Add the Provider Panel tab to the `tabButtonList` and `contentChildren`:

```qml
property var tabButtonList: [
    ...(Config.options.policies.ai !== 0 ? [
        {"icon": "neurology", "name": Translation.tr("Intelligence")},
        {"icon": "key", "name": Translation.tr("Providers")}
    ] : []),
    {"icon": "translate", "name": Translation.tr("Translator")},
    ...(Config.options.policies.weeb === 1 ? [{"icon": "bookmark_heart", "name": Translation.tr("Anime")}] : [])
]

// In contentChildren:
contentChildren: [
    ...(Config.options.policies.ai !== 0 ? [aiChat.createObject(), providerPanel.createObject()] : []),
    translator.createObject(),
    ...(Config.options.policies.weeb === 0 ? [] : [anime.createObject()])
]

Component {
    id: providerPanel
    ProviderPanel {}
}
```

## Data Models

### Provider Configuration Object

```javascript
{
    name: String,              // "OpenAI", "Gemini", etc.
    icon: String,              // Icon identifier: "ai-openai-symbolic"
    key_id: String,            // Key identifier in KeyringStorage: "openai"
    requires_key: Boolean,     // true for cloud providers, false for Ollama
    validation_endpoint: String,  // URL used for key validation
    model_endpoint: String,    // URL used for model discovery (same as validation)
    chat_endpoint: String,     // Base URL for chat completions
    chat_endpoint_template: String,  // Optional, for Gemini: includes {model} placeholder
    auth_type: String,         // "bearer" | "x-api-key" | "query_param" | "none"
    api_format: String,        // "openai" | "gemini" | "mistral"
    supports_balance: Boolean, // Whether the provider exposes balance/usage info
    balance_endpoint: String   // Optional URL for balance queries
}
```

### Validation State Object

```javascript
{
    status: String,  // "idle" | "loading" | "success" | "error"
    message: String  // Empty on success, error description on failure
}
```

### Discovered Model Object (before AiModel creation)

```javascript
{
    name: String,        // Human-friendly display name
    icon: String,        // Provider icon
    description: String, // "Provider | model-id"
    endpoint: String,    // Chat completions endpoint
    model: String,       // Raw model identifier for API calls
    requires_key: Boolean,
    key_id: String,
    api_format: String   // "openai" | "gemini" | "mistral"
}
```

## Interfaces

### ModelDiscoveryService Public API

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| `buildValidationCommand` | `providerId: string, apiKey: string` | `{endpoint, auth, command}` or `null` | Pure: builds the curl command for key validation |
| `mapErrorResponse` | `httpStatus: int, responseBody: string` | `string` | Pure: maps HTTP response to user-facing error message |
| `formatModelName` | `modelId: string` | `string` | Pure: converts model ID to display name |
| `mapModelToAiModel` | `providerId: string, modelData: object` | `object` or `null` | Pure: maps raw API model to AiModel properties |
| `parseModelListResponse` | `providerId: string, responseBody: string` | `array` | Pure: extracts model list from provider API response |
| `validateKey` | `providerId: string, apiKey: string` | `void` | Side-effect: triggers validation Process |
| `discoverModels` | `providerId: string` | `void` | Side-effect: triggers model listing Process |
| `fetchBalance` | `providerId: string` | `void` | Side-effect: triggers balance fetch Process |

### KeyringStorage Integration

Keys are stored at `keyringData.apiKeys.<key_id>` using the existing `setNestedField` API:
```javascript
KeyringStorage.setNestedField(["apiKeys", "openai"], "sk-abc123...");
// Retrieval:
var key = KeyringStorage.keyringData?.apiKeys?.openai ?? "";
```

## Error Handling

### Validation Errors

The `mapErrorResponse` function provides a deterministic mapping from HTTP status codes and response bodies to user-facing messages:

| Condition | Displayed Message |
|-----------|-------------------|
| HTTP 401 or 403 | "Invalid or revoked API key" |
| HTTP 429 | "Rate limited — try again later" |
| HTTP 402, or body contains "quota"/"insufficient"/"credit"/"billing" | "Insufficient credits or quota exceeded" |
| Body contains "permission"/"scope" | "Key lacks required permissions" |
| HTTP 0 (network failure / no response) | "Network error — check your connection" |
| Any other status | "Error {status}: {body}" |

### Model Discovery Errors

- If a provider's model listing endpoint returns a non-2xx status, that provider's model list remains empty and the error status is shown
- If Ollama is unreachable (connection refused), a connectivity warning is displayed and no Ollama models appear
- Parse failures result in an empty model list with a generic error message

### Process Execution Errors

All HTTP requests use `Process` components executing `curl`. The curl command includes `-s -w "\n%{http_code}"` to emit the HTTP status code as the last line of output. The `StdioCollector`/`SplitParser` reads stdout, splits body from status code, and routes to the appropriate handler.

## File Structure

```
configs/quickshell/
├── services/
│   ├── ai/
│   │   ├── AiModel.qml           (unchanged)
│   │   ├── ApiStrategy.qml       (unchanged)
│   │   ├── GeminiApiStrategy.qml (unchanged)
│   │   ├── OpenAiApiStrategy.qml (unchanged)
│   │   ├── MistralApiStrategy.qml(unchanged)
│   │   └── AiMessageData.qml     (unchanged)
│   ├── Ai.qml                    (refactored: remove hardcoded models)
│   ├── KeyringStorage.qml        (unchanged)
│   └── ModelDiscoveryService.qml  (NEW: core logic service)
├── modules/
│   └── sidebarLeft/
│       ├── SidebarLeftContent.qml (modified: add Providers tab)
│       ├── ProviderPanel.qml      (NEW: provider list + detail host)
│       ├── ProviderDetailView.qml (NEW: per-provider detail)
│       ├── ProviderListItem.qml   (NEW: list item delegate)
│       └── ModelListItem.qml      (NEW: model list delegate)
```

## Behavioral Flow

### Key Entry → Validation → Discovery Flow

```
User types key → debounceTimer.restart()
                        │
                        ▼ (1000ms idle)
            debounceTimer.onTriggered
                        │
                        ▼
    ModelDiscoveryService.validateKey(providerId, key)
        → sets validationStates[providerId] = { status: "loading" }
        → launches curl Process
                        │
                        ▼
    Process stdout collected, split into body + statusCode
                        │
            ┌───────────┴───────────┐
            ▼                       ▼
    statusCode 2xx            statusCode != 2xx
            │                       │
            ▼                       ▼
    status = "success"     mapErrorResponse(statusCode, body)
    KeyringStorage.set     status = "error", message = result
    discoverModels()
            │
            ▼
    curl GET model_endpoint
            │
            ▼
    parseModelListResponse(providerId, body)
            │
            ▼
    mapModelToAiModel() for each model
            │
            ▼
    discoveredModels[providerId] = [...]
    Ai.models recomputed (binding)
```

### Policy Enforcement

- `policies.ai === 0`: No AI features at all → Provider tab hidden
- `policies.ai === 1`: Normal mode → All providers shown
- `policies.ai === 2`: Local-only → Only Ollama provider shown

## QML/JavaScript Constraints

- **No spread operator (`...`)**: Use `Object.assign({}, obj)` for cloning, `arr.concat(otherArr)` for array merging
- **No `replaceAll`**: Use `str.split(old).join(new)` pattern
- **No `for...of`**: Use indexed for loops or `forEach`
- **No template literals in some contexts**: Build strings with concatenation when inside Process command arrays
- **Singleton pattern**: Services use `pragma Singleton` with `Singleton {}` root element
- **ComponentBehavior: Bound**: Required for components that reference parent scope properties
- **Object reactivity**: Reassign root objects (via `Object.assign({}, ...)`) to trigger QML change notifications

## Testing Strategy

The pure functions in `ModelDiscoveryService` are the primary targets for property-based testing. Since the QML runtime isn't easily unit-testable in isolation, the pure logic functions (`buildValidationCommand`, `mapErrorResponse`, `formatModelName`, `mapModelToAiModel`, `parseModelListResponse`) will be extracted or mirrored as JavaScript modules testable with a standard JS test runner (e.g., pytest with a JS bridge, or direct Node.js testing of the logic).

- **Property-based tests**: Cover the 8 correctness properties below—error mapping, endpoint construction, model metadata mapping, name formatting, registry composition
- **Example-based tests**: UI behavior (tab visibility per policy, masked input, loading states)
- **Integration tests**: End-to-end validation flow with mocked curl responses

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: API Key Storage Round-Trip

For any provider key_id and any non-empty API key string, storing the key via `KeyringStorage.setNestedField(["apiKeys", key_id], key)` and then reading `KeyringStorage.keyringData.apiKeys[key_id]` SHALL return the exact same key string.

**Validates: Requirements 2.2**

### Property 2: Debounce Timer Fires Only After Idle Period

For any sequence of input change events with timestamps, the validation function SHALL only be invoked after at least 1000ms have elapsed since the last input event. No validation SHALL fire while the user is actively typing (inter-event gap < 1000ms).

**Validates: Requirements 3.1**

### Property 3: Validation Endpoint Construction

For any provider ID in the set {openai, anthropic, gemini, mistral, openrouter, ollama} and any non-empty API key string, `buildValidationCommand(providerId, apiKey)` SHALL produce a command targeting the correct endpoint and authentication scheme as defined in the provider configuration: bearer-token Authorization header for openai/mistral/openrouter, x-api-key header for anthropic, query parameter for gemini, and no authentication for ollama.

**Validates: Requirements 3.2, 10.1, 10.2, 10.3, 10.4, 10.5, 10.6**

### Property 4: Error Response Mapping Completeness

For any HTTP status code (integer 0–599) and any response body string, `mapErrorResponse(httpStatus, responseBody)` SHALL return a non-empty string. Specifically: status 401 or 403 maps to "Invalid or revoked API key"; status 429 maps to "Rate limited — try again later"; status 402 or body containing quota/credit/billing/insufficient keywords maps to "Insufficient credits or quota exceeded"; body containing permission/scope keywords maps to "Key lacks required permissions"; status 0 maps to "Network error — check your connection"; all other statuses map to "Error {status}: {body}".

**Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.6**

### Property 5: Model Registry Composition

For any combination of discovered model sets (per provider) and any `extraModels` config array, the Ai service model registry SHALL contain exactly the union of all discovered models and all extraModels entries—no more, no less. ExtraModels SHALL always be present regardless of provider authentication state.

**Validates: Requirements 7.2, 7.4**

### Property 6: Model Metadata Mapping Correctness

For any provider ID and any valid model data object from that provider's API response, `mapModelToAiModel(providerId, modelData)` SHALL produce an object with: `api_format` matching the provider's configured format, `endpoint` matching the provider's chat endpoint (with model substitution for Gemini), `key_id` matching the provider's configured key_id, and `requires_key` matching the provider's configuration. For Ollama specifically, `requires_key` SHALL be false and `key_id` SHALL be empty string.

**Validates: Requirements 6.2, 11.1, 11.2, 11.3, 11.4, 11.5, 11.6**

### Property 7: Discovery and Validation Share Endpoints

For any provider ID, the endpoint used by `buildValidationCommand` SHALL be identical to the endpoint used by the model discovery request. That is, `providerConfigs[providerId].validation_endpoint` SHALL equal `providerConfigs[providerId].model_endpoint`.

**Validates: Requirements 10.7**

### Property 8: Model Name Formatting

For any model ID string (non-empty, containing alphanumeric characters, hyphens, colons, dots, and slashes), `formatModelName(modelId)` SHALL return a string where: each word-segment is capitalized, hyphens and colons are replaced with spaces or parenthetical grouping, and parameter-count suffixes (e.g. "7b") are formatted as uppercase with parentheses (e.g. "(7B)").

**Validates: Requirements 11.7**
