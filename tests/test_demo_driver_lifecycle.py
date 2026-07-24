"""
Property-based tests for scene lifecycle signal ordering.

Feature: desktop-demo-driver, Property 5: Scene Lifecycle Signals

Models the DemoDriverService state machine in Python and verifies that
signal sequences follow correct ordering for any tour configuration.

States: Idle, Running, Paused
- When a tour starts: tourStarted emitted
- For each scene: sceneStarted → (actions execute) → sceneCompleted
- When tour ends: tourCompleted emitted
- Stop always transitions to Idle + tourCompleted(cancelled=true)

**Validates: Requirements 2.5, 2.6**
"""

from hypothesis import given, settings, assume, HealthCheck
from hypothesis import strategies as st


# ─── DemoDriverSimulator: Python mirror of DemoDriverService state machine ───


class DemoDriverSimulator:
    """Models the DemoDriverService lifecycle signal emission logic."""

    IDLE, RUNNING, PAUSED = 0, 1, 2

    def __init__(self, scenes: list[dict]):
        self.state = self.IDLE
        self.queue = scenes
        self.queue_index = 0
        self.scenes_completed = 0
        self.signals: list[tuple] = []

    def start(self):
        """Start a tour. Emits tourStarted, then executes scenes in order."""
        if self.state != self.IDLE:
            self.stop()

        self.queue_index = 0
        self.scenes_completed = 0
        self.signals = []
        self.state = self.RUNNING
        self.signals.append(("tourStarted", len(self.queue)))
        self._execute_loop()

    def stop(self):
        """Stop the tour. Emits tourCompleted(cancelled=True)."""
        self.state = self.IDLE
        self.signals.append(("tourCompleted", True))  # cancelled=True

    def pause(self):
        """Pause execution without cancelling."""
        if self.state == self.RUNNING:
            self.state = self.PAUSED

    def resume(self):
        """Resume paused execution."""
        if self.state == self.PAUSED:
            self.state = self.RUNNING
            self._execute_loop()

    def stop_at(self, position: int):
        """Run the tour but stop after completing `position` scenes."""
        if self.state != self.IDLE:
            self.stop()

        self.queue_index = 0
        self.scenes_completed = 0
        self.signals = []
        self.state = self.RUNNING
        self.signals.append(("tourStarted", len(self.queue)))
        self._execute_loop_until(position)
        # Stop mid-tour
        self.stop()

    def _execute_loop(self):
        """Execute all remaining scenes in sequence."""
        while self.queue_index < len(self.queue) and self.state == self.RUNNING:
            scene = self.queue[self.queue_index]
            self.signals.append(("sceneStarted", scene["name"]))
            # Simulate action execution (all succeed)
            self.signals.append(("sceneCompleted", scene["name"], True))
            self.queue_index += 1
            self.scenes_completed += 1

        if self.state == self.RUNNING:
            # Tour completed naturally
            self.state = self.IDLE
            self.signals.append(("tourCompleted", False))  # cancelled=False

    def _execute_loop_until(self, stop_after: int):
        """Execute scenes but stop after completing `stop_after` scenes."""
        executed = 0
        while (self.queue_index < len(self.queue)
               and self.state == self.RUNNING
               and executed < stop_after):
            scene = self.queue[self.queue_index]
            self.signals.append(("sceneStarted", scene["name"]))
            self.signals.append(("sceneCompleted", scene["name"], True))
            self.queue_index += 1
            self.scenes_completed += 1
            executed += 1


# ─── Hypothesis Strategies ───

# Scene name generator: kebab-case strings
scene_name_chars = st.sampled_from("abcdefghijklmnopqrstuvwxyz0123456789-")
scene_name = st.text(
    alphabet="abcdefghijklmnopqrstuvwxyz",
    min_size=3,
    max_size=15,
).map(lambda s: s.lower())

# Generate a list of unique scene dicts (1-20 scenes)
scene_list = st.lists(
    scene_name,
    min_size=1,
    max_size=20,
    unique=True,
).map(lambda names: [{"name": n, "description": f"Demo {n}"} for n in names])

# Stop position within a tour
stop_position = st.integers(min_value=0, max_value=19)


