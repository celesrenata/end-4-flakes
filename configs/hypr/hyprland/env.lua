-- ######### Input method ##########
-- See https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland
hl.env("QT_IM_MODULE", "fcitx")
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("SDL_IM_MODULE", "fcitx")
hl.env("GLFW_IM_MODULE", "ibus")
hl.env("INPUT_METHOD", "fcitx")

-- ############ Wayland #############
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- ############ Themes #############
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("XDG_MENU_PREFIX", "plasma-")

-- ######## Wayland #########
-- Tearing
-- hl.env("WLR_DRM_NO_ATOMIC", "1")
-- ?
-- hl.env("WLR_NO_HARDWARE_CURSORS", "1")

-- ######## Virtual envrionment #########
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", "~/.local/state/quickshell/.venv")

-- ######## Terminal application #########
hl.env("TERMINAL", "kitty -1")
