-- Lines ending with [hidden] won't be shown on cheatsheet
-- Lines starting with #! are section headings

local qsConfig = "ii"

--
--- Shell
-- These absolutely need to be on top, or they won't work consistently
hl.bind("Super + Super_L", hl.dsp.global("quickshell:overviewToggleRelease"), { release = true, description = "Toggle overview" }) -- Toggle overview/launcher
hl.bind("Super + Super_R", hl.dsp.global("quickshell:overviewToggleRelease"), { release = true }) -- [hidden] Toggle overview/launcher
hl.bind("Super + Super_L", hl.dsp.exec_cmd("qs -c " .. qsConfig .. " ipc call TEST_ALIVE || pkill fuzzel || fuzzel")) -- [hidden] Launcher (fallback)
hl.bind("Super + Super_R", hl.dsp.exec_cmd("qs -c " .. qsConfig .. " ipc call TEST_ALIVE || pkill fuzzel || fuzzel")) -- [hidden] Launcher (fallback)
hl.bind("Super + catchall", hl.dsp.global("quickshell:overviewToggleReleaseInterrupt"), { release = true, transparent = true, non_consuming = true }) -- [hidden]
hl.bind("Ctrl + Super_L", hl.dsp.global("quickshell:overviewToggleReleaseInterrupt")) -- [hidden]
hl.bind("Ctrl + Super_R", hl.dsp.global("quickshell:overviewToggleReleaseInterrupt")) -- [hidden]
hl.bind("Super + mouse:272", hl.dsp.global("quickshell:overviewToggleReleaseInterrupt")) -- [hidden]
hl.bind("Super + mouse:273", hl.dsp.global("quickshell:overviewToggleReleaseInterrupt")) -- [hidden]
hl.bind("Super + mouse:274", hl.dsp.global("quickshell:overviewToggleReleaseInterrupt")) -- [hidden]
hl.bind("Super + mouse:275", hl.dsp.global("quickshell:overviewToggleReleaseInterrupt")) -- [hidden]
hl.bind("Super + mouse:276", hl.dsp.global("quickshell:overviewToggleReleaseInterrupt")) -- [hidden]
hl.bind("Super + mouse:277", hl.dsp.global("quickshell:overviewToggleReleaseInterrupt")) -- [hidden]
hl.bind("Super + mouse_up", hl.dsp.global("quickshell:overviewToggleReleaseInterrupt")) -- [hidden]
hl.bind("Super + mouse_down", hl.dsp.global("quickshell:overviewToggleReleaseInterrupt")) -- [hidden]

hl.bind("Super_L", hl.dsp.global("quickshell:workspaceNumber"), { release = true, transparent = true }) -- [hidden]
hl.bind("Super_R", hl.dsp.global("quickshell:workspaceNumber"), { release = true, transparent = true }) -- [hidden]
hl.bind("Super + V", hl.dsp.global("quickshell:overviewClipboardToggle"), { description = "Clipboard history >> clipboard" }) -- Clipboard history >> clipboard
hl.bind("Super + Period", hl.dsp.global("quickshell:overviewEmojiToggle"), { description = "Emoji >> clipboard" }) -- Emoji >> clipboard
hl.bind("Super + Tab", hl.dsp.global("quickshell:overviewToggle"), { description = "Toggle overview" }) -- [hidden] Toggle overview/launcher (alt)
hl.bind("Super + A", hl.dsp.global("quickshell:sidebarLeftToggle"), { description = "Toggle left sidebar" }) -- Toggle left sidebar
hl.bind("Super + Alt + A", hl.dsp.global("quickshell:sidebarLeftToggleDetach")) -- [hidden]
hl.bind("Super + B", hl.dsp.global("quickshell:sidebarLeftToggle")) -- [hidden]
hl.bind("Super + O", hl.dsp.global("quickshell:sidebarLeftToggle")) -- [hidden]
hl.bind("Super + N", hl.dsp.global("quickshell:sidebarRightToggle"), { description = "Toggle right sidebar" }) -- Toggle right sidebar
hl.bind("Super + Slash", hl.dsp.global("quickshell:cheatsheetToggle"), { description = "Toggle cheatsheet" }) -- Toggle cheatsheet
hl.bind("Super + K", hl.dsp.global("quickshell:oskToggle"), { description = "Toggle on-screen keyboard" }) -- Toggle on-screen keyboard
hl.bind("Super + M", hl.dsp.global("quickshell:mediaControlsToggle"), { description = "Toggle media controls" }) -- Toggle media controls
hl.bind("Ctrl + Alt + Delete", hl.dsp.global("quickshell:sessionToggle"), { description = "Toggle session menu" }) -- Toggle session menu
hl.bind("Super + J", hl.dsp.global("quickshell:barToggle"), { description = "Toggle bar" }) -- Toggle bar
hl.bind("Ctrl + Alt + Delete", hl.dsp.exec_cmd("qs -c " .. qsConfig .. " ipc call TEST_ALIVE || pkill wlogout || wlogout -p layer-shell")) -- [hidden] Session menu (fallback)
hl.bind("Shift + Super + Alt + Slash", hl.dsp.exec_cmd("qs -p ~/.config/quickshell/" .. qsConfig .. "/welcome.qml")) -- [hidden] Launch welcome app

hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("qs -c " .. qsConfig .. " ipc call brightness increment || brightnessctl s 5%+"), { locked = true, repeating = true }) -- [hidden]
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("qs -c " .. qsConfig .. " ipc call brightness decrement || brightnessctl s 5%-"), { locked = true, repeating = true }) -- [hidden]
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 2%+"), { locked = true, repeating = true }) -- [hidden]
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"), { locked = true, repeating = true }) -- [hidden]

hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SINK@ toggle"), { locked = true }) -- [hidden]
hl.bind("Super + Shift + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SINK@ toggle"), { locked = true, description = "Toggle mute" }) -- [hidden]
hl.bind("Alt + XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"), { locked = true }) -- [hidden]
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"), { locked = true }) -- [hidden]
hl.bind("Super + Alt + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"), { locked = true, description = "Toggle mic" }) -- [hidden]
hl.bind("Ctrl + Super + T", hl.dsp.exec_cmd("~/.config/quickshell/" .. qsConfig .. "/scripts/colors/switchwall.sh"), { description = "Change wallpaper" }) -- Change wallpaper
hl.bind("Ctrl + Super + R", hl.dsp.exec_cmd("killall ags agsv1 gjs ydotool qs quickshell; qs -c " .. qsConfig .. " &")) -- Restart widgets

