{
  description = "NixOS adaptation of end-4's dots-hyprland - self-contained installer replication";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      
      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      };
    in
    {
      overlays.default = final: prev: {
        quickshell = prev.quickshell.overrideAttrs (old: {
          buildInputs = (old.buildInputs or []) ++ [ final.qt6.qt5compat final.qt6.qtpositioning ];
          qtWrapperArgs = (old.qtWrapperArgs or []) ++ [
            "--prefix" "NIXPKGS_QT6_QML_IMPORT_PATH" ":" "${final.qt6.qt5compat}/lib/qt-6/qml"
            "--prefix" "NIXPKGS_QT6_QML_IMPORT_PATH" ":" "${final.qt6.qtpositioning}/lib/qt-6/qml"
          ];
        });
        
        # Patch kde-material-you-colors for non-Plasma systems
        kde-material-you-colors = (prev.python312Packages.kde-material-you-colors.overrideAttrs (old: {
          pname = "kde-material-you-colors-patched";
          nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ prev.makeWrapper ];
          
          postInstall = (old.postInstall or "") + ''
            # Patch konsole_utils.py to use exist_ok=True
            substituteInPlace $out/lib/python*/site-packages/kde_material_you_colors/utils/konsole_utils.py \
              --replace-fail 'os.makedirs(settings.KONSOLE_DIR)' 'os.makedirs(settings.KONSOLE_DIR, exist_ok=True)'
            
            # Patch kwin_utils.py to skip KWin reload (crashes on non-KDE systems)
            substituteInPlace $out/lib/python*/site-packages/kde_material_you_colors/utils/kwin_utils.py \
              --replace-fail 'def reload():' $'def reload():\n    return  # Skip on non-KDE'
            
            # Create stub plasma-apply-colorscheme
            cat > $out/bin/plasma-apply-colorscheme << 'EOF'
#!/bin/sh
exit 0
EOF
            chmod +x $out/bin/plasma-apply-colorscheme
            
            # Wrap to use our stub
            wrapProgram $out/bin/kde-material-you-colors \
              --prefix PATH : $out/bin
          '';
        }));
      };

      packages = forAllSystems (system: 
        let 
          pkgs = pkgsFor system;
          utilityPackages = import ./packages { inherit pkgs; };
        in utilityPackages // {
          default = utilityPackages.update-flake;
        }
      );

      devShells = forAllSystems (system:
        let 
          pkgs = pkgsFor system;
          utilityPackages = import ./packages { inherit pkgs; };
        in {
          default = pkgs.mkShell {
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
        }
      );

      homeManagerModules.default = import ./modules/home-manager.nix;
      homeManagerModules.dots-hyprland = self.homeManagerModules.default;

      nixosModules.default = import ./modules/components/system-services.nix;
      nixosModules.dots-hyprland = self.nixosModules.default;

      checks = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in {
          vm-integration = import ./tests/vm-test.nix {
            inherit pkgs self home-manager;
          };
        }
      );

      # Standalone VM for interactive testing
      # Run with: nix run .#vm
      nixosConfigurations.test-vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          home-manager.nixosModules.home-manager
          ({ config, pkgs, lib, modulesPath, ... }: {
            imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];

            system.stateVersion = "24.05";
            networking.hostName = "dots-hyprland-test";

            # Graphics for Hyprland
            hardware.graphics.enable = true;
            services.xserver.enable = false;

            environment.systemPackages = with pkgs; [
              hyprland
              foot
              vim
              htop
              # Qt5Compat needed for quickshell's GraphicalEffects
              kdePackages.qt5compat
              # Icon themes for quickshell
              adwaita-icon-theme
              kdePackages.breeze-icons
              hicolor-icon-theme
              # Color pipeline
              matugen
              sassc
            ];

            # Fonts for quickshell (Material Symbols used for bar icons)
            fonts.packages = with pkgs; [
              material-symbols
              noto-fonts
            ];

            # Required for HM's xdg portal with useUserPackages
            environment.pathsToLink = [ "/share/applications" "/share/xdg-desktop-portal" ];

            # Ensure Qt5Compat QML modules are findable
            environment.sessionVariables.QML2_IMPORT_PATH = "${pkgs.kdePackages.qt5compat}/lib/qt-6/qml:${pkgs.kdePackages.qtpositioning}/lib/qt-6/qml:${pkgs.kdePackages.kirigami.passthru.unwrapped}/lib/qt-6/qml";

            # Auto-login to test user
            services.getty.autologinUser = "testuser";

            users.users.testuser = {
              isNormalUser = true;
              password = "test";
              extraGroups = [ "wheel" "video" "input" ];
            };

            # Auto-start Hyprland on TTY1 login
            environment.loginShellInit = ''
              if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
                rm -f ~/.config/hypr/hyprland.lua
                exec Hyprland
              fi
            '';

            # Home Manager
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.testuser = {
              imports = [ self.homeManagerModules.default ];

              home.username = "testuser";
              home.homeDirectory = "/home/testuser";
              home.stateVersion = "24.05";
              home.enableNixpkgsReleaseCheck = false;

              programs.dots-hyprland = {
                enable = true;
                source = self + "/configs";
                packageSet = "essential";
                mode = "hybrid";
                python.autoSetup = lib.mkForce false;
                touchegg.enable = lib.mkForce false;
                # Let exec-once handle quickshell launch (uses -c ii which resolves imports correctly)
                quickshell.autoStart = lib.mkForce false;
                quickshell.enable = lib.mkForce false;

                quickshell = {
                  appearance.antiFlashbang = "weak";
                  bar.workspaces = {
                    shown = 10;
                    showAppIcons = true;
                  };
                  notifications.forceMonitor = "";
                };

                hyprland = {
                  general = {
                    gapsIn = 4;
                    gapsOut = 7;
                    borderSize = 2;
                  };
                  night.colorTemperature = 4500;
                  keybinds.darkLightToggle = true;
                };

                # Provide the full hypr directory so the VM has all config files
                # (on a real system these exist from initial setup)
                overrides.hyprDirectory = pkgs.runCommand "hypr-vm-config" {} ''
                  mkdir -p $out/scripts

                  # Process templates: substitute @VARIABLE@ placeholders with usable defaults
                  substitute() {
                    local src="$1" dst="$2"
                    cp "$src" "$dst"
                    # env.conf placeholders
                    sed -i 's|@QT_THEME@|qt6ct|g' "$dst"
                    sed -i 's|@NVIDIA_ENV@||g' "$dst"
                    sed -i 's|@AMD_ENV@||g' "$dst"
                    sed -i 's|@DATA_DIR@|~/.local/state/quickshell|g' "$dst"
                    # execs.conf placeholders
                    sed -i 's|@HYPRIDLE_BIN@|hypridle|g' "$dst"
                    sed -i 's|@GNOME_KEYRING_BIN@|gnome-keyring-daemon|g' "$dst"
                    sed -i 's|@POLKIT_AGENT_BIN@|# polkit-agent|g' "$dst"
                    sed -i 's|@INPUT_METHOD_EXEC@||g' "$dst"
                    sed -i 's|@AUDIO_EXEC@||g' "$dst"
                    sed -i 's|@WL_PASTE_BIN@|wl-paste|g' "$dst"
                    sed -i 's|@CLIPHIST_BIN@|cliphist|g' "$dst"
                    sed -i 's|@CURSOR_THEME@|default|g' "$dst"
                    sed -i 's|@CURSOR_SIZE@|24|g' "$dst"
                    sed -i 's|@CUSTOM_EXECS@||g' "$dst"
                    # keybinds.conf placeholders
                    sed -i 's|@TERMINAL_APPS@|foot|g' "$dst"
                    sed -i 's|@BROWSER_APPS@|firefox|g' "$dst"
                    sed -i 's|@QUICKSHELL_BIN@|quickshell|g' "$dst"
                    sed -i 's|@FUZZEL_BIN@|fuzzel|g' "$dst"
                    sed -i 's|@FILE_MANAGER_APPS@|nautilus|g' "$dst"
                    sed -i 's|@CODE_EDITOR_APPS@|code|g' "$dst"
                    sed -i 's|@OFFICE_APPS@|libreoffice|g' "$dst"
                    sed -i 's|@TEXT_EDITOR_APPS@|foot -e vim|g' "$dst"
                    sed -i 's|@VOLUME_MIXER_APPS@|pavucontrol|g' "$dst"
                    sed -i 's|@SETTINGS_APPS@|# settings|g' "$dst"
                    sed -i 's|@TASK_MANAGER_APPS@|foot -e htop|g' "$dst"
                    sed -i 's|@BRIGHTNESSCTL_BIN@|brightnessctl|g' "$dst"
                    sed -i 's|@WPCTL_BIN@|wpctl|g' "$dst"
                    sed -i 's|@PLAYERCTL_BIN@|playerctl|g' "$dst"
                    sed -i 's|@WL_COPY_BIN@|wl-copy|g' "$dst"
                    sed -i 's|@WLOGOUT_BIN@|wlogout|g' "$dst"
                    sed -i 's|@HYPRSHOT_BIN@|hyprshot|g' "$dst"
                    sed -i 's|@GRIM_BIN@|grim|g' "$dst"
                    sed -i 's|@SLURP_BIN@|slurp|g' "$dst"
                    sed -i 's|@TESSERACT_BIN@|tesseract|g' "$dst"
                    sed -i 's|@HYPRPICKER_BIN@|hyprpicker|g' "$dst"
                    sed -i 's|@CUSTOM_KEYBINDS@||g' "$dst"
                    # colors.conf placeholders
                    sed -i 's|@COLOR_[A-Z_]*@|rgba(cba6f7ff)|g' "$dst"
                    # rules.conf placeholders
                    sed -i 's|@QUICKSHELL_CLASS@|quickshell|g' "$dst"
                    sed -i 's|@CUSTOM_RULES@||g' "$dst"
                    sed -i 's|@CUSTOM_WINDOW_RULES@||g' "$dst"
                    # Hyprland 0.55+ compat: windowrulev2 → windowrule
                    sed -i 's/^windowrulev2/windowrule/g' "$dst"
                    # Catch-all: remove any remaining @VAR@ lines that would cause parse errors
                    sed -i '/@[A-Z_]*@/d' "$dst"
                  }

                  substitute ${self + "/configs/hypr/env.conf.template"} $out/env.conf
                  # Add Qt5Compat QML path for quickshell (append before file is finalized)
                  chmod u+w $out/env.conf
                  printf '\nenv = QML2_IMPORT_PATH, ${pkgs.kdePackages.qt5compat}/lib/qt-6/qml:${pkgs.kdePackages.qtdeclarative}/lib/qt-6/qml:${pkgs.kdePackages.qtpositioning}/lib/qt-6/qml:${pkgs.kdePackages.kirigami.passthru.unwrapped}/lib/qt-6/qml\n' >> $out/env.conf
                  substitute ${self + "/configs/hypr/execs.conf.template"} $out/execs.conf
                  substitute ${self + "/configs/hypr/colors.conf.template"} $out/colors.conf
                  substitute ${self + "/configs/hypr/keybinds.conf.template"} $out/keybinds.conf
                  substitute ${self + "/configs/hypr/hypridle.conf.template"} $out/hypridle.conf

                  # Post-process keybinds for Hyprland 0.55+ compat
                  # Add $Secondary variable definition at top
                  sed -i '1i\$Secondary = Super' $out/keybinds.conf
                  # Fix splitratio → layoutmsg splitratio
                  sed -i 's/, splitratio,/, layoutmsg, splitratio/g' $out/keybinds.conf
                  # Fix bindid → bindd (bindid is not valid in 0.55 hyprlang)
                  sed -i 's/^bindid /bindd /g' $out/keybinds.conf
                  # Fix bindit → bind (bindit not valid)
                  sed -i 's/^bindit /bind /g' $out/keybinds.conf
                  # Remove bringactivetotop (removed in 0.55, use alter_zorder)
                  sed -i '/bringactivetotop/d' $out/keybinds.conf
                  # Fix commas in bindd descriptions that break field parsing
                  sed -i 's/no sound, alt/no sound alt/g' $out/keybinds.conf

                  # Fix quickshell launch to use -p (path mode) instead of -c (config name mode)
                  sed -i 's|quickshell -c $qsConfig|quickshell --no-duplicate -p ~/.config/quickshell/ii|g' $out/execs.conf

                  # Minimal rules.conf for VM — full template has syntax that needs
                  # further adaptation for Hyprland 0.55+ windowrule changes
                  cat > $out/rules.conf << 'RULES'
# Window/Layer rules for VM testing (Hyprland 0.55+ hyprlang compat syntax)
workspace = special:special, gapsout:30

# Window rules (0.53+ syntax: windowrule = effect value, match:prop regex)
windowrule = no_blur on, match:class ^()$, match:title ^()$
windowrule = float on, match:class ^(pavucontrol)$
windowrule = size 45% 45%, match:class ^(pavucontrol)$
windowrule = center on, match:class ^(pavucontrol)$
windowrule = float on, match:class ^(nm-connection-editor)$
windowrule = float on, match:class .*plasmawindowed.*
windowrule = float on, match:title ^(Open File)(.*)$
windowrule = center on, match:title ^(Open File)(.*)$
windowrule = float on, match:title ^(Save As)(.*)$
windowrule = center on, match:title ^(Save As)(.*)$
windowrule = float on, match:title ^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$
windowrule = keep_aspect_ratio on, match:title ^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$
windowrule = pin on, match:title ^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$
windowrule = size 25% 25%, match:title ^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$
windowrule = move 73% 72%, match:title ^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$
windowrule = immediate on, match:title .*\.exe
windowrule = immediate on, match:class ^(steam_app).*
windowrule = no_shadow on, match:float false
windowrule = float on, match:class ^(plasma-changeicons)$
windowrule = no_initial_focus on, match:class ^(plasma-changeicons)$
windowrule = move 999999 999999, match:class ^(plasma-changeicons)$
windowrule = tile on, match:class ^dev\.warp\.Warp$
windowrule = float on, match:class ^(blueberry\.py)$
windowrule = float on, match:class ^(guifetch)$
windowrule = float on, match:class ^(org.pulseaudio.pavucontrol)$
windowrule = size 45% 45%, match:class ^(org.pulseaudio.pavucontrol)$
windowrule = center on, match:class ^(org.pulseaudio.pavucontrol)$
windowrule = float on, match:class kcm_.*
windowrule = float on, match:class .*bluedevilwizard
windowrule = float on, match:title .*Welcome
windowrule = float on, match:title ^(illogical-impulse Settings)$
windowrule = float on, match:class org.freedesktop.impl.portal.desktop.kde
windowrule = float on, match:class ^(Zotero)$
windowrule = size 45% 45%, match:class ^(Zotero)$
windowrule = float on, match:title ^(Select a File)(.*)$
windowrule = center on, match:title ^(Select a File)(.*)$
windowrule = float on, match:title ^(Choose wallpaper)(.*)$
windowrule = center on, match:title ^(Choose wallpaper)(.*)$
windowrule = float on, match:title ^(Open Folder)(.*)$
windowrule = center on, match:title ^(Open Folder)(.*)$
windowrule = float on, match:title ^(Library)(.*)$
windowrule = center on, match:title ^(Library)(.*)$
windowrule = float on, match:title ^(File Upload)(.*)$
windowrule = center on, match:title ^(File Upload)(.*)$
windowrule = float on, match:title ^(.*)(wants to save)$
windowrule = center on, match:title ^(.*)(wants to save)$
windowrule = float on, match:title ^(.*)(wants to open)$
windowrule = center on, match:title ^(.*)(wants to open)$
windowrule = immediate on, match:title .*minecraft.*
windowrule = move 40 80, match:title ^(Copying — Dolphin)$

# Layer rules (0.55 syntax: layerrule = effect value, match:namespace regex)
layerrule = xray on, match:namespace .*
layerrule = no_anim on, match:namespace walker
layerrule = no_anim on, match:namespace selection
layerrule = no_anim on, match:namespace overview
layerrule = no_anim on, match:namespace anyrun
layerrule = no_anim on, match:namespace indicator.*
layerrule = no_anim on, match:namespace osk
layerrule = no_anim on, match:namespace hyprpicker
layerrule = no_anim on, match:namespace noanim
layerrule = blur on, ignore_alpha 0, match:namespace gtk-layer-shell
layerrule = blur on, ignore_alpha 0.5, match:namespace launcher
layerrule = blur on, ignore_alpha 0.69, match:namespace notifications
layerrule = blur on, match:namespace logout_dialog
layerrule = animation slide left, match:namespace sideleft.*
layerrule = animation slide right, match:namespace sideright.*
layerrule = blur on, match:namespace session[0-9]*
layerrule = blur on, ignore_alpha 0.6, match:namespace bar[0-9]*
layerrule = blur on, ignore_alpha 0.6, match:namespace barcorner.*
layerrule = blur on, ignore_alpha 0.6, match:namespace dock[0-9]*
layerrule = blur on, ignore_alpha 0.6, match:namespace indicator.*
layerrule = blur on, ignore_alpha 0.6, match:namespace overview[0-9]*
layerrule = blur on, ignore_alpha 0.6, match:namespace cheatsheet[0-9]*
layerrule = blur on, ignore_alpha 0.6, match:namespace sideright[0-9]*
layerrule = blur on, ignore_alpha 0.6, match:namespace sideleft[0-9]*
layerrule = blur on, ignore_alpha 0.6, match:namespace osk[0-9]*
layerrule = blur_popups on, blur on, ignore_alpha 0.79, match:namespace quickshell:.*
layerrule = animation slide top, match:namespace quickshell:bar
layerrule = animation fade, match:namespace quickshell:screenCorners
layerrule = animation slide right, match:namespace quickshell:sidebarRight
layerrule = animation slide left, match:namespace quickshell:sidebarLeft
layerrule = animation slide bottom, match:namespace quickshell:osk
layerrule = animation slide bottom, match:namespace quickshell:dock
layerrule = blur on, no_anim on, ignore_alpha 0, match:namespace quickshell:session
layerrule = animation fade, match:namespace quickshell:notificationPopup
layerrule = blur on, ignore_alpha 0.05, match:namespace quickshell:backgroundWidgets
layerrule = no_anim on, match:namespace quickshell:screenshot
layerrule = animation popin 120%, match:namespace quickshell:screenCorners
layerrule = no_anim on, match:namespace quickshell:lockWindowPusher
layerrule = no_anim on, match:namespace quickshell:overview
layerrule = no_anim on, match:namespace gtk4-layer-shell
layerrule = blur on, ignore_alpha 0, match:namespace shell:bar
layerrule = blur on, ignore_alpha 0.1, match:namespace shell:notifications
RULES

                  cp -r ${self + "/configs/hypr/scripts"}/* $out/scripts/ 2>/dev/null || true
                  mkdir -p $out/custom
                  touch $out/custom/env.conf
                  touch $out/custom/general.conf
                  touch $out/custom/rules.conf
                  touch $out/custom/keybinds.conf
                  touch $out/monitors.conf
                  touch $out/workspaces.conf
                '';
              };

              # Use HM's Hyprland module to properly manage the session/config entry point
              wayland.windowManager.hyprland = {
                enable = true;
                systemd.enable = false;
                extraConfig = builtins.readFile (self + "/configs/hypr/hyprland.conf.template");
              };

            };

            nix.settings.experimental-features = [ "nix-command" "flakes" ];

            # Service to create the fake venv after HM finishes
            systemd.services.setup-color-venv = {
              description = "Create fake Python venv for color pipeline";
              wantedBy = [ "multi-user.target" ];
              after = [ "home-manager-testuser.service" ];
              serviceConfig = {
                Type = "oneshot";
                User = "testuser";
                ExecStart = pkgs.writeShellScript "setup-venv" ''
                  VENV=/home/testuser/.local/state/quickshell/.venv/bin
                  mkdir -p $VENV
                  PYPATH="${pkgs.python312.withPackages (ps: with ps; [ materialyoucolor material-color-utilities pillow numpy psutil ])}/bin/python3"
                  rm -f $VENV/python3 $VENV/python
                  printf '#!/bin/sh\nexec %s "$@"\n' "$PYPATH" > $VENV/python3
                  chmod +x $VENV/python3
                  cp $VENV/python3 $VENV/python
                  
                  # Generate initial colors so quickshell has them on first start
                  mkdir -p /home/testuser/.local/state/quickshell/user/generated
                  if [ ! -f /home/testuser/.local/state/quickshell/user/generated/colors.json ]; then
                    export PATH=/run/current-system/sw/bin:/etc/profiles/per-user/testuser/bin:$PATH
                    export ILLOGICAL_IMPULSE_VIRTUAL_ENV=/home/testuser/.local/state/quickshell/.venv
                    WALLPAPER=$(ls /home/testuser/Pictures/Wallpapers/*.jpg 2>/dev/null | head -1)
                    if [ -n "$WALLPAPER" ]; then
                      cd /home/testuser/.config/quickshell/ii/scripts/colors
                      $VENV/python3 generate_colors_material.py --image "$WALLPAPER" --darkmode --output /home/testuser/.local/state/quickshell/user/generated/material_colors.scss 2>/dev/null || true
                      # Convert scss to json
                      if [ -s /home/testuser/.local/state/quickshell/user/generated/material_colors.scss ]; then
                        sed 's/\$//g; s/: /": "/g; s/;/",/g; s/^/"/g' /home/testuser/.local/state/quickshell/user/generated/material_colors.scss | sed '1i{' | sed '$s/,$/\n}/' > /home/testuser/.local/state/quickshell/user/generated/colors.json
                      fi
                    fi
                  fi
                '';
              };
            };

            # SSH for debugging
            services.openssh = {
              enable = true;
              settings.PermitRootLogin = "yes";
            };
            users.users.root.password = "test";

            # Ensure home directory structure exists and mark setup complete
            system.activationScripts.testUserSetup = ''
              mkdir -p /home/testuser/.local/bin
              mkdir -p /home/testuser/.config
              mkdir -p /home/testuser/.local/share
              mkdir -p /home/testuser/.local/state/quickshell/.venv/bin
              mkdir -p /home/testuser/.local/state/quickshell/user/generated
              # Seed colors.json so quickshell's FileView watcher initializes correctly
              if [ ! -f /home/testuser/.local/state/quickshell/user/generated/colors.json ]; then
                echo '{"darkmode":"True","transparent":"False","background":"#1C1B1F","onBackground":"#E6E1E5","surface":"#1C1B1F","primary":"#D0BCFF","onPrimary":"#381E72","primaryContainer":"#4F378B","onPrimaryContainer":"#EADDFF"}' > /home/testuser/.local/state/quickshell/user/generated/colors.json
              fi
              mkdir -p /home/testuser/.cache/dots-hyprland
              echo "VM pre-configured" > /home/testuser/.cache/dots-hyprland/setup-complete
              # Create a fake venv with a proper python that has all color deps
              # This runs after HM so we use a post-boot oneshot service instead
              # For now, just create the directory - the service below will populate it
              # Copy quickshell config (must be writable for qmldir generation)
              rm -rf /home/testuser/.config/quickshell
              cp -r ${self + "/configs/quickshell"} /home/testuser/.config/quickshell
              chmod -R u+w /home/testuser/.config/quickshell
              # Run qmldir generation (required for 'import qs' to work)
              ${pkgs.bash}/bin/bash ${self + "/packages/scripts/generate-qmldir.sh"} /home/testuser/.config/quickshell/ii
              # Copy matugen templates (note: use contents, not directory itself)
              mkdir -p /home/testuser/.config/matugen
              cp -r ${self + "/configs/matugen/templates"} /home/testuser/.config/matugen/templates
              chmod -R u+w /home/testuser/.config/matugen
              # Create custom scripts dir
              mkdir -p /home/testuser/.config/hypr/custom/scripts
              # Add test wallpapers from celes-dots
              mkdir -p /home/testuser/Pictures/Wallpapers
              cp -r ${pkgs.fetchFromGitHub {
                owner = "celesrenata";
                repo = "dotfiles";
                rev = "84ffef9c6f9c0fb204cf7e3561d6dd05434b115c";
                sha256 = "sha256-RwK8A7kBCrNlU+Y7Nfc0P0jK8WO6d3fo49T65CZo+F8=";
              }}/Backgrounds/* /home/testuser/Pictures/Wallpapers/
              chown -R testuser:users /home/testuser
            '';

            # VM settings
            virtualisation = {
              memorySize = 4096;
              cores = 4;
              graphics = true;
              forwardPorts = [
                { from = "host"; host.port = 2222; guest.port = 22; }
              ];
              qemu.options = [
                "-device virtio-vga-gl"
                "-display gtk,gl=on"
              ];
            };
          })
        ];
      };

      homeConfigurations = {
        declarative = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor "x86_64-linux";
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
                    # "eDP-1,1920x1080@60,0x0,1.0"
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
          pkgs = pkgsFor "x86_64-linux";
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
