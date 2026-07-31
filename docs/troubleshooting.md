# Troubleshooting Guide

This guide covers common issues and their solutions for the end-4-flakes NixOS desktop environment.

## Quickshell Not Starting

### Symptom
Bar, sidebars, or launcher do not appear after login. Hyprland is running but no Quickshell UI.

```mermaid
flowchart TD
    A["Quickshell not starting"] --> B{"systemctl --user status quickshell.service"}
    B -->|inactive/failed| C["Service not running"]
    B -->|active (running)| D{"journalctl -n 50 shows errors?"}

    C --> E{"autoStart = true in config?"}
    E -->|no| F["Set programs.dots-hyprland.quickshell.autoStart = true;"]
    E -->|yes| G["Check Hyprland session target\nwayland.windowManager.hyprland.enable = true;"]

    D -->|QML cache errors| H["Clear QML cache:\nrm -rf ~/.cache/quickshell/qmlcache\nsystemctl --user restart quickshell"]
    D -->|Python venv missing| I["Rebuild: home-manager switch"]
    D -->|other error| J["Check journalctl for specific error"]

    style A fill:#e53935,color:#fff
    style B fill:#5c6bc0,color:#fff
    style C fill:#ef6c00,color:#fff
    style F fill:#43a047,color:#fff
    style G fill:#fb8c00,color:#fff
    style H fill:#26a69a,color:#fff
    style I fill:#5c6bc0,color:#fff
```

### Diagnosis Steps

1. **Check systemd service status:**
    ```bash
    systemctl --user status quickshell.service
    journalctl --user -u quickshell.service -n 50
    ```

2. **Verify QML cache exists:**
    ```bash
    ls -la ~/.cache/quickshell/qmlcache/
    # If empty or missing, clear and restart:
    rm -rf ~/.cache/quickshell/qmlcache
    systemctl --user restart quickshell
    ```

3. **Check Python venv:**
    ```bash
    ls -la ~/.local/state/quickshell/.venv/bin/python3
    # If missing, trigger rebuild or run manually:
    nix-build -A homeConfigurations.declarative.activationPackage
    ./result/activate
    ```

4. **Check environment variables:**
    ```bash
    echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV
    echo $QS_CONFIG_PATH  # Should point to ~/.config/quickshell/ii
    ```

### Common Fixes

| Issue | Fix |
|-------|-----|
| QML cache corrupted | `rm -rf ~/.cache/quickshell/qmlcache && systemctl --user restart quickshell` |
| Python venv missing | Run `home-manager switch` or `nix-build ... && ./result/activate` |
| PATH doesn't include Nix store | Check `~/.config/quickshell/ii/modules/common/Config.qml` has correct `@QUICKSHELL_BIN@` path |
| Service not started | Verify `programs.dots-hyprland.quickshell.autoStart = true;` in your config |
| Hyprland session target missing | Ensure `wayland.windowManager.hyprland.enable = true;` in system config |

## Color Theming Not Working

### Symptom
Wallpaper colors don't propagate to terminal, launcher, or window borders. Material You theme appears broken.

```mermaid
flowchart TD
    A["Colors not propagating"] --> B{"colors.json exists?"}
    
    B -->|no| C["No wallpaper set\nor matugen failed"]
    B -->|yes| D{"Content valid JSON?"}
    
    D -->|invalid| E["matugen generation error\nCheck Python venv deps"]
    D -->|valid| F{"Applied to apps?"}
    
    F -->|no| G["applycolor.sh not run\nor foot.ini missing refs"]
    F -->|yes| H["Colors applied correctly"]
    
    C --> I["Set wallpaper via Ctrl+Super+T\nor place .jpg in ~/Pictures/Wallpapers/"]
    E --> J["Rebuild: home-manager switch\nCheck modules/python-environment.nix"]
    G --> K["Run applycolor.sh manually\nVerify foot.ini color references"]

    style A fill:#e53935,color:#fff
    style B fill:#5c6bc0,color:#fff
    style C fill:#ef6c00,color:#fff
    style I fill:#43a047,color:#fff
    style E fill:#fb8c00,color:#fff
    style J fill:#26a69a,color:#fff
    style G fill:#e53935,color:#fff
    style K fill:#43a047,color:#fff
```

