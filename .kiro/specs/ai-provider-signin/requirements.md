# Requirements Document

## Introduction

This feature adds a dedicated AI Provider Sign-in and Model Discovery panel as a new tab in the left sidebar of the Quickshell desktop shell. It replaces the existing hardcoded model list in Ai.qml with a fully dynamic model discovery system. Users manage per-provider API keys through a settings-style UI, with real-time key validation and on-demand model list fetching from provider APIs. Supported providers are OpenAI, Anthropic/Claude, Google Gemini, Mistral, OpenRouter, local Ollama, and any user-defined OpenAI-compatible endpoint (vLLM, LMStudio, TabbyAPI, text-generation-webui, etc.).

## Glossary

- **Provider_Panel**: The new left sidebar tab UI dedicated to AI provider sign-in, key management, and model discovery
- **Provider**: A remote or local AI service that exposes models (OpenAI, Anthropic, Gemini, Mistral, OpenRouter, Ollama, or any OpenAI-compatible endpoint)
- **Custom_Provider**: A user-defined OpenAI-compatible endpoint where the user specifies the base URL and optional API key (e.g., vLLM, LMStudio, TabbyAPI, text-generation-webui)
- **API_Key_Validator**: The subsystem that pings a provider's API to confirm an entered key is valid and operational
- **Model_Discovery_Service**: The subsystem that queries provider APIs for available models and populates the model list
- **KeyringStorage**: The existing singleton service that persists sensitive data (API keys) via libsecret/secret-tool
- **Debounce_Timer**: A delay mechanism (typically 800–1200ms) that waits for the user to stop typing before triggering validation
- **AiModel**: The existing QtObject type representing a single AI model with properties like name, icon, endpoint, model, api_format, requires_key, key_id
- **ExtraModels**: User-defined model entries from the Config `ai.extraModels` array that supplement discovered models
- **Balance_Display**: A UI element showing remaining tokens, credits, or usage quota for a given provider when the API supports it

## Requirements

### Requirement 1: Provider Panel Tab

**User Story:** As a user, I want a dedicated settings tab in the left sidebar for managing AI providers, so that I can configure API keys without leaving the shell interface.

#### Acceptance Criteria

1. WHEN the AI policy config option (`policies.ai`) is not 0, THE Provider_Panel SHALL appear as a tab in the left sidebar SwipeView alongside existing tabs (Intelligence, Translator, Anime).
2. THE Provider_Panel SHALL display a list of all supported providers (OpenAI, Anthropic, Gemini, Mistral, OpenRouter, Ollama) with provider name and icon, plus an "Add Custom" button for OpenAI-compatible endpoints.
3. WHEN a provider entry is selected, THE Provider_Panel SHALL display a per-provider detail view containing an API key input field, validation status indicator, and model list section.
4. WHILE `policies.ai` is set to 0, THE Provider_Panel SHALL not appear in the sidebar tab list.
5. WHILE `policies.ai` is set to 2, THE Provider_Panel SHALL display only the Ollama provider and custom providers with localhost endpoints (local-only mode).
6. WHEN the user clicks "Add Custom", THE Provider_Panel SHALL display a form with fields for: display name, base URL (e.g., `http://localhost:5000/v1`), and optional API key.
7. WHEN a custom provider is added, THE Provider_Panel SHALL persist it in the config and treat it identically to built-in providers for validation and model discovery (using the OpenAI `/v1/models` and `/v1/chat/completions` endpoint conventions).

### Requirement 2: API Key Entry and Persistence

**User Story:** As a user, I want to enter and securely store API keys for each provider, so that my credentials persist across sessions without being exposed in plain text config files.

#### Acceptance Criteria

1. THE Provider_Panel SHALL provide a text input field for API key entry for each provider that requires a key (OpenAI, Anthropic, Gemini, Mistral, OpenRouter).
2. WHEN the user enters or pastes an API key, THE Provider_Panel SHALL store the key in KeyringStorage under the path `["apiKeys", <provider_key_id>]`.
3. THE Provider_Panel SHALL mask the API key input by default (password-style display).
4. WHEN a stored key exists for a provider, THE Provider_Panel SHALL display a masked representation of the key and a clear/remove button.
5. THE Provider_Panel SHALL not display an API key input field for the Ollama provider.

### Requirement 3: Auto-Validation with Debounce

