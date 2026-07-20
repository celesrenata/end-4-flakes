# Requirements Document

## Introduction

This feature adds AWS Bedrock as a provider in the existing AI Provider Sign-in and Model Discovery system. Unlike the other providers (OpenAI, Anthropic, Gemini, Mistral, OpenRouter, Ollama) which use simple HTTP bearer token or query parameter authentication, Bedrock uses AWS SigV4 request signing. Because SigV4 is too complex to implement in QML/JavaScript, the integration delegates all API calls to the `aws` CLI tool already installed on the system. Credentials are read from `~/.aws/credentials.bedrock` (a two-line file: access key on line 1, secret key on line 2) or standard `~/.aws/credentials`. The Bedrock Converse API provides a unified chat format similar to OpenAI's messages array, and model discovery uses `aws bedrock list-foundation-models`.

## Glossary

- **Bedrock_Provider**: The AWS Bedrock entry in the Provider Panel, representing the AWS Bedrock AI service as a selectable provider
- **Bedrock_Api_Strategy**: The ApiStrategy implementation for AWS Bedrock that uses the `aws` CLI for Converse API streaming chat requests
- **AWS_CLI**: The `aws` command-line tool installed on the system, used to perform SigV4-signed requests to AWS Bedrock endpoints
- **Credentials_File**: The file at `~/.aws/credentials.bedrock` containing the AWS access key ID on line 1 and secret access key on line 2
- **Converse_API**: The AWS Bedrock Runtime Converse API (`converse-stream`) that provides a unified chat message format across all Bedrock models
- **Model_Discovery_Service**: The existing singleton service that queries provider APIs for available models and populates the model list
- **Provider_Panel**: The existing left sidebar tab UI dedicated to AI provider sign-in, key management, and model discovery
- **SigV4**: AWS Signature Version 4, the request signing protocol used to authenticate AWS API requests
- **Bedrock_Region**: The AWS region for Bedrock API calls, read from `~/.aws/config` (default: `us-west-2`)

## Requirements

### Requirement 1: Bedrock Provider Registration

**User Story:** As a user, I want AWS Bedrock to appear as a provider in the Provider Panel alongside the other providers, so that I can access Bedrock models through the same unified interface.

#### Acceptance Criteria

1. THE Model_Discovery_Service SHALL include a "bedrock" entry in the provider configuration registry with provider name "AWS Bedrock", icon "aws-bedrock-symbolic", key_id "bedrock", auth_type "aws_cli", and api_format "bedrock".
2. THE Provider_Panel SHALL display the AWS Bedrock provider in the provider list alongside OpenAI, Anthropic, Gemini, Mistral, OpenRouter, and Ollama.
3. THE Bedrock_Provider SHALL set `requires_key` to false, because authentication is file-based rather than API-key-based.
4. THE Bedrock_Provider SHALL set `supports_balance` to false, because AWS Bedrock does not expose a credit balance endpoint.

### Requirement 2: File-Based Credential Detection

**User Story:** As a user, I want the system to detect my AWS credentials from the filesystem, so that I do not need to paste keys into a text field.

#### Acceptance Criteria

1. WHEN the Bedrock provider detail view is opened, THE Provider_Panel SHALL check for the existence of `~/.aws/credentials.bedrock`.
2. IF `~/.aws/credentials.bedrock` exists, THEN THE Provider_Panel SHALL display the file path and a "credentials detected" status indicator.
3. IF `~/.aws/credentials.bedrock` does not exist, THEN THE Provider_Panel SHALL check for the standard `~/.aws/credentials` file.
4. IF neither credentials file exists, THEN THE Provider_Panel SHALL display a message indicating that no AWS credentials were found and instructions to create `~/.aws/credentials.bedrock` with the access key on line 1 and secret key on line 2.
5. THE Provider_Panel SHALL not display an API key text input field for the Bedrock provider.
6. THE Provider_Panel SHALL display the detected credentials file path as read-only text in the Bedrock provider detail view.

### Requirement 3: Connection Validation via AWS CLI

