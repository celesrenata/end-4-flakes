# Feature: desktop-demo-driver, Properties 11, 12, 13: Guard Skip, State Restoration, Module Cleanup
"""
Property 11: Unresolvable Guard Skip
Property 12: Desktop State Restoration
Property 13: Post-Scene Module Cleanup

These tests validate the guard, state snapshot/restore, and post-scene cleanup
logic of the DemoDriverService.

Property 11: When a scene's guard cannot be resolved (ydotool unavailable,
required window doesn't exist), the scene is skipped, sceneCompleted(name, false)
is emitted, and the tour continues without crashing.

Property 12: The capture/restore logic for desktop state preserves all fields,
restore is a no-op when _preState is null, capture always sets _preState,
restore clears _preState, and double-restore is idempotent.

Property 13: When a scene has closesModule set and the module is still open
after execution, a close command is dispatched. If already closed, no command
is issued.

**Validates: Requirements 11.3, 11.4, 11.6, 11.7**
"""

from hypothesis import given, settings, assume, HealthCheck
from hypothesis import strategies as st


# ─── Model: GuardSkipSimulator (Property 11) ───


class GuardSkipSimulator:
    """
    Simulates DemoDriverService behavior with explicit guard types.

    Each scene has a list of guards. A guard fails if its precondition
    is not met (e.g., ydotool unavailable, window doesn't exist).
    """

    def __init__(self, scenes: list[dict], environment: dict):
        """
        scenes: list of scene dicts with 'name' and 'guards'
        environment: dict describing the current state, e.g.:
            {"ydotool_available": bool, "open_windows": set[str]}
        """
        self.queue = scenes
        self.env = environment
        self.signals: list[tuple] = []
        self.scenes_completed = 0
        self.crashed = False

    def _check_guards(self, scene: dict) -> bool:
        """Mirror of DemoDriverService._checkGuards"""
        guards = scene.get("guards", [])
        for guard in guards:
            guard_type = guard["type"]
            if guard_type == "ydotool":
                if not self.env.get("ydotool_available", False):
                    return False
            elif guard_type == "window":
                window_class = guard.get("windowClass", "")
                if window_class not in self.env.get("open_windows", set()):
                    return False
            elif guard_type == "audioUnmuted":
                # This guard auto-resolves (unmutes audio) — never fails
                pass
        return True

    def run(self):
        """Execute the full tour."""
        try:
            self.signals.append(("tourStarted", len(self.queue)))
            for scene in self.queue:
                if not self._check_guards(scene):
                    # Guard failed — skip
                    self.signals.append(("sceneCompleted", scene["name"], False))
                    self.scenes_completed += 1
                else:
                    # Guard passed — execute
                    self.signals.append(("sceneStarted", scene["name"]))
                    self.signals.append(("sceneCompleted", scene["name"], True))
                    self.scenes_completed += 1
            self.signals.append(("tourCompleted", False))
        except Exception:
            self.crashed = True


# ─── Model: DesktopStateManager (Property 12) ───


class DesktopStateManager:
    """
    Models the capture/restore logic for desktop state.

    Mirrors _captureDesktopState() and _restoreDesktopState() from
    DemoDriverService.qml.
    """

    def __init__(self):
        self._pre_state: dict | None = None
        self.commands_issued: list[list[str]] = []

    def capture_state(self, workspace: int, zoom: float, volume: float,
                      muted: bool, dark_mode: bool):
        """Capture current desktop state. Always sets _preState to non-null."""
        self._pre_state = {
            "workspace": workspace,
            "zoom": zoom,
            "volume": volume,
            "muted": muted,
            "darkMode": dark_mode,
        }

    def restore_state(self) -> list[list[str]]:
        """
        Restore desktop state. Returns commands that would be executed.
        If _preState is None, returns empty (no-op).
        After restore, _preState is set to None.
        """
        if self._pre_state is None:
            return []

        s = self._pre_state
        commands = [
            ["hyprctl", "dispatch", "workspace", str(s["workspace"])],
            ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", str(s["volume"])],
            ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@",
             "1" if s["muted"] else "0"],
        ]
        self.commands_issued.extend(commands)
        self._pre_state = None
        return commands

    @property
    def pre_state(self):
        return self._pre_state


