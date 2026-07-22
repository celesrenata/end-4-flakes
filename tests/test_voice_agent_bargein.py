# Feature: streaming-voice-agent, Property 7: Barge-in interrupts playback
"""Property-based tests for barge-in behavior in VoiceAgentService.

Generates states where Speaking is active, simulates activation key tap (bargeIn),
verifies pw-play terminated, BARGE_IN sent to helper, and transition to Listening.

**Validates: Requirements 4.5, 7.5**
"""

import enum
import time
from dataclasses import dataclass, field
from typing import Optional

import pytest
from hypothesis import given, settings, assume
from hypothesis import strategies as st


# ---------------------------------------------------------------------------
# Model: VoiceAgentService state machine with barge-in semantics
# ---------------------------------------------------------------------------


class State(enum.Enum):
    Idle = "Idle"
    Connecting = "Connecting"
    Listening = "Listening"
    Thinking = "Thinking"
    Speaking = "Speaking"
    ToolExecuting = "ToolExecuting"
    Error = "Error"


class EventType(enum.Enum):
    """Events arriving from the helper or user actions."""

    ACTIVATE = "ACTIVATE"
    READY = "READY"
    TURN_END = "TURN_END"
    AUDIO_RESPONSE = "AUDIO_RESPONSE"
    TOOL_CALL = "TOOL_CALL"
    TOOL_RESULT = "TOOL_RESULT"
    AUDIO_COMPLETE = "AUDIO_COMPLETE"
    BARGE_IN = "BARGE_IN"
    STOP = "STOP"
    SESSION_END = "SESSION_END"
    FATAL_ERROR = "FATAL_ERROR"
    TIMEOUT = "TIMEOUT"
    TICK = "TICK"


@dataclass
class ActionLog:
    """Records actions taken by the service (sent events, process kills)."""

    playback_kills: int = 0
    barge_in_events_sent: int = 0
    messages_sent_to_helper: list = field(default_factory=list)


@dataclass
class VoiceAgentModel:
    """Model of VoiceAgentService with barge-in instrumentation.

    Mirrors the real QML service's state machine, tracking:
    - Current state
    - Whether pw-play is running (playback active)
    - Action log for verifying barge-in side-effects
    - Timing for transition latency assertions
    """

    state: State = State.Idle
    playback_running: bool = False
    helper_running: bool = False
    barge_in_active: bool = False  # Mirrors root._bargeInActive
    action_log: ActionLog = field(default_factory=ActionLog)
    connecting_elapsed_s: float = 0.0
    barge_in_timestamp_ms: Optional[float] = None
    transition_timestamp_ms: Optional[float] = None

    def process_event(self, event: EventType) -> None:
        """Process event, mirroring VoiceAgentService logic."""

        # TICK: advance time for connection timeout tracking
        if event == EventType.TICK:
            if self.state == State.Connecting:
                self.connecting_elapsed_s += 1.0
                if self.connecting_elapsed_s >= 5.0:
                    self.state = State.Error
                    self.connecting_elapsed_s = 0.0
            return

        # Universal transitions
        if event in (EventType.STOP, EventType.SESSION_END) and self.state != State.Idle:
            self.state = State.Idle
            self.playback_running = False
            self.helper_running = False
            self.connecting_elapsed_s = 0.0
            return

        if event == EventType.FATAL_ERROR and self.state != State.Idle:
            self.state = State.Error
            self.playback_running = False
            self.helper_running = False
            self.connecting_elapsed_s = 0.0
            return

        # BARGE_IN: the key behavior under test
        if event == EventType.BARGE_IN:
            self._handle_barge_in()
            return

        # Specific transitions
        if self.state == State.Idle and event == EventType.ACTIVATE:
            self.state = State.Connecting
            self.helper_running = True
            self.connecting_elapsed_s = 0.0

        elif self.state == State.Connecting and event == EventType.READY:
            self.state = State.Listening
            self.connecting_elapsed_s = 0.0

        elif self.state == State.Connecting and event == EventType.TIMEOUT:
            self.state = State.Error
            self.connecting_elapsed_s = 0.0

        elif self.state == State.Listening and event == EventType.TURN_END:
            self.state = State.Thinking

        elif self.state == State.Thinking and event == EventType.AUDIO_RESPONSE:
            self.state = State.Speaking
            self.playback_running = True

        elif self.state == State.Thinking and event == EventType.TOOL_CALL:
            self.state = State.ToolExecuting

        elif self.state == State.ToolExecuting and event == EventType.TOOL_RESULT:
            self.state = State.Thinking

        elif self.state == State.Speaking and event == EventType.AUDIO_COMPLETE:
            self.state = State.Listening
            self.playback_running = False

    def _handle_barge_in(self) -> None:
        """Mirrors VoiceAgentService.bargeIn() logic.

        From the QML implementation:
        1. Guard: only acts if state == Speaking
        2. Set _bargeInActive = true (suppress playback exit error)
        3. Kill playbackProcess (set running = false)
        4. Send BARGE_IN JSON to helper stdin
        5. Clear responseText
        6. Transition to Listening
        """
        if self.state != State.Speaking:
            return  # Guard: bargeIn() returns early if not Speaking

        # Record timing for latency verification
        self.barge_in_timestamp_ms = time.monotonic_ns() / 1_000_000

        # Step 1: Set barge-in flag (suppresses playback exit handler)
        self.barge_in_active = True

        # Step 2: Kill pw-play
        self.playback_running = False
        self.action_log.playback_kills += 1

        # Step 3: Send BARGE_IN to helper
        if self.helper_running:
            self.action_log.barge_in_events_sent += 1
            self.action_log.messages_sent_to_helper.append({"type": "BARGE_IN"})

        # Step 4: Transition to Listening
        self.state = State.Listening

        # Record transition timestamp
        self.transition_timestamp_ms = time.monotonic_ns() / 1_000_000


