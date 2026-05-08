# System services required for dots-hyprland
{ config, lib, pkgs, ... }:

{
  # UPower for battery monitoring in quickshell bar
  services.upower.enable = lib.mkDefault true;
}