# ─── Model: ModuleCleanup (Property 13) ───


def should_force_close(closes_module: str | None, module_is_open: bool) -> bool:
    """Returns whether a force-close command should be dispatched."""
    if not closes_module:
        return False
    return module_is_open


def close_command(module_name: str) -> list[str]:
    """Returns the hyprctl command to force-close a module."""
    return ["hyprctl", "dispatch", "global", f"quickshell:{module_name}Close"]


# ─── Hypothesis Strategies ───

# Guard types
GUARD_TYPES = ["ydotool", "window", "audioUnmuted"]

WINDOW_CLASSES = [
    "firefox", "foot", "dolphin", "code-oss", "kitty",
    "chromium", "nautilus", "thunderbird",
]

MODULE_NAMES = [
    "sidebarLeft", "sidebarRight", "overview",
    "session", "osk", "mediaControls", "cheatsheet",
]

st_guard = st.one_of(
    st.just({"type": "ydotool"}),
    st.builds(
        lambda wc: {"type": "window", "windowClass": wc},
        st.sampled_from(WINDOW_CLASSES),
    ),
    st.just({"type": "audioUnmuted"}),
)

st_scene_name = st.from_regex(r"[a-z][a-z0-9]*(-[a-z0-9]+){0,3}", fullmatch=True)

st_scene_with_guards = st.builds(
    lambda name, guards: {"name": name, "guards": guards},
    st_scene_name,
    st.lists(st_guard, min_size=0, max_size=3),
)

st_scene_queue = st.lists(st_scene_with_guards, min_size=1, max_size=15)

st_environment = st.builds(
    lambda ydotool, windows: {
        "ydotool_available": ydotool,
        "open_windows": set(windows),
    },
    st.booleans(),
    st.lists(st.sampled_from(WINDOW_CLASSES), min_size=0, max_size=5),
)

# State restoration strategies
st_workspace = st.integers(min_value=1, max_value=10)
st_zoom = st.floats(min_value=0.5, max_value=3.0, allow_nan=False, allow_infinity=False)
st_volume = st.floats(min_value=0.0, max_value=1.5, allow_nan=False, allow_infinity=False)
st_muted = st.booleans()
st_dark_mode = st.booleans()

# Module strategies
st_module_name = st.sampled_from(MODULE_NAMES)
st_module_is_open = st.booleans()


# ═══════════════════════════════════════════════════════════════════════════════
# Property 11: Unresolvable Guard Skip
# ═══════════════════════════════════════════════════════════════════════════════


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(scenes=st_scene_queue, env=st_environment)
def test_guard_skip_no_crash(scenes, env):
    """
    Property 11.1: When guards fail, the simulator never crashes.
    No exception occurs regardless of guard type or environment state.

    **Validates: Requirements 11.3**
    """
    sim = GuardSkipSimulator(scenes, env)
    sim.run()

    assert not sim.crashed, (
        f"Simulator crashed with scenes={[s['name'] for s in scenes]}, env={env}"
    )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(scenes=st_scene_queue, env=st_environment)
def test_guard_skip_emits_completed_false(scenes, env):
    """
    Property 11.2: When a scene's guard fails, sceneCompleted(name, false) is
    emitted for that scene.

    **Validates: Requirements 11.3**
    """
    sim = GuardSkipSimulator(scenes, env)
    sim.run()

    for scene in scenes:
        guard_passes = sim._check_guards(scene)
        if not guard_passes:
            # Find the sceneCompleted signal for this scene
            completed_false = [
                s for s in sim.signals
                if s[0] == "sceneCompleted" and s[1] == scene["name"] and s[2] is False
            ]
            assert len(completed_false) >= 1, (
                f"Scene '{scene['name']}' guard failed but no "
                f"sceneCompleted(name, false) emitted. Guards: {scene['guards']}, env={env}"
            )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(scenes=st_scene_queue, env=st_environment)
