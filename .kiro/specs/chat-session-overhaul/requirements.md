# Requirements Document

## Introduction

Overhaul of the Quickshell sidebar chat system to deliver a polished, session-aware AI chat experience. This spec captures the desired end-state for viewport anchoring, session persistence, session management, context compaction, search, prior chat management, smart dictation routing, and HyprMCP theme/behavior customization. Some of these features exist in partial or broken form and need to be audited and corrected during implementation.

## Glossary

- **Chat_View**: The `AiChat.qml` component that renders the message list, input area, and session drawer in the sidebar
- **Session_Drawer**: The collapsible panel within Chat_View that lists all chat sessions and provides management actions
- **Ai_Service**: The `Ai.qml` singleton service responsible for message storage, session lifecycle, model communication, and context tracking
- **Session**: A named, persisted collection of messages with metadata (name, creation date, last modified timestamp)
- **Free_Dictation_Session**: A protected session named "Free Dictation" that receives voice-dictated input; cannot be renamed
- **Context_Meter**: The UI element displaying current context window usage as a progress bar and text
- **Persistent_State**: The `Persistent.qml` singleton that stores shell state across restarts (model, temperature, active session)
- **Config_Service**: The `Config.qml` singleton that manages user-configurable options
- **Dictation_Service**: The `DictationService.qml` singleton that manages voice recording, transcription, and intent routing
- **HyprMCP_Service**: The MCP server at `ii-desktop-mcp` providing tools for querying and modifying Hyprland configuration
- **Trivial_Command**: A dictation utterance that maps to a simple desktop action (open app, maximize window, change workspace, adjust volume, etc.) requiring no AI summarization
- **Context_Compaction**: The process of summarizing conversation history into a condensed form to free context window space
- **Prior_Chat**: A saved chat session that is not currently active, accessible for review and management

## Requirements

### Requirement 1: Chat Viewport Anchors at Bottom

**User Story:** As a user, I want the chat to start scrolled to the newest messages when I open it, so that I immediately see the latest context without manual scrolling.

#### Acceptance Criteria

1. WHEN the Chat_View becomes visible, THE Chat_View SHALL position the viewport such that the bottommost message is within 10 pixels of the viewport's bottom edge
2. WHEN a Session is loaded or switched to, THE Chat_View SHALL position the viewport at the bottom of the message list within 200 milliseconds of the switch completing
3. WHILE the viewport is within 10 pixels of the bottom edge, WHEN a new message is appended, THE Chat_View SHALL auto-scroll to keep the newest message visible
4. WHILE the viewport is more than 10 pixels above the bottom edge, WHEN a new message is appended, THE Chat_View SHALL NOT auto-scroll and SHALL preserve the current scroll position
5. WHEN the user scrolls upward during an active auto-scroll animation, THE Chat_View SHALL immediately cancel the auto-scroll and preserve the user's scroll position

### Requirement 2: Restore Last Open Chat on Reopen

**User Story:** As a user, I want the sidebar to remember which chat I was viewing, so that reopening the sidebar or restarting the shell restores my previous context.

#### Acceptance Criteria

1. WHEN the user switches to a Session, THE Ai_Service SHALL persist the active Session name to Persistent_State before any subsequent user interaction is processed
2. WHEN the sidebar becomes visible after being closed, THE Chat_View SHALL load and display the message history of the Session whose name is stored in Persistent_State
3. WHEN the shell restarts, THE Ai_Service SHALL load the Session stored in Persistent_State and restore all messages from that Session's save file in their original order
4. IF the persisted Session name references a Session whose save file does not exist or whose name is absent from the sessions index, THEN THE Ai_Service SHALL fall back to the most recently modified Session according to the sessions index
5. IF no sessions exist in the sessions index when restoring, THEN THE Ai_Service SHALL create a new default Session using the next available default name

### Requirement 3: Full Chat Content Swap on Session Switch

**User Story:** As a user, I want switching between sessions to completely replace the displayed messages, so that I see only the selected session's content without any remnants from the prior session.

#### Acceptance Criteria

1. WHEN the user selects a different Session from the Session_Drawer, THE Chat_View SHALL clear all displayed messages and disable the input field before rendering the new Session's messages
2. WHEN the user selects a different Session, THE Ai_Service SHALL fully unload the previous Session's message data from the active message store such that zero messages from the previous Session remain
3. WHEN a Session switch completes, THE Chat_View SHALL display only messages belonging to the newly active Session and re-enable the input field
4. WHEN a Session switch completes, THE Chat_View SHALL position the viewport at the bottom of the newly loaded messages
5. IF the target Session's persisted file cannot be loaded during a switch, THEN THE Ai_Service SHALL display an error message indicating the Session could not be loaded and SHALL remain on the previously active Session with its messages intact

