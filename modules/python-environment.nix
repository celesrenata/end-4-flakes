# Python Virtual Environment for dots-hyprland
# This replicates the installer's Python setup exactly
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.dots-hyprland.python;
  mainCfg = config.programs.dots-hyprland;
  
  # Virtual environment setup script that replicates installer behavior
  setupVenvScript = pkgs.writeShellScript "setup-dots-hyprland-venv" ''
    #!/usr/bin/env bash
    set -e
    
    VENV_PATH="$HOME/.local/state/quickshell/.venv"
    
    echo "🐍 Setting up dots-hyprland Python virtual environment..."
    echo "📁 Target: $VENV_PATH"
    
    # Create directory structure
    mkdir -p "$(dirname "$VENV_PATH")"
    
    # Only create venv if it doesn't exist
    if [[ ! -d "$VENV_PATH" ]]; then
      echo "🏗️  Creating Python 3.12 virtual environment..."
      ${pkgs.python312}/bin/python -m venv "$VENV_PATH" --prompt .venv
    else
      echo "✅ Virtual environment already exists at $VENV_PATH"
    fi
    
    # Set up proper library path for Python packages (64-bit only)
    export LD_LIBRARY_PATH="${lib.makeLibraryPath (with pkgs; [
      stdenv.cc.cc.lib  # provides libstdc++.so.6
      gcc-unwrapped.lib
      glibc
      zlib
      libffi
      openssl
      bzip2
      xz.out
      ncurses
      readline
      sqlite
    ])}"
    
    # Clear Python path to avoid conflicts
    export PYTHONPATH=""
    export PYTHONDONTWRITEBYTECODE=1
    
    echo "📚 Library path: $LD_LIBRARY_PATH"
    
    # Activate and install exact requirements from installer
    echo "📦 Installing Python packages with proper library linking..."
    source "$VENV_PATH/bin/activate"
    
    # Add build tools to PATH for building Python packages
    export PATH="${pkgs.cmake}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.gnumake}/bin:$PATH"
    export CMAKE_GENERATOR="Unix Makefiles"
    export CMAKE_MAKE_PROGRAM="${pkgs.gnumake}/bin/make"
    export CC="${pkgs.gcc}/bin/gcc"
    export CXX="${pkgs.gcc}/bin/g++"
    
    # Set wayland protocol path for pywayland
    export PKG_CONFIG_PATH="${pkgs.wayland}/lib/pkgconfig:${pkgs.wayland-protocols}/share/pkgconfig"
    export WAYLAND_PROTOCOLS_DIR="${pkgs.wayland}/share/wayland"
    
    # Upgrade pip first
    pip install --upgrade pip
    
    # Install exact versions from scriptdata/requirements.txt
    pip install --no-cache-dir --force-reinstall \
      build==1.2.2.post1 \
      cffi==1.17.1 \
      libsass==0.23.0 \
      material-color-utilities==0.2.1 \
      materialyoucolor==2.0.10 \
      numpy==2.2.2 \
      packaging==24.2 \
      pillow==11.1.0 \
      psutil==6.1.1 \
      pycparser==2.22 \
      pyproject-hooks==1.2.0 \
      setproctitle==1.3.4 \
      setuptools==80.9.0 \
      setuptools-scm==8.1.0 \
      wheel==0.45.1
    
    # Install pywayland separately with custom protocol path
    pip install --no-cache-dir --force-reinstall \
      --global-option=build_ext \
      --global-option="--wayland-scanner=${pkgs.wayland-scanner}/bin/wayland-scanner" \
      --global-option="--wayland-protocols=${pkgs.wayland}/share/wayland" \
      pywayland==0.4.18 || echo "⚠️  pywayland install failed, continuing..."
    
    # Test critical imports
    echo "🧪 Testing critical package imports..."
    python -c "
import sys
print(f'Python: {sys.version}')

tests = [
    ('materialyoucolor', 'materialyoucolor'),
    ('material_color_utilities', 'material_color_utilities'),
    ('sass', 'sass'),
    ('numpy', 'numpy'),
    ('PIL', 'PIL'),
    ('pywayland.client', 'pywayland.client'),
    ('psutil', 'psutil'),
    ('setproctitle', 'setproctitle')
]

working = 0
for name, module in tests:
    try:
        __import__(module)
        print(f'✅ {name}')
        working += 1
    except Exception as e:
        print(f'❌ {name}: {e}')