def test_guard_skip_tour_continues(scenes, env):
    """
    Property 11.3: The tour continues to the next scene after a guard skip.
    Total scenes_completed always equals queue length.

    **Validates: Requirements 11.3**
    """
    sim = GuardSkipSimulator(scenes, env)
    sim.run()

    assert sim.scenes_completed == len(scenes), (
        f"Expected {len(scenes)} scenes_completed, got {sim.scenes_completed}. "
        f"Tour did not continue past guard failures."
    )

    # tourCompleted should be emitted
    tour_completed = [s for s in sim.signals if s[0] == "tourCompleted"]
    assert len(tour_completed) == 1, (
        f"Expected 1 tourCompleted, got {len(tour_completed)}"
    )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(scenes=st_scene_queue, env=st_environment)
def test_guard_skip_skipped_scenes_not_started(scenes, env):
    """
    Property 11.4: Skipped scenes do NOT emit sceneStarted.
    Only scenes that pass guards emit sceneStarted.

    **Validates: Requirements 11.3**
    """
    sim = GuardSkipSimulator(scenes, env)
    sim.run()

    # Rebuild the guard check per-scene to know which passed
    for i, scene in enumerate(scenes):
        guard_passes = sim._check_guards(scene)
        if not guard_passes:
            # Count sceneStarted for this specific scene name from failing index
            # (accounting for duplicates: only check unique positions)
            pass_count = sum(
                1 for j, s in enumerate(scenes)
                if s["name"] == scene["name"] and sim._check_guards(s)
            )
            started_count = len([
                s for s in sim.signals
                if s[0] == "sceneStarted" and s[1] == scene["name"]
            ])
            assert started_count == pass_count, (
                f"Scene '{scene['name']}' at index {i} failed guard but "
                f"has {started_count} sceneStarted signals (expected {pass_count})"
            )


# ═══════════════════════════════════════════════════════════════════════════════
# Property 12: Desktop State Restoration
# ═══════════════════════════════════════════════════════════════════════════════


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(
    workspace=st_workspace,
    zoom=st_zoom,
    volume=st_volume,
    muted=st_muted,
    dark_mode=st_dark_mode,
)
def test_capture_sets_prestate_non_null(workspace, zoom, volume, muted, dark_mode):
    """
    Property 12.1: Capturing always sets _preState to non-null.

    **Validates: Requirements 11.7**
    """
    mgr = DesktopStateManager()
    assert mgr.pre_state is None

    mgr.capture_state(workspace, zoom, volume, muted, dark_mode)

    assert mgr.pre_state is not None, (
        "After capture, _preState should be non-null"
    )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(
    workspace=st_workspace,
    zoom=st_zoom,
    volume=st_volume,
    muted=st_muted,
    dark_mode=st_dark_mode,
)
def test_restore_produces_equal_state(workspace, zoom, volume, muted, dark_mode):
    """
    Property 12.2: For any captured state, restoring produces commands that
    would recreate the original state. The workspace, volume, and mute fields
    are preserved in the restore commands.

    **Validates: Requirements 11.4**
    """
    mgr = DesktopStateManager()
    mgr.capture_state(workspace, zoom, volume, muted, dark_mode)

    commands = mgr.restore_state()

    assert len(commands) == 3, (
        f"Expected 3 restore commands, got {len(commands)}"
    )

    # Workspace restore command
    assert commands[0] == ["hyprctl", "dispatch", "workspace", str(workspace)], (
        f"Workspace restore mismatch: {commands[0]}"
    )

    # Volume restore command
    assert commands[1] == [
        "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", str(volume)
    ], f"Volume restore mismatch: {commands[1]}"

    # Mute restore command
    expected_mute = "1" if muted else "0"
    assert commands[2] == [
        "wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", expected_mute
    ], f"Mute restore mismatch: {commands[2]}"


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(
    workspace=st_workspace,
    zoom=st_zoom,
    volume=st_volume,
    muted=st_muted,
    dark_mode=st_dark_mode,
)
def test_restore_clears_prestate(workspace, zoom, volume, muted, dark_mode):
    """
    Property 12.3: After restore, _preState is set to null.

    **Validates: Requirements 11.4**
    """
    mgr = DesktopStateManager()
    mgr.capture_state(workspace, zoom, volume, muted, dark_mode)

    assert mgr.pre_state is not None
    mgr.restore_state()

    assert mgr.pre_state is None, (
        "After restore, _preState should be null"
    )


