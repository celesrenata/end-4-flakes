# Package definitions for dots-hyprland utilities
{ pkgs }:

{
  update-flake = pkgs.writeShellScriptBin "update-flake" 
    (builtins.readFile ./scripts/update-flake.sh);
  
  test-python-env = pkgs.writeShellScriptBin "test-python-env" 
    (builtins.readFile ./scripts/test-python-env.sh);
  
  test-quickshell = pkgs.writeShellScriptBin "test-quickshell" 
    (builtins.readFile ./scripts/test-quickshell.sh);
  
  compare-modes = pkgs.writeShellScriptBin "compare-modes" 
    (builtins.readFile ./scripts/compare-modes.sh);
  
  # QML directory generator for quickshell
  generate-qmldir = pkgs.writeShellScriptBin "generate-qmldir" 
    (builtins.readFile ./scripts/generate-qmldir.sh);
  
  # Quickshell reset script
  quickshell-reset = pkgs.writeShellScriptBin "quickshell-reset.sh" 
    (builtins.readFile ./scripts/quickshell-reset.sh);
}
