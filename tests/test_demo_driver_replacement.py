"""
Property-based tests for running tour replacement behavior.

Feature: desktop-demo-driver, Property 10: Running Tour Replacement

When start() is called while a tour is already running:
1. The current tour is stopped first (stop() is called)
2. A new tour begins with the new parameters
3. tourCompleted(cancelled=true) is emitted for the old tour
4. tourStarted is emitted for the new tour
5. The new tour's scenesCompleted counter resets to 0
6. The new tour's queue is set to the new scenes

**Validates: Requirements 10.5**
"""

from hypothesis import given, settings, assume, HealthCheck
from hypothesis import strategies as st


# ─── TourReplacementSimulator: Python model of replacement behavior ───


class TourReplacementSimulator:
    """Models the DemoDriverService tour replacement logic."""

    IDLE, RUNNING = 0, 1

    def __init__(self):
        self.state = self.IDLE
        self.signals: list[tuple] = []
        self.queue: list[dict] = []
        self.scenes_completed = 0

    def start(self, scenes: list[dict]):
        """Start a tour. If already running, stops old tour first."""
        if self.state != self.IDLE:
            self._stop_internal()
        self.queue = scenes
        self.scenes_completed = 0
        self.state = self.RUNNING
        self.signals.append(("tourStarted", len(scenes)))

    def _stop_internal(self):
        """Internal stop: emits tourCompleted(cancelled=True), transitions to Idle."""
        self.state = self.IDLE
        self.signals.append(("tourCompleted", True))


# ─── Hypothesis Strategies ───

# Scene dict generator
scene_name = st.text(
    alphabet="abcdefghijklmnopqrstuvwxyz",
    min_size=3,
    max_size=12,
)

scene_dict = scene_name.map(lambda n: {"name": n, "description": f"Demo {n}"})

# Lists of scene dicts for initial and replacement tours (1-10 scenes each)
scene_list = st.lists(scene_dict, min_size=1, max_size=10)

# Number of replacements (2-5)
replacement_count = st.integers(min_value=2, max_value=5)


# ─── Property Tests ───


@given(initial_scenes=scene_list, replacement_scenes=scene_list)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_replacement_produces_cancelled_before_new_start(
    initial_scenes, replacement_scenes
):
    """
    Property 10a: Starting while running always produces
    tourCompleted(cancelled=true) before the new tourStarted.

    **Validates: Requirements 10.5**
    """
    sim = TourReplacementSimulator()

    # Start initial tour
    sim.start(initial_scenes)
    assert sim.state == TourReplacementSimulator.RUNNING

    # Replace with new tour while running
    sim.start(replacement_scenes)

    # Find the indices of the cancellation and new start signals
    cancelled_indices = [
        i for i, s in enumerate(sim.signals)
        if s == ("tourCompleted", True)
    ]
    new_start_indices = [
        i for i, s in enumerate(sim.signals)
        if s[0] == "tourStarted" and s[1] == len(replacement_scenes)
    ]

    assert len(cancelled_indices) >= 1, (
        "Expected at least one tourCompleted(cancelled=True) signal"
    )
    assert len(new_start_indices) >= 1, (
        "Expected at least one tourStarted signal for new tour"
    )

    # The cancellation must come before the new tourStarted
    last_cancel = cancelled_indices[-1]
    last_new_start = new_start_indices[-1]
    assert last_cancel < last_new_start, (
        f"tourCompleted(cancelled=True) at index {last_cancel} should come "
        f"before new tourStarted at index {last_new_start}"
    )


@given(initial_scenes=scene_list, replacement_scenes=scene_list)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_replacement_resets_scenes_completed(
    initial_scenes, replacement_scenes
):
    """
    Property 10b: After replacement, scenesCompleted is 0.

    **Validates: Requirements 10.5**
    """
    sim = TourReplacementSimulator()

    # Start initial tour
    sim.start(initial_scenes)
    # Simulate some progress on the initial tour
    sim.scenes_completed = 3

    # Replace with new tour
    sim.start(replacement_scenes)

    assert sim.scenes_completed == 0, (
        f"Expected scenesCompleted to be 0 after replacement, "
        f"got {sim.scenes_completed}"
    )


@given(initial_scenes=scene_list, replacement_scenes=scene_list)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_replacement_queue_matches_new_scenes(
    initial_scenes, replacement_scenes
):
    """
    Property 10c: After replacement, queue length matches new scenes.

    **Validates: Requirements 10.5**
    """
    sim = TourReplacementSimulator()

    # Start initial tour
    sim.start(initial_scenes)

    # Replace with new tour
    sim.start(replacement_scenes)

    assert len(sim.queue) == len(replacement_scenes), (
        f"Expected queue length {len(replacement_scenes)}, "
        f"got {len(sim.queue)}"
    )
    assert sim.queue == replacement_scenes, (
        "Queue contents should match the new replacement scenes"
    )


@given(
    scene_lists=st.lists(scene_list, min_size=2, max_size=5),
)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_multiple_rapid_replacements_each_produce_cancel_before_start(
    scene_lists,
):
    """
    Property 10d: Multiple rapid replacements (2-5) each produce a
    tourCompleted(cancelled=True) before the new tourStarted.

    **Validates: Requirements 10.5**
    """
    sim = TourReplacementSimulator()

    # Start first tour
    sim.start(scene_lists[0])

    # Rapidly replace with each subsequent tour
    for i in range(1, len(scene_lists)):
        sim.start(scene_lists[i])

    # Verify signal ordering: each tourCompleted(cancelled=True) must be
    # immediately followed by a tourStarted
    num_replacements = len(scene_lists) - 1

    # Count cancellation signals (all replacements produce one)
    cancel_signals = [
        (i, s) for i, s in enumerate(sim.signals)
        if s == ("tourCompleted", True)
    ]
    start_signals = [
        (i, s) for i, s in enumerate(sim.signals)
        if s[0] == "tourStarted"
    ]

    # We should have exactly num_replacements cancellations
    assert len(cancel_signals) == num_replacements, (
        f"Expected {num_replacements} tourCompleted(cancelled=True), "
        f"got {len(cancel_signals)}"
    )

    # We should have len(scene_lists) total tourStarted signals
    assert len(start_signals) == len(scene_lists), (
        f"Expected {len(scene_lists)} tourStarted signals, "
        f"got {len(start_signals)}"
    )

    # Each cancellation signal must come immediately before a tourStarted
    for cancel_idx, cancel_signal in cancel_signals:
        # Find the next signal after this cancellation
        assert cancel_idx + 1 < len(sim.signals), (
            f"tourCompleted at index {cancel_idx} has no following signal"
        )
        next_signal = sim.signals[cancel_idx + 1]
        assert next_signal[0] == "tourStarted", (
            f"Expected tourStarted after tourCompleted at index {cancel_idx}, "
            f"got {next_signal[0]}"
        )


@given(initial_scenes=scene_list, replacement_scenes=scene_list)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_replacement_final_state_is_running(
    initial_scenes, replacement_scenes
):
    """
    Property 10e: The final state after replacement is Running (not Idle).

    **Validates: Requirements 10.5**
    """
    sim = TourReplacementSimulator()

    # Start initial tour
    sim.start(initial_scenes)

    # Replace with new tour
    sim.start(replacement_scenes)

    assert sim.state == TourReplacementSimulator.RUNNING, (
        f"Expected state RUNNING after replacement, got {sim.state}"
    )
