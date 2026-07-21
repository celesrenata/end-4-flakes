# Requirements Document

## Introduction

The Desktop Demo Driver is an automated demonstration system that programmatically showcases every aspect of the user's Hyprland/Quickshell desktop environment. It uses ydotool for keyboard and mouse emulation to drive real interactions, creating a guided tour that highlights shell modules, workspace management, utilities, and MCP tool capabilities. The system supports running individual demo "scenes" independently or as a continuous full tour with configurable pacing.

## Glossary

- **Demo_Driver**: The orchestration engine that coordinates and executes demo scenes in sequence or individually
- **Scene**: A self-contained demonstration unit that showcases a specific desktop feature or workflow
- **Scene_Registry**: The data structure that catalogs all available scenes with metadata (name, description, duration, dependencies)
- **Ydotool_Service**: The QML singleton service that interfaces with the ydotool daemon for keyboard and mouse emulation
- **IPC_Signal**: A Quickshell global signal used to toggle shell modules (e.g., quickshell:sidebarLeftToggle)
- **MCP_Server**: The ii-desktop-mcp FastMCP server providing tools for querying and controlling the desktop environment
- **Pacing_Controller**: The timing subsystem that inserts delays between actions so demonstrations are visible to the viewer
- **State_Guard**: A pre-execution check that validates environmental preconditions before a scene runs
- **Tour**: A complete sequential execution of all scenes in a defined order
- **Trigger**: The mechanism that initiates a demo (keybind, MCP tool call, or CLI command)

## Requirements

### Requirement 1: Ydotool Mouse Emulation Extension

**User Story:** As a developer, I want the Ydotool QML service to support mouse emulation (move, click, scroll), so that demo scenes can simulate full pointer interactions alongside keyboard input.

#### Acceptance Criteria

1. THE Ydotool_Service SHALL expose a `moveMouse(x, y)` function that moves the pointer to absolute screen coordinates using ydotool mousemove
2. THE Ydotool_Service SHALL expose a `moveMouseRelative(dx, dy)` function that moves the pointer by a relative offset using ydotool mousemove
3. THE Ydotool_Service SHALL expose a `click(button)` function that performs a mouse click at the current pointer position, where button is 0 (left), 1 (right), or 2 (middle)
4. THE Ydotool_Service SHALL expose a `doubleClick(button)` function that performs two rapid clicks at the current pointer position
5. THE Ydotool_Service SHALL expose a `scroll(direction, amount)` function that scrolls vertically or horizontally by the specified amount
6. THE Ydotool_Service SHALL expose a `drag(startX, startY, endX, endY, button)` function that performs a press-move-release sequence
7. IF ydotool is not running or not accessible, THEN THE Ydotool_Service SHALL log an error and return a failure status without crashing

### Requirement 2: Demo Scene Engine

**User Story:** As a user, I want a scene-based orchestration engine that can run demonstrations sequentially or individually, so that I can showcase specific features or run a complete tour.

#### Acceptance Criteria

1. THE Demo_Driver SHALL maintain a Scene_Registry containing all available demo scenes with their metadata (name, description, estimated duration, category, dependencies)
2. THE Demo_Driver SHALL execute scenes sequentially when running a full Tour
3. WHEN a specific scene name is provided, THE Demo_Driver SHALL execute only that scene
4. WHEN a category name is provided, THE Demo_Driver SHALL execute all scenes in that category in order
5. THE Demo_Driver SHALL emit a signal before each scene starts, containing the scene name and description
6. THE Demo_Driver SHALL emit a signal after each scene completes, containing the scene name and success status
7. WHILE a Tour is running, THE Demo_Driver SHALL allow cancellation via a stop signal or keybind
8. IF a scene fails during execution, THEN THE Demo_Driver SHALL log the failure, skip to the next scene, and continue the Tour
9. THE Demo_Driver SHALL expose its current state (idle, running, paused, scene name) as readable properties

### Requirement 3: Pacing and Timing Control

**User Story:** As a viewer, I want demonstrations to have visible pacing between actions, so that I can follow what is happening on screen.

#### Acceptance Criteria

