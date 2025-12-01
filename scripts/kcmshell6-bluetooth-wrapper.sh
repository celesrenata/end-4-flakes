#!/usr/bin/env bash
export QML2_IMPORT_PATH="/nix/store/dpcsk75hmiyiqjx5xqrrcd4vqz04g0sx-bluez-qt-6.20.0/lib/qt-6/qml:/nix/store/4lqcd9h2zjqbw9fslaz1013hsxsqpyq5-bluedevil-6.5.3/lib/qt-6/qml:/nix/store/glsmwvihb0zxx1fp7ajdrznj2md9g25a-plasma-nm-6.5.3/lib/qt-6/qml:/nix/store/shlx6p5760n95svcili68pmj8dfzrgfm-kconfig-6.20.0/lib/qt-6/qml:/nix/store/227q5lxrfk76rxmvv0d2hfg38in2yvky-kirigami-wrapped-6.20.0/lib/qt-6/qml"
exec kcmshell6 kcm_bluetooth
