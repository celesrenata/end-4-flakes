{
  description = "NixOS adaptation of end-4's dots-hyprland - self-contained installer replication";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell.url = "github:outfoxxed/quickshell";
  };

  outputs = { self, nixpkgs, home-manager, quickshell, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      };
      
      # Import our utility packages
      utilityPackages = import ./packages { inherit pkgs; };
    in
    {
      overlays.default = final: prev: {
        quickshell = quickshell.packages.${system}.default;
      };

      packages.${system} = utilityPackages // {
        default = utilityPackages.update-flake;
      };

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nixpkgs-fmt
          nil
          git
          jq
        ] ++ (with utilityPackages; [
          update-flake
          test-python-env
          test-quickshell
          compare-modes
        ]);
        
        shellHook = builtins.readFile ./packages/scripts/dev-shell-hook.sh;
      };

      homeManagerModules.default = import ./modules/home-manager.nix;
      homeManagerModules.dots-hyprland = self.homeManagerModules.default;

      homeConfigurations = {
        declarative = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            self.homeManagerModules.default
            {
              home.username = "celes";
              home.homeDirectory = "/home/celes";
              home.stateVersion = "24.05";
              
              programs.dots-hyprland = {
                enable = true;
                source = ./configs;  # Use local configs
                packageSet = "essential";
                mode = "declarative";
              };
            }
          ];
        };
        
        writable = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            self.homeManagerModules.default
            {
              home.username = "celes";
              home.homeDirectory = "/home/celes";
              home.stateVersion = "24.05";
              
              programs.dots-hyprland = {
                enable = true;
                source = ./configs;  # Use local configs
                packageSet = "essential";
                mode = "writable";
                writable = {
                  stagingDir = ".configstaging";
                  setupScript = "initialSetup.sh";
                  backupExisting = true;
                };
              };
            }
          ];
        };
        
        example = self.homeConfigurations.declarative;
      };
    };
}
