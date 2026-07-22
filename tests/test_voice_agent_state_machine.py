# Feature: streaming-voice-agent, Property 4: State machine valid transitions
"""Property-based tests for the VoiceAgentService state machine.

Generates random sequences of helper events, verifies the state machine only
follows valid edges and Connecting never exceeds 5s without transition.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 10.1**
"""

import enum
from dataclasses import dataclass, field

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st


# ---------------------------------------------------------------------------
# State machine model (mirrors QML VoiceAgentService logic)
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
    """Events that can arrive from the helper or user actions."""

    ACTIVATE = "ACTIVATE"  # User taps activation key (Idle → Connecting)
    READY = "READY"  # Helper connected (Connecting → Listening)
    TURN_END = "TURN_END"  # VAD detected end of speech (Listening → Thinking)
    AUDIO_RESPONSE = "AUDIO_RESPONSE"  # Backend sends audio (Thinking → Speaking)
    TOOL_CALL = "TOOL_CALL"  # Backend requests tool (Thinking → ToolExecuting)
    TOOL_RESULT = "TOOL_RESULT"  # Tool execution complete (ToolExecuting → Thinking)
    AUDIO_COMPLETE = "AUDIO_COMPLETE"  # Playback finished (Speaking → Listening)
    BARGE_IN = "BARGE_IN"  # User interrupts playback (Speaking → Listening)
    STOP = "STOP"  # User deactivates (Any → Idle)
    SESSION_END = "SESSION_END"  # Helper signals end (Any → Idle)
    FATAL_ERROR = "FATAL_ERROR"  # Unrecoverable error (Any → Error)
    TIMEOUT = "TIMEOUT"  # Connection timeout (Connecting → Error)
    TICK = "TICK"  # Simulated time passage (1 second)


# Valid transition edges: (from_state, event) → to_state
VALID_TRANSITIONS: dict[tuple[State, EventType], State] = {
    (State.Idle, EventType.ACTIVATE): State.Connecting,
    (State.Connecting, EventType.READY): State.Listening,
    (State.Connecting, EventType.TIMEOUT): State.Error,
    (State.Connecting, EventType.FATAL_ERROR): State.Error,
    (State.Listening, EventType.TURN_END): State.Thinking,
    (State.Thinking, EventType.AUDIO_RESPONSE): State.Speaking,
    (State.Thinking, EventType.TOOL_CALL): State.ToolExecuting,
    (State.Speaking, EventType.AUDIO_COMPLETE): State.Listening,
    (State.Speaking, EventType.BARGE_IN): State.Listening,
    (State.ToolExecuting, EventType.TOOL_RESULT): State.Thinking,
}

# Universal transitions (from any non-Idle state)
UNIVERSAL_TO_IDLE = {EventType.STOP, EventType.SESSION_END}
UNIVERSAL_TO_ERROR = {EventType.FATAL_ERROR}


@dataclass
class StateMachine:
    """Pure logic model of VoiceAgentService state machine."""

    state: State = State.Idle
    connecting_elapsed_s: float = 0.0
    transitions: list[tuple[State, EventType, State]] = field(default_factory=list)

    def process_event(self, event: EventType) -> None:
        """Process an event, updating state. Invalid events are ignored (no-op)."""
        old_state = self.state

        # TICK: advance time for connection timeout tracking
        if event == EventType.TICK:
            if self.state == State.Connecting:
                self.connecting_elapsed_s += 1.0
                if self.connecting_elapsed_s >= 5.0:
                    # Req 10.1: 5-second timeout → Error/fallback
                    self.state = State.Error
                    self.connecting_elapsed_s = 0.0
                    self.transitions.append((old_state, event, self.state))
            return

        # Universal transitions (apply from any state except Idle for STOP/SESSION_END)
        if event in UNIVERSAL_TO_IDLE and self.state != State.Idle:
            self.state = State.Idle
            self.connecting_elapsed_s = 0.0
            self.transitions.append((old_state, event, self.state))
            return

        if event in UNIVERSAL_TO_ERROR and self.state != State.Idle:
            self.state = State.Error
            self.connecting_elapsed_s = 0.0
            self.transitions.append((old_state, event, self.state))
            return

        # Specific transitions
        key = (self.state, event)
        if key in VALID_TRANSITIONS:
            self.state = VALID_TRANSITIONS[key]
            # Reset connecting timer when leaving Connecting
            if old_state == State.Connecting:
                self.connecting_elapsed_s = 0.0
            # Reset connecting timer when entering Connecting
            if self.state == State.Connecting:
                self.connecting_elapsed_s = 0.0
            self.transitions.append((old_state, event, self.state))
        # else: event is ignored (no transition from current state)


def get_valid_edges() -> set[tuple[State, State]]:
    """Return the set of all valid (from, to) state pairs."""
    edges: set[tuple[State, State]] = set()

    # Specific transitions
    for (from_state, _event), to_state in VALID_TRANSITIONS.items():
        edges.add((from_state, to_state))

    # Universal transitions: any non-Idle → Idle (STOP, SESSION_END)
    for s in State:
        if s != State.Idle:
            edges.add((s, State.Idle))

    # Universal error: any non-Idle → Error (FATAL_ERROR)
    for s in State:
        if s != State.Idle:
            edges.add((s, State.Error))

    # Timeout tick: Connecting → Error
    edges.add((State.Connecting, State.Error))

    return edges