# ─── Property Tests ───


@given(scenes=scene_list)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_full_tour_signal_count(scenes):
    """
    Property 5a: For any sequence of N scenes (1-20), a full tour produces
    exactly N sceneStarted signals and N sceneCompleted signals, wrapped by
    tourStarted and tourCompleted.

    **Validates: Requirements 2.5, 2.6**
    """
    sim = DemoDriverSimulator(scenes)
    sim.start()

    n = len(scenes)

    # Count signal types
    tour_started = [s for s in sim.signals if s[0] == "tourStarted"]
    scene_started = [s for s in sim.signals if s[0] == "sceneStarted"]
    scene_completed = [s for s in sim.signals if s[0] == "sceneCompleted"]
    tour_completed = [s for s in sim.signals if s[0] == "tourCompleted"]

    assert len(tour_started) == 1, (
        f"Expected 1 tourStarted, got {len(tour_started)}"
    )
    assert len(scene_started) == n, (
        f"Expected {n} sceneStarted, got {len(scene_started)}"
    )
    assert len(scene_completed) == n, (
        f"Expected {n} sceneCompleted, got {len(scene_completed)}"
    )
    assert len(tour_completed) == 1, (
        f"Expected 1 tourCompleted, got {len(tour_completed)}"
    )

    # tourStarted carries total scene count
    assert tour_started[0][1] == n

    # tourCompleted carries cancelled=False for natural completion
    assert tour_completed[0][1] is False


@given(scenes=scene_list)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_full_tour_signal_order(scenes):
    """
    Property 5b: The signal order is always: tourStarted, then
    (sceneStarted[i], sceneCompleted[i]) for each i, then tourCompleted.

    **Validates: Requirements 2.5, 2.6**
    """
    sim = DemoDriverSimulator(scenes)
    sim.start()

    n = len(scenes)

    # Expected signal sequence
    expected_length = 1 + (2 * n) + 1  # tourStarted + N*(start+complete) + tourCompleted
    assert len(sim.signals) == expected_length, (
        f"Expected {expected_length} signals, got {len(sim.signals)}"
    )

    # First signal: tourStarted
    assert sim.signals[0][0] == "tourStarted"

    # Middle signals: alternating sceneStarted/sceneCompleted pairs
    for i in range(n):
        start_idx = 1 + (2 * i)
        complete_idx = 1 + (2 * i) + 1
        assert sim.signals[start_idx][0] == "sceneStarted", (
            f"Signal at index {start_idx} should be sceneStarted, "
            f"got {sim.signals[start_idx][0]}"
        )
        assert sim.signals[complete_idx][0] == "sceneCompleted", (
            f"Signal at index {complete_idx} should be sceneCompleted, "
            f"got {sim.signals[complete_idx][0]}"
        )

    # Last signal: tourCompleted
    assert sim.signals[-1][0] == "tourCompleted"


@given(scenes=scene_list)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_scene_started_completed_matching_names(scenes):
    """
    Property 5c: sceneStarted and sceneCompleted for the same scene always
    have matching names.

    **Validates: Requirements 2.5, 2.6**
    """
    sim = DemoDriverSimulator(scenes)
    sim.start()

    n = len(scenes)

    # Extract paired signals
    for i in range(n):
        start_idx = 1 + (2 * i)
        complete_idx = 1 + (2 * i) + 1

        start_signal = sim.signals[start_idx]
        complete_signal = sim.signals[complete_idx]

        assert start_signal[0] == "sceneStarted"
        assert complete_signal[0] == "sceneCompleted"

        # Names must match
        assert start_signal[1] == complete_signal[1], (
            f"Scene {i}: sceneStarted name '{start_signal[1]}' != "
            f"sceneCompleted name '{complete_signal[1]}'"
        )

        # Must match the original scene queue name
        assert start_signal[1] == scenes[i]["name"], (
            f"Scene {i}: signal name '{start_signal[1]}' != "
            f"queue name '{scenes[i]['name']}'"
        )