1. THE Pacing_Controller SHALL insert a configurable delay between each action within a scene (default: 800 milliseconds)
2. THE Pacing_Controller SHALL insert a configurable delay between scenes during a Tour (default: 2000 milliseconds)
3. THE Pacing_Controller SHALL support a speed multiplier property (0.5x to 3.0x) that scales all delays proportionally
4. WHEN the speed multiplier is set to a value outside the range 0.5 to 3.0, THE Pacing_Controller SHALL clamp the value to the nearest boundary
5. THE Pacing_Controller SHALL support a pause/resume mechanism that halts scene progression without cancelling the Tour
6. WHILE the Demo_Driver is paused, THE Pacing_Controller SHALL not advance to the next action until resumed

### Requirement 4: Shell Module Demonstrations

**User Story:** As a user, I want demo scenes that showcase each Quickshell module, so that viewers can see the full shell feature set.

#### Acceptance Criteria

1. WHEN the "sidebar-left" scene runs, THE Demo_Driver SHALL open the left sidebar via IPC_Signal (quickshell:sidebarLeftToggle), pause for visibility, then close the left sidebar
2. WHEN the "sidebar-right" scene runs, THE Demo_Driver SHALL open the right sidebar via IPC_Signal (quickshell:sidebarRightToggle), pause for visibility, then close the right sidebar
3. WHEN the "overview" scene runs, THE Demo_Driver SHALL open the overview via IPC_Signal (quickshell:overviewToggle), pause for visibility, then close the overview
4. WHEN the "cheatsheet" scene runs, THE Demo_Driver SHALL open the cheatsheet via IPC_Signal (quickshell:cheatsheetToggle), pause for visibility, then close the cheatsheet
5. WHEN the "media-controls" scene runs, THE Demo_Driver SHALL open the media controls panel via IPC_Signal (quickshell:mediaControlsToggle), pause for visibility, then close the media controls panel
6. WHEN the "on-screen-keyboard" scene runs, THE Demo_Driver SHALL open the on-screen keyboard via IPC_Signal (quickshell:oskToggle), pause for visibility, then close the on-screen keyboard
7. WHEN the "session-menu" scene runs, THE Demo_Driver SHALL open the session menu via IPC_Signal (quickshell:sessionToggle), pause for visibility, then close the session menu without executing any session action
8. WHEN the "clipboard-history" scene runs, THE Demo_Driver SHALL open the clipboard overlay via IPC_Signal (quickshell:overviewClipboardToggle), pause for visibility, then close the clipboard overlay
9. WHEN the "emoji-picker" scene runs, THE Demo_Driver SHALL open the emoji overlay via IPC_Signal (quickshell:overviewEmojiToggle), pause for visibility, then close the emoji overlay
10. WHEN the "bar-toggle" scene runs, THE Demo_Driver SHALL toggle the bar off via IPC_Signal (quickshell:barToggle), pause for visibility, then toggle the bar back on
11. WHEN the "dock" scene runs, THE Demo_Driver SHALL move the mouse to the dock region to reveal the dock, pause for visibility, then move the mouse away

### Requirement 5: Workspace Management Demonstrations

**User Story:** As a user, I want demo scenes that show workspace creation, switching, and window movement across workspaces, so that viewers understand the workspace system.

#### Acceptance Criteria

1. WHEN the "workspace-switching" scene runs, THE Demo_Driver SHALL switch through workspaces 1 through 5 sequentially using keyboard emulation (Super+1 through Super+5), pausing on each workspace
2. WHEN the "workspace-overview" scene runs, THE Demo_Driver SHALL open the workspace overview via IPC_Signal (quickshell:overviewWorkspacesToggle), pause for visibility, then close the overview
3. WHEN the "window-move-workspace" scene runs, THE Demo_Driver SHALL move the active window to workspace 3 using keyboard emulation (Super+Alt+3), switch to workspace 3, pause for visibility, then move the window back to the original workspace
4. WHEN the "workspace-scroll" scene runs, THE Demo_Driver SHALL scroll through adjacent workspaces using Ctrl+Super+Right and Ctrl+Super+Left keyboard emulation
5. WHEN the "special-workspace" scene runs, THE Demo_Driver SHALL toggle the scratchpad workspace via keyboard emulation (Super+S), pause for visibility, then toggle the scratchpad closed

### Requirement 6: Window Management Demonstrations

