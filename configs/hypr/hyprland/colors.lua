-- exec = export SLURP_ARGS='-d -c FFDAD4BB -b 673B3444 -s 00000000'

hl.config({
    general = {
        ["col.active_border"] = { colors = {"rgba(F7DCDE39)"}, angle = 0 },
        ["col.inactive_border"] = { colors = {"rgba(A58A8D30)"}, angle = 0 },
    },

    misc = {
        background_color = "rgba(1D1011FF)",
    },
})

-- hyprbars plugin: disabled until hyprland-plugins is updated for Hyprland 0.56
-- (upstream repo has broken compat — source expects 0.56 headers but flake pins 0.55)
-- hl.config({
--     plugin = {
--         hyprbars = {
--             bar_text_font = "Rubik, Geist, AR One Sans, Reddit Sans, Inter, Roboto, Ubuntu, Noto Sans, sans-serif",
--             bar_height = 30,
--             bar_padding = 10,
--             bar_button_padding = 5,
--             bar_precedence_over_border = true,
--             bar_part_of_window = true,
--             bar_color = "rgba(1D1011FF)",
--             ["col.text"] = "rgba(F7DCDEFF)",
--             ["hyprbars-button"] = {
--                 "rgb(F7DCDE), 13, 󰖭, hyprctl dispatch killactive",
--                 "rgb(F7DCDE), 13, 󰖯, hyprctl dispatch fullscreen 1",
--                 "rgb(F7DCDE), 13, 󰖰, hyprctl dispatch movetoworkspacesilent special",
--             },
--         },
--     },
-- })

hl.window_rule({
    name = "pinned border color",
    match = { pin = true },
    border_color = { colors = {"rgba(FFB2BCAA)", "rgba(FFB2BC77)"}, angle = 0 },
})