### Diagnosis Steps

1. **Check if colors.json exists:**
   ```bash
   cat ~/.local/state/quickshell/user/generated/colors.json
   # Should contain: primary, onPrimary, background, surface, etc.
   ```

2. **Verify matugen is installed:**
   ```bash
   which matugen
   # If missing, add to your packages or rebuild with themePackages
   ```

3. **Check Python venv dependencies:**
   ```bash
   ~/.local/state/quickshell/.venv/bin/python3 -c "import materialyoucolor; print(materialyoucolor.__version__)"
   ```

4. **Test color generation manually:**
   ```bash
   # Find a wallpaper
   ls ~/Pictures/Wallpapers/*.jpg
   
   # Run the generator script
   ~/.local/state/quickshell/.venv/bin/python3 \
     ~/.config/quickshell/ii/scripts/colors/generate_colors_material.py \
     --image ~/Pictures/Wallpapers/your-wallpaper.jpg \
     --darkmode \
     --output ~/.local/state/quickshell/user/generated/material_colors.scss
   ```

### Common Fixes

| Issue | Fix |
|-------|-----|
| No wallpaper found | Place a `.jpg` in `~/Pictures/Wallpapers/` or set via `Ctrl+Super+T` |
| matugen not in PATH | Add to your NixOS packages: `programs.dots-hyprland.packages.includeMatugen = true;` |
| Python venv missing deps | Rebuild with `home-manager switch`; check `modules/python-environment.nix` |
| Colors not applied to terminal | Verify foot.ini has correct color references; run `applycolor.sh` manually |
| Dark/Light mode stuck | Toggle with `Ctrl+Super+Shift+D`; check `~/.local/state/quickshell/user/generated/darkmode.json` |

## Keybinds Not Working

### Symptom
Keyboard shortcuts don't trigger expected actions. Cheatsheet (`Super+/`) shows empty or wrong entries.

```mermaid
flowchart TD
    A["Keybinds not working"] --> B{"hyprctl keyword bindd Super,A,... succeeds?"}
    
    B -->|error| C["Config syntax error\nCheck keybinds.conf for typos"]
    B -->|success| D{"grep '@' keybinds.conf finds anything?"}
    
    D -->|yes| E["@VARIABLE@ unresolved\nRebuild: home-manager switch"]
    D -->|no| F{"Custom keybinds loading?"}
    
    F -->|no| G["Check ~/.config/hypr/custom/keybinds.conf exists"]
    F -->|yes| H{"Hyprland version compatible?"}
    
    H -->|deprecated syntax| I["See docs/keybind-analysis.md for version changes"]
    H -->|compatible| J["$Secondary variable undefined?\nCheck env.conf: Secondary = Super"]

    style A fill:#e53935,color:#fff
    style B fill:#5c6bc0,color:#fff
    style C fill:#ef6c00,color:#fff
    style E fill:#fb8c00,color:#fff
    style G fill:#26a69a,color:#fff
    style I fill:#e53935,color:#fff
    style J fill:#43a047,color:#fff
```

### Diagnosis Steps

1. **Check keybinds.conf is loaded:**
   ```bash
   hyprctl keyword bindd Super,A,global,quickshell:sidebarLeftToggle
   # Should return success; if error, config has syntax issues
   ```

2. **Verify template variables resolved:**
   ```bash
   grep '@' ~/.config/hypr/keybinds.conf
   # Any remaining @VARIABLE@ means substitution failed
   ```

3. **Check for Hyprland version compatibility:**
   ```bash
   hyprctl version
   # Some binds use deprecated syntax in newer versions
   ```

### Common Fixes

| Issue | Fix |
|-------|-----|
| `@VARIABLE@` still in config | Rebuild with `home-manager switch`; check template substitution in activation script |
| Deprecated Hyprland syntax | See [`docs/keybind-analysis.md`](./keybind-analysis.md) for version-specific changes |
| Custom keybinds not loading | Verify `~/.config/hypr/custom/keybinds.conf` exists and is sourced |
| `$Secondary` variable undefined | Check `env.conf` has ` Secondary = Super` or your preferred modifier |
| Numpad binds not working | Ensure NumLock is off; numpad keys behave differently with NumLock on |