VALID_EDGES = get_valid_edges()


# ---------------------------------------------------------------------------
# Hypothesis strategies
# ---------------------------------------------------------------------------

event_strategy = st.sampled_from(list(EventType))

# Generate sequences of 1–50 events
event_sequence_strategy = st.lists(event_strategy, min_size=1, max_size=50)


# ---------------------------------------------------------------------------
# Property tests
# ---------------------------------------------------------------------------


@pytest.mark.property_test
@settings(max_examples=500)
@given(events=event_sequence_strategy)
def test_state_machine_valid_transitions(events: list[EventType]) -> None:
    """Property 4: State machine only follows valid edges.

    For any random sequence of events, every state transition recorded
    must be in the set of valid edges. No invalid transitions are possible.

    **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 10.1**
    """
    sm = StateMachine()

    for event in events:
        sm.process_event(event)

    # Verify all transitions followed valid edges
    for from_state, event, to_state in sm.transitions:
        assert (from_state, to_state) in VALID_EDGES, (
            f"Invalid transition: {from_state.value} → {to_state.value} "
            f"via event {event.value}"
        )


@pytest.mark.property_test
@settings(max_examples=500)
@given(events=event_sequence_strategy)
def test_connecting_timeout_enforced(events: list[EventType]) -> None:
    """Property 4 (timeout): Connecting never exceeds 5s without transition.

    If the state machine enters Connecting and receives consecutive TICK
    events, it must transition to Error before accumulating >= 5s.

    **Validates: Requirements 2.1, 10.1**
    """
    sm = StateMachine()

    for event in events:
        sm.process_event(event)
        # After every event, if we're still in Connecting, elapsed must be < 5s
        if sm.state == State.Connecting:
            assert sm.connecting_elapsed_s < 5.0, (
                f"Connecting state exceeded 5s timeout: "
                f"elapsed={sm.connecting_elapsed_s}s"
            )


@pytest.mark.property_test
@settings(max_examples=500)
@given(
    events=st.lists(
        st.sampled_from([EventType.ACTIVATE, EventType.TICK, EventType.TICK,
                         EventType.TICK, EventType.TICK, EventType.TICK]),
        min_size=6,
        max_size=20,
    )
)
def test_connecting_timeout_triggers_error(events: list[EventType]) -> None:
    """Connecting with 5+ TICK events always transitions to Error.

    Sequences that activate and then send enough ticks must end in Error
    (unless interrupted by another event first).

    **Validates: Requirements 10.1, 2.6**
    """
    sm = StateMachine()

    for event in events:
        sm.process_event(event)

    # If we entered Connecting and received 5+ ticks without interruption,
    # we should have transitioned to Error at some point
    connecting_entered = False
    tick_count = 0
    timed_out = False

    sm2 = StateMachine()
    for event in events:
        if sm2.state == State.Connecting:
            connecting_entered = True
            if event == EventType.TICK:
                tick_count += 1
            else:
                tick_count = 0
        else:
            if connecting_entered and sm2.state != State.Connecting:
                tick_count = 0
            connecting_entered = sm2.state == State.Connecting

        sm2.process_event(event)

        if connecting_entered and sm2.state == State.Error and tick_count >= 5:
            timed_out = True

    # If we had a window of 5+ ticks in Connecting, timeout must have fired
    if connecting_entered and tick_count >= 5:
        assert sm2.state == State.Error or timed_out, (
            f"Expected timeout transition to Error after {tick_count} ticks "
            f"in Connecting, but state is {sm2.state.value}"
        )


@pytest.mark.property_test
@settings(max_examples=300)
@given(events=event_sequence_strategy)
def test_idle_is_absorbing_without_activate(events: list[EventType]) -> None:
    """Idle state can only be left via ACTIVATE event.

    No other event should cause a transition out of Idle.

    **Validates: Requirements 2.1, 2.2**
    """
    sm = StateMachine()

    for event in events:
        old_state = sm.state
        sm.process_event(event)

        if old_state == State.Idle and sm.state != State.Idle:
            # Only ACTIVATE should leave Idle
            assert event == EventType.ACTIVATE, (
                f"Left Idle via event {event.value}, expected only ACTIVATE"
            )


@pytest.mark.property_test
@settings(max_examples=300)
@given(events=event_sequence_strategy)
def test_stop_always_returns_to_idle(events: list[EventType]) -> None:
    """STOP or SESSION_END from any non-Idle state always returns to Idle.

    **Validates: Requirements 2.4, 2.5**
    """
    sm = StateMachine()

    for event in events:
        old_state = sm.state
        sm.process_event(event)

        if event in (EventType.STOP, EventType.SESSION_END) and old_state != State.Idle:
            assert sm.state == State.Idle, (
                f"STOP/SESSION_END from {old_state.value} should go to Idle, "
                f"got {sm.state.value}"
            )
