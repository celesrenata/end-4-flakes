# Patch kde-material-you-colors to work without KDE Plasma
# Creates stub plasma-apply-colorscheme for non-Plasma environments

final: prev: {
  kde-material-you-colors = prev.python312Packages.kde-material-you-colors.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ prev.makeWrapper ];
    postInstall = (old.postInstall or "") + ''
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
  });
}