### Requirement 4: Session Purge and Rename

**User Story:** As a user, I want to purge (clear all messages) and rename my chat sessions, so that I can keep my session list organized and reset conversations without deleting the session itself.

#### Acceptance Criteria

1. WHEN the user selects "Purge" on a Session, THE Ai_Service SHALL remove all messages from that Session, persist the empty message list to disk, and preserve the Session entry in the sessions index
2. WHEN the user selects "Rename" on a Session, THE Ai_Service SHALL update the Session name in the sessions index, rename the persisted file on disk, and update Persistent_State if the renamed Session is the active session
3. THE Session_Drawer SHALL display both purge and rename actions for all Sessions except the Free_Dictation_Session
4. THE Session_Drawer SHALL display only the purge action for the Free_Dictation_Session
5. THE Session_Drawer SHALL NOT display the rename action for the Free_Dictation_Session
6. IF the user attempts to rename a Session to a name that already exists in the sessions index, THEN THE Ai_Service SHALL reject the rename and display an inline error message indicating a duplicate name
7. IF the user attempts to rename a Session to an empty string or a string containing path separator characters (/ or \\), THEN THE Ai_Service SHALL reject the rename

### Requirement 5: Context Compaction and Summarization

**User Story:** As a user, I want to compact my conversation context or summarize it into a new auto-named chat, so that I can continue working without losing important context when the context window fills up.

#### Acceptance Criteria

1. WHEN the user issues the `/compact` command on the active Session, THE Ai_Service SHALL send the conversation history to the current model for summarization and replace the message history with a single system-role message containing the returned summary
2. WHEN the user issues the `/summarize` command on the active Session, THE Ai_Service SHALL create a new Session with a model-generated title of at most 50 characters describing the conversation topic, populate it with a single system-role summary message, switch to the new session, and leave the original Session unchanged
3. IF the model fails to generate a summary during compaction or summarize-to-new-chat (network error or empty response), THEN THE Ai_Service SHALL preserve the original Session's message history unchanged and display an error message indicating the summarization failed
4. THE Context_Meter SHALL display the current context usage as both a percentage value and the maximum token count for the current model (e.g., "42% of 128k")
5. WHEN context usage exceeds 85% for the first time in a Session, THE Chat_View SHALL display a non-blocking, dismissible notification suggesting the user run `/compact`
6. WHEN context usage reaches 100% (estimated tokens meet or exceed context_length), THE Chat_View SHALL disable the message input field and display actions offering compaction and model switch options

### Requirement 6: Chat Search with Filters

**User Story:** As a user, I want to search within a chat using filters, so that I can quickly locate specific messages by keyword, date, subject, or group.

#### Acceptance Criteria

1. THE Chat_View SHALL provide a search interface accessible from the chat toolbar
2. WHEN the user enters a keyword of at least 2 characters, THE Chat_View SHALL filter and highlight messages containing that keyword (case-insensitive, substring match) in the active Session
3. WHERE the date filter is active, THE Chat_View SHALL display only messages sent within the specified date range, where either a start date, an end date, or both may be provided
4. WHERE the subject filter is active, THE Chat_View SHALL display only messages whose subject or topic contains the specified filter text as a case-insensitive substring
5. WHERE the group filter is active, THE Chat_View SHALL display only messages belonging to the specified group
6. WHEN search results are displayed, THE Chat_View SHALL allow navigation between matches using next/previous controls, wrapping from the last match back to the first and from the first match forward to the last
7. IF the search query and active filters yield no matching messages, THEN THE Chat_View SHALL display an empty-state indicator informing the user that no results were found
8. IF the user enters a keyword shorter than 2 characters, THEN THE Chat_View SHALL not execute the search and SHALL indicate the minimum required length

### Requirement 7: Prior Chat Management

**User Story:** As a user, I want to archive, group, edit subjects, and delete prior chat sessions, so that I can organize my conversation history meaningfully.

#### Acceptance Criteria

1. WHEN the user selects "Archive" on a Prior_Chat, THE Ai_Service SHALL set the Session's `archived` metadata flag to true and remove it from the active session list in the Session_Drawer
2. WHEN the user selects "Unarchive" on an archived Session, THE Ai_Service SHALL set the Session's `archived` metadata flag to false and restore it to the active session list
3. WHEN the user selects "Group" on a Prior_Chat, THE Ai_Service SHALL prompt for a group label and assign it to the Session's `group` metadata field, where the label must be between 1 and 64 characters
4. IF the user provides an empty or whitespace-only group label, THEN THE Ai_Service SHALL reject the assignment and retain the Session's current group value
5. WHEN the user selects "Edit Subject" on a Prior_Chat, THE Ai_Service SHALL prompt for a new subject string and update the Session's `subject` metadata field, where the subject must be between 1 and 128 characters
6. WHEN the user selects "Delete" on a Prior_Chat, THE Ai_Service SHALL present a confirmation prompt before permanently removing the Session's persisted file and its entry from the sessions index
7. IF the user attempts to delete the currently active Session, THEN THE Ai_Service SHALL reject the deletion and display an error message indicating the active session cannot be deleted
8. THE Session_Drawer SHALL display archived Sessions in a separate collapsible section positioned below the active session list
9. THE Session_Drawer SHALL display group labels as section headers in alphabetical order, with grouped Sessions listed under their respective header

