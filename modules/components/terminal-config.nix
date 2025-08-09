# Terminal configuration options for dots-hyprland
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.dots-hyprland.terminal;
in
{
  options.programs.dots-hyprland.terminal = {
    # Terminal settings
    scrollback = {
      lines = mkOption {
        type = types.int;
        default = 1000;
        description = "Number of scrollback lines";
      };
      
      multiplier = mkOption {
        type = types.float;
        default = 3.0;
        description = "Scrollback multiplier";
      };
    };
    
    cursor = {
      style = mkOption {
        type = types.enum [ "block" "beam" "underline" ];
        default = "beam";
        description = "Cursor style";
      };
      
      blink = mkOption {
        type = types.bool;
        default = false;
        description = "Enable cursor blinking";
      };
      
      beamThickness = mkOption {
        type = types.float;
        default = 1.5;
        description = "Beam cursor thickness";
      };
    };
    
    colors = {
      alpha = mkOption {
        type = types.float;
        default = 0.95;
        description = "Terminal transparency (0.0 - 1.0)";
      };
    };
    
    mouse = {
      hideWhenTyping = mkOption {
        type = types.bool;
        default = false;
        description = "Hide mouse cursor when typing";
      };
      
      alternateScrollMode = mkOption {
        type = types.bool;
        default = true;
        description = "Enable alternate scroll mode";
      };
    };
  };
  
  config = mkIf (config.programs.dots-hyprland.enable && config.programs.dots-hyprland.overrides.footConfig == null) {
    # Only generate if no manual override is set
    xdg.configFile."foot/foot.ini".text = ''
      [main]
      term=xterm-256color
      login-shell=yes
      app-id=foot
      title=foot
      locked-title=no

      [bell]
      urgent=no
      notify=no
      visual=no
      command=
      command-focused=no

      [scrollback]
      lines=${toString cfg.scrollback.lines}
      multiplier=${toString cfg.scrollback.multiplier}
      indicator-position=relative
      indicator-format=""

      [url]
      launch=xdg-open ''${url}
      label-letters=sadfjklewcmpgh
      osc8-underline=url-mode
      protocols=http, https, ftp, ftps, file, gemini, gopher
      uri-characters=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.,~:;/?#@!$&%*+="'()[]

      [cursor]
      style=${cfg.cursor.style}
      color=cdd6f4
      blink=${boolToString cfg.cursor.blink}
      beam-thickness=${toString cfg.cursor.beamThickness}
      underline-thickness=<font-metrics>

      [mouse]
      hide-when-typing=${boolToString cfg.mouse.hideWhenTyping}
      alternate-scroll-mode=${boolToString cfg.mouse.alternateScrollMode}

      [colors]
      alpha=${toString cfg.colors.alpha}
      background=1e1e2e
      foreground=cdd6f4

      # Catppuccin Mocha color palette
      regular0=45475a
      regular1=f38ba8
      regular2=a6e3a1
      regular3=f9e2af
      regular4=89b4fa
      regular5=f5c2e7
      regular6=94e2d5
      regular7=bac2de

      bright0=585b70
      bright1=f38ba8
      bright2=a6e3a1
      bright3=f9e2af
      bright4=89b4fa
      bright5=f5c2e7
      bright6=94e2d5
      bright7=a6adc8

      [key-bindings]
      scrollback-up-page=Shift+Page_Up
      scrollback-up-half-page=none
      scrollback-up-line=none
      scrollback-down-page=Shift+Page_Down
      scrollback-down-half-page=none
      scrollback-down-line=none
      clipboard-copy=Control+Shift+c XF86Copy
      clipboard-paste=Control+Shift+v XF86Paste
      primary-paste=Shift+Insert
      search-start=Control+Shift+r
      font-increase=Control+plus Control+equal Control+KP_Add
      font-decrease=Control+minus Control+KP_Subtract
      font-reset=Control+0 Control+KP_0
      spawn-terminal=Control+Shift+n
      minimize=none
      maximize=none
      fullscreen=none
      pipe-visible=[sh -c "xurls | fuzzel | xargs -r firefox"] none
      pipe-scrollback=[sh -c "xurls | fuzzel | xargs -r firefox"] none
      pipe-selected=[xargs -r firefox] none
      show-urls-launch=Control+Shift+u
      show-urls-copy=none
      show-urls-persistent=none
      prompt-prev=Control+Shift+z
      prompt-next=Control+Shift+x
      unicode-input=Control+Shift+u
      noop=none

      [search-bindings]
      cancel=Control+g Control+c Escape
      commit=Return
      find-prev=Control+r
      find-next=Control+s
      cursor-left=Left Control+b
      cursor-left-word=Control+Left Mod1+b
      cursor-right=Right Control+f
      cursor-right-word=Control+Right Mod1+f
      cursor-home=Home Control+a
      cursor-end=End Control+e
      delete-prev=BackSpace
      delete-prev-word=Mod1+BackSpace Control+BackSpace
      delete-next=Delete
      delete-next-word=Mod1+d Control+Delete
      extend-to-word-boundary=Control+w
      extend-to-next-whitespace=Control+Shift+w
      clipboard-paste=Control+v Control+Shift+v Control+y XF86Paste
      primary-paste=Shift+Insert
      unicode-input=none

      [url-bindings]
      cancel=Control+g Control+c Control+d Escape
      toggle-url-visible=t
    '';
  };
}
