# Bugfix Requirements Document

## Introduction

The left sidebar's AI Chat (Intelligence tab) has several usability bugs affecting scrolling, markdown rendering, and interactive navigation. These bugs degrade the chat experience when viewing AI responses containing code blocks or tables, and when navigating long conversation histories. The affected components are primarily in `modules/sidebarLeft/` and `modules/sidebarLeft/aiChat/`.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN an AI response contains a markdown table AND the MessageTextBlock TextArea width is narrow (sidebar at default or near-minimum width) THEN the system renders the table with empty/collapsed cells where data should be visible

1.2 WHEN a user scrolls up or down through the AI chat message history THEN the system provides no visible or interactive scrollbar element that can be grabbed and dragged with the mouse

1.3 WHEN the mouse cursor is positioned over a code block (MessageCodeBlock) in an AI response AND the user scrolls the mouse wheel vertically THEN the system blocks the vertical scroll event from propagating to the parent message list, preventing the user from scrolling past the code block

1.4 WHEN a user has a long conversation history in the AI chat system THEN the system provides no mechanism overview or introspection of how sessions, messages, context management, and the overall chat lifecycle work together (this is a documentation/review gap rather than a runtime defect)

### Expected Behavior (Correct)

2.1 WHEN an AI response contains a markdown table AND the sidebar width is narrow THEN the system SHALL render the table with all cell data visible, using horizontal scrolling or text wrapping within cells to accommodate narrow widths without collapsing columns to zero

2.2 WHEN a user views the AI chat message list THEN the system SHALL display an interactive vertical scrollbar that the user can grab and drag with the mouse to navigate the conversation history, appearing on hover or during scroll activity

2.3 WHEN the mouse cursor is over a code block AND the user scrolls the mouse wheel vertically THEN the system SHALL propagate the vertical scroll event to the parent message list (messageListView), allowing uninterrupted vertical scrolling through the entire conversation regardless of cursor position over code blocks

2.4 WHEN reviewing the AI chat system architecture THEN the system SHALL have clear documentation or a mechanism review of how sessions, messages, context compaction, message versioning, and the chat lifecycle operate together

### Unchanged Behavior (Regression Prevention)

3.1 WHEN an AI response contains inline code, bold text, links, or other non-table markdown formatting THEN the system SHALL CONTINUE TO render these elements correctly in the MessageTextBlock

3.2 WHEN a user scrolls the message list via mouse wheel over regular text blocks THEN the system SHALL CONTINUE TO scroll smoothly with the existing animated scroll behavior

3.3 WHEN a code block has content wider than its container THEN the system SHALL CONTINUE TO allow horizontal scrolling within the code block via the horizontal scrollbar

3.4 WHEN a user flicks/drags the message list to scroll THEN the system SHALL CONTINUE TO support touch-style drag scrolling with the existing bounce-back behavior

3.5 WHEN a user uses keyboard shortcuts (PageUp/PageDown) to navigate messages THEN the system SHALL CONTINUE TO scroll the message list as currently implemented

3.6 WHEN new messages arrive and the user is near the bottom of the chat THEN the system SHALL CONTINUE TO auto-scroll to show the latest message

3.7 WHEN a user switches sessions, saves, loads, or creates new chat sessions THEN the system SHALL CONTINUE TO manage session state correctly without data loss