## Voice Assistant / Dictation Not Working

### Symptom
Voice commands don't respond. Streaming dictation fails. AI chat in sidebar doesn't connect.

```mermaid
flowchart TD
    A["Voice assistant not working"] --> B{"Python venv voice deps present?"}
    
    B -->|no| C["Rebuild: home-manager switch\nCheck modules/python-environment.nix"]
    B -->|yes| D{"API keys stored in keyring?"}
    
    D -->|no| E["Store via secret-tool or Quickshell Providers tab"]
    D -->|yes| F{"Voice agent scripts exist?"}
    
    F -->|no| G["Check configs/quickshell/scripts/voice-agent-stream.py exists"]
    F -->|yes| H{"WebSocket connection works?"}
    
    H -->|refused| I["Check network; verify provider endpoint URL in Config.qml"]
    H -->|success| J{"Ollama model loaded?"}
    
    J -->|no| K["Run show-loaded-ollama-models.sh to check"]
    J -->|yes| L["Mic not detected?\nCheck PipeWire: pactl list sources short"]

    style A fill:#e53935,color:#fff
    style B fill:#5c6bc0,color:#fff
    style C fill:#fb8c00,color:#fff
    style D fill:#26a69a,color:#fff
    style E fill:#ef6c00,color:#fff
    style F fill:#5c6bc0,color:#fff
    style G fill:#e53935,color:#fff
    style H fill:#43a047,color:#fff
    style I fill:#fb8c00,color:#fff
    style K fill:#ef6c00,color:#fff
```

### Diagnosis Steps

1. **Check Python venv has voice deps:**
   ```bash
   ~/.local/state/quickshell/.venv/bin/python3 -c "import websockets; print('OK')"
   ~/.local/state/quickshell/.venv/bin/python3 -c "import boto3; print('OK')"
   ```

2. **Verify API keys are stored:**
   ```bash
   secret-tool lookup quickshell openai-api-key 2>/dev/null || echo "Not found"
   # Or check via Quickshell sidebar → Providers tab
   ```

3. **Check voice agent scripts:**
   ```bash
   ls -la ~/.config/quickshell/ii/scripts/voice-agent-stream.py
   ls -la ~/.config/quickshell/ii/scripts/dictation-stream.py
   ```

4. **Test WebSocket connection (OpenAI Realtime):**
   ```bash
   # With your API key:
   OPENAI_API_KEY=sk-xxx ~/.local/state/quickshell/.venv/bin/python3 \
     ~/.config/quickshell/ii/scripts/voice-agent-stream.py --provider openai-realtime
   ```

### Common Fixes

| Issue | Fix |
|-------|-----|
| API key not found | Store via `secret-tool store quickshell <provider>-api-key <key>` or use Quickshell Providers tab |
| Python deps missing | Rebuild: `home-manager switch`; check `modules/python-environment.nix` includes websockets, boto3 |
| Microphone not detected | Check PipeWire: `pactl list sources short`; ensure mic is unmuted |
| WebSocket connection refused | Check network; verify provider endpoint URL in Config.qml |
| Ollama model not loaded | Run `~/.config/quickshell/ii/scripts/ai/show-loaded-ollama-models.sh` to check |

## Hyprland Crashes on Startup

### Symptom
Hyprland starts but immediately crashes or shows black screen.

```mermaid
flowchart TD
    A["Hyprland crash / black screen"] --> B{"GPU drivers correct?"}
    
    B -->|NVIDIA missing| C["Add hardware.nvidia.package = nixpkgs-ck4\nRebuild system config"]
    B -->|AMD/Intel OK| D{"general.conf syntax valid?"}
    
    D -->|syntax error| E["Check hyprctl getoption decoration:rounding for errors\nFix general.conf template"]
    D -->|valid| F{"Template variables resolved?"}
    
    F -->|@VARIABLE@ still present| G["Rebuild; check all @VARIABLE@ in .conf.template are substituted"]
    F -->|resolved| H{"Hyprland version compatible?"}
    
    H -->|mismatch| I["Update flake input: nix flake update"]
    H -->|compatible| J["Check rules.conf for regex errors; test with minimal config"]

    style A fill:#e53935,color:#fff
    style B fill:#5c6bc0,color:#fff
    style C fill:#ef6c00,color:#fff
    style D fill:#26a69a,color:#fff
    style E fill:#fb8c00,color:#fff
    style G fill:#e53935,color:#fff
    style I fill:#43a047,color:#fff
```

