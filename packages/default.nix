# Package definitions for dots-hyprland utilities
{ pkgs }:

let
  scriptsPath = ./scripts;
in
{
  update-flake = pkgs.writeShellScriptBin "update-flake" 
    (builtins.readFile "${scriptsPath}/update-flake.sh");
  
  test-python-env = pkgs.writeShellScriptBin "test-python-env" 
    (builtins.readFile "${scriptsPath}/test-python-env.sh");
  
  test-quickshell = pkgs.writeShellScriptBin "test-quickshell" 
    (builtins.readFile "${scriptsPath}/test-quickshell.sh");
  
  compare-modes = pkgs.writeShellScriptBin "compare-modes" 
    (builtins.readFile "${scriptsPath}/compare-modes.sh");
}