**User Story:** As a user, I want my API keys validated automatically after I finish typing, so that I get immediate feedback without needing to manually trigger a check.

#### Acceptance Criteria

1. WHEN the user stops typing or pasting in the API key input field, THE API_Key_Validator SHALL wait for a debounce period of 1000ms before initiating validation.
2. WHEN the debounce period elapses, THE API_Key_Validator SHALL send a lightweight request to the provider's API using the entered key to verify it is operational.
3. WHILE validation is in progress, THE Provider_Panel SHALL display a loading indicator next to the key input field.
4. WHEN validation succeeds, THE Provider_Panel SHALL display a success indicator (green checkmark or equivalent visual cue).
5. WHEN validation fails, THE Provider_Panel SHALL display a descriptive error message indicating the failure reason.

### Requirement 4: Manual Re-Test Button

**User Story:** As a user, I want a manual re-test button so that I can retry validation after fixing a transient issue (network outage, rate limit) without re-entering the key.

#### Acceptance Criteria

1. WHEN a stored API key exists for a provider, THE Provider_Panel SHALL display a re-test button adjacent to the validation status indicator.
2. WHEN the user clicks the re-test button, THE API_Key_Validator SHALL immediately initiate a validation request for the stored key, bypassing the debounce timer.
3. WHILE a validation request is already in progress, THE Provider_Panel SHALL disable the re-test button.

### Requirement 5: Validation Error Messages

**User Story:** As a user, I want clear error messages when my API key fails validation, so that I can diagnose and fix the problem.

#### Acceptance Criteria

1. IF the provider API returns an authentication error (HTTP 401 or 403), THEN THE Provider_Panel SHALL display "Invalid or revoked API key".
2. IF the provider API returns a rate limit error (HTTP 429), THEN THE Provider_Panel SHALL display "Rate limited — try again later".
3. IF the provider API returns an insufficient credits/quota error, THEN THE Provider_Panel SHALL display "Insufficient credits or quota exceeded".
4. IF the provider API returns a permissions error indicating the key lacks required scopes, THEN THE Provider_Panel SHALL display "Key lacks required permissions".
5. IF the validation request fails due to a network error or timeout, THEN THE Provider_Panel SHALL display "Network error — check your connection".
6. IF the provider API returns an unrecognized error, THEN THE Provider_Panel SHALL display the HTTP status code and response message body.

### Requirement 6: Dynamic Model Discovery

**User Story:** As a user, I want the available model list to be populated directly from provider APIs, so that I always see models my key actually has access to without relying on a hardcoded list.

#### Acceptance Criteria

1. WHEN an API key is successfully validated for a provider, THE Model_Discovery_Service SHALL query that provider's model listing endpoint to retrieve available models.
2. WHEN model discovery completes for a provider, THE Model_Discovery_Service SHALL create AiModel objects for each discovered model and add them to the Ai service model registry.
3. THE Model_Discovery_Service SHALL query the Ollama local API (`http://localhost:11434/api/tags`) for installed models without requiring an API key.
4. IF the Ollama endpoint is unreachable, THEN THE Model_Discovery_Service SHALL display no models for the Ollama provider and show a connectivity warning.
5. IF a provider's model listing endpoint returns an error, THEN THE Model_Discovery_Service SHALL display no models for that provider and show the error status.

### Requirement 7: Remove Hardcoded Model List

**User Story:** As a user, I want the model list to contain only models I can actually use (discovered from my authenticated providers plus config-defined extras), so that I am not presented with models I cannot access.

#### Acceptance Criteria

1. THE Ai service SHALL not contain a hardcoded `models` property object with pre-defined model entries.
2. THE Ai service SHALL populate the model registry exclusively from models discovered by the Model_Discovery_Service and from the `ai.extraModels` config array.
3. WHEN no providers have been authenticated and no Ollama models are available, THE Ai service SHALL present an empty model list.
4. WHEN the user has defined entries in `ai.extraModels` in Config, THE Ai service SHALL include those models in the registry regardless of provider authentication status.

### Requirement 8: On-Demand Model Refresh

**User Story:** As a user, I want to manually refresh the model list so that I can pick up newly released models or changes to my account's access without restarting the shell.

#### Acceptance Criteria