### Diagnosis Steps

1. **Check Hyprland logs:**
   ```bash
   journalctl -b --user -u hyprland 2>/dev/null || echo "No user service"
   # Or check XDG_RUNTIME_DIR/logs
   ```

2. **Verify GPU drivers:**
   ```bash
   glxinfo | grep "OpenGL renderer"
   # For NVIDIA: ensure nvidia-dkms is installed and MODULES_PROPER="nvidia-dkms" in config.nix
   ```

3. **Check for conflicting configs:**
   ```bash
   hyprctl getoption decoration:rounding
   # If error, general.conf has syntax issues
   ```

### Common Fixes

| Issue | Fix |
|-------|-----|
| NVIDIA GPU not detected | Add `hardware.nvidia.package = config.boot.kernelPackages.nixpkgs-ck4;` to system config |
| Template variable unresolved | Rebuild; check that all `@VARIABLE@` in `.conf.template` are substituted |
| Hyprland version mismatch | Update flake input: `nix flake update`; some binds require newer Hyprland |
| Conflicting window rules | Check `rules.conf` for regex errors; test with minimal config first |
| Missing Qt5Compat module | Verify overlay in `flake.nix` adds `qt5compat` and `qtpositioning` to quickshell buildInputs |

## Screenshot / Recording Issues

### Symptom
Screenshots don't save. Screen recording fails or produces empty files.

```mermaid
flowchart TD
    A["Screenshot/recording failing"] --> B{"grim works?"}
    
    B -->|no| C["Add pkgs.grim to package set\nCheck Wayland compatibility"]
    B -->|yes| D{"slurp works?"}
    
    D -->|no| E["Ensure wl-copy installed; check PipeWire session active"]
    D -->|yes| F{"record.sh --help runs?"}
    
    F -->|error| G["Check ffmpeg available: which ffmpeg\nAdd pkgs.ffmpeg to packages"]
    F -->|success| H{"Audio recorded?"}
    
    H -->|no| I["Verify PipeWire running:\npw-cli list-objects type/Node\nCheck mic/speaker permissions"]
    H -->|yes| J["Screenshots save correctly?"]

    style A fill:#e53935,color:#fff
    style B fill:#5c6bc0,color:#fff
    style C fill:#ef6c00,color:#fff
    style D fill:#26a69a,color:#fff
    style E fill:#fb8c00,color:#fff
    style F fill:#43a047,color:#fff
    style G fill:#e53935,color:#fff
    style I fill:#ef6c00,color:#fff
```

### Diagnosis Steps

1. **Test grim (screenshot tool):**
   ```bash
   grim ~/test-screenshot.png && file ~/test-screenshot.png
   # Should show PNG image; if error, grim not installed or Wayland incompatible
   ```

2. **Test slurp (region selection):**
   ```bash
   slurp 2>&1 | head -5
   # Should show usage; if "command not found", add to packages
   ```

3. **Test recording script:**
   ```bash
   ~/.config/hypr/scripts/record.sh --help
   # Check ffmpeg is available: which ffmpeg
   ```

### Common Fixes

| Issue | Fix |
|-------|-----|
| grim not found | Add to packages: `pkgs.grim` in your dots-hyprland package set |
| slurp hangs or crashes | Ensure `wl-copy` is installed; check PipeWire session is active |
| Recording produces no audio | Verify PipeWire is running: `pw-cli list-objects type/Node`; check mic/speaker permissions |
| Screenshots save to wrong location | Check `xdg-user-dir PICTURES` resolves correctly in your environment |
| hyprshot not working | Alternative: use `grim + slurp` pipeline (default fallback) |

## Clipboard History Not Working

