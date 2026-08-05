-- ######## Window rules ########

-- Uncomment to apply global transparency to all windows:
-- hl.window_rule({ name = "global-transparency", match = { class = ".*" }, opacity = "0.89 override 0.89 override" })

-- Disable blur for xwayland context menus
hl.window_rule({ name = "xwayland-context-menu-noblur", match = { class = "^()$", title = "^()$" }, no_blur = true })
-- hl.window_rule({ name = "xwayland-noblur", match = { xwayland = true }, no_blur = true })


-- Floating
hl.window_rule({ name = "blueberry-float", match = { class = "^(blueberry\\.py)$" }, float = true })
hl.window_rule({ name = "guifetch-float", match = { class = "^(guifetch)$" }, float = true })  -- FlafyDev/guifetch
hl.window_rule({ name = "pavucontrol-float", match = { class = "^(pavucontrol)$" }, float = true })
hl.window_rule({ name = "pavucontrol-size", match = { class = "^(pavucontrol)$" }, size = "45% 45%" })
hl.window_rule({ name = "pavucontrol-center", match = { class = "^(pavucontrol)$" }, center = true })
hl.window_rule({ name = "pavucontrol-new-float", match = { class = "^(org.pulseaudio.pavucontrol)$" }, float = true })
hl.window_rule({ name = "pavucontrol-new-size", match = { class = "^(org.pulseaudio.pavucontrol)$" }, size = "45% 45%" })
hl.window_rule({ name = "pavucontrol-new-center", match = { class = "^(org.pulseaudio.pavucontrol)$" }, center = true })
hl.window_rule({ name = "nm-connection-editor-float", match = { class = "^(nm-connection-editor)$" }, float = true })
hl.window_rule({ name = "nm-connection-editor-size", match = { class = "^(nm-connection-editor)$" }, size = "45% 45%" })
hl.window_rule({ name = "nm-connection-editor-center", match = { class = "^(nm-connection-editor)$" }, center = true })
hl.window_rule({ name = "plasmawindowed-float", match = { class = ".*plasmawindowed.*" }, float = true })
hl.window_rule({ name = "kcm-float", match = { class = "kcm_.*" }, float = true })
hl.window_rule({ name = "bluedevilwizard-float", match = { class = ".*bluedevilwizard" }, float = true })
hl.window_rule({ name = "welcome-float", match = { title = ".*Welcome" }, float = true })
hl.window_rule({ name = "ii-settings-float", match = { title = "^(illogical-impulse Settings)$" }, float = true })
hl.window_rule({ name = "kde-portal-float", match = { class = "org.freedesktop.impl.portal.desktop.kde" }, float = true })
hl.window_rule({ name = "zotero-float", match = { class = "^(Zotero)$" }, float = true })
hl.window_rule({ name = "zotero-size", match = { class = "^(Zotero)$" }, size = "45% 45%" })


-- Move
-- kde-material-you-colors spawns a window when changing dark/light theme. This is to make sure it doesn't interfere at all.
hl.window_rule({ name = "plasma-changeicons-float", match = { class = "^(plasma-changeicons)$" }, float = true })
hl.window_rule({ name = "plasma-changeicons-noinitialfocus", match = { class = "^(plasma-changeicons)$" }, no_initial_focus = true })
hl.window_rule({ name = "plasma-changeicons-move", match = { class = "^(plasma-changeicons)$" }, move = "999999 999999" })
-- stupid dolphin copy
hl.window_rule({ name = "dolphin-copy-move", match = { title = "^(Copying — Dolphin)$" }, move = "40 80" })

-- Tiling
hl.window_rule({ name = "warp-tile", match = { class = "^dev\\.warp\\.Warp$" }, tile = true })