print(f'📊 {working}/{len(tests)} packages working')
if working == len(tests):
    print('🎉 All critical packages imported successfully!')
else:
    print('⚠️  Some packages failed - may need additional system libraries')
"
    
    deactivate
    
    echo "✅ Python virtual environment setup complete!"
    echo "🔗 Environment variable: ILLOGICAL_IMPULSE_VIRTUAL_ENV=$VENV_PATH"
    echo "📚 Library path configured for NixOS compatibility"
  '';
  
  # Test script to verify the Python environment works
  testVenvScript = pkgs.writeShellScript "test-dots-hyprland-venv" ''
    #!/usr/bin/env bash
    
    VENV_PATH="$HOME/.local/state/quickshell/.venv"
    
    echo "🧪 Testing dots-hyprland Python virtual environment..."
    
    if [[ ! -d "$VENV_PATH" ]]; then
      echo "❌ Virtual environment not found at $VENV_PATH"
      exit 1
    fi
    
    source "$VENV_PATH/bin/activate"
    
    # Test critical packages
    echo "📦 Testing Python packages..."
    python -c "import material_color_utilities; print('✅ material-color-utilities')" || echo "❌ material-color-utilities"
    python -c "import materialyoucolor; print('✅ materialyoucolor')" || echo "❌ materialyoucolor"
    python -c "import pywayland; print('✅ pywayland')" || echo "❌ pywayland"
    python -c "import PIL; print('✅ pillow')" || echo "❌ pillow"
    python -c "import numpy; print('✅ numpy')" || echo "❌ numpy"
    python -c "import psutil; print('✅ psutil')" || echo "❌ psutil"
    
    deactivate
    
    echo "🎉 Python environment test complete!"
  '';
in
{
  options.programs.dots-hyprland.python = {
    enable = mkEnableOption "Python virtual environment for dots-hyprland";
    
    venvPath = mkOption {
      type = types.str;
      default = "$HOME/.local/state/quickshell/.venv";
      description = "Path to Python virtual environment";
    };
    
    autoSetup = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically set up virtual environment on activation";
    };
  };

  config = mkIf cfg.enable {
    # Install system Python and required build dependencies + test script
    home.packages = with pkgs; [
      python312
      python312Packages.pip
      python312Packages.virtualenv
      
      # System dependencies for Python packages (from illogical-impulse-python PKGBUILD)
      clang
      gtk4
      libadwaita
      libsoup_3
      libportal-gtk4
      gobject-introspection
      sassc
      opencv4
      
      # Critical system libraries for Python packages (64-bit)
      gcc-unwrapped.lib  # Provides proper libstdc++.so.6
      glibc
      zlib
      libffi
      openssl
      
      # Additional libraries that might be needed
      bzip2
      xz
      ncurses
      readline
      sqlite
      
      # Development tools
      pkg-config
      cairo
      gdk-pixbuf
      glib
      
      # Test script
      (writeShellScriptBin "test-dots-hyprland-venv" ''
        ${testVenvScript}
      '')
    ];

    # Set up virtual environment on Home Manager activation
    home.activation.setupDotsHyprlandVenv = mkIf cfg.autoSetup (
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        $DRY_RUN_CMD ${setupVenvScript}
      ''
    );

    # Set critical environment variable and library paths
    home.sessionVariables = {
      ILLOGICAL_IMPULSE_VIRTUAL_ENV = cfg.venvPath;
      # Ensure Python packages can find system libraries (64-bit only)
      LD_LIBRARY_PATH = lib.makeLibraryPath (with pkgs; [
        gcc-unwrapped.lib
        glibc
        zlib
        libffi
        openssl
        bzip2
        xz.out
        ncurses
        readline
        sqlite
      ]);
      # Additional environment variables for Python
      PYTHONPATH = "";  # Clear to avoid conflicts
      PYTHONDONTWRITEBYTECODE = "1";  # Prevent .pyc files
      
      # QML import paths for quickshell
      QML2_IMPORT_PATH = lib.concatStringsSep ":" (with pkgs; [
        "${kdePackages.qt5compat}/lib/qt-6/qml"
        "${kdePackages.qtdeclarative}/lib/qt-6/qml"
        "${kdePackages.qtwayland}/lib/qt-6/qml"
      ]);
    };
  };
}