### Symptom
Clipboard history (`Super+V`) shows nothing or crashes.

```mermaid
flowchart TD
    A["Clipboard history empty/crashing"] --> B{"cliphist list returns entries?"}
    
    B -->|no entries| C["wl-paste watcher not running\nCheck execs.conf for: wl-paste --type text --watch cliphist store"]
    B -->|has entries| D{"cliphist decode works?"}
    
    D -->|error| E["cliphist corrupted — run cliphist wipe then rebuild"]
    D -->|success| F{"Image clipboard tracked?"}
    
    F -->|no| G["Add to execs.conf:\nwl-paste --type image --watch cliphist store"]
    F -->|yes| H["History too large?\nAdjust cliphist config or clear with cliphist wipe"]

    style A fill:#e53935,color:#fff
    style B fill:#5c6bc0,color:#fff
    style C fill:#ef6c00,color:#fff
    style E fill:#fb8c00,color:#fff
    style G fill:#26a69a,color:#fff
```

### Diagnosis Steps

1. **Check cliphist service:**
   ```bash
   systemctl --user status cliphist 2>/dev/null || echo "Not a systemd service"
   # cliphist runs via exec-once in hyprland, not as a separate service
   ```

2. **Test cliphist manually:**
   ```bash
   cliphist list | head -5
   cliphist decode <index>  # Copy an entry to clipboard
   ```

3. **Check wl-paste watcher:**
   ```bash
   pgrep -f "wl-paste.*cliphist" && echo "Watcher running" || echo "Not running"
   ```

### Common Fixes

| Issue | Fix |
|-------|-----|
| cliphist not installed | Add `pkgs.cliphist` to your package set |
| wl-paste watcher not active | Verify `exec-once = wl-paste --type text --watch cliphist store` in execs.conf |
| Image clipboard not tracked | Add `wl-paste --type image --watch cliphist store` to execs.conf |
| History too large | Adjust cliphist config or clear with `cliphist wipe` |

## Night Light Not Working

### Symptom
Hyprsunset doesn't activate. Screen color temperature unchanged.

```mermaid
flowchart TD
    A["Night light not working"] --> B{"hyprsunset process running?"}
    
    B -->|no| C["Add pkgs.hyprsunset to package set\nCheck execs.conf: exec-once = hyprsunset -t 4500"]
    B -->|yes| D{"Temperature applied?"}
    
    D -->|no| E["Custom config override?\nCheck ~/.config/hypr/custom/general.conf doesn't override"]
    D -->|yes| F{"Quickshell toggle works?"}
    
    F -->|no| G["Ensure quickshell.utilButtons.showDarkModeToggle = true;"]
    F -->|yes| H["Night light working correctly"]

    style A fill:#e53935,color:#fff
    style B fill:#5c6bc0,color:#fff
    style C fill:#ef6c00,color:#fff
    style E fill:#fb8c00,color:#fff
    style G fill:#26a69a,color:#fff
```

### Diagnosis Steps

1. **Check hyprsunset is running:**
   ```bash
   pgrep -f hyprsunset && echo "Running" || echo "Not running"
   ```

2. **Test manually:**
   ```bash
   hyprsunset -t 4500 &
   sleep 2
   # Screen should warm; kill with Ctrl+C
   ```

3. **Verify config option:**
   ```nix
   programs.dots-hyprland.hyprland.night.colorTemperature = 4500;
   ```

### Common Fixes

| Issue | Fix |
|-------|-----|
| hyprsunset not in PATH | Add `pkgs.hyprsunset` to package set |
| Temperature not applied | Check `~/.config/hypr/custom/general.conf` doesn't override |
| Automatic scheduling broken | Verify `exec-once = hyprsunset -t 4500` in execs.conf |
| Quickshell toggle not working | Ensure `quickshell.utilButtons.showDarkModeToggle = true;` |

## Package Set Issues

### Symptom
Missing applications. Terminal, browser, or settings don't open from the launcher.

