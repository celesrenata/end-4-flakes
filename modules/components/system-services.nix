# System services required for dots-hyprland
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.dots-hyprland;
in
{
  config = mkIf cfg.enable {
    # UPower for battery monitoring in quickshell bar
    services.upower.enable = true;
  };
}
