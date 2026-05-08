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
  
  # Foot configuration disabled - let Quickshell transparency system handle it dynamically
  config = {};
}
