# Package mappings from dots-hyprland meta-packages to nixpkgs
# Direct mapping from PKGBUILD files in arch-packages/
{ lib, pkgs }:

let
  # Import utility packages
  utilityPackages = import ./default.nix { inherit pkgs; };

  # illogical-impulse-basic PKGBUILD
  basicPackages = with pkgs; [
    axel
    bc
    coreutils
    cliphist
    cmake
    curl
    rsync
    wget
    ripgrep
    jq
    meson
    xdg-user-dirs
  ];

  # illogical-impulse-widgets PKGBUILD
  widgetPackages = with pkgs; [
    fuzzel
    glib # for gsettings
    gsettings-desktop-schemas # GNOME schemas for non-GNOME environments
    hypridle
    hyprutils
    hyprlock
    hyprpicker
    networkmanagerapplet # nm-connection-editor
    quickshell  # Provided by quickshell flake input via overlay
    translate-shell
    wlogout
    
    # Qt modules needed for quickshell widgets
    kdePackages.qt5compat  # For Qt5Compat.GraphicalEffects
    kdePackages.qtdeclarative  # For QML
    kdePackages.kdialog
    kdePackages.qtwayland  # For Wayland support
    kdePackages.qtpositioning  # For Weather service location features
    kdePackages.qtlocation  # Additional location services for QtPositioning
  ];

  # illogical-impulse-hyprland PKGBUILD
  hyprlandPackages = with pkgs; [
    hypridle
    hyprcursor
    hyprland
    hyprland-qtutils
    # hyprland-qt-support -> might be in hyprland-qtutils
    hyprlang
    hyprlock
    hyprpicker
    hyprsunset
    hyprutils
    hyprwayland-scanner
    xdg-desktop-portal-hyprland
    wl-clipboard
  ];

  # illogical-impulse-python PKGBUILD (system dependencies)
  pythonSystemPackages = with pkgs; [
    clang
    # uv -> not needed in NixOS approach, we use pip directly
    gtk4
    libadwaita
    libsoup_3 # libsoup3
    libportal-gtk4
    gobject-introspection
    sassc
    opencv4 # python-opencv
    
    # Additional system libraries needed for Python packages
    stdenv.cc.cc.lib # provides libstdc++.so.6
    glibc
    zlib
    libffi
    openssl
    bzip2
    xz
    ncurses
    readline
    sqlite
  ];

  # Additional packages that might be needed
  audioPackages = with pkgs; [
    pipewire
    wireplumber
    pavucontrol
    playerctl
  ];

  # Font packages (from installer analysis)
  fontPackages = with pkgs; [
    # Rubik font (installer sets this as default)
    # Note: might need to add custom font derivation
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-emoji
    font-awesome
    material-design-icons
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
  ];

  # Theme and appearance packages
  themePackages = with pkgs; [
    matugen # for Material You color generation
    # Additional theme packages as needed
  ];
in
{
  inherit 
    basicPackages 
    widgetPackages 
    hyprlandPackages 
    pythonSystemPackages
    audioPackages
    fontPackages
    themePackages;
  
  # Combined package sets for different use cases
  essentialPackages = basicPackages ++ widgetPackages ++ hyprlandPackages ++ 
                     (builtins.attrValues utilityPackages);
  
  allPackages = basicPackages ++ widgetPackages ++ hyprlandPackages ++ 
                pythonSystemPackages ++ audioPackages ++ fontPackages ++ themePackages ++
                (builtins.attrValues utilityPackages);
  
  # Minimal set for testing
  minimalPackages = basicPackages ++ widgetPackages ++ (builtins.attrValues utilityPackages);
}