@given(scenes=scene_list, stop_pos=stop_position)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_stop_mid_tour_signal_count(scenes, stop_pos):
    """
    Property 5d: If stopped mid-tour after completing k scenes, exactly k
    sceneCompleted signals are emitted before tourCompleted(cancelled=true).

    **Validates: Requirements 2.5, 2.6**
    """
    n = len(scenes)
    # Clamp stop position to valid range (0 to n-1 means stop before completing all)
    k = min(stop_pos, n - 1)  # Stop before the tour would naturally complete

    sim = DemoDriverSimulator(scenes)
    sim.stop_at(k)

    scene_started = [s for s in sim.signals if s[0] == "sceneStarted"]
    scene_completed = [s for s in sim.signals if s[0] == "sceneCompleted"]
    tour_completed = [s for s in sim.signals if s[0] == "tourCompleted"]

    # Exactly k scenes started and completed
    assert len(scene_started) == k, (
        f"Expected {k} sceneStarted, got {len(scene_started)}"
    )
    assert len(scene_completed) == k, (
        f"Expected {k} sceneCompleted, got {len(scene_completed)}"
    )

    # tourCompleted emitted with cancelled=True (since we stopped)
    assert len(tour_completed) == 1, (
        f"Expected 1 tourCompleted, got {len(tour_completed)}"
    )
    assert tour_completed[0][1] is True, (
        "tourCompleted should have cancelled=True when stopped mid-tour"
    )


@given(scenes=scene_list)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_scenes_completed_counter_matches_signals(scenes):
    """
    Property 5e: scenesCompleted counter equals the number of sceneCompleted
    signals emitted.

    **Validates: Requirements 2.5, 2.6**
    """
    sim = DemoDriverSimulator(scenes)
    sim.start()

    scene_completed_count = len(
        [s for s in sim.signals if s[0] == "sceneCompleted"]
    )

    assert sim.scenes_completed == scene_completed_count, (
        f"Counter {sim.scenes_completed} != signal count {scene_completed_count}"
    )
    assert sim.scenes_completed == len(scenes), (
        f"Counter {sim.scenes_completed} != total scenes {len(scenes)}"
    )


@given(scenes=scene_list, stop_pos=stop_position)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_scenes_completed_counter_matches_on_stop(scenes, stop_pos):
    """
    Property 5f: After stopping mid-tour, scenesCompleted counter equals
    the number of sceneCompleted signals emitted (k).

    **Validates: Requirements 2.5, 2.6**
    """
    n = len(scenes)
    k = min(stop_pos, n - 1)

    sim = DemoDriverSimulator(scenes)
    sim.stop_at(k)

    scene_completed_count = len(
        [s for s in sim.signals if s[0] == "sceneCompleted"]
    )

    assert sim.scenes_completed == scene_completed_count, (
        f"Counter {sim.scenes_completed} != signal count {scene_completed_count}"
    )
    assert sim.scenes_completed == k, (
        f"Counter {sim.scenes_completed} != stop position {k}"
    )


@given(scenes=scene_list)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_state_transitions_full_tour(scenes):
    """
    Property 5g: A full tour transitions state: Idle → Running → Idle.
    After tour completion, state is Idle.

    **Validates: Requirements 2.5, 2.6**
    """
    sim = DemoDriverSimulator(scenes)
    assert sim.state == DemoDriverSimulator.IDLE

    sim.start()

    # After a full synchronous tour, state should be Idle
    assert sim.state == DemoDriverSimulator.IDLE, (
        f"Expected IDLE after tour, got {sim.state}"
    )


@given(scenes=scene_list, stop_pos=stop_position)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_state_transitions_stopped_tour(scenes, stop_pos):
    """
    Property 5h: Stop always transitions to Idle with tourCompleted(cancelled=true).

    **Validates: Requirements 2.5, 2.6**
    """
    n = len(scenes)
    k = min(stop_pos, n - 1)

    sim = DemoDriverSimulator(scenes)
    sim.stop_at(k)

    # After stop, state should be Idle
    assert sim.state == DemoDriverSimulator.IDLE, (
        f"Expected IDLE after stop, got {sim.state}"
    )

    # Last signal should be tourCompleted with cancelled=True
    assert sim.signals[-1] == ("tourCompleted", True), (
        f"Expected tourCompleted(True) as last signal, got {sim.signals[-1]}"
    )
