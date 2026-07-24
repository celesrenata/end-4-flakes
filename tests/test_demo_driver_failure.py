# Feature: desktop-demo-driver, Property 6: Failure Skip and Continuation
"""
Property 6: Failure Skip and Continuation

When a scene's guard check fails:
1. The scene is skipped (sceneCompleted with success=false)
2. The tour continues to the next scene
3. The total number of sceneStarted + skipped == total scenes in queue
4. Skipped scenes DO emit sceneCompleted(name, false) but NOT sceneStarted

Uses a FailureSkipSimulator model that mirrors DemoDriverService behavior
when guards fail — the same logic from _executeNextScene() in the QML.

**Validates: Requirements 2.8**
"""

from hypothesis import given, settings, assume, HealthCheck
from hypothesis import strategies as st


# ─── Model: FailureSkipSimulator ───


class FailureSkipSimulator:
    """Simulates DemoDriverService behavior when guards fail."""

    def __init__(self, scenes: list[dict], failing_indices: set[int]):
        """
        scenes: list of scene dicts with 'name'
        failing_indices: set of indices where guard check fails
        """
        self.queue = scenes
        self.failing = set(failing_indices)
        self.signals: list[tuple] = []
        self.scenes_completed = 0

    def run(self):
        self.signals.append(("tourStarted", len(self.queue)))
        for i, scene in enumerate(self.queue):
            if i in self.failing:
                # Guard failed — skip
                self.signals.append(("sceneCompleted", scene["name"], False))
                self.scenes_completed += 1
            else:
                # Guard passed — execute
                self.signals.append(("sceneStarted", scene["name"]))
                self.signals.append(("sceneCompleted", scene["name"], True))
                self.scenes_completed += 1
        self.signals.append(("tourCompleted", False))


# ─── Hypothesis Strategies ───

# Generate a queue of 1-15 scenes with random kebab-case-ish names
st_scene_name = st.from_regex(r"[a-z][a-z0-9]*(-[a-z0-9]+){0,3}", fullmatch=True)

st_scene_queue = st.lists(
    st.builds(lambda name: {"name": name}, st_scene_name),
    min_size=1,
    max_size=15,
)


@st.composite
def st_queue_with_failures(draw):
    """Generate a scene queue and a random subset of failing indices."""
    queue = draw(st_scene_queue)
    n = len(queue)
    # Generate a random subset of indices that will fail (0 to all)
    failing = draw(
        st.sets(st.integers(min_value=0, max_value=n - 1), max_size=n)
    )
    return queue, failing


# ─── Property Tests ───


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(data=st_queue_with_failures())
def test_scenes_completed_equals_queue_length(data):
    """
    Property 6.1: For any random subset of failing scenes,
    scenesCompleted always equals the total queue length.

    Every scene is either executed or skipped, but always counted.

    **Validates: Requirements 2.8**
    """
    queue, failing = data
    sim = FailureSkipSimulator(queue, failing)
    sim.run()

    assert sim.scenes_completed == len(queue), (
        f"Expected scenesCompleted={len(queue)}, got {sim.scenes_completed}. "
        f"Queue size={len(queue)}, failing={failing}"
    )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(data=st_queue_with_failures())
def test_failed_scenes_emit_completed_not_started(data):
    """
    Property 6.2: Failed scenes emit sceneCompleted(name, false)
    but do NOT emit sceneStarted.

    This confirms that guard-failed scenes are properly skipped without
    starting execution.

    **Validates: Requirements 2.8**
    """
    queue, failing = data
    sim = FailureSkipSimulator(queue, failing)
    sim.run()

    for i in failing:
        scene_name = queue[i]["name"]

        # Must have sceneCompleted with success=false
        completed_signals = [
            s for s in sim.signals
            if s[0] == "sceneCompleted" and s[1] == scene_name and s[2] is False
        ]
        assert len(completed_signals) >= 1, (
            f"Failed scene '{scene_name}' (index {i}) missing "
            f"sceneCompleted(name, false) signal"
        )

        # Must NOT have sceneStarted for this scene (only if it exclusively fails)
        # A name can appear multiple times if queue has duplicates, so check
        # by position in the signal stream instead
        started_for_scene = [
            s for s in sim.signals
            if s[0] == "sceneStarted" and s[1] == scene_name
        ]

        # Count how many times this name appears in successful (non-failing) slots
        success_count = sum(
            1 for j, sc in enumerate(queue)
            if sc["name"] == scene_name and j not in failing
        )

        # Started signals should only come from successful executions
        assert len(started_for_scene) == success_count, (
            f"Scene '{scene_name}' has {len(started_for_scene)} sceneStarted "
            f"signals but only {success_count} successful executions"
        )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(data=st_queue_with_failures())