```mermaid
flowchart TD
    A["Package missing"] --> B{"Which package set?"}
    
    B -->|minimal| C["Basic utilities only\nNo Hyprland tools, no Python deps"]
    B -->|essential| D["Hyprland + KDE + fonts included\nRecommended for most users"]
    B -->|all| E["Everything: Python, audio,\ntheme tools, nwg-displays"]
    
    C --> F{"Need more?"}
    D --> G{"Specific app missing?"}
    E --> H{"KDE components missing?"}
    
    F -->|yes| I["Switch to essential or all\nprograms.dots-hyprland.packageSet = \"essential\";"]
    G -->|monitor config| J["Add includeNwgDisplays = true;"]
    G -->|fonts| K["Verify noto-fonts, nerd-fonts.*,\nmaterial-design-icons in package set"]
    H -->|yes| L["Ensure kdePackages.qt5compat\nand kirigami in widgetPackages"]

    style A fill:#e53935,color:#fff
    style B fill:#5c6bc0,color:#fff
    style C fill:#ef6c00,color:#fff
    style D fill:#26a69a,color:#fff
    style E fill:#7e57c2,color:#fff
    style I fill:#43a047,color:#fff
```

### Diagnosis Steps

1. **Check which package set you're using:**
    ```nix
    programs.dots-hyprland.packageSet = "essential";  # minimal | essential | all
    ```

2. **Verify packages are installed:**
    ```bash
    nix-store -qR $(readlink -f ~/.local/state/quickshell/.venv) 2>/dev/null || true
    # Or check your home-manager store:
    ls ~/.nix-profile/bin/ | head -20
    ```

### Package Set Contents

| Package Set | Includes | Best For |
|------------|----------|----------|
| `minimal` | Basic utilities (curl, jq, cliphist) + fuzzel + quickshell | Testing / minimal installs |
| `essential` | All minimal + Hyprland tools + KDE components + fonts | Most users (recommended) |
| `all` | Essential + Python deps + audio + theme tools + nwg-displays | Full-featured setup |

### Common Fixes

| Issue | Fix |
|-------|-----|
| Need more packages | Switch to `"essential"` or `"all"` package set |
| Specific app missing | Add `programs.dots-hyprland.packages.includeNwgDisplays = true;` for monitor config |
| Fonts not rendering | Verify `noto-fonts`, `nerd-fonts.*`, and `material-design-icons` are in the package set |
| KDE components missing | Ensure `kdePackages.qt5compat` and `kdePackages.kirigami` are in widgetPackages |

## Template Variable Resolution Failures

### Symptom
Config files contain literal `@VARIABLE@` text instead of resolved values. Hyprland fails to parse configs.

```mermaid
flowchart TD
    A["@VARIABLE@ still in config"] --> B{"grep '@' finds matches?"}
    
    B -->|yes| C["Template substitution failed"]
    B -->|no| D["Variables resolved — issue elsewhere"]
    
    C --> E{"home-manager switch ran successfully?"}
    
    E -->|error| F["Run home-manager switch explicitly; check output for errors"]
    E -->|success| G{"Variable defined in hyprland-config.nix?"}
    
    G -->|no| H["Add variable mapping to modules/components/hyprland-config.nix"]
    G -->|yes| I{"Custom config overriding template?"}
    
    I -->|yes| J["Remove @VARIABLE@ from ~/.config/hypr/custom/ files"]
    I -->|no| K["Template variables resolve at build time (nix-build), not runtime"]

    style A fill:#e53935,color:#fff
    style B fill:#5c6bc0,color:#fff
    style C fill:#ef6c00,color:#fff
    style E fill:#26a69a,color:#fff
    style F fill:#fb8c00,color:#fff
    style H fill:#e53935,color:#fff
    style J fill:#43a047,color:#fff
```

### Diagnosis Steps

1. **Check generated config:**
   ```bash
   grep '@' ~/.config/hypr/keybinds.conf
   # Any matches indicate unresolved variables
   ```

2. **Verify activation script ran:**
   ```bash
   journalctl --user -u home-manager.service -n 30 | grep -i template
   ```

### Common Fixes

| Issue | Fix |
|-------|-----|
| Activation script skipped | Run `home-manager switch` explicitly; check for errors in output |
| Variable not defined in substitution map | Check `modules/components/hyprland-config.nix` has the variable mapped |
| Custom config overrides template | Ensure `~/.config/hypr/custom/` files don't contain unresolved `@VARIABLE@` |
| Build-time vs runtime confusion | Template variables resolve at **build time** (nix-build), not at runtime |

