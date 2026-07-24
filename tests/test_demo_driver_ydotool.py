"""
Property-based tests for Ydotool command construction.

Feature: desktop-demo-driver, Properties 1-3: Ydotool Command Construction

Tests validate the pure algorithmic logic of Ydotool command construction
without executing any commands. Python functions mirror the QML implementation
in configs/quickshell/ii/services/Ydotool.qml.

**Validates: Requirements 1.1, 1.2, 1.5, 1.6**
"""

import re
from hypothesis import given, settings, HealthCheck
from hypothesis import strategies as st


# ─── Pure Python functions mirroring Ydotool.qml logic ───


BUTTON_CODES = {0: 0xC0, 1: 0xC1, 2: 0xC2}


def build_move_mouse(x: int, y: int) -> list:
    """Mirror Ydotool.moveMouse(x, y) command construction."""
    return ["ydotool", "mousemove", "--absolute", "-x", str(x), "-y", str(y)]


def build_move_mouse_relative(dx: int, dy: int) -> list:
    """Mirror Ydotool.moveMouseRelative(dx, dy) command construction."""
    return ["ydotool", "mousemove", "-x", str(dx), "-y", str(dy)]


def build_click(button: int) -> list:
    """Mirror Ydotool.click(button) command construction."""
    code = BUTTON_CODES.get(button, 0xC0)
    return ["ydotool", "click", "0x" + format(code, "X")]


def build_double_click(button: int) -> list:
    """Mirror Ydotool.doubleClick(button) command construction."""
    code = BUTTON_CODES.get(button, 0xC0)
    return ["ydotool", "click", "--repeat", "2", "--next-delay", "50",
            "0x" + format(code, "X")]


def build_scroll(direction: str, amount: int) -> list:
    """Mirror Ydotool.scroll(direction, amount) command construction."""
    dx, dy = 0, 0
    if direction == "up":
        dy = -amount
    elif direction == "down":
        dy = amount
    elif direction == "left":
        dx = -amount
    elif direction == "right":
        dx = amount
    return ["ydotool", "mousemove", "--wheel", "-x", str(dx), "-y", str(dy)]


def build_drag(start_x: int, start_y: int, end_x: int, end_y: int,
               button: int) -> str:
    """Mirror Ydotool.drag(...) bash command string construction."""
    code = BUTTON_CODES.get(button, 0xC0)
    hex_code = "0x" + format(code, "X")
    return (
        f"ydotool mousemove --absolute -x {start_x} -y {start_y}"
        f" && sleep 0.05"
        f" && ydotool mousedown {hex_code}"
        f" && sleep 0.05"
        f" && ydotool mousemove --absolute -x {end_x} -y {end_y}"
        f" && sleep 0.05"
        f" && ydotool mouseup {hex_code}"
    )


def build_key_combo(keycodes: list) -> list:
    """Mirror Ydotool.keyCombo(keycodes) command construction."""
    args = ["ydotool", "key", "--key-delay", "20"]
    for kc in keycodes:
        args.append(f"{kc}:1")
    for kc in reversed(keycodes):
        args.append(f"{kc}:0")
    return args


# ─── Hypothesis strategies ───

# Valid absolute coordinates (resolution up to 8K)
coord_x = st.integers(min_value=0, max_value=7680)
coord_y = st.integers(min_value=0, max_value=4320)

# Relative movement can be negative
relative_offset = st.integers(min_value=-7680, max_value=7680)

# Valid button indices
button_strategy = st.integers(min_value=0, max_value=2)

# Scroll direction
scroll_direction = st.sampled_from(["up", "down", "left", "right"])
scroll_amount = st.integers(min_value=1, max_value=120)

# Keycodes (Linux input event codes, 1-248)
keycode = st.integers(min_value=1, max_value=248)
keycode_list = st.lists(keycode, min_size=1, max_size=8)


# ─── Property 1: Mouse/Scroll Command Construction ───


@given(x=coord_x, y=coord_y)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_move_mouse_absolute_command(x, y):
    """
    Property 1a: moveMouse produces correct absolute mousemove args.

    For arbitrary valid coordinates (x: 0-7680, y: 0-4320):
    moveMouse(x, y) produces ["ydotool", "mousemove", "--absolute", "-x", str(x), "-y", str(y)]

    **Validates: Requirements 1.1**
    """
    args = build_move_mouse(x, y)
    assert args[0] == "ydotool"
    assert args[1] == "mousemove"
    assert args[2] == "--absolute"
    assert args[3] == "-x"
    assert args[4] == str(x)
    assert args[5] == "-y"
    assert args[6] == str(y)
    assert len(args) == 7


@given(dx=relative_offset, dy=relative_offset)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_move_mouse_relative_command(dx, dy):
    """
    Property 1b: moveMouseRelative produces correct relative mousemove args.

    For arbitrary relative offsets:
    moveMouseRelative(dx, dy) produces ["ydotool", "mousemove", "-x", str(dx), "-y", str(dy)]

    **Validates: Requirements 1.2**
    """
    args = build_move_mouse_relative(dx, dy)
    assert args == ["ydotool", "mousemove", "-x", str(dx), "-y", str(dy)]


@given(button=button_strategy)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_click_command(button):
    """
    Property 1c: click produces correct button code in hex format.

    click(button) produces ["ydotool", "click", "0x" + hex_code]
    where button 0→0xC0, 1→0xC1, 2→0xC2

    **Validates: Requirements 1.2**
    """
    args = build_click(button)
    expected_code = BUTTON_CODES[button]
    assert args == ["ydotool", "click", "0x" + format(expected_code, "X")]
    # Verify the hex code is correct for each button
    if button == 0:
        assert args[2] == "0xC0"
    elif button == 1:
        assert args[2] == "0xC1"
    elif button == 2:
        assert args[2] == "0xC2"