**User Story:** As a user, I want to test that my AWS credentials work for Bedrock access, so that I can confirm my setup before trying to use models.

#### Acceptance Criteria

1. THE Provider_Panel SHALL display a "Test Connection" button in the Bedrock provider detail view when a credentials file is detected.
2. WHEN the user clicks the "Test Connection" button, THE API_Key_Validator SHALL execute `aws bedrock list-foundation-models --max-results 1 --region us-west-2` using the detected credentials.
3. WHEN the AWS CLI command exits with code 0, THE Provider_Panel SHALL display a success indicator for the Bedrock provider.
4. IF the AWS CLI command exits with a non-zero exit code, THEN THE Provider_Panel SHALL display the stderr output as an error message.
5. WHILE the connection test is in progress, THE Provider_Panel SHALL display a loading indicator and disable the "Test Connection" button.
6. THE API_Key_Validator SHALL set the `AWS_SHARED_CREDENTIALS_FILE` environment variable to point to the detected credentials file path when executing the AWS CLI command.

### Requirement 4: Model Discovery via AWS CLI

**User Story:** As a user, I want available Bedrock models to be discovered automatically, so that I can select from models my account has access to.

#### Acceptance Criteria

1. WHEN the Bedrock connection validation succeeds, THE Model_Discovery_Service SHALL execute `aws bedrock list-foundation-models --region us-west-2 --output json` to retrieve available models.
2. WHEN the model listing command completes successfully, THE Model_Discovery_Service SHALL parse the JSON output and create AiModel objects for each model in the `modelSummaries` array.
3. THE Model_Discovery_Service SHALL filter discovered models to include only models with `inferenceTypesSupported` containing "ON_DEMAND" and `modelLifecycle.status` equal to "ACTIVE".
4. THE Model_Discovery_Service SHALL set the `AWS_SHARED_CREDENTIALS_FILE` environment variable to point to the detected credentials file path when executing the model discovery command.
5. IF the model listing command fails, THEN THE Model_Discovery_Service SHALL display no models for the Bedrock provider and show the error output.
6. WHEN the user clicks the refresh button for the Bedrock provider, THE Model_Discovery_Service SHALL re-execute the model listing command and update the model registry.

### Requirement 5: Discovered Model Metadata Mapping

**User Story:** As a developer, I want discovered Bedrock models mapped to AiModel properties correctly, so that the chat system can use them through the Converse API.

#### Acceptance Criteria

1. WHEN creating an AiModel from a discovered Bedrock model, THE Model_Discovery_Service SHALL set the `model` property to the `modelId` field from the API response (e.g., `anthropic.claude-sonnet-4-20250514-v1:0`).
2. WHEN creating an AiModel from a discovered Bedrock model, THE Model_Discovery_Service SHALL set `api_format` to "bedrock".
3. WHEN creating an AiModel from a discovered Bedrock model, THE Model_Discovery_Service SHALL set `requires_key` to false and `key_id` to "bedrock".
4. WHEN creating an AiModel from a discovered Bedrock model, THE Model_Discovery_Service SHALL derive a human-friendly `name` from the `modelName` field in the API response.
5. WHEN creating an AiModel from a discovered Bedrock model, THE Model_Discovery_Service SHALL set the `icon` property to "aws-bedrock-symbolic".
6. THE Model_Discovery_Service SHALL set the `endpoint` property to the string "aws-bedrock-converse" as a sentinel value indicating CLI-based invocation rather than an HTTP URL.

### Requirement 6: BedrockApiStrategy for Chat

**User Story:** As a developer, I want a BedrockApiStrategy that uses the `aws` CLI to call the Converse API for streaming chat, so that Bedrock models integrate with the existing chat system.

#### Acceptance Criteria