--- Utilities
-- Screenshot, Record, OCR, Color picker, Clipboard history
hl.bind("Super + V", hl.dsp.exec_cmd("qs -c " .. qsConfig .. " ipc call TEST_ALIVE || pkill fuzzel || cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy"), { description = "Copy clipboard history entry" }) -- [hidden] Clipboard history >> clipboard (fallback)
hl.bind("Super + Period", hl.dsp.exec_cmd("qs -c " .. qsConfig .. " ipc call TEST_ALIVE || pkill fuzzel || ~/.config/hypr/hyprland/scripts/fuzzel-emoji.sh copy"), { description = "Copy an emoji" }) -- [hidden] Emoji >> clipboard (fallback)
hl.bind("Super + Shift + S", hl.dsp.exec_cmd("qs -p ~/.config/quickshell/" .. qsConfig .. "/screenshot.qml || pidof slurp || hyprshot --freeze --clipboard-only --mode region --silent"), { description = "Screen snip" }) -- Screen snip
-- OCR
hl.bind("Super + Shift + T", hl.dsp.exec_cmd('grim -g "$(slurp $SLURP_ARGS)" "tmp.png" && tesseract "tmp.png" - | wl-copy && rm "tmp.png"'), { description = "Character recognition" }) -- [hidden]
-- Color picker
hl.bind("Super + Shift + C", hl.dsp.exec_cmd("hyprpicker -a"), { description = "Color picker" }) -- Pick color (Hex) >> clipboard
-- Fullscreen screenshot
hl.bind("Print", hl.dsp.exec_cmd("grim - | wl-copy"), { locked = true, description = "Screenshot >> clipboard" }) -- Screenshot >> clipboard
hl.bind("Ctrl + Print", hl.dsp.exec_cmd('mkdir -p $(xdg-user-dir PICTURES)/Screenshots && grim $(xdg-user-dir PICTURES)/Screenshots/Screenshot_"$(date \'+%Y-%m-%d_%H.%M.%S\')".png'), { locked = true, description = "Screenshot >> clipboard & save" }) -- Screenshot >> clipboard & file
-- Recording stuff
hl.bind("Super + Alt + R", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/record.sh"), { description = "Record region (no sound)" }) -- Record region (no sound)
hl.bind("Ctrl + Alt + R", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/record.sh --fullscreen"), { description = "Record screen (no sound)" }) -- [hidden] Record screen (no sound)
hl.bind("Super + Shift + Alt + R", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/record.sh --fullscreen-sound"), { description = "Record screen (with sound)" }) -- Record screen (with sound)
-- AI
hl.bind("Super + Shift + Alt + mouse:273", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/ai/primary-buffer-query.sh"), { description = "Generate AI summary for selected text" }) -- AI summary for selected text

--
--- Window
-- Focusing
hl.bind("Super + mouse:272", hl.dsp.window.drag(), { mouse = true }) -- Move
hl.bind("Super + mouse:274", hl.dsp.window.drag(), { mouse = true }) -- [hidden]
hl.bind("Super + mouse:273", hl.dsp.window.resize(), { mouse = true }) -- Resize
--/-- bind = Super, ←/↑/→/↓,, -- Focus in direction
hl.bind("Super + Left", hl.dsp.focus({ direction = "left" })) -- [hidden]
hl.bind("Super + Right", hl.dsp.focus({ direction = "right" })) -- [hidden]
hl.bind("Super + Up", hl.dsp.focus({ direction = "up" })) -- [hidden]
hl.bind("Super + Down", hl.dsp.focus({ direction = "down" })) -- [hidden]
hl.bind("Super + BracketLeft", hl.dsp.focus({ direction = "left" })) -- [hidden]
hl.bind("Super + BracketRight", hl.dsp.focus({ direction = "right" })) -- [hidden]
--/-- bind = Super+Shift, ←/↑/→/↓,, -- Move in direction
hl.bind("Super + Shift + Left", hl.dsp.window.move({ direction = "left" })) -- [hidden]
hl.bind("Super + Shift + Right", hl.dsp.window.move({ direction = "right" })) -- [hidden]
hl.bind("Super + Shift + Up", hl.dsp.window.move({ direction = "up" })) -- [hidden]
hl.bind("Super + Shift + Down", hl.dsp.window.move({ direction = "down" })) -- [hidden]
hl.bind("Alt + F4", hl.dsp.window.close()) -- [hidden] Close (Windows)
hl.bind("Super + Q", hl.dsp.window.close()) -- Close
hl.bind("Super + Shift + Alt + Q", hl.dsp.exec_cmd("hyprctl kill")) -- Forcefully zap a window

-- Window split ratio
--/-- binde = Super, ;/',, -- Adjust split ratio
hl.bind("Super + Semicolon", hl.dsp.layout("splitratio", -0.1), { repeating = true }) -- [hidden]
hl.bind("Super + Apostrophe", hl.dsp.layout("splitratio", 0.1), { repeating = true }) -- [hidden]
-- Positioning mode
hl.bind("Super + Alt + Space", hl.dsp.window.float({ action = "toggle" })) -- Float/Tile
hl.bind("Super + D", hl.dsp.window.fullscreen(1)) -- Maximize
hl.bind("Super + F", hl.dsp.window.fullscreen(0)) -- Fullscreen
hl.bind("Super + Alt + F", hl.dsp.exec_cmd("hyprctl dispatch fullscreenstate 0 3")) -- Fullscreen spoof
hl.bind("Super + P", hl.dsp.window.pin()) -- Pin

--/-- bind = Super+Alt, Hash,, -- Send to workspace # (1, 2, 3,...)
hl.bind("Super + Alt + 1", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 1")) -- [hidden]
hl.bind("Super + Alt + 2", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 2")) -- [hidden]
hl.bind("Super + Alt + 3", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 3")) -- [hidden]
hl.bind("Super + Alt + 4", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 4")) -- [hidden]
hl.bind("Super + Alt + 5", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 5")) -- [hidden]
hl.bind("Super + Alt + 6", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 6")) -- [hidden]
hl.bind("Super + Alt + 7", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 7")) -- [hidden]
hl.bind("Super + Alt + 8", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 8")) -- [hidden]
hl.bind("Super + Alt + 9", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 9")) -- [hidden]
hl.bind("Super + Alt + 0", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 10")) -- [hidden]

-- --/-- bind = Super+Shift, Scroll ↑/↓,, -- Send to workspace left/right
hl.bind("Super + Shift + mouse_down", hl.dsp.window.move({ workspace = "r-1" })) -- [hidden]
hl.bind("Super + Shift + mouse_up", hl.dsp.window.move({ workspace = "r+1" })) -- [hidden]
hl.bind("Super + Alt + mouse_down", hl.dsp.window.move({ workspace = "-1" })) -- [hidden]
hl.bind("Super + Alt + mouse_up", hl.dsp.window.move({ workspace = "+1" })) -- [hidden]

--/-- bind = Super+Shift, Page_↑/↓,, -- Send to workspace left/right
hl.bind("Super + Alt + Page_Down", hl.dsp.window.move({ workspace = "+1" })) -- [hidden]
hl.bind("Super + Alt + Page_Up", hl.dsp.window.move({ workspace = "-1" })) -- [hidden]
hl.bind("Super + Shift + Page_Down", hl.dsp.window.move({ workspace = "r+1" })) -- [hidden]
hl.bind("Super + Shift + Page_Up", hl.dsp.window.move({ workspace = "r-1" })) -- [hidden]
hl.bind("Ctrl + Super + Shift + Right", hl.dsp.window.move({ workspace = "r+1" })) -- [hidden]
hl.bind("Ctrl + Super + Shift + Left", hl.dsp.window.move({ workspace = "r-1" })) -- [hidden]

hl.bind("Super + Alt + S", hl.dsp.exec_cmd("hyprctl dispatch movetoworkspacesilent special")) -- Send to scratchpad

hl.bind("Ctrl + Super + S", hl.dsp.workspace.toggle_special("")) -- [hidden]
hl.bind("Alt + Tab", hl.dsp.window.cycle_next()) -- [hidden] sus keybind
hl.bind("Alt + Tab", hl.dsp.window.bring_to_top()) -- [hidden] bring it to the top

--- Workspace
-- Switching
--/-- bind = Super, Hash,, -- Focus workspace # (1, 2, 3,...)
hl.bind("Super + 1", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 1")) -- [hidden]
hl.bind("Super + 2", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 2")) -- [hidden]
hl.bind("Super + 3", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 3")) -- [hidden]
hl.bind("Super + 4", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 4")) -- [hidden]
hl.bind("Super + 5", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 5")) -- [hidden]
hl.bind("Super + 6", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 6")) -- [hidden]
hl.bind("Super + 7", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 7")) -- [hidden]
hl.bind("Super + 8", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 8")) -- [hidden]
hl.bind("Super + 9", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 9")) -- [hidden]
hl.bind("Super + 0", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 10")) -- [hidden]

--/-- bind = Ctrl+Super, ←/→,, -- Focus left/right
hl.bind("Ctrl + Super + Right", hl.dsp.focus({ workspace = "r+1" })) -- [hidden]
hl.bind("Ctrl + Super + Left", hl.dsp.focus({ workspace = "r-1" })) -- [hidden]
--/-- bind = Ctrl+Super+Alt, ←/→,, -- [hidden] Focus busy left/right
hl.bind("Ctrl + Super + Alt + Right", hl.dsp.focus({ workspace = "m+1" })) -- [hidden]
hl.bind("Ctrl + Super + Alt + Left", hl.dsp.focus({ workspace = "m-1" })) -- [hidden]
--/-- bind = Super, Page_↑/↓,, -- Focus left/right
hl.bind("Super + Page_Down", hl.dsp.focus({ workspace = "+1" })) -- [hidden]
hl.bind("Super + Page_Up", hl.dsp.focus({ workspace = "-1" })) -- [hidden]
hl.bind("Ctrl + Super + Page_Down", hl.dsp.focus({ workspace = "r+1" })) -- [hidden]
hl.bind("Ctrl + Super + Page_Up", hl.dsp.focus({ workspace = "r-1" })) -- [hidden]
--/-- bind = Super, Scroll ↑/↓,, -- Focus left/right
hl.bind("Super + mouse_up", hl.dsp.focus({ workspace = "+1" })) -- [hidden]
hl.bind("Super + mouse_down", hl.dsp.focus({ workspace = "-1" })) -- [hidden]
hl.bind("Ctrl + Super + mouse_up", hl.dsp.focus({ workspace = "r+1" })) -- [hidden]
hl.bind("Ctrl + Super + mouse_down", hl.dsp.focus({ workspace = "r-1" })) -- [hidden]
-- Special
hl.bind("Super + S", hl.dsp.workspace.toggle_special("")) -- Toggle scratchpad
hl.bind("Super + mouse:275", hl.dsp.workspace.toggle_special("")) -- [hidden]
hl.bind("Ctrl + Super + BracketLeft", hl.dsp.focus({ workspace = "-1" })) -- [hidden]
hl.bind("Ctrl + Super + BracketRight", hl.dsp.focus({ workspace = "+1" })) -- [hidden]
hl.bind("Ctrl + Super + Up", hl.dsp.focus({ workspace = "r-5" })) -- [hidden]
hl.bind("Ctrl + Super + Down", hl.dsp.focus({ workspace = "r+5" })) -- [hidden]

--
-- Testing
hl.bind("Super + Alt + f11", hl.dsp.exec_cmd([==[bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | grep -v -i "nipple" | grep -v -i "pussy" | shuf -n 1); ACTION=$(notify-send "Test notification with body image" "This notification should contain your user account <b>image</b> and <a href=\"https://discord.com/app\">Discord</a> <b>icon</b>. Oh and here is a random image in your Pictures folder: <img src=\"$RANDOM_IMAGE\" alt=\"Testing image\"/>" -a "Hyprland keybind" -p -h "string:image-path:/var/lib/AccountsService/icons/$USER" -t 6000 -i "discord" -A "openImage=Open profile image" -A "action2=Open the random image" -A "action3=Useless button"); [[ $ACTION == *openImage ]] && xdg-open "/var/lib/AccountsService/icons/$USER"; [[ $ACTION == *action2 ]] && xdg-open \"$RANDOM_IMAGE\"']==])) -- [hidden]
hl.bind("Super + Alt + f12", hl.dsp.exec_cmd([==[bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | grep -v -i "nipple" | grep -v -i "pussy" | shuf -n 1); ACTION=$(notify-send "Test notification" "This notification should contain a random image in your <b>Pictures</b> folder and <a href=\"https://discord.com/app\">Discord</a> <b>icon</b>.\n<i>Flick right to dismiss!</i>" -a "Discord (fake)" -p -h "string:image-path:$RANDOM_IMAGE" -t 6000 -i "discord" -A "openImage=Open profile image" -A "action2=Useless button" -A "action3=Cry more"); [[ $ACTION == *openImage ]] && xdg-open "/var/lib/AccountsService/icons/$USER"']==])) -- [hidden]
hl.bind("Super + Alt + Equal", hl.dsp.exec_cmd("notify-send \"Urgent notification\" \"Ah hell no\" -u critical -a 'Hyprland keybind'")) -- [hidden]

--- Session
hl.bind("Super + L", hl.dsp.exec_cmd("loginctl lock-session"), { description = "Lock" }) -- Lock
hl.bind("Super + Shift + L", hl.dsp.exec_cmd("loginctl lock-session")) -- [hidden]
hl.bind("Super + Shift + L", hl.dsp.exec_cmd("sleep 0.1 && systemctl suspend || loginctl suspend"), { locked = true, description = "Suspend system" }) -- Sleep
hl.bind("Ctrl + Shift + Alt + Super + Delete", hl.dsp.exec_cmd("systemctl poweroff || loginctl poweroff"), { description = "Shutdown" }) -- [hidden] Power off

--- Screen
-- Zoom
hl.bind("Super + Minus", hl.dsp.exec_cmd("qs -c " .. qsConfig .. " ipc call zoom zoomOut"), { repeating = true }) -- Zoom out
hl.bind("Super + Equal", hl.dsp.exec_cmd("qs -c " .. qsConfig .. " ipc call zoom zoomIn"), { repeating = true }) -- Zoom in
hl.bind("Super + Minus", hl.dsp.exec_cmd("qs -c " .. qsConfig .. " ipc call TEST_ALIVE || ~/.config/hypr/hyprland/scripts/zoom.sh decrease 0.1"), { repeating = true }) -- [hidden] Zoom out
hl.bind("Super + Equal", hl.dsp.exec_cmd("qs -c " .. qsConfig .. " ipc call TEST_ALIVE || ~/.config/hypr/hyprland/scripts/zoom.sh increase 0.1"), { repeating = true }) -- [hidden] Zoom in

--- Media
hl.bind("Super + Shift + N", hl.dsp.exec_cmd('playerctl next || playerctl position `bc <<< "100 * $(playerctl metadata mpris:length) / 1000000 / 100"`'), { locked = true }) -- Next track
hl.bind("XF86AudioNext", hl.dsp.exec_cmd('playerctl next || playerctl position `bc <<< "100 * $(playerctl metadata mpris:length) / 1000000 / 100"`'), { locked = true }) -- [hidden]
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true }) -- [hidden]
hl.bind("Super + Shift + Alt + mouse:275", hl.dsp.exec_cmd("playerctl previous")) -- [hidden]
hl.bind("Super + Shift + Alt + mouse:276", hl.dsp.exec_cmd('playerctl next || playerctl position `bc <<< "100 * $(playerctl metadata mpris:length) / 1000000 / 100"`')) -- [hidden]
hl.bind("Super + Shift + B", hl.dsp.exec_cmd("playerctl previous"), { locked = true }) -- Previous track
hl.bind("Super + Shift + P", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true }) -- Play/pause media
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true }) -- [hidden]
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true }) -- [hidden]

--- Apps
hl.bind("Super + Return", hl.dsp.exec_cmd('~/.config/hypr/hyprland/scripts/launch_first_available.sh "$TERMINAL" "kitty -1" "foot" "alacritty" "wezterm" "konsole" "kgx" "uxterm" "xterm"')) -- Terminal
hl.bind("Super + T", hl.dsp.exec_cmd('~/.config/hypr/hyprland/scripts/launch_first_available.sh "$TERMINAL" "kitty -1" "foot" "alacritty" "wezterm" "konsole" "kgx" "uxterm" "xterm"')) -- [hidden] (terminal) (alt)
hl.bind("Ctrl + Alt + T", hl.dsp.exec_cmd('~/.config/hypr/hyprland/scripts/launch_first_available.sh "$TERMINAL" "kitty -1" "foot" "alacritty" "wezterm" "konsole" "kgx" "uxterm" "xterm"')) -- [hidden] (terminal) (for Ubuntu people)
hl.bind("Super + E", hl.dsp.exec_cmd('~/.config/hypr/hyprland/scripts/launch_first_available.sh "dolphin" "nautilus" "nemo" "thunar" "$TERMINAL" "kitty -1 fish -c yazi"')) -- File manager
hl.bind("Super + W", hl.dsp.exec_cmd('~/.config/hypr/hyprland/scripts/launch_first_available.sh "google-chrome-stable" "zen-browser" "firefox" "brave" "chromium" "microsoft-edge-stable" "opera" "librewolf"')) -- Browser
hl.bind("Super + C", hl.dsp.exec_cmd('~/.config/hypr/hyprland/scripts/launch_first_available.sh "code" "codium" "cursor" "zed" "zedit" "zeditor" "kate" "gnome-text-editor" "emacs" "command -v nvim && kitty -1 nvim"')) -- Code editor
hl.bind("Super + Shift + W", hl.dsp.exec_cmd('~/.config/hypr/hyprland/scripts/launch_first_available.sh "wps" "onlyoffice-desktopeditors"')) -- Office software
hl.bind("Super + X", hl.dsp.exec_cmd('~/.config/hypr/hyprland/scripts/launch_first_available.sh "kate" "gnome-text-editor" "emacs"')) -- Text editor
hl.bind("Ctrl + Super + V", hl.dsp.exec_cmd('~/.config/hypr/hyprland/scripts/launch_first_available.sh "pavucontrol-qt" "pavucontrol"')) -- Volume mixer
hl.bind("Super + I", hl.dsp.exec_cmd('XDG_CURRENT_DESKTOP=gnome ~/.config/hypr/hyprland/scripts/launch_first_available.sh "qs -p ~/.config/quickshell/' .. qsConfig .. '/settings.qml" "systemsettings" "gnome-control-center" "better-control"')) -- Settings app
hl.bind("Ctrl + Shift + Escape", hl.dsp.exec_cmd('~/.config/hypr/hyprland/scripts/launch_first_available.sh "gnome-system-monitor" "plasma-systemmonitor --page-name Processes" "command -v btop && kitty -1 fish -c btop"')) -- Task manager

-- Cursed stuff
--- Make window not amogus large
hl.bind("Ctrl + Super + Backslash", hl.dsp.exec_cmd("hyprctl dispatch resizeactive exact 640 480")) -- [hidden]