**User Story:** As a user, I want demo scenes that demonstrate window tiling, floating, fullscreen, and focus switching, so that viewers understand the tiling window manager.

#### Acceptance Criteria

1. WHEN the "window-tile-float" scene runs, THE Demo_Driver SHALL toggle the active window to floating mode (Super+Alt+Space), move the floating window using mouse drag emulation, then toggle the window back to tiled mode
2. WHEN the "window-fullscreen" scene runs, THE Demo_Driver SHALL maximize the active window (Super+D), pause for visibility, fullscreen the window (Super+F), pause for visibility, then restore the window to tiled state
3. WHEN the "window-focus" scene runs, THE Demo_Driver SHALL cycle focus between visible windows using directional keys (Super+Left, Super+Right, Super+Up, Super+Down)
4. WHEN the "window-resize" scene runs, THE Demo_Driver SHALL adjust the active window split ratio using Super+Semicolon and Super+Apostrophe keyboard emulation
5. WHEN the "window-close" scene runs, THE Demo_Driver SHALL launch a disposable application, pause for visibility, then close the window using keyboard emulation (Super+Q)

### Requirement 7: Utility Feature Demonstrations

**User Story:** As a user, I want demo scenes that showcase utility features like screenshots, color picker, and zoom, so that viewers see the productivity tools available.

#### Acceptance Criteria

1. WHEN the "screenshot" scene runs, THE Demo_Driver SHALL capture a fullscreen screenshot using the Print key emulation, pause for visibility of the notification, then demonstrate the screen snip keybind (Super+Shift+S) with a predefined region selection via mouse emulation
2. WHEN the "color-picker" scene runs, THE Demo_Driver SHALL invoke the color picker via keyboard emulation (Super+Shift+C), move the mouse to a colorful screen region, click to pick the color, and pause for visibility of the result notification
3. WHEN the "zoom" scene runs, THE Demo_Driver SHALL zoom in three times using Super+Equal keyboard emulation, pause for visibility, then zoom out three times using Super+Minus to restore normal zoom level
4. WHEN the "wallpaper" scene runs, THE Demo_Driver SHALL trigger a random wallpaper change via IPC_Signal (quickshell:wallpaperSelectorRandom) and pause for visibility of the transition
5. WHEN the "light-dark-toggle" scene runs, THE Demo_Driver SHALL toggle between light and dark mode via IPC_Signal (quickshell:toggleLightDark), pause for visibility, then toggle back to the original mode

### Requirement 8: Application Launch Demonstrations

**User Story:** As a user, I want demo scenes that show launching common applications, so that viewers see how apps are accessed.

#### Acceptance Criteria

1. WHEN the "launch-terminal" scene runs, THE Demo_Driver SHALL launch a terminal using keyboard emulation (Super+Return), pause for visibility, then close the terminal window (Super+Q)
2. WHEN the "launch-browser" scene runs, THE Demo_Driver SHALL launch a browser using keyboard emulation (Super+W), wait for the window to appear, pause for visibility, then close the window (Super+Q)
3. WHEN the "launch-file-manager" scene runs, THE Demo_Driver SHALL launch a file manager using keyboard emulation (Super+E), wait for the window to appear, pause for visibility, then close the window (Super+Q)
4. WHEN the "launch-from-overview" scene runs, THE Demo_Driver SHALL open the overview (quickshell:overviewToggle), type an application name using keyboard emulation, pause for visibility, then close the overview without launching

### Requirement 9: MCP Tool Integration Demonstrations

**User Story:** As a user, I want demo scenes that showcase the ii-desktop-mcp tools by querying and displaying system state, so that viewers understand the MCP integration capabilities.

#### Acceptance Criteria

1. WHEN the "mcp-system-info" scene runs, THE Demo_Driver SHALL use the MCP_Server system_info tool to gather hardware information, display the results as a notification, and pause for visibility
2. WHEN the "mcp-audio-control" scene runs, THE Demo_Driver SHALL use the MCP_Server audio_status tool to read current volume, adjust volume up by 10% using audio_set_volume, pause for visibility, then restore the original volume
3. WHEN the "mcp-workspace-query" scene runs, THE Demo_Driver SHALL use the MCP_Server list_workspaces tool to enumerate active workspaces, display the count as a notification, and pause for visibility
4. WHEN the "mcp-network-status" scene runs, THE Demo_Driver SHALL use the MCP_Server network_status tool to read connectivity state, display a summary notification, and pause for visibility
5. WHEN the "mcp-clipboard" scene runs, THE Demo_Driver SHALL use the MCP_Server clipboard_list tool to show recent clipboard entries, display the count as a notification, and pause for visibility
6. WHEN the "mcp-diagnostics" scene runs, THE Demo_Driver SHALL use the MCP_Server diagnostic_bundle tool to collect a system snapshot, display a summary notification with key health indicators, and pause for visibility