1. THE Bedrock_Api_Strategy SHALL implement the ApiStrategy interface (buildEndpoint, buildRequestData, buildAuthorizationHeader, parseResponseLine, onRequestFinished, reset).
2. WHEN buildRequestData is called, THE Bedrock_Api_Strategy SHALL format the messages array into the Bedrock Converse API format with `role` and `content` fields where content is an array of content blocks (e.g., `[{"text": "message text"}]`).
3. WHEN buildRequestData is called, THE Bedrock_Api_Strategy SHALL include the system prompt as a top-level `system` array parameter (e.g., `[{"text": "system prompt"}]`) rather than a system message in the messages array.
4. THE Bedrock_Api_Strategy SHALL construct an `aws bedrock-runtime converse-stream` command with `--model-id`, `--messages`, `--region us-west-2`, and `--output json` parameters.
5. WHEN parseResponseLine is called with Converse API stream output, THE Bedrock_Api_Strategy SHALL extract text content from `contentBlockDelta.delta.text` fields and append the text to the message content.
6. WHEN a `messageStop` event is received in the stream, THE Bedrock_Api_Strategy SHALL signal that the response is complete.
7. THE Bedrock_Api_Strategy SHALL set `AWS_SHARED_CREDENTIALS_FILE` environment variable to the detected credentials file path when executing the CLI command.

### Requirement 7: Region Configuration

**User Story:** As a user, I want the Bedrock region to be read from my AWS config, so that the system uses the correct regional endpoint without manual configuration.

#### Acceptance Criteria

1. THE Bedrock_Provider SHALL read the AWS region from `~/.aws/config` by parsing the `[default]` profile's `region` value.
2. IF `~/.aws/config` does not exist or does not contain a region value, THEN THE Bedrock_Provider SHALL default to `us-west-2`.
3. THE Provider_Panel SHALL display the configured region in the Bedrock provider detail view as read-only informational text.
4. THE Bedrock_Provider SHALL pass the resolved region value to all AWS CLI commands via the `--region` flag.

### Requirement 8: Policy Compliance

**User Story:** As a system administrator, I want Bedrock to respect the same AI policy settings as other providers, so that access control is consistent.

#### Acceptance Criteria

1. WHILE `policies.ai` is set to 0, THE Bedrock_Provider SHALL not appear in the Provider Panel (consistent with all other providers being hidden).
2. WHILE `policies.ai` is set to 2 (local-only mode), THE Bedrock_Provider SHALL not appear in the Provider Panel, because Bedrock is a remote cloud service.
3. WHEN `policies.ai` is set to 1 (full mode), THE Bedrock_Provider SHALL appear in the Provider Panel alongside other remote providers.

### Requirement 9: AWS CLI Availability Check

**User Story:** As a user, I want clear feedback if the `aws` CLI is not available on my system, so that I understand what prerequisite is missing.

#### Acceptance Criteria

1. WHEN the Bedrock provider is first accessed, THE Bedrock_Provider SHALL verify that the `aws` command is available by checking its existence on the system PATH.
2. IF the `aws` command is not found, THEN THE Provider_Panel SHALL display an error message: "AWS CLI not found. Install the aws-cli package to use Bedrock."
3. IF the `aws` command is not found, THEN THE Provider_Panel SHALL disable the "Test Connection" button and model discovery for the Bedrock provider.

### Requirement 10: Streaming Chat Execution

**User Story:** As a user, I want chat with Bedrock models to stream responses in real time, so that the experience matches the other providers.

#### Acceptance Criteria

1. WHEN a chat request is sent to a Bedrock model, THE Bedrock_Api_Strategy SHALL invoke `aws bedrock-runtime converse-stream` as a subprocess and read its stdout incrementally.
2. WHILE the subprocess is producing output, THE Bedrock_Api_Strategy SHALL parse each JSON event line and append extracted text to the message content in real time.
3. WHEN the subprocess exits with code 0, THE Bedrock_Api_Strategy SHALL mark the message as complete.
4. IF the subprocess exits with a non-zero exit code, THEN THE Bedrock_Api_Strategy SHALL append the stderr content as an error to the message and mark it as failed.
5. WHEN the user cancels a chat request, THE Bedrock_Api_Strategy SHALL terminate the running subprocess.