### Requirement 8: Smart Dictation Routing for Free Dictation

**User Story:** As a user, I want my Free Dictation input to automatically summarize the current task unless it's a trivial command, so that voice notes capture context intelligently while simple commands execute immediately.

#### Acceptance Criteria

1. WHERE the smart dictation routing option is enabled in sidebar settings, THE Dictation_Service SHALL classify each utterance sent to the Free_Dictation_Session as either a Trivial_Command or non-trivial using the Intent_Classifier heuristic rules (imperative verb prefix, question patterns) or, when `Config.options.dictation.intentMode` is "ai", by invoking the configured LLM
2. WHEN a dictated utterance is classified as a Trivial_Command, THE Dictation_Service SHALL route the command text to the Action_Pipeline for execution without sending it to the AI model or storing it as a chat message in the Free_Dictation_Session
3. WHEN a dictated utterance is classified as non-trivial, THE Dictation_Service SHALL send the utterance text along with the active window title and current session message history (last 5 messages) to the AI model with a summarization prompt, and store the AI-generated summary as an assistant message in the Free_Dictation_Session
4. THE Config_Service SHALL provide a togglable "Smart Dictation Routing" option in the sidebar settings section with a default value of disabled
5. IF intent classification fails due to timeout (no response within 5 seconds) or returns an error, THEN THE Dictation_Service SHALL default to sending the utterance as a normal user message to the Free_Dictation_Session without summarization
6. IF the utterance is under 20 words and does not match any Trivial_Command heuristic pattern, THEN THE Dictation_Service SHALL treat the classification as ambiguous and default to sending the utterance as a normal user message to the Free_Dictation_Session

### Requirement 9: HyprMCP Integration for Theme and Behavior Customization

**User Story:** As a user, I want to customize Hyprland theme pieces and behaviors from the sidebar chat using the HyprMCP service, so that I can tweak my desktop without manually editing config files.

#### Acceptance Criteria

1. THE Ai_Service SHALL expose HyprMCP tools (config_read, config_set, set_keyword) as available function calls for the active AI model
2. WHEN the AI model calls a config modification tool, THE Ai_Service SHALL invoke the corresponding HyprMCP_Service endpoint to apply the change (config_set for Quickshell configuration, set_keyword for Hyprland runtime keywords)
3. WHEN a config modification is applied, THE Ai_Service SHALL read back the value from the active configuration within 3 seconds to verify the change took effect
4. IF the read-back value does not match the intended change, THEN THE Ai_Service SHALL display a message to the user indicating the expected value and the actual value returned by the read-back
5. IF the HyprMCP_Service is unreachable or returns an error when a tool is invoked, THEN THE Ai_Service SHALL display an error message to the user indicating that the configuration change could not be applied and include the failure reason from the service
6. WHEN the AI model calls config_read or set_keyword in read mode, THE Ai_Service SHALL invoke HyprMCP_Service and return the current configuration state to the model within the same tool-call response
7. THE Ai_Service SHALL NOT present a config modification as successful to the user without completing the verification read-back step

### Requirement 10: Voice Dictation Auto-Submits to Free Dictation

**User Story:** As a user, I want voice-dictated text that is routed to the Free Dictation session to be sent immediately as a message, so that it is processed by the AI rather than sitting idle in the input field.

#### Acceptance Criteria

1. WHEN DictationService emits `transcriptionComplete` and the active Session is the Free_Dictation_Session, THE Chat_View SHALL immediately submit the transcribed text as a user message via `Ai.sendUserMessage()` without requiring manual confirmation
2. WHEN DictationService emits `transcriptionComplete` and the active Session is NOT the Free_Dictation_Session, THE Chat_View SHALL place the transcribed text into the input field at the cursor position without auto-submitting, preserving existing behavior for manual editing before send
3. WHEN the transcribed text is auto-submitted to the Free_Dictation_Session, THE Chat_View SHALL clear the input field after submission
4. IF the transcribed text is empty or whitespace-only, THEN THE Chat_View SHALL NOT submit the message and SHALL NOT modify the input field