### Requirement 10: Demo Triggering Mechanisms

**User Story:** As a user, I want multiple ways to start a demo (keybind, MCP tool, CLI), so that demonstrations can be initiated from any context.

#### Acceptance Criteria

1. THE Demo_Driver SHALL be triggerable via a dedicated Hyprland keybind (Super+Alt+F10) to start the full Tour
2. THE Demo_Driver SHALL be triggerable via an IPC_Signal (quickshell:demoStart) that accepts an optional scene name parameter
3. THE Demo_Driver SHALL be triggerable via a CLI command that accepts optional arguments for scene name, category, or speed multiplier
4. THE Demo_Driver SHALL be stoppable via a keybind (Super+Alt+F10 when running, acting as a toggle) or an IPC_Signal (quickshell:demoStop)
5. WHEN a new trigger is received while a Tour is already running, THE Demo_Driver SHALL stop the current Tour and start the newly requested demonstration

### Requirement 11: State Guards and Edge Case Handling

**User Story:** As a developer, I want the demo driver to validate preconditions before each scene and handle failures gracefully, so that demonstrations do not break or leave the desktop in a bad state.

#### Acceptance Criteria

1. WHEN a scene requires a specific window to exist, THE State_Guard SHALL verify the window exists using hyprctl clients query before executing the scene
2. WHEN a scene requires audio to be unmuted, THE State_Guard SHALL check and unmute audio before executing the audio demonstration scene
3. IF a State_Guard check fails and the precondition cannot be automatically resolved, THEN THE Demo_Driver SHALL skip the scene and log the reason
4. WHEN a Tour completes or is cancelled, THE Demo_Driver SHALL restore the desktop to its pre-tour state (original workspace, zoom level, volume, and light/dark mode)
5. IF a keyboard or mouse emulation command fails, THEN THE Demo_Driver SHALL retry the command once after a 500-millisecond delay before marking the action as failed
6. WHEN a scene opens a shell module (sidebar, overview, cheatsheet), THE State_Guard SHALL verify the module is closed at scene end, closing the module if the expected toggle did not work
7. THE Demo_Driver SHALL record the pre-tour desktop state (active workspace, zoom level, volume, mute status, light/dark mode) before starting any scene execution

### Requirement 12: Nix Packaging and Service Integration

**User Story:** As a NixOS user, I want the demo driver to be packaged as part of the flake and integrated with home-manager, so that installation and updates follow the standard Nix workflow.

#### Acceptance Criteria

1. THE Demo_Driver SHALL be distributable as a Nix package within the end-4-flakes repository
2. THE Demo_Driver SHALL declare ydotool as a runtime dependency in its Nix package definition
3. WHEN the home-manager module is enabled, THE Demo_Driver SHALL register the dedicated keybind in the Hyprland keybind configuration
4. THE Demo_Driver SHALL integrate with the existing Quickshell configuration structure under the configs/quickshell directory
5. IF the ydotoold daemon is not running, THEN THE Demo_Driver SHALL display a notification indicating that ydotoold must be started before demonstrations can run

### Requirement 13: Scene Metadata and Discovery

**User Story:** As a user, I want to list available demo scenes with descriptions and categories, so that I can choose which demonstration to run.

#### Acceptance Criteria

1. THE Scene_Registry SHALL categorize scenes into groups: "shell", "workspace", "window", "utility", "app-launch", "mcp"
2. THE Scene_Registry SHALL provide a list operation that returns all scenes with their name, description, category, and estimated duration
3. WHEN queried via the CLI or MCP tool, THE Scene_Registry SHALL return scene metadata in a structured format (JSON)
4. THE Scene_Registry SHALL include a total estimated duration for the full Tour based on the sum of scene durations plus inter-scene delays