1. THE Provider_Panel SHALL display a refresh button for each authenticated provider's model list section.
2. WHEN the user clicks the refresh button for a provider, THE Model_Discovery_Service SHALL re-query that provider's model listing endpoint and update the model registry.
3. WHILE a model refresh request is in progress, THE Provider_Panel SHALL display a loading state on the refresh button.
4. WHEN the model refresh completes, THE Provider_Panel SHALL update the displayed model list for that provider with the new results.

### Requirement 9: Token/Credit Balance Display

**User Story:** As a user, I want to see my remaining balance or quota at a glance, so that I know when I need to top up credits.

#### Acceptance Criteria

1. WHERE a provider's API exposes balance or usage information (OpenRouter, OpenAI), THE Provider_Panel SHALL display the current credit balance or usage quota for authenticated providers.
2. WHEN the balance information is unavailable or the provider does not support it (Gemini free tier, Ollama, Anthropic, Mistral), THE Provider_Panel SHALL omit the balance display for that provider.
3. WHEN the user signs in or refreshes models for a balance-supporting provider, THE Provider_Panel SHALL fetch and update the displayed balance.

### Requirement 10: Provider API Integration Endpoints

**User Story:** As a developer, I want clear endpoint definitions for each provider's validation and model listing APIs, so that the implementation targets the correct URLs and response formats.

#### Acceptance Criteria

1. THE API_Key_Validator SHALL validate OpenAI keys by sending a GET request to `https://api.openai.com/v1/models` with the Authorization header.
2. THE API_Key_Validator SHALL validate Anthropic keys by sending a GET request to `https://api.anthropic.com/v1/models` with the `x-api-key` header and `anthropic-version` header.
3. THE API_Key_Validator SHALL validate Gemini keys by sending a GET request to `https://generativelanguage.googleapis.com/v1beta/models?key=<key>`.
4. THE API_Key_Validator SHALL validate Mistral keys by sending a GET request to `https://api.mistral.ai/v1/models` with the Authorization header.
5. THE API_Key_Validator SHALL validate OpenRouter keys by sending a GET request to `https://openrouter.ai/api/v1/models` with the Authorization header.
6. THE API_Key_Validator SHALL validate Ollama connectivity by sending a GET request to `http://localhost:11434/api/tags` without authentication.
7. THE Model_Discovery_Service SHALL use the same endpoints listed in criteria 1–6 to retrieve the list of available models for each provider.

### Requirement 11: Discovered Model Metadata Mapping

**User Story:** As a developer, I want discovered models mapped to AiModel properties correctly, so that the chat system can use them without further configuration.

#### Acceptance Criteria

1. WHEN creating an AiModel from a discovered OpenAI-format model, THE Model_Discovery_Service SHALL set api_format to "openai", endpoint to `https://api.openai.com/v1/chat/completions`, and key_id to "openai".
2. WHEN creating an AiModel from a discovered Anthropic model, THE Model_Discovery_Service SHALL set api_format to "openai" (Anthropic uses OpenAI-compatible chat format), endpoint to `https://api.anthropic.com/v1/messages`, and key_id to "anthropic".
3. WHEN creating an AiModel from a discovered Gemini model, THE Model_Discovery_Service SHALL set api_format to "gemini", construct the endpoint using the model name in the Gemini streaming URL pattern, and key_id to "gemini".
4. WHEN creating an AiModel from a discovered Mistral model, THE Model_Discovery_Service SHALL set api_format to "mistral", endpoint to `https://api.mistral.ai/v1/chat/completions`, and key_id to "mistral".
5. WHEN creating an AiModel from a discovered OpenRouter model, THE Model_Discovery_Service SHALL set api_format to "openai", endpoint to `https://openrouter.ai/api/v1/chat/completions`, and key_id to "openrouter".
6. WHEN creating an AiModel from a discovered Ollama model, THE Model_Discovery_Service SHALL set api_format to "openai", endpoint to `http://localhost:11434/v1/chat/completions`, requires_key to false, and key_id to empty string.
7. THE Model_Discovery_Service SHALL set the AiModel `name` property to a human-friendly display name derived from the model ID (capitalize words, format version numbers).
8. THE Model_Discovery_Service SHALL set the AiModel `icon` property using the provider's icon (e.g., "google-gemini-symbolic" for Gemini, "mistral-symbolic" for Mistral, "ai-openai-symbolic" for OpenAI, "ollama-symbolic" for Ollama).
