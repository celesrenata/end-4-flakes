# Requirements Document

## Introduction

Add context window management, multiple chat sessions, and intelligent context compression to the Quickshell sidebar AI chat. This feature extends the existing `Ai.qml` singleton with multi-session support, token tracking against model context limits, a `/compact` slash command for conversation summarization, and proactive context limit handling including model upgrade suggestions.

## Glossary

- **Ai_Service**: The `Ai.qml` singleton that manages LLM chat interactions, message storage, model configuration, and API communication.
- **Chat_Session**: An independent conversation with its own message history, name, and metadata, stored as a JSON file in the `aiChats` directory.
- **Session_Manager**: The component within Ai_Service responsible for creating, switching, listing, and deleting Chat_Sessions.
- **Token_Estimator**: The component that estimates token count for message content using a character-based heuristic (characters / 4).
- **Context_Window**: The maximum number of tokens a model can process in a single request, defined per model in configuration.
- **Context_Usage**: The ratio of estimated tokens currently in the conversation to the model's Context_Window size.
- **Context_Indicator**: A visual UI element in the chat status bar that displays current Context_Usage as a percentage and progress bar.
- **Compact_Command**: The `/compact` slash command that summarizes the current conversation to free context space.
- **Compact_Summary**: The condensed system message produced by Compact_Command that replaces the original conversation history.
- **AI_Doctor**: The advisory component that suggests alternative models with larger context windows when the current Context_Window is exhausted.
- **Auto_Compact_Threshold**: The Context_Usage percentage (85%) at which the system proactively suggests compaction.
- **Persistent_State**: The `Persistent.qml` JsonAdapter that stores session metadata and active session reference across Quickshell restarts.

## Requirements

### Requirement 1: Multiple Chat Sessions

**User Story:** As a user, I want to maintain multiple independent named conversations so that I can organize different topics and switch between them without losing history.

#### Acceptance Criteria

1. WHEN the user issues the `/new` command with an optional name argument, THE Session_Manager SHALL create a new Chat_Session with an empty message history and switch to it.
2. WHEN no name argument is provided to `/new`, THE Session_Manager SHALL generate a default name using the format "Chat {N}" where N is the next sequential number.
3. WHEN the user issues the `/switch` command with a session name, THE Session_Manager SHALL save the current Chat_Session and load the specified Chat_Session's message history.
4. WHEN the user issues the `/list` command, THE Session_Manager SHALL display all available Chat_Sessions with their names and last-modified timestamps.
5. WHEN the user issues the `/delete` command with a session name, THE Session_Manager SHALL remove the specified Chat_Session's persisted file and remove it from the session list.
6. IF the user attempts to `/delete` the currently active Chat_Session, THEN THE Session_Manager SHALL reject the deletion and display an error message indicating the active session cannot be deleted.
7. WHEN Quickshell starts, THE Session_Manager SHALL restore the last active Chat_Session from Persistent_State.
8. WHEN a Chat_Session is modified (message added or removed), THE Ai_Service SHALL auto-save the session to its JSON file.

### Requirement 2: Context Window Tracking

**User Story:** As a user, I want to see how much of the model's context window I'm using so that I know when I'm approaching the limit and can take action.

#### Acceptance Criteria

1. THE Token_Estimator SHALL estimate token count for a given text string by dividing the character count by 4 and rounding up to the nearest integer.
2. THE Ai_Service SHALL maintain a `contextUsage` property that recalculates whenever the message list changes, summing the estimated tokens of all messages plus the system prompt.
3. THE AiModel SHALL include a `context_length` integer property representing the model's maximum context window in tokens.
4. WHEN the context_length is not explicitly configured for a model, THE AiModel SHALL default to 128000 tokens.
5. THE Context_Indicator SHALL display the current Context_Usage as a percentage and a colored progress segment in the chat status bar.
6. WHEN Context_Usage exceeds 70%, THE Context_Indicator SHALL change color from the default subtle color to a warning color (Appearance.m3colors.m3tertiary).
7. WHEN Context_Usage exceeds 90%, THE Context_Indicator SHALL change color to an error color (Appearance.m3colors.m3error).

### Requirement 3: Compact Command

**User Story:** As a user, I want to compress my conversation history into a summary so that I can free up context space while retaining essential information.

#### Acceptance Criteria

1. WHEN the user issues `/compact` without arguments, THE Compact_Command SHALL send the full conversation history to the current model with a summarization system prompt requesting a general summary.
2. WHEN the user issues `/compact` with a focus argument (e.g., `/compact keep the code examples`), THE Compact_Command SHALL include the focus instruction in the summarization prompt to guide what information to emphasize or preserve.
3. WHEN the model returns the Compact_Summary, THE Ai_Service SHALL replace the entire message history with a single system-role message containing the Compact_Summary.
4. WHILE the Compact_Command is processing, THE Context_Indicator SHALL display a "Compacting..." status and disable user input.
5. IF the model fails to generate a Compact_Summary (network error or empty response), THEN THE Ai_Service SHALL preserve the original message history unchanged and display an error message.
6. WHEN compaction completes successfully, THE Ai_Service SHALL recalculate Context_Usage to reflect the reduced token count.

### Requirement 4: Context Limit Handling

**User Story:** As a user, I want clear guidance when I hit the context window limit so that I can continue my conversation without losing important information.

#### Acceptance Criteria

1. WHEN Context_Usage reaches 100% (estimated tokens meet or exceed context_length), THE Ai_Service SHALL block sending new messages and display the context-full UI.
2. WHEN the context-full UI is displayed, THE AI_Doctor SHALL list available models from the user's configured providers that have a larger context_length than the current model.
3. WHEN the context-full UI is displayed, THE Ai_Service SHALL offer a button to execute `/compact` with an optional focus input field.
4. WHEN the user selects a suggested model from the AI_Doctor list, THE Ai_Service SHALL switch to that model and unblock message sending.
5. IF no models with a larger context_length are available, THEN THE AI_Doctor SHALL omit the model suggestion section and only show the compact option.

### Requirement 5: Auto-Compact Suggestion

**User Story:** As a user, I want to be proactively notified when my context is getting full so that I can compact before hitting the hard limit.

#### Acceptance Criteria

1. WHEN Context_Usage crosses the Auto_Compact_Threshold (85%) for the first time in a session, THE Ai_Service SHALL display a non-blocking notification suggesting the user run `/compact`.
2. THE auto-compact notification SHALL include a dismiss button that hides the notification for the remainder of the current Chat_Session.
3. THE auto-compact notification SHALL include a "Compact now" action button that executes `/compact` with no arguments.
4. WHILE the auto-compact notification is displayed, THE Ai_Service SHALL continue to accept and send user messages without interruption.
5. WHEN the user manually compacts (bringing usage below 85%) and then crosses the threshold again, THE Ai_Service SHALL display the notification again.

### Requirement 6: Session Persistence

**User Story:** As a user, I want my chat sessions and active session state to survive Quickshell restarts so that I don't lose my work.

#### Acceptance Criteria

1. THE Session_Manager SHALL store each Chat_Session as a separate JSON file in the `Directories.aiChats` directory using the session name as the filename.
2. THE Persistent_State SHALL store the active session name under `ai.activeSession` so it can be restored on startup.
3. WHEN Quickshell starts and the previously active session file exists, THE Session_Manager SHALL load that session's message history.
4. IF the previously active session file does not exist on startup, THEN THE Session_Manager SHALL create a new default Chat_Session and set it as active.
5. THE Session_Manager SHALL store session metadata (name, creation timestamp, last-modified timestamp) in a `sessions-index.json` file in the `Directories.aiChats` directory.