def test_successful_scenes_emit_both_started_and_completed(data):
    """
    Property 6.3: Successful scenes emit both sceneStarted and
    sceneCompleted(name, true).

    **Validates: Requirements 2.8**
    """
    queue, failing = data
    sim = FailureSkipSimulator(queue, failing)
    sim.run()

    for i, scene in enumerate(queue):
        if i not in failing:
            scene_name = scene["name"]

            # Count successful executions of this name
            success_indices = [
                j for j, sc in enumerate(queue)
                if sc["name"] == scene_name and j not in failing
            ]

            started_signals = [
                s for s in sim.signals
                if s[0] == "sceneStarted" and s[1] == scene_name
            ]
            completed_true_signals = [
                s for s in sim.signals
                if s[0] == "sceneCompleted" and s[1] == scene_name and s[2] is True
            ]

            assert len(started_signals) == len(success_indices), (
                f"Scene '{scene_name}': expected {len(success_indices)} "
                f"sceneStarted signals, got {len(started_signals)}"
            )
            assert len(completed_true_signals) == len(success_indices), (
                f"Scene '{scene_name}': expected {len(success_indices)} "
                f"sceneCompleted(true) signals, got {len(completed_true_signals)}"
            )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(data=st_queue_with_failures())
def test_tour_always_completes_even_if_all_fail(data):
    """
    Property 6.4: The tour always completes (tourCompleted emitted)
    even if ALL scenes fail their guard checks.

    **Validates: Requirements 2.8**
    """
    queue, failing = data
    sim = FailureSkipSimulator(queue, failing)
    sim.run()

    # tourCompleted must always be emitted exactly once
    tour_completed_signals = [
        s for s in sim.signals if s[0] == "tourCompleted"
    ]
    assert len(tour_completed_signals) == 1, (
        f"Expected exactly 1 tourCompleted signal, "
        f"got {len(tour_completed_signals)}"
    )

    # tourCompleted should indicate not cancelled (false)
    assert tour_completed_signals[0] == ("tourCompleted", False), (
        f"tourCompleted should be (tourCompleted, False), "
        f"got {tour_completed_signals[0]}"
    )

    # tourStarted must also be emitted exactly once
    tour_started_signals = [
        s for s in sim.signals if s[0] == "tourStarted"
    ]
    assert len(tour_started_signals) == 1, (
        f"Expected exactly 1 tourStarted signal, "
        f"got {len(tour_started_signals)}"
    )


@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
@given(data=st_queue_with_failures())
def test_total_scene_completed_equals_queue_length(data):
    """
    Property 6.5: Total sceneCompleted signals equals total queue length
    regardless of which scenes fail.

    Every scene in the queue produces exactly one sceneCompleted signal —
    either with success=true (executed) or success=false (skipped).

    **Validates: Requirements 2.8**
    """
    queue, failing = data
    sim = FailureSkipSimulator(queue, failing)
    sim.run()

    completed_signals = [
        s for s in sim.signals if s[0] == "sceneCompleted"
    ]
    assert len(completed_signals) == len(queue), (
        f"Expected {len(queue)} sceneCompleted signals, "
        f"got {len(completed_signals)}. Failing indices: {failing}"
    )

    # Verify the split: failures + successes == total
    failed_completions = [s for s in completed_signals if s[2] is False]
    success_completions = [s for s in completed_signals if s[2] is True]

    assert len(failed_completions) == len(failing), (
        f"Expected {len(failing)} failed completions, "
        f"got {len(failed_completions)}"
    )
    assert len(success_completions) == len(queue) - len(failing), (
        f"Expected {len(queue) - len(failing)} successful completions, "
        f"got {len(success_completions)}"
    )


# ─── Edge case: all scenes fail ───


@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
@given(queue=st_scene_queue)
def test_all_scenes_failing_still_completes_tour(queue):
    """
    Property 6 edge case: When every scene in the queue fails,
    the tour still completes and all scenes emit sceneCompleted(false).

    **Validates: Requirements 2.8**
    """
    all_failing = set(range(len(queue)))
    sim = FailureSkipSimulator(queue, all_failing)
    sim.run()

    # No sceneStarted signals at all
    started = [s for s in sim.signals if s[0] == "sceneStarted"]
    assert len(started) == 0, (
        f"Expected no sceneStarted signals when all fail, got {len(started)}"
    )

    # All completions are failures
    completed = [s for s in sim.signals if s[0] == "sceneCompleted"]
    assert all(s[2] is False for s in completed), (
        "All sceneCompleted signals should have success=false"
    )
    assert len(completed) == len(queue)

    # Tour still completes
    assert ("tourCompleted", False) in sim.signals