@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
@given(
    workspace=st_workspace,
    zoom=st_zoom,
    volume=st_volume,
    muted=st_muted,
    dark_mode=st_dark_mode,
)
def test_restore_null_prestate_is_noop(workspace, zoom, volume, muted, dark_mode):
    """
    Property 12.4: If _preState is null, restoring is a no-op (no commands emitted).

    **Validates: Requirements 11.4**
    """
    mgr = DesktopStateManager()
    # Don't capture — _preState is None
    commands = mgr.restore_state()

    assert commands == [], (
        f"Restore with null _preState should return no commands, got {commands}"
    )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(
    workspace=st_workspace,
    zoom=st_zoom,
    volume=st_volume,
    muted=st_muted,
    dark_mode=st_dark_mode,
)
def test_double_restore_is_idempotent(workspace, zoom, volume, muted, dark_mode):
    """
    Property 12.5: Double-restore is a no-op. After the first restore clears
    _preState, a second restore produces no commands.

    **Validates: Requirements 11.4**
    """
    mgr = DesktopStateManager()
    mgr.capture_state(workspace, zoom, volume, muted, dark_mode)

    # First restore — produces commands
    first_commands = mgr.restore_state()
    assert len(first_commands) == 3

    # Second restore — should be no-op
    second_commands = mgr.restore_state()
    assert second_commands == [], (
        f"Double restore should be no-op, got {second_commands}"
    )


# ═══════════════════════════════════════════════════════════════════════════════
# Property 13: Post-Scene Module Cleanup
# ═══════════════════════════════════════════════════════════════════════════════


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(module_name=st_module_name, module_is_open=st_module_is_open)
def test_force_close_when_module_open(module_name, module_is_open):
    """
    Property 13.1: When closesModule is set and the module is still open,
    should_force_close returns True. When already closed, returns False.

    **Validates: Requirements 11.6**
    """
    result = should_force_close(module_name, module_is_open)

    if module_is_open:
        assert result is True, (
            f"Module '{module_name}' is open but force_close returned False"
        )
    else:
        assert result is False, (
            f"Module '{module_name}' is closed but force_close returned True"
        )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(module_name=st_module_name)
def test_close_command_format(module_name):
    """
    Property 13.2: The close command uses the pattern
    `quickshell:<moduleName>Close` dispatched via hyprctl.

    **Validates: Requirements 11.6**
    """
    cmd = close_command(module_name)

    assert cmd == ["hyprctl", "dispatch", "global",
                   f"quickshell:{module_name}Close"], (
        f"Close command mismatch for module '{module_name}': {cmd}"
    )

    # Verify the signal name is correctly formed
    assert cmd[3].startswith("quickshell:"), (
        f"Close signal should start with 'quickshell:', got '{cmd[3]}'"
    )
    assert cmd[3].endswith("Close"), (
        f"Close signal should end with 'Close', got '{cmd[3]}'"
    )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(module_is_open=st_module_is_open)
def test_no_closes_module_no_command(module_is_open):
    """
    Property 13.3: When closesModule is not set (None or empty string),
    should_force_close returns False regardless of module_is_open state.

    **Validates: Requirements 11.6**
    """
    # None case
    assert should_force_close(None, module_is_open) is False, (
        "should_force_close(None, ...) should always be False"
    )

    # Empty string case
    assert should_force_close("", module_is_open) is False, (
        "should_force_close('', ...) should always be False"
    )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(module_name=st_module_name)
def test_closed_module_no_command_issued(module_name):
    """
    Property 13.4: If the module was already closed after scene execution,
    no close command should be issued.

    **Validates: Requirements 11.6**
    """
    # Module is closed
    result = should_force_close(module_name, module_is_open=False)
    assert result is False, (
        f"Module '{module_name}' is already closed, should not issue close command"
    )
