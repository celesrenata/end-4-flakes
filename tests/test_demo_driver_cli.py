"""
Property-based tests for CLI argument parsing logic.

Feature: desktop-demo-driver, Property 9: CLI Argument Parsing

Tests validate the pure algorithmic logic of command-line argument parsing
as modeled from demo-driver.sh. Python functions mirror the bash case statement
in configs/quickshell/ii/scripts/demo-driver.sh.

**Validates: Requirements 10.3**
"""

from hypothesis import given, settings, HealthCheck, assume
from hypothesis import strategies as st


# ─── Pure Python model mirroring demo-driver.sh case statement ───

VALID_COMMANDS = {"start", "stop", "pause", "resume", "list", "speed"}


def parse_cli_args(args: list[str]) -> dict:
    """Mirror the case statement in demo-driver.sh.

    Returns: {"command": str, "args": list[str], "exit_code": int}
    """
    if not args:
        # Default: start
        return {"command": "start", "args": [], "exit_code": 0}

    cmd = args[0]

    if cmd not in VALID_COMMANDS:
        return {"command": "usage", "args": [], "exit_code": 1}

    if cmd == "start":
        scene = args[1] if len(args) > 1 else ""
        return {"command": "start", "args": [scene] if scene else [], "exit_code": 0}
    elif cmd == "speed":
        multiplier = args[1] if len(args) > 1 else "1.0"
        return {"command": "speed", "args": [multiplier], "exit_code": 0}
    else:
        return {"command": cmd, "args": [], "exit_code": 0}


# ─── Hypothesis strategies ───

# Valid commands sampled from the known set
valid_command_strategy = st.sampled_from(["start", "stop", "pause", "resume", "list", "speed"])

# Invalid commands: random strings guaranteed not in valid set
invalid_command_strategy = st.text(
    alphabet=st.characters(whitelist_categories=("L", "N", "P")),
    min_size=1,
    max_size=20,
).filter(lambda s: s not in VALID_COMMANDS)

# Scene names: kebab-case strings (lowercase letters and hyphens)
scene_name_strategy = st.from_regex(r"[a-z][a-z0-9\-]{0,30}", fullmatch=True)

# Speed multipliers: string representations of positive floats
speed_multiplier_strategy = st.floats(
    min_value=0.1, max_value=10.0, allow_nan=False, allow_infinity=False
).map(lambda f: f"{f:.2f}")


# ─── Property 9a: Valid commands always produce exit_code 0 ───


@given(cmd=valid_command_strategy)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_valid_commands_exit_zero(cmd):
    """
    Property 9a: Valid commands (start, stop, pause, resume, list, speed)
    always produce exit_code 0.

    For any valid command, parse_cli_args([cmd, ...]) returns exit_code == 0.

    **Validates: Requirements 10.3**
    """
    result = parse_cli_args([cmd])
    assert result["exit_code"] == 0, (
        f"Valid command '{cmd}' should produce exit_code 0, got {result['exit_code']}"
    )


# ─── Property 9b: Invalid commands always produce exit_code 1 ───


@given(cmd=invalid_command_strategy)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_invalid_commands_exit_one(cmd):
    """
    Property 9b: Invalid commands always produce exit_code 1.

    For any string not in the valid command set, parse_cli_args([cmd])
    returns exit_code == 1 and command == "usage".

    **Validates: Requirements 10.3**
    """
    result = parse_cli_args([cmd])
    assert result["exit_code"] == 1, (
        f"Invalid command '{cmd}' should produce exit_code 1, got {result['exit_code']}"
    )
    assert result["command"] == "usage", (
        f"Invalid command '{cmd}' should produce command 'usage', got '{result['command']}'"
    )


# ─── Property 9c: start with a scene name passes it as an arg ───


@given(scene=scene_name_strategy)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_start_with_scene_passes_scene(scene):
    """
    Property 9c: `start` with a scene name passes the scene name as an arg.

    parse_cli_args(["start", scene]) returns args == [scene] for any
    non-empty kebab-case scene name.

    **Validates: Requirements 10.3**
    """
    assume(len(scene) > 0)
    result = parse_cli_args(["start", scene])
    assert result["command"] == "start"
    assert result["args"] == [scene], (
        f"start with scene '{scene}' should pass ['{scene}'], got {result['args']}"
    )
    assert result["exit_code"] == 0


# ─── Property 9d: start without args defaults to no scene argument ───


def test_start_without_scene_no_args():
    """
    Property 9d: `start` without args defaults to no scene argument.

    parse_cli_args(["start"]) returns args == [].

    **Validates: Requirements 10.3**
    """
    result = parse_cli_args(["start"])
    assert result["command"] == "start"
    assert result["args"] == [], (
        f"start without scene should have empty args, got {result['args']}"
    )
    assert result["exit_code"] == 0


# ─── Property 9e: speed without a multiplier defaults to "1.0" ───


def test_speed_without_multiplier_defaults():
    """
    Property 9e: `speed` without a multiplier defaults to "1.0".

    parse_cli_args(["speed"]) returns args == ["1.0"].

    **Validates: Requirements 10.3**
    """
    result = parse_cli_args(["speed"])
    assert result["command"] == "speed"
    assert result["args"] == ["1.0"], (
        f"speed without multiplier should default to ['1.0'], got {result['args']}"
    )
    assert result["exit_code"] == 0


# ─── Property 9f: speed with a multiplier passes it through ───


@given(multiplier=speed_multiplier_strategy)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_speed_with_multiplier_passes_through(multiplier):
    """
    Property 9f: `speed` with a multiplier passes it through.

    parse_cli_args(["speed", multiplier]) returns args == [multiplier]
    for any string representation of a float.

    **Validates: Requirements 10.3**
    """
    result = parse_cli_args(["speed", multiplier])
    assert result["command"] == "speed"
    assert result["args"] == [multiplier], (
        f"speed with multiplier '{multiplier}' should pass ['{multiplier}'], "
        f"got {result['args']}"
    )
    assert result["exit_code"] == 0


# ─── Property 9g: Empty args list defaults to "start" command ───


def test_empty_args_defaults_to_start():
    """
    Property 9g: Empty args list defaults to "start" command.

    parse_cli_args([]) returns command == "start" with no args and exit_code 0.

    **Validates: Requirements 10.3**
    """
    result = parse_cli_args([])
    assert result["command"] == "start", (
        f"Empty args should default to 'start', got '{result['command']}'"
    )
    assert result["args"] == []
    assert result["exit_code"] == 0


# ─── Additional property: simple commands ignore extra args ───


@given(
    cmd=st.sampled_from(["stop", "pause", "resume", "list"]),
    extra=st.lists(st.text(min_size=1, max_size=10), min_size=0, max_size=3),
)
@settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
def test_simple_commands_ignore_extra_args(cmd, extra):
    """
    Property 9h: Simple commands (stop, pause, resume, list) always return
    empty args regardless of extra arguments passed.

    parse_cli_args([cmd, *extra]) returns command == cmd, args == [],
    and exit_code == 0.

    **Validates: Requirements 10.3**
    """
    result = parse_cli_args([cmd] + extra)
    assert result["command"] == cmd
    assert result["args"] == [], (
        f"Command '{cmd}' should ignore extra args, got {result['args']}"
    )
    assert result["exit_code"] == 0