@given(button=button_strategy)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_double_click_command(button):
    """
    Property 1d: doubleClick produces correct repeat args with button code.

    doubleClick(button) produces ["ydotool", "click", "--repeat", "2",
                                   "--next-delay", "50", "0x" + hex_code]

    **Validates: Requirements 1.2**
    """
    args = build_double_click(button)
    expected_code = BUTTON_CODES[button]
    assert args == ["ydotool", "click", "--repeat", "2", "--next-delay", "50",
                    "0x" + format(expected_code, "X")]
    assert args[2] == "--repeat"
    assert args[3] == "2"
    assert args[4] == "--next-delay"
    assert args[5] == "50"


@given(direction=scroll_direction, amount=scroll_amount)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_scroll_command(direction, amount):
    """
    Property 1e: scroll produces correct wheel movement args.

    scroll(direction, amount) produces correct
    ["ydotool", "mousemove", "--wheel", "-x", str(dx), "-y", str(dy)]
    based on direction mapping: up→(0,-amount), down→(0,amount),
    left→(-amount,0), right→(amount,0)

    **Validates: Requirements 1.5**
    """
    args = build_scroll(direction, amount)
    assert args[0:3] == ["ydotool", "mousemove", "--wheel"]
    assert args[3] == "-x"
    assert args[5] == "-y"

    dx_val = int(args[4])
    dy_val = int(args[6])

    if direction == "up":
        assert dx_val == 0
        assert dy_val == -amount
    elif direction == "down":
        assert dx_val == 0
        assert dy_val == amount
    elif direction == "left":
        assert dx_val == -amount
        assert dy_val == 0
    elif direction == "right":
        assert dx_val == amount
        assert dy_val == 0


# ─── Property 2: Drag Sequence Ordering ───


@given(
    start_x=coord_x, start_y=coord_y,
    end_x=coord_x, end_y=coord_y,
    button=button_strategy,
)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_drag_sequence_ordering(start_x, start_y, end_x, end_y, button):
    """
    Property 2: Drag Sequence Ordering.

    For arbitrary start/end coordinates and buttons:
    - The bash command string must contain steps in order:
      mousemove to start, mousedown, mousemove to end, mouseup
    - The button code must be consistent between mousedown and mouseup
    - All coordinate values must appear correctly

    **Validates: Requirements 1.6**
    """
    cmd = build_drag(start_x, start_y, end_x, end_y, button)

    # Verify ordering: mousemove(start) before mousedown before mousemove(end) before mouseup
    idx_move_start = cmd.index(f"ydotool mousemove --absolute -x {start_x} -y {start_y}")
    idx_mousedown = cmd.index("ydotool mousedown")
    idx_move_end = cmd.index(
        f"ydotool mousemove --absolute -x {end_x} -y {end_y}",
        idx_mousedown  # search after mousedown to avoid matching start move
    )
    idx_mouseup = cmd.index("ydotool mouseup")

    assert idx_move_start < idx_mousedown, "mousemove to start must come before mousedown"
    assert idx_mousedown < idx_move_end, "mousedown must come before mousemove to end"
    assert idx_move_end < idx_mouseup, "mousemove to end must come before mouseup"

    # Verify button code is consistent between mousedown and mouseup
    expected_code = BUTTON_CODES.get(button, 0xC0)
    hex_code = "0x" + format(expected_code, "X")
    assert f"ydotool mousedown {hex_code}" in cmd
    assert f"ydotool mouseup {hex_code}" in cmd

    # Verify all coordinate values appear
    assert f"-x {start_x}" in cmd
    assert f"-y {start_y}" in cmd
    assert f"-x {end_x}" in cmd
    assert f"-y {end_y}" in cmd

    # Verify sleep delays between steps
    assert cmd.count("sleep 0.05") == 3


# ─── Property 3: keyCombo Sequence Ordering ───


@given(keycodes=keycode_list)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_key_combo_sequence_ordering(keycodes):
    """
    Property 3: keyCombo Sequence Ordering.

    For arbitrary keycodes list (1-8 keycodes, values 1-248):
    - The args array starts with ["ydotool", "key", "--key-delay", "20"]
    - Then all keycodes appear as "code:1" (press) in order
    - Then all keycodes appear as "code:0" (release) in reverse order

    **Validates: Requirements 1.2**
    """
    args = build_key_combo(keycodes)

    # Verify prefix
    assert args[0:4] == ["ydotool", "key", "--key-delay", "20"]

    n = len(keycodes)
    # Total length: 4 prefix + n presses + n releases
    assert len(args) == 4 + 2 * n

    # Verify press sequence (in order)
    press_args = args[4:4 + n]
    for i, kc in enumerate(keycodes):
        assert press_args[i] == f"{kc}:1", (
            f"Expected press {kc}:1 at position {4+i}, got {press_args[i]}"
        )

    # Verify release sequence (in reverse order)
    release_args = args[4 + n:]
    for i, kc in enumerate(reversed(keycodes)):
        assert release_args[i] == f"{kc}:0", (
            f"Expected release {kc}:0 at position {4+n+i}, got {release_args[i]}"
        )

    # Verify that every keycode that is pressed is also released
    pressed = {arg.split(":")[0] for arg in press_args}
    released = {arg.split(":")[0] for arg in release_args}
    assert pressed == released, "Every pressed key must be released"
