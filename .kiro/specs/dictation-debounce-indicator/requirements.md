# Requirements Document

## Introduction

The Logitech Dictation button fires a Ctrl+H combo 3 times in rapid succession (~300ms apart), causing DictationService to receive multiple dictationTap signals. This creates a state machine loop (activate → stop → reset → activate). This feature adds signal debouncing to prevent multi-fire activation, and enhances the DictationIndicator with color-coded state feedback so the user has clear visual confirmation of what the dictation system is doing at all times.

## Glossary

- **Debounce_Guard**: A timing mechanism in DictationService that suppresses duplicate dictationTap signals arriving within a configurable window after the first activation signal is processed.
- **DictationService**: The QML Singleton service managing dictation state transitions, recording, and transcription.
- **DictationIndicator**: The floating overlay PanelWindow that displays dictation status to the user.
- **Dictation_Tap_Signal**: The GlobalShortcut signal named "dictationTap" received from Hyprland when the Logitech button fires.
- **Debounce_Window**: The time period (default 500ms) after activation during which subsequent Dictation_Tap_Signals are ignored.
- **Initializing_State**: A visual sub-state shown in the indicator when dictation has just activated but no audio has been detected yet.
- **Recording_State**: A visual sub-state shown in the indicator when the microphone is actively picking up audio.
- **Processing_State**: A visual sub-state shown in the indicator during transcription.
- **Primary_Monitor**: The monitor identified as the focused monitor by Hyprland.

## Requirements

### Requirement 1: Signal Debounce on Activation

**User Story:** As a user with a Logitech Dictation button, I want duplicate rapid-fire signals to be ignored after the first activation, so that the dictation service does not enter a start-stop loop.

#### Acceptance Criteria

1. WHEN a Dictation_Tap_Signal activates DictationService from the Idle state, THE Debounce_Guard SHALL start the Debounce_Window timer (default 500ms).
2. WHILE the Debounce_Window timer is running, THE Debounce_Guard SHALL discard any incoming Dictation_Tap_Signal without changing DictationService state.
3. WHEN the Debounce_Window timer expires, THE Debounce_Guard SHALL allow subsequent Dictation_Tap_Signals to be processed normally.
4. WHEN a Dictation_Tap_Signal arrives after the Debounce_Window has expired AND DictationService is in Listening or StreamingActive state, THE DictationService SHALL stop recording (existing behavior preserved).

### Requirement 2: Debounce Configuration

**User Story:** As a user, I want the debounce duration to be configurable, so that I can tune it if my hardware fires at a different rate.

#### Acceptance Criteria

1. THE DictationService SHALL expose a configurable `debounceMs` property with a default value of 500.
2. WHEN `debounceMs` is set to 0, THE Debounce_Guard SHALL be disabled and all Dictation_Tap_Signals SHALL be processed immediately.

### Requirement 3: Initializing Visual State

**User Story:** As a user, I want to see that dictation has started even before audio is detected, so that I know the system acknowledged my button press.

#### Acceptance Criteria

1. WHEN DictationService transitions to Listening or StreamingActive state, THE DictationIndicator SHALL display the microphone icon in an amber/yellow color with a pulsing animation.
2. WHILE DictationService is in Listening or StreamingActive state AND no audio activity has been detected, THE DictationIndicator SHALL remain in the Initializing_State visual appearance.

### Requirement 4: Recording Visual State

**User Story:** As a user, I want clear feedback when the microphone is actually picking up sound, so that I know my voice is being captured.

#### Acceptance Criteria

1. WHEN the silence monitor reports audio activity (RMS above threshold) for the first time after activation, THE DictationIndicator SHALL transition the microphone icon color from amber to green.
2. WHILE DictationService is in Listening or StreamingActive state AND audio has been detected, THE DictationIndicator SHALL display the microphone icon in green with a steady pulse animation.

### Requirement 5: Processing Visual State

**User Story:** As a user, I want to see that my recording is being transcribed, so that I know the system is working on my input.

#### Acceptance Criteria

1. WHEN DictationService transitions to the Processing state, THE DictationIndicator SHALL display a blue-colored processing icon with a rotation animation.
2. WHILE DictationService is in Processing state, THE DictationIndicator SHALL show a "Transcribing..." status label alongside the blue processing icon.

### Requirement 6: Indicator Dismissal

**User Story:** As a user, I want the indicator to disappear smoothly when dictation completes or errors out, so that it does not linger and obstruct my workflow.

#### Acceptance Criteria

1. WHEN DictationService transitions from Processing or Error state to Idle, THE DictationIndicator SHALL fade out over a duration between 200ms and 500ms.
2. WHEN DictationService transitions to Error state, THE DictationIndicator SHALL display the error for 2 seconds before beginning the fade-out.

### Requirement 7: Indicator Positioning and Focus Behavior

**User Story:** As a user, I want the dictation indicator to be visible above all windows without stealing focus, so that it does not interrupt my current task.

#### Acceptance Criteria

1. THE DictationIndicator SHALL render in the Wayland Overlay layer (WlrLayer.Overlay) with exclusiveZone set to 0.
2. THE DictationIndicator SHALL be positioned at the top-right area of the Primary_Monitor, offset below the status bar.
3. THE DictationIndicator SHALL NOT receive keyboard focus or steal focus from the active window.

### Requirement 8: Audio Detection Signal

**User Story:** As a developer, I want DictationService to expose an audio-detected flag, so that the DictationIndicator can differentiate between initializing and actively recording states.

#### Acceptance Criteria

1. WHEN the silence monitor first reports "AUDIO" after DictationService enters Listening or StreamingActive state, THE DictationService SHALL set an `audioDetected` property to true.
2. WHEN DictationService transitions to Idle state, THE DictationService SHALL reset the `audioDetected` property to false.