## Writable Mode Issues

### Symptom
After switching to writable mode, configs are editable but Quickshell doesn't pick up changes.

```mermaid
flowchart TD
    A["Writable mode issues"] --> B{"Staging dir exists?"}
    
    B -->|no| C["Setup script not run\nExecute ~/.local/bin/initialSetup.sh manually"]
    B -->|yes| D{"Symlink conflict?"}
    
    D -->|yes| E["Remove existing ~/.config/quickshell symlink\nbefore switching to writable mode"]
    D -->|no| F{"Configs copied to ~/.config?"}
    
    F -->|no| G["Re-run home-manager switch\nCheck writable mode options in config"]
    F -->|yes| H{"Changes reflected after restart?"}
    
    H -->|no| I["Restart Quickshell:\nsystemctl --user restart quickshell\nOr reload Hyprland: hyprctl reload"]
    H -->|yes| J["Writable mode working correctly"]

    style A fill:#e53935,color:#fff
    style B fill:#5c6bc0,color:#fff
    style C fill:#ef6c00,color:#fff
    style D fill:#26a69a,color:#fff
    style E fill:#fb8c00,color:#fff
    style F fill:#7e57c2,color:#fff
    style G fill:#43a047,color:#fff
    style I fill:#26a69a,color:#fff
```

### Diagnosis Steps

1. **Check staging directory:**
    ```bash
    ls -la ~/.configstaging/quickshell/ii/modules/common/Config.qml
    # Should exist after home-manager switch
    ```

2. **Verify setup script ran:**
    ```bash
    cat ~/.cache/dots-hyprland/setup-complete
    # Should show timestamp; if missing, run initialSetup.sh manually
    ```

3. **Check config symlink:**
    ```bash
    ls -la ~/.config/quickshell
    # In writable mode: should be a real directory (not symlink)
    ```

### Common Fixes

| Issue | Fix |
|-------|-----|
| Setup script not run | Execute `~/.local/bin/initialSetup.sh` manually |
| Configs not copied to ~/.config | Re-run `home-manager switch`; check writable mode options in your config |
| Changes not reflected | Restart Quickshell: `systemctl --user restart quickshell` or reload Hyprland: `hyprctl reload` |
| Symlink conflict | Remove any existing `~/.config/quickshell` symlink before switching to writable mode |

## Git / Flake Update Issues

### Symptom
`nix flake update` fails. Lock file corrupted. Build errors after updating.

```mermaid
flowchart TD
    A["flake update failing"] --> B{"nix flake metadata . works?"}
    
    B -->|error| C["Lock file may be corrupted\nDelete flake.lock and regenerate: nix flake lock"]
    B -->|success| D{"experimental-features enabled?"}
    
    D -->|no| E["Add to /etc/nix/nix.conf:\nexperimental-features = nix-command flakes"]
    D -->|yes| F{"Network accessible from build machine?"}
    
    F -->|no| G["Check internet; verify GitHub API reachable\nUse nix flake update --override-input for specific inputs"]
    F -->|yes| H["Build errors after update?\nRun nix flake check to validate"]

    style A fill:#e53935,color:#fff
    style B fill:#5c6bc0,color:#fff
    style C fill:#ef6c00,color:#fff
    style E fill:#fb8c00,color:#fff
    style G fill:#26a69a,color:#fff
```

### Diagnosis Steps

1. **Check flake.lock integrity:**
   ```bash
   nix flake metadata .
   # Should show current inputs without error
   ```

2. **Verify network access for fetch:**
   ```bash
   # NixOS may block network at build time; ensure flakes are enabled:
   cat /etc/nix/nix.conf | grep experimental-features
   ```

### Common Fixes

| Issue | Fix |
|-------|-----|
| Flakes not enabled | Add `experimental-features = nix-command flakes` to `/etc/nix/nix.conf` |
| Network blocked at build time | Use `nix flake update --override-input` instead of full rebuild |
| Lock file corrupted | Delete `flake.lock` and regenerate: `nix flake lock` |
| Input resolution fails | Check internet connection; verify GitHub API is accessible from the build machine |