# ---------------------------------------------------------------------------
# Hypothesis strategies
# ---------------------------------------------------------------------------

# Events that can bring the state machine from Idle to Speaking
# (the prefix needed before barge-in can be tested)
prefix_events_to_speaking = st.just([
    EventType.ACTIVATE,
    EventType.READY,
    EventType.TURN_END,
    EventType.AUDIO_RESPONSE,
])

# Random number of additional AUDIO_RESPONSE events (simulating ongoing playback)
additional_audio_events = st.lists(
    st.just(EventType.AUDIO_RESPONSE),
    min_size=0,
    max_size=5,
)

# Full event strategy for reaching Speaking through various paths
event_strategy = st.sampled_from(list(EventType))

# Sequences that might reach Speaking state
random_event_sequence = st.lists(event_strategy, min_size=1, max_size=30)

# Strategy for number of prior turns (multi-turn scenarios reaching Speaking)
prior_turns = st.integers(min_value=0, max_value=3)


@st.composite
def speaking_state_scenario(draw):
    """Generate a scenario that reaches Speaking state via various paths.

    Includes:
    - Direct path: ACTIVATE → READY → TURN_END → AUDIO_RESPONSE
    - Multi-turn: multiple TURN_END/AUDIO_RESPONSE/AUDIO_COMPLETE cycles
    - With tool calls: TURN_END → TOOL_CALL → TOOL_RESULT → AUDIO_RESPONSE
    """
    events = [EventType.ACTIVATE, EventType.READY]

    # Optionally add some prior turns before the final Speaking state
    n_prior_turns = draw(prior_turns)
    for _ in range(n_prior_turns):
        events.append(EventType.TURN_END)

        # Optionally interleave a tool call
        has_tool_call = draw(st.booleans())
        if has_tool_call:
            events.append(EventType.TOOL_CALL)
            events.append(EventType.TOOL_RESULT)

        events.append(EventType.AUDIO_RESPONSE)
        events.append(EventType.AUDIO_COMPLETE)  # Back to Listening

    # Final turn that puts us in Speaking
    events.append(EventType.TURN_END)

    # Optionally add tool call before audio response
    has_final_tool = draw(st.booleans())
    if has_final_tool:
        events.append(EventType.TOOL_CALL)
        events.append(EventType.TOOL_RESULT)

    events.append(EventType.AUDIO_RESPONSE)

    # Add some additional audio chunks while in Speaking
    extra_audio = draw(additional_audio_events)
    events.extend(extra_audio)

    return events


# ---------------------------------------------------------------------------
# Property tests
# ---------------------------------------------------------------------------


@pytest.mark.property_test
@settings(max_examples=500)
@given(prefix_events=speaking_state_scenario())
def test_barge_in_terminates_playback(prefix_events: list[EventType]) -> None:
    """Property 7: Barge-in from Speaking state terminates pw-play.

    For any scenario that reaches Speaking state, bargeIn() must kill
    the playback process (pw-play).

    **Validates: Requirements 4.5, 7.5**
    """
    model = VoiceAgentModel()

    # Drive to Speaking state
    for event in prefix_events:
        model.process_event(event)

    # Verify precondition: we're in Speaking with playback running
    assert model.state == State.Speaking, (
        f"Precondition failed: expected Speaking, got {model.state.value}"
    )
    assert model.playback_running, "Precondition failed: playback not running"

    # Execute barge-in
    model.process_event(EventType.BARGE_IN)

    # Verify: playback terminated
    assert not model.playback_running, (
        "Barge-in did not terminate playback (pw-play still running)"
    )
    assert model.action_log.playback_kills >= 1, (
        "Barge-in did not record a playback kill action"
    )


@pytest.mark.property_test
@settings(max_examples=500)
@given(prefix_events=speaking_state_scenario())
def test_barge_in_sends_event_to_helper(prefix_events: list[EventType]) -> None:
    """Property 7: Barge-in sends BARGE_IN JSON event to helper stdin.

    For any scenario that reaches Speaking state with helper running,
    bargeIn() must send {"type": "BARGE_IN"} to the helper process stdin.

    **Validates: Requirements 4.5, 7.5**
    """
    model = VoiceAgentModel()

    for event in prefix_events:
        model.process_event(event)

    assert model.state == State.Speaking
    assert model.helper_running, "Precondition failed: helper not running"

    # Record baseline
    events_before = model.action_log.barge_in_events_sent

    # Execute barge-in
    model.process_event(EventType.BARGE_IN)

    # Verify: BARGE_IN event was sent
    assert model.action_log.barge_in_events_sent == events_before + 1, (
        "Barge-in did not send BARGE_IN event to helper"
    )
    # Verify the message content
    last_msg = model.action_log.messages_sent_to_helper[-1]
    assert last_msg == {"type": "BARGE_IN"}, (
        f"Expected BARGE_IN message, got {last_msg}"
    )