-- Picture-in-Picture
hl.window_rule({ name = "pip-float", match = { title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, float = true })
hl.window_rule({ name = "pip-keepaspectratio", match = { title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, keep_aspect_ratio = true })
hl.window_rule({ name = "pip-move", match = { title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, move = "73% 72%" })
hl.window_rule({ name = "pip-size", match = { title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, size = "25% 25%" })
hl.window_rule({ name = "pip-float-2", match = { title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, float = true })
hl.window_rule({ name = "pip-pin", match = { title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, pin = true })

-- Dialog windows – float+center these windows.
hl.window_rule({ name = "dialog-open-file-center", match = { title = "^(Open File)(.*)$" }, center = true })
hl.window_rule({ name = "dialog-select-file-center", match = { title = "^(Select a File)(.*)$" }, center = true })
hl.window_rule({ name = "dialog-choose-wallpaper-center", match = { title = "^(Choose wallpaper)(.*)$" }, center = true })
hl.window_rule({ name = "dialog-open-folder-center", match = { title = "^(Open Folder)(.*)$" }, center = true })
hl.window_rule({ name = "dialog-save-as-center", match = { title = "^(Save As)(.*)$" }, center = true })
hl.window_rule({ name = "dialog-library-center", match = { title = "^(Library)(.*)$" }, center = true })
hl.window_rule({ name = "dialog-file-upload-center", match = { title = "^(File Upload)(.*)$" }, center = true })
hl.window_rule({ name = "dialog-wants-to-save-center", match = { title = "^(.*)(wants to save)$" }, center = true })
hl.window_rule({ name = "dialog-wants-to-open-center", match = { title = "^(.*)(wants to open)$" }, center = true })
hl.window_rule({ name = "dialog-open-file-float", match = { title = "^(Open File)(.*)$" }, float = true })
hl.window_rule({ name = "dialog-select-file-float", match = { title = "^(Select a File)(.*)$" }, float = true })
hl.window_rule({ name = "dialog-choose-wallpaper-float", match = { title = "^(Choose wallpaper)(.*)$" }, float = true })
hl.window_rule({ name = "dialog-open-folder-float", match = { title = "^(Open Folder)(.*)$" }, float = true })
hl.window_rule({ name = "dialog-save-as-float", match = { title = "^(Save As)(.*)$" }, float = true })
hl.window_rule({ name = "dialog-library-float", match = { title = "^(Library)(.*)$" }, float = true })
hl.window_rule({ name = "dialog-file-upload-float", match = { title = "^(File Upload)(.*)$" }, float = true })
hl.window_rule({ name = "dialog-wants-to-save-float", match = { title = "^(.*)(wants to save)$" }, float = true })
hl.window_rule({ name = "dialog-wants-to-open-float", match = { title = "^(.*)(wants to open)$" }, float = true })


-- --- Tearing ---
hl.window_rule({ name = "tearing-exe", match = { title = ".*\\.exe" }, immediate = true })
hl.window_rule({ name = "tearing-minecraft", match = { title = ".*minecraft.*" }, immediate = true })
hl.window_rule({ name = "tearing-steam-app", match = { class = "^(steam_app).*" }, immediate = true })

-- No shadow for tiled windows (matches windows that are not floating).
hl.window_rule({ name = "tiled-noshadow", match = { float = false }, no_shadow = true })

-- ######## Workspace rules ########
hl.workspace_rule({ workspace = "special:special", gaps_out = 30 })

-- ######## Layer rules ########
hl.layer_rule({ name = "xray-all", match = { namespace = ".*" }, xray = 1 })
-- hl.layer_rule({ name = "noanim-all", match = { namespace = ".*" }, no_anim = true })
hl.layer_rule({ name = "noanim-walker", match = { namespace = "walker" }, no_anim = true })
hl.layer_rule({ name = "noanim-selection", match = { namespace = "selection" }, no_anim = true })
hl.layer_rule({ name = "noanim-overview", match = { namespace = "overview" }, no_anim = true })
hl.layer_rule({ name = "noanim-anyrun", match = { namespace = "anyrun" }, no_anim = true })
hl.layer_rule({ name = "noanim-indicator", match = { namespace = "indicator.*" }, no_anim = true })
hl.layer_rule({ name = "noanim-osk", match = { namespace = "osk" }, no_anim = true })
hl.layer_rule({ name = "noanim-hyprpicker", match = { namespace = "hyprpicker" }, no_anim = true })

hl.layer_rule({ name = "noanim-noanim", match = { namespace = "noanim" }, no_anim = true })
hl.layer_rule({ name = "blur-gtk-layer-shell", match = { namespace = "gtk-layer-shell" }, blur = true })
hl.layer_rule({ name = "ignorezero-gtk-layer-shell", match = { namespace = "gtk-layer-shell" }, ignore_alpha = 0 })
hl.layer_rule({ name = "blur-launcher", match = { namespace = "launcher" }, blur = true })
hl.layer_rule({ name = "ignore_alpha-launcher", match = { namespace = "launcher" }, ignore_alpha = 0.5 })
hl.layer_rule({ name = "blur-notifications", match = { namespace = "notifications" }, blur = true })
hl.layer_rule({ name = "ignore_alpha-notifications", match = { namespace = "notifications" }, ignore_alpha = 0.69 })
hl.layer_rule({ name = "blur-logout-dialog", match = { namespace = "logout_dialog" }, blur = true }) -- wlogout

-- ags
hl.layer_rule({ name = "anim-sideleft", match = { namespace = "sideleft.*" }, animation = "slide left" })
hl.layer_rule({ name = "anim-sideright", match = { namespace = "sideright.*" }, animation = "slide right" })
hl.layer_rule({ name = "blur-session", match = { namespace = "session[0-9]*" }, blur = true })
hl.layer_rule({ name = "blur-bar", match = { namespace = "bar[0-9]*" }, blur = true })
hl.layer_rule({ name = "ignore_alpha-bar", match = { namespace = "bar[0-9]*" }, ignore_alpha = 0.6 })
hl.layer_rule({ name = "blur-barcorner", match = { namespace = "barcorner.*" }, blur = true })
hl.layer_rule({ name = "ignore_alpha-barcorner", match = { namespace = "barcorner.*" }, ignore_alpha = 0.6 })
hl.layer_rule({ name = "blur-dock", match = { namespace = "dock[0-9]*" }, blur = true })
hl.layer_rule({ name = "ignore_alpha-dock", match = { namespace = "dock[0-9]*" }, ignore_alpha = 0.6 })
hl.layer_rule({ name = "blur-indicator", match = { namespace = "indicator.*" }, blur = true })
hl.layer_rule({ name = "ignore_alpha-indicator", match = { namespace = "indicator.*" }, ignore_alpha = 0.6 })
hl.layer_rule({ name = "blur-overview", match = { namespace = "overview[0-9]*" }, blur = true })
hl.layer_rule({ name = "ignore_alpha-overview", match = { namespace = "overview[0-9]*" }, ignore_alpha = 0.6 })
hl.layer_rule({ name = "blur-cheatsheet", match = { namespace = "cheatsheet[0-9]*" }, blur = true })
hl.layer_rule({ name = "ignore_alpha-cheatsheet", match = { namespace = "cheatsheet[0-9]*" }, ignore_alpha = 0.6 })
hl.layer_rule({ name = "blur-sideright", match = { namespace = "sideright[0-9]*" }, blur = true })
hl.layer_rule({ name = "ignore_alpha-sideright", match = { namespace = "sideright[0-9]*" }, ignore_alpha = 0.6 })
hl.layer_rule({ name = "blur-sideleft", match = { namespace = "sideleft[0-9]*" }, blur = true })
hl.layer_rule({ name = "ignore_alpha-sideleft", match = { namespace = "sideleft[0-9]*" }, ignore_alpha = 0.6 })
hl.layer_rule({ name = "blur-indicator-2", match = { namespace = "indicator.*" }, blur = true })
hl.layer_rule({ name = "ignore_alpha-indicator-2", match = { namespace = "indicator.*" }, ignore_alpha = 0.6 })
hl.layer_rule({ name = "blur-osk", match = { namespace = "osk[0-9]*" }, blur = true })
hl.layer_rule({ name = "ignore_alpha-osk", match = { namespace = "osk[0-9]*" }, ignore_alpha = 0.6 })

-- Quickshell
hl.layer_rule({ name = "qs-blur_popups", match = { namespace = "quickshell:.*" }, blur_popups = true })
hl.layer_rule({ name = "qs-blur", match = { namespace = "quickshell:.*" }, blur = true })
hl.layer_rule({ name = "qs-ignore_alpha", match = { namespace = "quickshell:.*" }, ignore_alpha = 0.79 })
hl.layer_rule({ name = "qs-bar-anim", match = { namespace = "quickshell:bar" }, animation = "slide top" })
hl.layer_rule({ name = "qs-screenCorners-anim", match = { namespace = "quickshell:screenCorners" }, animation = "fade" })
hl.layer_rule({ name = "qs-sidebarRight-anim", match = { namespace = "quickshell:sidebarRight" }, animation = "slide right" })
hl.layer_rule({ name = "qs-sidebarLeft-anim", match = { namespace = "quickshell:sidebarLeft" }, animation = "slide left" })
hl.layer_rule({ name = "qs-osk-anim", match = { namespace = "quickshell:osk" }, animation = "slide bottom" })
hl.layer_rule({ name = "qs-dock-anim", match = { namespace = "quickshell:dock" }, animation = "slide bottom" })
hl.layer_rule({ name = "qs-session-blur", match = { namespace = "quickshell:session" }, blur = true })
hl.layer_rule({ name = "qs-session-noanim", match = { namespace = "quickshell:session" }, no_anim = true })
hl.layer_rule({ name = "qs-session-ignore_alpha", match = { namespace = "quickshell:session" }, ignore_alpha = 0 })
hl.layer_rule({ name = "qs-notificationPopup-anim", match = { namespace = "quickshell:notificationPopup" }, animation = "fade" })
hl.layer_rule({ name = "qs-backgroundWidgets-blur", match = { namespace = "quickshell:backgroundWidgets" }, blur = true })
hl.layer_rule({ name = "qs-backgroundWidgets-ignore_alpha", match = { namespace = "quickshell:backgroundWidgets" }, ignore_alpha = 0.05 })
hl.layer_rule({ name = "qs-screenshot-noanim", match = { namespace = "quickshell:screenshot" }, no_anim = true })
hl.layer_rule({ name = "qs-screenCorners-popin", match = { namespace = "quickshell:screenCorners" }, animation = "popin 120%" })
hl.layer_rule({ name = "qs-lockWindowPusher-noanim", match = { namespace = "quickshell:lockWindowPusher" }, no_anim = true })


-- Launchers need to be FAST
hl.layer_rule({ name = "qs-overview-noanim", match = { namespace = "quickshell:overview" }, no_anim = true })
hl.layer_rule({ name = "noanim-gtk4-layer-shell", match = { namespace = "gtk4-layer-shell" }, no_anim = true })
-- outfoxxed's stuff
hl.layer_rule({ name = "blur-shell-bar", match = { namespace = "shell:bar" }, blur = true })
hl.layer_rule({ name = "ignorezero-shell-bar", match = { namespace = "shell:bar" }, ignore_alpha = 0 })
hl.layer_rule({ name = "blur-shell-notifications", match = { namespace = "shell:notifications" }, blur = true })
hl.layer_rule({ name = "ignore_alpha-shell-notifications", match = { namespace = "shell:notifications" }, ignore_alpha = 0.1 })