## VM Test Issues

### Symptom
`nix run .#vm` or `nix build .#checks.x86_64-linux.vm-integration` fails.

```mermaid
flowchart TD
    A["VM test failing"] --> B{"KVM available? (ls /dev/kvm)"}
    
    B -->|no| C["Install kvm package or enable VT-x/AMD-V in BIOS\nOr run headless: nix flake check"]
    B -->|yes| D{"Display server available?"}
    
    D -->|no (headless)| E["Use SSH: ssh -p 2222 testuser@localhost\nPassword: test"]
    D -->|yes| F{"Build timeout / too slow?"}
    
    F -->|yes| G["Run headless check instead of interactive VM:\nnix flake check"]
    F -->|no| H{"Memory sufficient? (default 4096MB)"}
    
    H -->|increase needed| I["Increase virtualisation.memorySize in flake.nix"]
    H -->|sufficient| J["Check nix-store -qR result for dependency issues"]

    style A fill:#e53935,color:#fff
    style B fill:#5c6bc0,color:#fff
    style C fill:#ef6c00,color:#fff
    style E fill:#fb8c00,color:#fff
    style G fill:#26a69a,color:#fff
    style I fill:#e53935,color:#fff
```

### Diagnosis Steps

1. **Check QEMU/KVM support:**
   ```bash
   ls /dev/kvm && echo "KVM available" || echo "No KVM — VM test will be slow or fail"
   ```

2. **Verify display server for QEMU GUI:**
   ```bash
   # For headless testing:
   nix build .#checks.x86_64-linux.vm-integration --no-build-output
   # For interactive:
   nix run .#vm
   ```

3. **Check VM test logs:**
   ```bash
   # The VM test creates a NixOS configuration; check its output:
   nix-store -qR result 2>/dev/null | head -5
   ```

### Common Fixes

| Issue | Fix |
|-------|-----|
| No KVM support | Install `kvm` package or run on hardware with VT-x/AMD-V enabled |
| Display not available for GUI VM | Use SSH: `ssh -p 2222 testuser@localhost` (password: `test`) |
| Build takes too long | Run headless check: `nix flake check` instead of interactive VM |
| Memory insufficient | Increase `virtualisation.memorySize` in flake.nix (default: 4096MB) |

## General Debugging Commands

```bash
# Quickshell service management
systemctl --user status quickshell.service
journalctl --user -u quickshell.service -f    # Follow logs
systemctl --user restart quickshell.service   # Restart

# Hyprland debugging
hyprctl dispatch reload              # Reload config without restarting
hyprctl clients                      # List all windows
hyprctl monitors                     # List monitors
hyprctl workspaces                   # List workspaces
hyprctl keyword decoration:rounding 0  # Disable rounding (debug)

# Python venv management
~/.local/state/quickshell/.venv/bin/python3 --version
~/.local/state/quickshell/.venv/bin/pip list | grep materialyoucolor

# Template variable debugging
grep -r '@[A-Z_]*@' ~/.config/hypr/    # Find unresolved variables
grep -r '@[A-Z_]*@' ~/.config/quickshell/  # Check QML templates

# Color pipeline debugging
cat ~/.local/state/quickshell/user/generated/colors.json | python3 -m json.tool
~/.local/state/quickshell/.venv/bin/python3 \
  ~/.config/quickshell/ii/scripts/colors/scheme_for_image.py --help

# Voice agent debugging
systemctl --user status quickshell.service | grep voice
~/.local/state/quickshell/.venv/bin/python3 \
  ~/.config/quickshell/ii/scripts/dictation-stream.py --help
```

## Getting Help

1. **Check existing docs:** [`docs/keybind-analysis.md`](./keybind-analysis.md), [`docs/upstream-sync.md`](./upstream-sync.md)
2. **Review logs:** `journalctl --user -f` for real-time system messages
3. **Test in VM:** `nix run .#vm` for isolated testing without affecting your system
4. **Ask on Discord:** Link to upstream dots-hyprland Discord server (see upstream README)