@pytest.mark.property_test
@settings(max_examples=500)
@given(prefix_events=speaking_state_scenario())
def test_barge_in_transitions_to_listening(prefix_events: list[EventType]) -> None:
    """Property 7: Barge-in transitions state from Speaking to Listening.

    For any scenario that reaches Speaking state, bargeIn() must transition
    the state machine to Listening within 200ms (modeled as immediate
    in the synchronous model — the 200ms bound is architectural, not
    blocked by async I/O in the QML implementation).

    **Validates: Requirements 4.5, 7.5**
    """
    model = VoiceAgentModel()

    for event in prefix_events:
        model.process_event(event)

    assert model.state == State.Speaking

    # Execute barge-in
    model.process_event(EventType.BARGE_IN)

    # Verify: state is now Listening
    assert model.state == State.Listening, (
        f"Barge-in should transition to Listening, got {model.state.value}"
    )


@pytest.mark.property_test
@settings(max_examples=500)
@given(prefix_events=speaking_state_scenario())
def test_barge_in_latency_within_200ms(prefix_events: list[EventType]) -> None:
    """Property 7: Barge-in completes transition within 200ms.

    The model records timestamps at barge-in initiation and state transition.
    In the synchronous QML implementation, this is effectively instantaneous,
    but we verify the bound holds (< 200ms elapsed between action and state change).

    **Validates: Requirements 4.5, 7.5**
    """
    model = VoiceAgentModel()

    for event in prefix_events:
        model.process_event(event)

    assert model.state == State.Speaking

    # Execute barge-in (timestamps recorded internally)
    model.process_event(EventType.BARGE_IN)

    # Verify latency
    assert model.barge_in_timestamp_ms is not None
    assert model.transition_timestamp_ms is not None
    latency_ms = model.transition_timestamp_ms - model.barge_in_timestamp_ms
    assert latency_ms < 200.0, (
        f"Barge-in transition took {latency_ms:.2f}ms, exceeds 200ms bound"
    )


@pytest.mark.property_test
@settings(max_examples=500)
@given(prefix_events=speaking_state_scenario())
def test_barge_in_all_invariants_combined(prefix_events: list[EventType]) -> None:
    """Property 7: Combined invariant — barge-in from Speaking satisfies all conditions.

    A single test verifying all three barge-in invariants together:
    1. pw-play terminated
    2. BARGE_IN event sent to helper
    3. State transitions to Listening

    **Validates: Requirements 4.5, 7.5**
    """
    model = VoiceAgentModel()

    for event in prefix_events:
        model.process_event(event)

    # Preconditions
    assert model.state == State.Speaking
    assert model.playback_running
    assert model.helper_running

    # Execute barge-in
    model.process_event(EventType.BARGE_IN)

    # All invariants must hold simultaneously
    assert not model.playback_running, "Invariant 1 failed: playback not terminated"
    assert model.action_log.barge_in_events_sent >= 1, "Invariant 2 failed: BARGE_IN not sent"
    assert model.state == State.Listening, (
        f"Invariant 3 failed: expected Listening, got {model.state.value}"
    )


@pytest.mark.property_test
@settings(max_examples=300)
@given(
    prefix_events=speaking_state_scenario(),
    non_speaking_state=st.sampled_from([
        State.Idle, State.Connecting, State.Listening,
        State.Thinking, State.ToolExecuting, State.Error,
    ]),
)
def test_barge_in_no_op_when_not_speaking(
    prefix_events: list[EventType],
    non_speaking_state: State,
) -> None:
    """Property 7 (guard): Barge-in is a no-op when not in Speaking state.

    The bargeIn() function has a guard: `if state != Speaking: return`.
    Verify that calling barge-in from non-Speaking states has no effect.

    **Validates: Requirements 4.5, 7.5**
    """
    model = VoiceAgentModel()

    # Force model into the target non-Speaking state
    model.state = non_speaking_state
    model.playback_running = False
    model.helper_running = True

    original_state = model.state
    original_kills = model.action_log.playback_kills
    original_events = model.action_log.barge_in_events_sent

    # Attempt barge-in
    model.process_event(EventType.BARGE_IN)

    # Verify: no state change, no side effects
    assert model.state == original_state, (
        f"Barge-in from {non_speaking_state.value} changed state to {model.state.value}"
    )
    assert model.action_log.playback_kills == original_kills, (
        "Barge-in from non-Speaking state killed playback"
    )
    assert model.action_log.barge_in_events_sent == original_events, (
        "Barge-in from non-Speaking state sent event to helper"
    )
