{
  description = "NixOS adaptation of end-4's dots-hyprland - self-contained installer replication";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell = {
      url = "github:outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
        # Enhanced quickshell with Qt5Compat support for dots-hyprland
        quickshell = final.writeShellScriptBin "quickshell" ''
          # Add Qt5Compat, QtPositioning, and quickshell config directories to QML import path
          export QML2_IMPORT_PATH="${final.kdePackages.qt5compat}/lib/qt-6/qml:${final.kdePackages.qtpositioning}/lib/qt-6/qml:${final.kdePackages.qtlocation}/lib/qt-6/qml:$HOME/.config/quickshell/ii:$HOME/.config/quickshell:$QML2_IMPORT_PATH"
          
          # Set critical environment variables for dots-hyprland functionality
          export ILLOGICAL_IMPULSE_VIRTUAL_ENV="$HOME/.local/state/quickshell/.venv"
          export XDG_DATA_DIRS="$XDG_DATA_DIRS:${final.gsettings-desktop-schemas}/share"
          
          # Ensure child processes (execDetached) have access to system libraries for Python virtual environment
          export LD_LIBRARY_PATH="${final.stdenv.cc.cc.lib}/lib:${final.glibc}/lib:${final.zlib}/lib:${final.libffi}/lib:${final.openssl}/lib:${final.bzip2.out}/lib:${final.xz.out}/lib:${final.ncurses}/lib:${final.readline}/lib:${final.sqlite.out}/lib:$LD_LIBRARY_PATH"
          
          # Execute the original quickshell
          exec ${quickshell.packages.${system}.default}/bin/qs "$@"
        '';
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
                mode = "hybrid";
                
                # 🎨 Quickshell Configuration
                quickshell = {
                  appearance = {
                    extraBackgroundTint = true;
                    fakeScreenRounding = 2;  # When not fullscreen
                    transparency = false;
                  };
                  
                  bar = {
                    bottom = false;  # Top bar
                    cornerStyle = 0;  # Hug style
                    topLeftIcon = "spark";
                    showBackground = true;
                    verbose = true;
                    
                    utilButtons = {
                      showScreenSnip = true;
                      showColorPicker = true;   # 🎯 Enable color picker!
                      showMicToggle = false;
                      showKeyboardToggle = true;
                      showDarkModeToggle = true;
                      showPerformanceProfileToggle = false;
                    };
                    
                    workspaces = {
                      monochromeIcons = true;
                      shown = 10;
                      showAppIcons = true;
                      alwaysShowNumbers = false;
                      showNumberDelay = 300;
                    };
                  };
                  
                  battery = {
                    low = 20;
                    critical = 5;
                    automaticSuspend = true;
                    suspend = 3;
                  };
                  
                  apps = {
                    terminal = "foot";
                    bluetooth = "kcmshell6 kcm_bluetooth";
                    network = "plasmawindowed org.kde.plasma.networkmanagement";
                    taskManager = "plasma-systemmonitor --page-name Processes";
                  };
                  
                  time = {
                    format = "hh:mm";
                    dateFormat = "ddd, dd/MM";
                  };
                };
                
                # 🖥️ Hyprland Configuration
                hyprland = {
                  general = {
                    gapsIn = 4;
                    gapsOut = 7;
                    borderSize = 2;
                    allowTearing = false;
                  };
                  
                  decoration = {
                    rounding = 16;
                    blurEnabled = true;
                  };
                  
                  gestures = {
                    workspaceSwipe = true;
                  };
                  
                  monitors = [
                    # Add your monitor config here, e.g.:
                    # "eDP-1,1920x1080@60,0x0,1"
                  ];
                };
                
                # 🖥️ Terminal Configuration
                terminal = {
                  scrollback = {
                    lines = 1000;
                    multiplier = 3.0;
                  };
                  
                  cursor = {
                    style = "beam";
                    blink = false;
                    beamThickness = 1.5;
                  };
                  
                  colors = {
                    alpha = 0.95;
                  };
                  
                  mouse = {
                    hideWhenTyping = false;
                    alternateScrollMode = true;
                  };
                };
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
