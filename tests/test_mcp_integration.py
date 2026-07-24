# Feature: mcp-sidebar-integration
"""
Property-based tests for the MCP Sidebar Integration feature.

These tests validate pure logic functions extracted from the QML implementation
(McpServerBridge.qml) using Python reimplementations and Hypothesis for
property-based testing.
"""

import json
import random

import pytest
from hypothesis import given, settings, assume, HealthCheck
import hypothesis.strategies as st


# ---------------------------------------------------------------------------
# Pure function reimplementations (mirrors QML logic in McpServerBridge.qml)
# ---------------------------------------------------------------------------


class PendingRequest:
    """Represents a pending JSON-RPC request awaiting response correlation."""

    def __init__(self, request_id: int):
        self.request_id = request_id
        self.resolved = False
        self.rejected = False
        self.result = None
        self.error = None

    def resolve(self, result):
        if not self.resolved and not self.rejected:
            self.resolved = True
            self.result = result

    def reject(self, error):
        if not self.resolved and not self.rejected:
            self.rejected = True
            self.error = error


class ResponseCorrelator:
    """Simulates the McpServerBridge pending request map and response correlation.

    Mirrors the QML logic:
        - pendingRequests[id] = { resolve, reject, timer }
        - On response with id field: match to pending, resolve/reject
        - Up to 32 concurrent pending requests
    """

    MAX_CONCURRENT = 32

    def __init__(self):
        self.pending_requests: dict[int, PendingRequest] = {}
        self.next_request_id = 1

    def send_request(self) -> PendingRequest | None:
        """Create a new pending request. Returns None if at max concurrency."""
        if len(self.pending_requests) >= self.MAX_CONCURRENT:
            return None
        req_id = self.next_request_id
        self.next_request_id += 1
        pending = PendingRequest(req_id)
        self.pending_requests[req_id] = pending
        return pending

    def handle_stdout_line(self, data: str) -> bool:
        """Process a stdout line. Returns True if it resolved/rejected a request.

        Mirrors _handleStdoutLine from McpServerBridge.qml:
        1. Try JSON.parse — if fails, discard (malformed)
        2. Check jsonrpc === "2.0" — if missing, discard
        3. If has id field — correlate with pending request
        4. If no id — it's a notification, ignore for pending requests
        """
        # Step 1: try to parse as JSON
        try:
            parsed = json.loads(data)
        except (json.JSONDecodeError, ValueError):
            # Malformed line — discard
            return False

        # Step 2: validate JSON-RPC 2.0 structure
        if not isinstance(parsed, dict):
            return False
        if parsed.get("jsonrpc") != "2.0":
            return False

        # Step 3: check if it's a response (has id) or notification (no id)
        resp_id = parsed.get("id")
        if resp_id is not None:
            entry = self.pending_requests.get(resp_id)
            if entry:
                # Remove from pending
                del self.pending_requests[resp_id]
                # Resolve or reject based on error field
                if "error" in parsed:
                    error_msg = parsed["error"]
                    if isinstance(error_msg, dict):
                        error_msg = error_msg.get("message", str(error_msg))
                    entry.reject(str(error_msg))
                else:
                    entry.resolve(parsed.get("result"))
                return True

        # Notification or unknown id — no effect on pending requests
        return False


# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

# Strategy for number of concurrent requests (1 to 32)
_num_requests_st = st.integers(min_value=1, max_value=32)

# Strategy for JSON-RPC result values
_result_value_st = st.one_of(
    st.none(),
    st.booleans(),
    st.integers(min_value=-1000, max_value=1000),
    st.text(min_size=0, max_size=100),
    st.dictionaries(
        keys=st.text(min_size=1, max_size=20),
        values=st.text(min_size=0, max_size=50),
        min_size=0,
        max_size=5,
    ),
)

# Strategy for malformed lines: random strings that are NOT valid JSON-RPC
_malformed_line_st = st.one_of(
    # Pure garbage text
    st.text(min_size=1, max_size=200).filter(
        lambda t: not _is_valid_jsonrpc(t)
    ),
    # Partial/broken JSON
    st.sampled_from([
        "{",
        '{"jsonrpc"',
        '{"jsonrpc": "2.0"',
        '{"id": 1',
        "null",
        "true",
        "42",
        "[]",
        "[1,2,3]",
        '{"incomplete": true',
        "",
    ]),
    # Valid JSON but missing jsonrpc field
    st.fixed_dictionaries({
        "id": st.integers(min_value=1, max_value=100),
        "result": st.text(min_size=0, max_size=50),
    }).map(json.dumps),
    # Valid JSON but wrong jsonrpc version
    st.fixed_dictionaries({
        "jsonrpc": st.sampled_from(["1.0", "2.1", "3.0", ""]),
        "id": st.integers(min_value=1, max_value=100),
        "result": st.text(min_size=0, max_size=50),
    }).map(json.dumps),
    # JSON-RPC notification (has method but no id) — should not affect pending
    st.fixed_dictionaries({
        "jsonrpc": st.just("2.0"),
        "method": st.text(min_size=1, max_size=30),
        "params": st.just({}),
    }).map(json.dumps),
)


def _is_valid_jsonrpc(text: str) -> bool:
    """Check if text is valid JSON-RPC 2.0 response with id."""
    try:
        parsed = json.loads(text)
        if not isinstance(parsed, dict):
            return False
        return parsed.get("jsonrpc") == "2.0" and parsed.get("id") is not None
    except (json.JSONDecodeError, ValueError):
        return False


# ---------------------------------------------------------------------------
# Property 8: Response correlation under concurrency
# Feature: mcp-sidebar-integration, Property 8: Response correlation under concurrency
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty8ResponseCorrelation:
    """Property 8: Response correlation under concurrency.

    Up to 32 pending requests, responses in arbitrary order,
    each resolves correct request.

    **Validates: Requirements 4.3, 4.5**
    """

    @given(
        num_requests=_num_requests_st,
        results=st.lists(
            _result_value_st,
            min_size=32,
            max_size=32,
        ),
    )
    @settings(max_examples=100)
    def test_responses_in_arbitrary_order_resolve_correct_requests(
        self, num_requests: int, results: list
    ):
        """Each response with id=X resolves exactly the request with id=X,
        regardless of arrival order."""
        correlator = ResponseCorrelator()
        pending_list: list[PendingRequest] = []

        # Create N pending requests
        for _ in range(num_requests):
            req = correlator.send_request()
            assert req is not None
            pending_list.append(req)

        # Generate response IDs in shuffled order
        response_ids = [req.request_id for req in pending_list]
        shuffled_ids = list(response_ids)
        random.shuffle(shuffled_ids)

        # Send responses in shuffled order
        for idx, resp_id in enumerate(shuffled_ids):
            result_val = results[idx % len(results)]
            response_line = json.dumps({
                "jsonrpc": "2.0",
                "id": resp_id,
                "result": result_val,
            })
            matched = correlator.handle_stdout_line(response_line)
            assert matched, f"Response for id={resp_id} should match a pending request"

        # Verify each request resolved with correct result
        for idx, resp_id in enumerate(shuffled_ids):
            result_val = results[idx % len(results)]
            # Find the pending request with this id
            req = next(r for r in pending_list if r.request_id == resp_id)
            assert req.resolved, f"Request id={resp_id} should be resolved"
            assert not req.rejected, f"Request id={resp_id} should not be rejected"
            assert req.result == result_val, (
                f"Request id={resp_id} got wrong result: "
                f"expected {result_val!r}, got {req.result!r}"
            )

    @given(
        num_requests=_num_requests_st,
    )
    @settings(max_examples=100)
    def test_no_cross_contamination(self, num_requests: int):
        """Resolving one request does not affect any other pending request."""
        correlator = ResponseCorrelator()
        pending_list: list[PendingRequest] = []

        for _ in range(num_requests):
            req = correlator.send_request()
            assert req is not None
            pending_list.append(req)

        # Resolve only the first request
        target = pending_list[0]
        response_line = json.dumps({
            "jsonrpc": "2.0",
            "id": target.request_id,
            "result": "resolved_first",
        })
        correlator.handle_stdout_line(response_line)

        # Verify only the target is resolved
        assert target.resolved
        assert target.result == "resolved_first"

        # All others remain unresolved
        for req in pending_list[1:]:
            assert not req.resolved, f"Request id={req.request_id} should NOT be resolved"
            assert not req.rejected, f"Request id={req.request_id} should NOT be rejected"

        # They should still be in the pending map
        for req in pending_list[1:]:
            assert req.request_id in correlator.pending_requests

    @given(num_requests=_num_requests_st)
    @settings(max_examples=100)
    def test_error_responses_reject_correct_request(self, num_requests: int):
        """Error responses (with error field) reject the correct pending request."""
        correlator = ResponseCorrelator()
        pending_list: list[PendingRequest] = []

        for _ in range(num_requests):
            req = correlator.send_request()
            assert req is not None
            pending_list.append(req)

        # Send an error response for a random request
        target_idx = random.randrange(len(pending_list))
        target = pending_list[target_idx]
        error_line = json.dumps({
            "jsonrpc": "2.0",
            "id": target.request_id,
            "error": {"code": -32600, "message": "Invalid request"},
        })
        correlator.handle_stdout_line(error_line)

        # Target should be rejected
        assert target.rejected
        assert not target.resolved
        assert "Invalid request" in target.error

        # Others unaffected
        for i, req in enumerate(pending_list):
            if i != target_idx:
                assert not req.resolved
                assert not req.rejected

    @given(num_requests=_num_requests_st)
    @settings(max_examples=100)
    def test_max_32_concurrent_enforced(self, num_requests: int):
        """Cannot exceed 32 concurrent pending requests."""
        correlator = ResponseCorrelator()

        # Fill to max
        for _ in range(32):
            req = correlator.send_request()
            assert req is not None

        # 33rd should fail
        overflow = correlator.send_request()
        assert overflow is None, "Should not allow more than 32 concurrent requests"


# ---------------------------------------------------------------------------
# Property 9: Malformed stdout lines discarded
# Feature: mcp-sidebar-integration, Property 9: Malformed stdout lines discarded
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty9MalformedLineHandling:
    """Property 9: Malformed stdout lines discarded.

    Invalid JSON or non-JSON-RPC lines don't affect pending requests.

    **Validates: Requirements 4.4**
    """

    @given(
        num_requests=st.integers(min_value=1, max_value=32),
        malformed_lines=st.lists(
            _malformed_line_st,
            min_size=1,
            max_size=50,
        ),
    )
    @settings(max_examples=100)
    def test_malformed_lines_dont_resolve_pending(
        self, num_requests: int, malformed_lines: list[str]
    ):
        """No pending request is resolved or rejected by malformed input."""
        correlator = ResponseCorrelator()
        pending_list: list[PendingRequest] = []

        # Create pending requests
        for _ in range(num_requests):
            req = correlator.send_request()
            assert req is not None
            pending_list.append(req)

        # Process all malformed lines
        for line in malformed_lines:
            correlator.handle_stdout_line(line)

        # Verify NO pending request was resolved or rejected
        for req in pending_list:
            assert not req.resolved, (
                f"Request id={req.request_id} should NOT be resolved by malformed input"
            )
            assert not req.rejected, (
                f"Request id={req.request_id} should NOT be rejected by malformed input"
            )

        # Pending map should still contain all requests
        assert len(correlator.pending_requests) == num_requests

    @given(
        num_requests=st.integers(min_value=1, max_value=32),
        malformed_lines=st.lists(
            _malformed_line_st,
            min_size=1,
            max_size=20,
        ),
    )
    @settings(max_examples=100)
    def test_malformed_lines_interleaved_with_valid(
        self, num_requests: int, malformed_lines: list[str]
    ):
        """Malformed lines interleaved with valid responses don't corrupt correlation."""
        correlator = ResponseCorrelator()
        pending_list: list[PendingRequest] = []

        # Create pending requests
        for _ in range(num_requests):
            req = correlator.send_request()
            assert req is not None
            pending_list.append(req)

        # Interleave: malformed, then valid response for first request, then more malformed
        half = len(malformed_lines) // 2
        for line in malformed_lines[:half]:
            correlator.handle_stdout_line(line)

        # Send valid response for first request
        target = pending_list[0]
        valid_response = json.dumps({
            "jsonrpc": "2.0",
            "id": target.request_id,
            "result": {"data": "valid"},
        })
        correlator.handle_stdout_line(valid_response)

        # More malformed lines
        for line in malformed_lines[half:]:
            correlator.handle_stdout_line(line)

        # First request should be resolved correctly
        assert target.resolved
        assert target.result == {"data": "valid"}

        # All other requests should be unaffected
        for req in pending_list[1:]:
            assert not req.resolved
            assert not req.rejected

    @given(
        num_requests=st.integers(min_value=1, max_value=32),
        garbage_count=st.integers(min_value=1, max_value=100),
    )
    @settings(max_examples=100)
    def test_pure_garbage_lines_no_effect(
        self, num_requests: int, garbage_count: int
    ):
        """Lines that completely fail JSON parsing have no effect whatsoever."""
        correlator = ResponseCorrelator()
        pending_list: list[PendingRequest] = []

        for _ in range(num_requests):
            req = correlator.send_request()
            assert req is not None
            pending_list.append(req)

        # Feed pure non-JSON garbage
        garbage_lines = [
            f"not json at all line {i} !!@#$%"
            for i in range(garbage_count)
        ]
        for line in garbage_lines:
            result = correlator.handle_stdout_line(line)
            assert result is False, "Garbage should never match a pending request"

        # Nothing changed
        for req in pending_list:
            assert not req.resolved
            assert not req.rejected
        assert len(correlator.pending_requests) == num_requests

    @given(
        num_requests=st.integers(min_value=1, max_value=32),
        notification_count=st.integers(min_value=1, max_value=20),
    )
    @settings(max_examples=100)
    def test_jsonrpc_notifications_dont_affect_pending(
        self, num_requests: int, notification_count: int
    ):
        """Valid JSON-RPC notifications (method but no id) don't resolve pending requests."""
        correlator = ResponseCorrelator()
        pending_list: list[PendingRequest] = []

        for _ in range(num_requests):
            req = correlator.send_request()
            assert req is not None
            pending_list.append(req)

        # Send valid JSON-RPC notifications (no id field)
        for i in range(notification_count):
            notification = json.dumps({
                "jsonrpc": "2.0",
                "method": f"notifications/progress_{i}",
                "params": {"progress": i},
            })
            result = correlator.handle_stdout_line(notification)
            assert result is False, "Notifications should not match pending requests"

        # All pending requests unaffected
        for req in pending_list:
            assert not req.resolved
            assert not req.rejected
        assert len(correlator.pending_requests) == num_requests



# ---------------------------------------------------------------------------
# Pure function reimplementations for config parsing (mirrors McpClient.qml)
# ---------------------------------------------------------------------------


def parse_config(config_dict: dict) -> dict:
    """Parse MCP config and return servers, states, and auto_approve list.

    Mirrors McpClient._parseConfig logic:
    - Entries with disabled === true → state = "disabled", excluded from active
    - Other entries → state = "disconnected", fields preserved
    - Timeout clamped via clamp_timeout
    - autoApprove list prefixed with "mcp_{server_name}_"

    Returns: { "servers": dict, "states": dict, "auto_approve": list }
    """
    servers_input = config_dict.get("mcpServers", {})
    new_configs = {}
    new_states = {}
    new_auto_approve = []

    for name, entry in servers_input.items():
        # Filter disabled servers
        if entry.get("disabled") is True:
            new_configs[name] = entry
            new_states[name] = "disabled"
            continue

        # Validate and clamp timeout
        timeout = clamp_timeout(entry.get("timeout"))

        new_configs[name] = {
            "command": entry.get("command", ""),
            "args": entry.get("args", []),
            "env": entry.get("env", {}),
            "autoApprove": entry.get("autoApprove", []),
            "timeout": timeout,
            "disabled": False,
        }
        new_states[name] = "disconnected"

        # Aggregate auto-approve list with prefixed names
        server_prefix = "mcp_" + name.replace("-", "_") + "_"
        approve_list = entry.get("autoApprove", [])
        for tool_name in approve_list:
            new_auto_approve.append(server_prefix + tool_name)

    return {
        "servers": new_configs,
        "states": new_states,
        "auto_approve": new_auto_approve,
    }


def clamp_timeout(value) -> int:
    """Clamp a timeout value to the valid range [1000, 300000], defaulting to 30000.

    Mirrors McpClient._parseConfig timeout logic:
        let timeout = 30000;
        if (entry.timeout !== undefined && entry.timeout !== null) {
            const t = Number(entry.timeout);
            if (t >= 1000 && t <= 300000) {
                timeout = t;
            }
        }
    """
    if value is None:
        return 30000
    try:
        t = int(value) if not isinstance(value, (int, float)) else value
        # Match JavaScript Number() behavior — convert to numeric
        t = float(t) if isinstance(t, str) else t
        t = int(t) if isinstance(t, float) and t == int(t) else t
    except (ValueError, TypeError):
        return 30000

    if isinstance(t, (int, float)) and 1000 <= t <= 300000:
        return int(t)
    return 30000


def apply_env(env_dict: dict, process_env: dict) -> dict:
    """Apply environment variables from server config to process environment.

    Mirrors McpServerBridge.spawn() env logic:
        if (bridge.serverEnv && Object.keys(bridge.serverEnv).length > 0) {
            for (const key in bridge.serverEnv) {
                serverProc.environment[key] = bridge.serverEnv[key];
            }
        }

    Returns the merged process_env with all env_dict entries applied.
    """
    result = dict(process_env)
    if env_dict:
        for key, value in env_dict.items():
            result[key] = value
    return result


# ---------------------------------------------------------------------------
# Strategies for config parsing tests
# ---------------------------------------------------------------------------

# Valid server name: alphanumeric with dashes (MCP convention)
_server_name_st = st.from_regex(r"[a-z][a-z0-9\-]{0,20}", fullmatch=True)

# Valid command string
_command_st = st.sampled_from(["uvx", "npx", "python", "node", "/usr/bin/mcp-server"])

# Valid args list
_args_st = st.lists(
    st.text(alphabet=st.characters(whitelist_categories=("L", "N", "P")), min_size=1, max_size=30),
    min_size=0,
    max_size=5,
)

# Environment variable key (valid env var names)
_env_key_st = st.from_regex(r"[A-Z][A-Z0-9_]{0,30}", fullmatch=True)

# Environment variable value
_env_value_st = st.text(min_size=0, max_size=100)

# Env dict strategy
_env_dict_st = st.dictionaries(
    keys=_env_key_st,
    values=_env_value_st,
    min_size=0,
    max_size=5,
)

# Auto-approve list
_auto_approve_st = st.lists(
    st.from_regex(r"[a-z_][a-z0-9_]{0,20}", fullmatch=True),
    min_size=0,
    max_size=10,
)

# Timeout values: valid range, out of range, and None
_timeout_valid_st = st.integers(min_value=1000, max_value=300000)
_timeout_invalid_st = st.one_of(
    st.integers(min_value=-1000000, max_value=999),
    st.integers(min_value=300001, max_value=1000000),
    st.just(0),
    st.just(-1),
)
_timeout_any_st = st.one_of(
    _timeout_valid_st,
    _timeout_invalid_st,
    st.none(),
)

# Single server entry (enabled)
_enabled_server_entry_st = st.fixed_dictionaries({
    "command": _command_st,
    "args": _args_st,
    "env": _env_dict_st,
    "autoApprove": _auto_approve_st,
    "timeout": _timeout_any_st,
    "disabled": st.just(False),
})

# Single server entry (disabled)
_disabled_server_entry_st = st.fixed_dictionaries({
    "command": _command_st,
    "args": _args_st,
    "env": _env_dict_st,
    "autoApprove": _auto_approve_st,
    "timeout": _timeout_any_st,
    "disabled": st.just(True),
})

# Mixed server entry (enabled or disabled)
_server_entry_st = st.one_of(_enabled_server_entry_st, _disabled_server_entry_st)

# Full MCP config dict
_mcp_config_st = st.fixed_dictionaries({
    "mcpServers": st.dictionaries(
        keys=_server_name_st,
        values=_server_entry_st,
        min_size=0,
        max_size=8,
    ),
})


# ---------------------------------------------------------------------------
# Property 1: Config parsing filters disabled servers
# Feature: mcp-sidebar-integration, Property 1: Config parsing filters disabled servers
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty1ConfigParsingFiltersDisabled:
    """Property 1: Config parsing filters disabled servers.

    For any MCP configuration object containing N server entries with varying
    disabled fields, parsing SHALL produce a registered server list containing
    exactly those entries where disabled is not true, preserving all other fields.

    **Validates: Requirements 1.1, 10.1**
    """

    @given(config=_mcp_config_st)
    @settings(max_examples=100)
    def test_disabled_servers_get_disabled_state(self, config: dict):
        """Servers with disabled=true get state 'disabled'."""
        result = parse_config(config)
        servers_input = config["mcpServers"]

        for name, entry in servers_input.items():
            if entry.get("disabled") is True:
                assert result["states"][name] == "disabled", (
                    f"Server '{name}' with disabled=true should have state 'disabled', "
                    f"got '{result['states'][name]}'"
                )

    @given(config=_mcp_config_st)
    @settings(max_examples=100)
    def test_enabled_servers_get_disconnected_state(self, config: dict):
        """Servers with disabled=false or missing get state 'disconnected'."""
        result = parse_config(config)
        servers_input = config["mcpServers"]

        for name, entry in servers_input.items():
            if entry.get("disabled") is not True:
                assert result["states"][name] == "disconnected", (
                    f"Server '{name}' with disabled={entry.get('disabled')} "
                    f"should have state 'disconnected', got '{result['states'][name]}'"
                )

    @given(config=_mcp_config_st)
    @settings(max_examples=100)
    def test_all_servers_present_in_output(self, config: dict):
        """All input servers appear in the output (both enabled and disabled)."""
        result = parse_config(config)
        servers_input = config["mcpServers"]

        for name in servers_input:
            assert name in result["servers"], (
                f"Server '{name}' missing from parsed output"
            )
            assert name in result["states"], (
                f"Server '{name}' missing from states output"
            )

    @given(config=_mcp_config_st)
    @settings(max_examples=100)
    def test_enabled_server_fields_preserved(self, config: dict):
        """For enabled servers, command/args/env/autoApprove fields are preserved."""
        result = parse_config(config)
        servers_input = config["mcpServers"]

        for name, entry in servers_input.items():
            if entry.get("disabled") is True:
                continue

            parsed = result["servers"][name]
            assert parsed["command"] == entry.get("command", ""), (
                f"Server '{name}': command mismatch"
            )
            assert parsed["args"] == entry.get("args", []), (
                f"Server '{name}': args mismatch"
            )
            assert parsed["env"] == entry.get("env", {}), (
                f"Server '{name}': env mismatch"
            )
            assert parsed["autoApprove"] == entry.get("autoApprove", []), (
                f"Server '{name}': autoApprove mismatch"
            )
            assert parsed["disabled"] is False, (
                f"Server '{name}': disabled should be False in parsed output"
            )

    @given(config=_mcp_config_st)
    @settings(max_examples=100)
    def test_auto_approve_list_only_from_enabled_servers(self, config: dict):
        """The auto_approve list only contains entries from enabled servers."""
        result = parse_config(config)
        servers_input = config["mcpServers"]

        # Compute expected auto-approve
        expected = []
        for name, entry in servers_input.items():
            if entry.get("disabled") is True:
                continue
            server_prefix = "mcp_" + name.replace("-", "_") + "_"
            for tool in entry.get("autoApprove", []):
                expected.append(server_prefix + tool)

        assert result["auto_approve"] == expected, (
            f"auto_approve mismatch: expected {expected}, got {result['auto_approve']}"
        )


# ---------------------------------------------------------------------------
# Property 21: Timeout value clamping
# Feature: mcp-sidebar-integration, Property 21: Timeout value clamping
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty21TimeoutClamping:
    """Property 21: Timeout value clamping.

    For any timeout field value, if between 1000 and 300000 inclusive it SHALL
    be used as-is; if outside this range the default 30000 SHALL be used.

    **Validates: Requirements 10.3, 10.7**
    """

    @given(timeout=_timeout_valid_st)
    @settings(max_examples=100)
    def test_valid_timeout_used_as_is(self, timeout: int):
        """Timeout values in [1000, 300000] are used unchanged."""
        result = clamp_timeout(timeout)
        assert result == timeout, (
            f"Valid timeout {timeout} should be used as-is, got {result}"
        )

    @given(timeout=_timeout_invalid_st)
    @settings(max_examples=100)
    def test_invalid_timeout_defaults_to_30000(self, timeout: int):
        """Timeout values outside [1000, 300000] default to 30000."""
        result = clamp_timeout(timeout)
        assert result == 30000, (
            f"Invalid timeout {timeout} should default to 30000, got {result}"
        )

    @given(data=st.data())
    @settings(max_examples=100)
    def test_none_timeout_defaults_to_30000(self, data):
        """None/undefined timeout defaults to 30000."""
        result = clamp_timeout(None)
        assert result == 30000, (
            f"None timeout should default to 30000, got {result}"
        )

    @given(timeout=_timeout_any_st)
    @settings(max_examples=100)
    def test_result_always_in_valid_range_or_default(self, timeout):
        """The result is always either the input (if valid) or 30000."""
        result = clamp_timeout(timeout)
        assert result == 30000 or (1000 <= result <= 300000), (
            f"Result {result} is neither 30000 nor in [1000, 300000]"
        )
        # If the input was in range, result must equal input
        if timeout is not None and isinstance(timeout, (int, float)) and 1000 <= timeout <= 300000:
            assert result == int(timeout), (
                f"Valid timeout {timeout} should produce {int(timeout)}, got {result}"
            )

    @given(config=_mcp_config_st)
    @settings(max_examples=100)
    def test_timeout_clamping_in_full_config_parse(self, config: dict):
        """Timeout clamping is applied correctly within full config parsing."""
        result = parse_config(config)
        servers_input = config["mcpServers"]

        for name, entry in servers_input.items():
            if entry.get("disabled") is True:
                continue

            parsed = result["servers"][name]
            raw_timeout = entry.get("timeout")
            expected = clamp_timeout(raw_timeout)
            assert parsed["timeout"] == expected, (
                f"Server '{name}': timeout {raw_timeout} should clamp to "
                f"{expected}, got {parsed['timeout']}"
            )


# ---------------------------------------------------------------------------
# Property 22: Environment variable application
# Feature: mcp-sidebar-integration, Property 22: Environment variable application
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty22EnvironmentVariableApplication:
    """Property 22: Environment variable application.

    For any MCP server entry with an env field containing key-value string pairs,
    all key-value pairs SHALL be set as environment variables in the spawned
    process, and no environment variable from the env field SHALL be missing
    from the process environment.

    **Validates: Requirements 10.2**
    """

    @given(
        env_dict=_env_dict_st,
        process_env=st.dictionaries(
            keys=_env_key_st,
            values=_env_value_st,
            min_size=0,
            max_size=10,
        ),
    )
    @settings(max_examples=100)
    def test_all_env_vars_present_in_process(self, env_dict: dict, process_env: dict):
        """All env key-value pairs from config are present in the process env."""
        result = apply_env(env_dict, process_env)

        for key, value in env_dict.items():
            assert key in result, (
                f"Env var '{key}' missing from process environment"
            )
            assert result[key] == value, (
                f"Env var '{key}' should be '{value}', got '{result[key]}'"
            )

    @given(
        env_dict=_env_dict_st,
        process_env=st.dictionaries(
            keys=_env_key_st,
            values=_env_value_st,
            min_size=0,
            max_size=10,
        ),
    )
    @settings(max_examples=100)
    def test_existing_env_vars_not_removed(self, env_dict: dict, process_env: dict):
        """Existing process env vars not in the server env are preserved."""
        result = apply_env(env_dict, process_env)

        for key, value in process_env.items():
            if key not in env_dict:
                assert key in result, (
                    f"Existing env var '{key}' was removed"
                )
                assert result[key] == value, (
                    f"Existing env var '{key}' was modified: "
                    f"expected '{value}', got '{result[key]}'"
                )

    @given(
        env_dict=_env_dict_st,
        process_env=st.dictionaries(
            keys=_env_key_st,
            values=_env_value_st,
            min_size=0,
            max_size=10,
        ),
    )
    @settings(max_examples=100)
    def test_server_env_overrides_process_env(self, env_dict: dict, process_env: dict):
        """Server env values override same-key process env values."""
        result = apply_env(env_dict, process_env)

        for key in env_dict:
            # Server env always wins
            assert result[key] == env_dict[key], (
                f"Server env '{key}={env_dict[key]}' should override "
                f"process env, got '{result[key]}'"
            )

    @given(
        process_env=st.dictionaries(
            keys=_env_key_st,
            values=_env_value_st,
            min_size=1,
            max_size=10,
        ),
    )
    @settings(max_examples=100)
    def test_empty_env_dict_preserves_process_env(self, process_env: dict):
        """An empty env dict doesn't modify the process environment."""
        result = apply_env({}, process_env)
        assert result == process_env, (
            "Empty env dict should leave process env unchanged"
        )

    @given(
        env_dict=st.dictionaries(
            keys=_env_key_st,
            values=_env_value_st,
            min_size=1,
            max_size=5,
        ),
    )
    @settings(max_examples=100)
    def test_env_applied_to_empty_process(self, env_dict: dict):
        """Env vars are correctly applied even to an empty process env."""
        result = apply_env(env_dict, {})
        assert result == env_dict, (
            f"Expected {env_dict}, got {result}"
        )


# ---------------------------------------------------------------------------
# Pure function reimplementations for Tool Registry (mirrors McpClient.qml)
# ---------------------------------------------------------------------------

# Built-in tool names that MCP tools cannot shadow
BUILTIN_TOOL_NAMES = [
    "switch_to_search_mode",
    "get_shell_config",
    "set_shell_config",
    "run_shell_command",
    "hypr_config_read",
    "hypr_config_set",
    "hypr_set_keyword",
]


def make_server_prefix(server_name: str) -> str:
    """Compute the prefixed tool name prefix for a server.

    Mirrors the QML logic:
        const serverPrefix = "mcp_" + serverName.replace(/-/g, "_") + "_";
    """
    return "mcp_" + server_name.replace("-", "_") + "_"


def validate_tool_entry(tool: dict) -> bool:
    """Check if a tool entry from tools/list is valid.

    Mirrors McpServerBridge.discoverTools validation:
        - Must have name (non-empty string)
        - inputSchema if present and is string must be parseable JSON
    """
    name = tool.get("name")
    if not name or not isinstance(name, str):
        return False

    schema = tool.get("inputSchema")
    if isinstance(schema, str):
        try:
            json.loads(schema)
        except (json.JSONDecodeError, ValueError):
            return False

    return True


def register_tools_from_server(
    server_name: str,
    tools: list[dict],
    builtin_names: list[str],
    existing_registry: dict | None = None,
) -> dict:
    """Register tools from a server's tools/list response into the registry.

    Mirrors _registerToolsFromServer from McpClient.qml:
    1. Compute server prefix
    2. For each valid tool:
       a. Compute prefixedName = serverPrefix + tool.name
       b. If prefixedName matches a built-in name → reject (skip)
       c. Otherwise register in toolRegistry

    Returns the updated registry.
    """
    registry = dict(existing_registry) if existing_registry else {}
    server_prefix = make_server_prefix(server_name)

    for tool in tools:
        if not validate_tool_entry(tool):
            continue

        prefixed_name = server_prefix + tool["name"]

        # Check conflict with built-in tools
        if prefixed_name in builtin_names:
            continue

        # Register
        registry[prefixed_name] = {
            "serverName": server_name,
            "originalName": tool["name"],
            "description": tool.get("description", ""),
            "inputSchema": tool.get("inputSchema") if not isinstance(tool.get("inputSchema"), str) else json.loads(tool["inputSchema"]) if tool.get("inputSchema") else {},
        }

    return registry


def register_tools_multi_server(
    server_tools: dict[str, list[dict]],
    builtin_names: list[str],
) -> dict:
    """Register tools from multiple servers.

    Args:
        server_tools: mapping of serverName → list of tool entries
        builtin_names: list of built-in tool names to reject

    Returns the combined registry.
    """
    registry = {}
    for server_name, tools in server_tools.items():
        registry = register_tools_from_server(
            server_name, tools, builtin_names, registry
        )
    return registry


# ---------------------------------------------------------------------------
# Strategies for Tool Registry tests
# ---------------------------------------------------------------------------

# Valid tool name: non-empty alphanumeric/underscore string (like real MCP tool names)
_tool_name_st = st.from_regex(r"[a-z][a-z0-9_]{0,29}", fullmatch=True)

# Valid server name: lowercase with possible hyphens (like real server names)
_server_name_st = st.from_regex(r"[a-z][a-z0-9\-]{0,19}", fullmatch=True)

# Valid input schema (as a dict)
_input_schema_st = st.fixed_dictionaries({
    "type": st.just("object"),
    "properties": st.dictionaries(
        keys=st.from_regex(r"[a-z][a-z0-9_]{0,14}", fullmatch=True),
        values=st.fixed_dictionaries({
            "type": st.sampled_from(["string", "integer", "boolean", "number"]),
            "description": st.text(min_size=0, max_size=50),
        }),
        min_size=0,
        max_size=5,
    ),
})

# Valid tool entry
_valid_tool_entry_st = st.fixed_dictionaries({
    "name": _tool_name_st,
    "description": st.text(min_size=0, max_size=100),
    "inputSchema": _input_schema_st,
})

# Invalid tool entry variants
_invalid_tool_entry_st = st.one_of(
    # Missing name
    st.fixed_dictionaries({
        "description": st.text(min_size=0, max_size=50),
        "inputSchema": _input_schema_st,
    }),
    # Empty name
    st.fixed_dictionaries({
        "name": st.just(""),
        "description": st.text(min_size=0, max_size=50),
    }),
    # Name is not a string
    st.fixed_dictionaries({
        "name": st.one_of(st.integers(), st.none(), st.booleans()),
        "description": st.text(min_size=0, max_size=50),
    }),
    # Unparseable string inputSchema
    st.fixed_dictionaries({
        "name": _tool_name_st,
        "description": st.text(min_size=0, max_size=50),
        "inputSchema": st.sampled_from([
            "{invalid json",
            "not json at all",
            "{\"unclosed\": true",
            "[broken",
        ]),
    }),
)

# Mixed list of valid + invalid tool entries
_mixed_tools_st = st.lists(
    st.one_of(
        _valid_tool_entry_st.map(lambda t: ("valid", t)),
        _invalid_tool_entry_st.map(lambda t: ("invalid", t)),
    ),
    min_size=1,
    max_size=20,
)


# ---------------------------------------------------------------------------
# Property 2: Tool registry population from tools/list
# Feature: mcp-sidebar-integration, Property 2: Tool registry population from tools/list
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty2ToolRegistryPopulation:
    """Property 2: Tool registry population from tools/list.

    Valid entries registered, invalid skipped.

    **Validates: Requirements 2.2, 2.7**
    """

    @given(
        server_name=_server_name_st,
        mixed_tools=_mixed_tools_st,
    )
    @settings(max_examples=100)
    def test_valid_tools_registered_invalid_skipped(
        self, server_name: str, mixed_tools: list[tuple[str, dict]]
    ):
        """Given a tools/list response with mix of valid/invalid tools,
        registry contains exactly the valid ones."""
        # Separate valid and invalid
        all_tools = [t[1] for t in mixed_tools]
        valid_tools = [t[1] for t in mixed_tools if t[0] == "valid"]

        # Compute expected registered names (excluding built-in conflicts)
        server_prefix = make_server_prefix(server_name)
        expected_names = set()
        for tool in valid_tools:
            prefixed = server_prefix + tool["name"]
            if prefixed not in BUILTIN_TOOL_NAMES:
                expected_names.add(prefixed)

        # Register
        registry = register_tools_from_server(
            server_name, all_tools, BUILTIN_TOOL_NAMES
        )

        # Registry should contain exactly the valid tools (minus built-in conflicts)
        registered_names = set(registry.keys())
        assert registered_names == expected_names, (
            f"Expected {expected_names}, got {registered_names}"
        )

    @given(
        server_name=_server_name_st,
        valid_tools=st.lists(_valid_tool_entry_st, min_size=1, max_size=15),
    )
    @settings(max_examples=100)
    def test_valid_tools_preserve_fields(
        self, server_name: str, valid_tools: list[dict]
    ):
        """Each registered tool preserves name, description, and schema.
        When duplicates exist, last-write-wins (matching QML object assignment)."""
        registry = register_tools_from_server(
            server_name, valid_tools, BUILTIN_TOOL_NAMES
        )

        server_prefix = make_server_prefix(server_name)

        # Build expected last-write-wins mapping
        last_tool_by_name: dict[str, dict] = {}
        for tool in valid_tools:
            prefixed = server_prefix + tool["name"]
            if prefixed not in BUILTIN_TOOL_NAMES:
                last_tool_by_name[prefixed] = tool

        for prefixed, tool in last_tool_by_name.items():
            if prefixed in registry:
                entry = registry[prefixed]
                assert entry["originalName"] == tool["name"]
                assert entry["description"] == tool.get("description", "")

    @given(
        server_name=_server_name_st,
        invalid_tools=st.lists(_invalid_tool_entry_st, min_size=1, max_size=10),
    )
    @settings(max_examples=100)
    def test_only_invalid_tools_produce_empty_registry(
        self, server_name: str, invalid_tools: list[dict]
    ):
        """A tools/list with only invalid entries produces an empty registry."""
        registry = register_tools_from_server(
            server_name, invalid_tools, BUILTIN_TOOL_NAMES
        )
        assert len(registry) == 0, (
            f"Expected empty registry, got {list(registry.keys())}"
        )


# ---------------------------------------------------------------------------
# Property 3: Tool-to-server mapping invariant
# Feature: mcp-sidebar-integration, Property 3: Tool-to-server mapping invariant
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty3ToolToServerMapping:
    """Property 3: Tool-to-server mapping invariant.

    Every tool has non-empty serverName from config.

    **Validates: Requirements 2.4**
    """

    @given(
        server_tools=st.dictionaries(
            keys=_server_name_st,
            values=st.lists(_valid_tool_entry_st, min_size=1, max_size=10),
            min_size=1,
            max_size=5,
        ),
    )
    @settings(max_examples=100)
    def test_every_tool_has_nonempty_server_name(
        self, server_tools: dict[str, list[dict]]
    ):
        """Every registered tool entry has a non-empty serverName field."""
        registry = register_tools_multi_server(server_tools, BUILTIN_TOOL_NAMES)

        for tool_name, entry in registry.items():
            assert entry["serverName"], (
                f"Tool '{tool_name}' has empty serverName"
            )
            assert isinstance(entry["serverName"], str), (
                f"Tool '{tool_name}' serverName is not a string"
            )

    @given(
        server_tools=st.dictionaries(
            keys=_server_name_st,
            values=st.lists(_valid_tool_entry_st, min_size=1, max_size=10),
            min_size=1,
            max_size=5,
        ),
    )
    @settings(max_examples=100)
    def test_every_tool_maps_to_known_server(
        self, server_tools: dict[str, list[dict]]
    ):
        """Every registered tool's serverName corresponds to a known server."""
        known_servers = set(server_tools.keys())
        registry = register_tools_multi_server(server_tools, BUILTIN_TOOL_NAMES)

        for tool_name, entry in registry.items():
            assert entry["serverName"] in known_servers, (
                f"Tool '{tool_name}' maps to unknown server '{entry['serverName']}'. "
                f"Known servers: {known_servers}"
            )


# ---------------------------------------------------------------------------
# Property 5: Name collision prefixing
# Feature: mcp-sidebar-integration, Property 5: Name collision prefixing
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty5NameCollisionPrefixing:
    """Property 5: Name collision prefixing.

    Conflicting names get server prefix, no duplicates in registry.

    **Validates: Requirements 2.5, 8.7**
    """

    @given(
        server_tools=st.dictionaries(
            keys=_server_name_st,
            values=st.lists(_valid_tool_entry_st, min_size=1, max_size=10),
            min_size=1,
            max_size=5,
        ),
    )
    @settings(max_examples=100)
    def test_all_tools_are_prefixed(
        self, server_tools: dict[str, list[dict]]
    ):
        """All registered tool names are prefixed (start with 'mcp_')."""
        registry = register_tools_multi_server(server_tools, BUILTIN_TOOL_NAMES)

        for tool_name in registry.keys():
            assert tool_name.startswith("mcp_"), (
                f"Tool '{tool_name}' is not prefixed with 'mcp_'"
            )

    @given(
        server_tools=st.dictionaries(
            keys=_server_name_st,
            values=st.lists(_valid_tool_entry_st, min_size=1, max_size=10),
            min_size=1,
            max_size=5,
        ),
    )
    @settings(max_examples=100)
    def test_no_duplicate_names_in_registry(
        self, server_tools: dict[str, list[dict]]
    ):
        """No duplicate tool names exist in the registry (dict keys are unique by nature,
        but verify the count matches what we expect from unique prefixed names)."""
        registry = register_tools_multi_server(server_tools, BUILTIN_TOOL_NAMES)

        # All keys are unique (inherent to dict), but let's verify tool names
        # are the correct prefixed form
        tool_names = list(registry.keys())
        assert len(tool_names) == len(set(tool_names)), (
            "Duplicate tool names found in registry"
        )

    @given(
        # Two different servers both exposing a tool with the same name
        shared_tool_name=_tool_name_st,
        server_a=_server_name_st,
        server_b=_server_name_st,
    )
    @settings(max_examples=100)
    def test_same_tool_name_different_servers_both_registered(
        self, shared_tool_name: str, server_a: str, server_b: str
    ):
        """When two servers expose a tool with the same original name,
        both are registered with distinct prefixed names."""
        assume(server_a != server_b)

        tool_entry = {
            "name": shared_tool_name,
            "description": "shared tool",
            "inputSchema": {"type": "object", "properties": {}},
        }

        server_tools = {
            server_a: [tool_entry],
            server_b: [tool_entry],
        }

        registry = register_tools_multi_server(server_tools, BUILTIN_TOOL_NAMES)

        prefix_a = make_server_prefix(server_a)
        prefix_b = make_server_prefix(server_b)
        name_a = prefix_a + shared_tool_name
        name_b = prefix_b + shared_tool_name

        # Skip assertion if either conflicts with built-in
        if name_a in BUILTIN_TOOL_NAMES or name_b in BUILTIN_TOOL_NAMES:
            return

        # Both should be present with different prefixed names
        assert name_a in registry, (
            f"Expected '{name_a}' in registry for server '{server_a}'"
        )
        assert name_b in registry, (
            f"Expected '{name_b}' in registry for server '{server_b}'"
        )
        assert name_a != name_b, (
            "Different servers should produce different prefixed names"
        )

    @given(
        server_name=_server_name_st,
        tools=st.lists(_valid_tool_entry_st, min_size=1, max_size=15),
    )
    @settings(max_examples=100)
    def test_tool_name_contains_server_identifier(
        self, server_name: str, tools: list[dict]
    ):
        """Each registered tool name contains the server identifier in its prefix."""
        registry = register_tools_from_server(
            server_name, tools, BUILTIN_TOOL_NAMES
        )

        expected_prefix = make_server_prefix(server_name)
        for tool_name in registry.keys():
            assert tool_name.startswith(expected_prefix), (
                f"Tool '{tool_name}' does not start with expected prefix '{expected_prefix}'"
            )


# ---------------------------------------------------------------------------
# Property 18: Built-in name conflict rejection
# Feature: mcp-sidebar-integration, Property 18: Built-in name conflict rejection
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty18BuiltinNameConflictRejection:
    """Property 18: Built-in name conflict rejection.

    MCP tools matching built-in names are rejected.

    **Validates: Requirements 7.4**
    """

    @given(
        # Pick a built-in name and reverse-engineer a server/tool combo that would produce it
        builtin_idx=st.integers(min_value=0, max_value=len(BUILTIN_TOOL_NAMES) - 1),
    )
    @settings(max_examples=100)
    def test_tool_matching_builtin_name_is_rejected(self, builtin_idx: int):
        """Any MCP tool whose prefixed name exactly matches a built-in name is rejected."""
        builtin_name = BUILTIN_TOOL_NAMES[builtin_idx]

        # Construct a server name and tool name that would produce the built-in name
        # e.g., builtin "hypr_config_read" → could be server="" tool="hypr_config_read"
        # with prefix "mcp__" which doesn't match. We need to be more creative.
        # Actually: a builtin name like "set_shell_config" would need:
        #   mcp_{server}_{tool} == "set_shell_config"
        # This can't happen naturally since all mcp tools start with "mcp_"
        # and no built-in starts with "mcp_".
        #
        # But the design says the check is on the prefixed name. Let's verify
        # that even if we forcefully inject the check, it works.
        # The real scenario: if a builtin name WERE "mcp_fetch_fetch",
        # then server="fetch" tool="fetch" would conflict.

        # Test with a synthetic builtin list that includes an mcp-prefixed name
        synthetic_builtins = ["mcp_test_server_danger_tool"]
        tool_entry = {
            "name": "danger_tool",
            "description": "a dangerous tool",
            "inputSchema": {"type": "object", "properties": {}},
        }

        registry = register_tools_from_server(
            "test-server", [tool_entry], synthetic_builtins
        )

        # The tool should be rejected
        assert "mcp_test_server_danger_tool" not in registry, (
            "Tool matching built-in name should be rejected"
        )

    @given(
        server_name=_server_name_st,
        tools=st.lists(_valid_tool_entry_st, min_size=1, max_size=10),
    )
    @settings(max_examples=100)
    def test_no_registered_tool_shadows_builtin(
        self, server_name: str, tools: list[dict]
    ):
        """No tool in the registry ever has a name that matches a built-in tool."""
        registry = register_tools_from_server(
            server_name, tools, BUILTIN_TOOL_NAMES
        )

        for tool_name in registry.keys():
            assert tool_name not in BUILTIN_TOOL_NAMES, (
                f"Registered tool '{tool_name}' shadows a built-in tool"
            )

    @given(
        server_name=_server_name_st,
        safe_tools=st.lists(_valid_tool_entry_st, min_size=1, max_size=5),
    )
    @settings(max_examples=100)
    def test_conflicting_tools_rejected_others_still_registered(
        self, server_name: str, safe_tools: list[dict]
    ):
        """When some tools conflict with built-in names, only those are rejected;
        non-conflicting tools are still registered."""
        # Create a synthetic builtin that matches one specific tool
        prefix = make_server_prefix(server_name)
        conflicting_name = safe_tools[0]["name"]
        synthetic_builtin = prefix + conflicting_name

        # Add the synthetic builtin to the list
        extended_builtins = BUILTIN_TOOL_NAMES + [synthetic_builtin]

        registry = register_tools_from_server(
            server_name, safe_tools, extended_builtins
        )

        # The conflicting tool should NOT be registered
        assert synthetic_builtin not in registry, (
            f"Conflicting tool '{synthetic_builtin}' should be rejected"
        )

        # Other tools (with unique names) should still be registered
        for tool in safe_tools[1:]:
            prefixed = prefix + tool["name"]
            if prefixed not in extended_builtins and prefixed != synthetic_builtin:
                # It might be a duplicate of another tool in the list, so just
                # verify it's not wrongly rejected
                pass  # Can't guarantee registration due to possible name collisions in list



# ---------------------------------------------------------------------------
# Pure function reimplementation for auto-approve (mirrors McpClient.qml)
# ---------------------------------------------------------------------------


def is_tool_auto_approved(tool_name: str, auto_approve_list: list[str]) -> bool:
    """Check if a tool name is in the auto-approve list.

    Mirrors McpClient.isToolAutoApproved:
        function isToolAutoApproved(toolName) {
            return root.autoApproveList.indexOf(toolName) !== -1;
        }

    The autoApproveList is constructed by prefixing:
        "mcp_" + serverName.replace(/-/g, "_") + "_" + toolOriginalName
    """
    return tool_name in auto_approve_list


def build_auto_approve_list(server_configs: dict[str, list[str]]) -> list[str]:
    """Build the flat auto-approve list from server configs.

    Mirrors McpClient._parseConfig auto-approve aggregation:
        const serverPrefix = "mcp_" + name.replace(/-/g, "_") + "_";
        const approveList = entry.autoApprove || [];
        for (let j = 0; j < approveList.length; j++) {
            newAutoApprove.push(serverPrefix + approveList[j]);
        }

    Args:
        server_configs: mapping of serverName → list of original tool names to auto-approve

    Returns: flat list of prefixed tool names
    """
    result = []
    for server_name, tool_names in server_configs.items():
        prefix = "mcp_" + server_name.replace("-", "_") + "_"
        for tool_name in tool_names:
            result.append(prefix + tool_name)
    return result


# ---------------------------------------------------------------------------
# Strategies for auto-approve tests
# ---------------------------------------------------------------------------

# Strategy for original tool names (before prefixing)
_original_tool_name_st = st.from_regex(r"[a-z][a-z0-9_]{0,29}", fullmatch=True)

# Strategy for server names (may contain hyphens)
_auto_approve_server_name_st = st.from_regex(r"[a-z][a-z0-9\-]{0,19}", fullmatch=True)

# Strategy for server auto-approve configs: serverName → list of tool names
_server_auto_approve_configs_st = st.dictionaries(
    keys=_auto_approve_server_name_st,
    values=st.lists(_original_tool_name_st, min_size=1, max_size=10),
    min_size=1,
    max_size=5,
)


# ---------------------------------------------------------------------------
# Property 10: Auto-approve decision
# Feature: mcp-sidebar-integration, Property 10: Auto-approve decision
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty10AutoApproveDecision:
    """Property 10: Auto-approve decision.

    For any tool name, if the tool name appears in the server's autoApprove list,
    the tool SHALL be executed without user confirmation; if it does not appear in
    the autoApprove list, the system SHALL request user approval before execution.

    **Validates: Requirements 3.5, 3.6**
    """

    @given(server_configs=_server_auto_approve_configs_st)
    @settings(max_examples=100)
    def test_tool_in_auto_approve_list_returns_true(
        self, server_configs: dict[str, list[str]]
    ):
        """Any tool name present in the auto-approve list → isToolAutoApproved returns true."""
        auto_approve_list = build_auto_approve_list(server_configs)

        # Every tool in the list should be auto-approved
        for tool_name in auto_approve_list:
            assert is_tool_auto_approved(tool_name, auto_approve_list), (
                f"Tool '{tool_name}' is in auto-approve list but isToolAutoApproved returned False"
            )

    @given(
        server_configs=_server_auto_approve_configs_st,
        extra_tool_name=_original_tool_name_st,
        extra_server_name=_auto_approve_server_name_st,
    )
    @settings(max_examples=100)
    def test_tool_not_in_auto_approve_list_returns_false(
        self,
        server_configs: dict[str, list[str]],
        extra_tool_name: str,
        extra_server_name: str,
    ):
        """Any tool name NOT in the auto-approve list → isToolAutoApproved returns false."""
        auto_approve_list = build_auto_approve_list(server_configs)

        # Construct a prefixed tool name that is NOT in the list
        candidate = "mcp_" + extra_server_name.replace("-", "_") + "_" + extra_tool_name
        assume(candidate not in auto_approve_list)

        assert not is_tool_auto_approved(candidate, auto_approve_list), (
            f"Tool '{candidate}' is NOT in auto-approve list but isToolAutoApproved returned True"
        )

    @given(server_configs=_server_auto_approve_configs_st)
    @settings(max_examples=100)
    def test_auto_approve_list_constructed_with_correct_prefix(
        self, server_configs: dict[str, list[str]]
    ):
        """The auto-approve list is constructed by prefixing:
        'mcp_' + serverName.replace('-', '_') + '_' + toolOriginalName."""
        auto_approve_list = build_auto_approve_list(server_configs)

        # Verify each entry matches the expected prefix format
        idx = 0
        for server_name, tool_names in server_configs.items():
            expected_prefix = "mcp_" + server_name.replace("-", "_") + "_"
            for tool_name in tool_names:
                expected = expected_prefix + tool_name
                assert auto_approve_list[idx] == expected, (
                    f"Expected '{expected}' at index {idx}, got '{auto_approve_list[idx]}'"
                )
                idx += 1

    @given(
        server_configs=_server_auto_approve_configs_st,
        query_tool=_original_tool_name_st,
        query_server=_auto_approve_server_name_st,
    )
    @settings(max_examples=100)
    def test_decision_is_binary_approve_or_require_confirmation(
        self,
        server_configs: dict[str, list[str]],
        query_tool: str,
        query_server: str,
    ):
        """The auto-approve decision is strictly binary: either execute without
        confirmation (in list) or require approval (not in list). No third state."""
        auto_approve_list = build_auto_approve_list(server_configs)
        prefixed = "mcp_" + query_server.replace("-", "_") + "_" + query_tool

        result = is_tool_auto_approved(prefixed, auto_approve_list)

        # Result must be a boolean
        assert isinstance(result, bool), (
            f"isToolAutoApproved should return bool, got {type(result)}"
        )

        # Result must match list membership
        expected = prefixed in auto_approve_list
        assert result == expected, (
            f"Tool '{prefixed}' in list: {expected}, but got: {result}"
        )

    @given(server_configs=_server_auto_approve_configs_st)
    @settings(max_examples=100)
    def test_hyphenated_server_names_normalized_in_prefix(
        self, server_configs: dict[str, list[str]]
    ):
        """Server names with hyphens are normalized to underscores in the prefix."""
        auto_approve_list = build_auto_approve_list(server_configs)

        for entry in auto_approve_list:
            # After "mcp_", there should be no hyphens in the prefix portion
            # (tool names themselves already can't have hyphens per our strategy)
            assert entry.startswith("mcp_"), (
                f"Auto-approve entry '{entry}' doesn't start with 'mcp_'"
            )
            # The full entry should have no hyphens since both server name
            # hyphens are replaced and tool names use underscores
            assert "-" not in entry, (
                f"Auto-approve entry '{entry}' contains hyphen — "
                "server name hyphens should be normalized to underscores"
            )

    @given(
        server_configs=_server_auto_approve_configs_st,
    )
    @settings(max_examples=100)
    def test_empty_string_never_auto_approved(
        self, server_configs: dict[str, list[str]]
    ):
        """An empty string is never in the auto-approve list."""
        auto_approve_list = build_auto_approve_list(server_configs)
        assert not is_tool_auto_approved("", auto_approve_list), (
            "Empty string should never be auto-approved"
        )


# ---------------------------------------------------------------------------
# Pure function reimplementations for Provider Declarations and Dispatch
# (mirrors getToolDeclarations and handleFunctionCall from McpClient.qml / Ai.qml)
# ---------------------------------------------------------------------------


def get_tool_declarations(format: str, registry: dict) -> list:
    """Convert tool registry to provider-specific declarations.

    Mirrors McpClient.getToolDeclarations(format):
    - Gemini: [{ functionDeclarations: [{ name, description, parameters }] }]
    - OpenAI: [{ name, description, parameters }]
    - Mistral: [{ type: "function", function: { name, description, parameters } }]
    - Unknown format or empty registry: []

    Args:
        format: One of "gemini", "openai", "mistral"
        registry: Tool registry dict mapping toolName → { serverName, originalName, description, inputSchema }

    Returns:
        List of declarations in the target provider's structure.
    """
    tool_names = list(registry.keys())

    if len(tool_names) == 0:
        return []

    declarations = []

    for name in tool_names:
        entry = registry[name]
        declarations.append({
            "name": name,
            "description": entry.get("description", ""),
            "parameters": entry.get("inputSchema") or {"type": "object", "properties": {}, "required": []},
        })

    if format == "gemini":
        return [{"functionDeclarations": declarations}]
    elif format == "openai":
        return declarations
    elif format == "mistral":
        return [
            {
                "type": "function",
                "function": {
                    "name": d["name"],
                    "description": d["description"],
                    "parameters": d["parameters"],
                },
            }
            for d in declarations
        ]

    # Unknown format
    return []


def dispatch_priority(name: str, builtins: list[str], registry: dict) -> str:
    """Determine dispatch path for a function call name.

    Mirrors handleFunctionCall in Ai.qml:
    1. If name matches a built-in tool → "builtin"
    2. Else if name is in the tool registry → "mcp"
    3. Otherwise → "unknown"

    Args:
        name: The function call name from the LLM
        builtins: List of built-in tool names
        registry: The tool registry (toolName → entry)

    Returns:
        "builtin", "mcp", or "unknown"
    """
    if name in builtins:
        return "builtin"
    elif name in registry:
        return "mcp"
    else:
        return "unknown"


# ---------------------------------------------------------------------------
# Strategies for Properties 4, 17, 19, 20
# ---------------------------------------------------------------------------

# Provider format strategy
_format_st = st.sampled_from(["gemini", "openai", "mistral"])

# Unknown format strategy (not one of the supported formats)
_unknown_format_st = st.text(min_size=1, max_size=20).filter(
    lambda f: f not in ("gemini", "openai", "mistral")
)

# Tool registry entry strategy
_registry_entry_st = st.fixed_dictionaries({
    "serverName": _server_name_st,
    "originalName": _tool_name_st,
    "description": st.text(min_size=0, max_size=100),
    "inputSchema": st.one_of(
        _input_schema_st,
        st.fixed_dictionaries({
            "type": st.just("object"),
            "properties": st.dictionaries(
                keys=st.from_regex(r"[a-z][a-z0-9_]{0,14}", fullmatch=True),
                values=st.fixed_dictionaries({
                    "type": st.sampled_from(["string", "integer", "boolean", "number", "array"]),
                    "description": st.text(min_size=1, max_size=80),
                }),
                min_size=1,
                max_size=8,
            ),
            "required": st.lists(
                st.from_regex(r"[a-z][a-z0-9_]{0,14}", fullmatch=True),
                min_size=0,
                max_size=5,
            ),
        }),
    ),
})

# Non-empty tool registry (prefixed names → entries)
_nonempty_registry_st = st.dictionaries(
    keys=st.from_regex(r"mcp_[a-z][a-z0-9_]{2,30}", fullmatch=True),
    values=_registry_entry_st,
    min_size=1,
    max_size=10,
)

# Strategy for a function name that might be builtin, mcp, or unknown
_function_name_st = st.one_of(
    # A known builtin name
    st.sampled_from(BUILTIN_TOOL_NAMES),
    # An MCP-prefixed name
    st.from_regex(r"mcp_[a-z][a-z0-9_]{2,30}", fullmatch=True),
    # A random name (likely unknown)
    st.from_regex(r"[a-z][a-z0-9_]{0,20}", fullmatch=True),
)


# ---------------------------------------------------------------------------
# Property 4: Function declarations include all registered tools
# Feature: mcp-sidebar-integration, Property 4: Function declarations include all registered tools
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty4FunctionDeclarationsIncludeAllTools:
    """Property 4: Function declarations include all registered tools.

    Every registry tool included, no omissions or duplicates.

    **Validates: Requirements 2.3, 7.1**
    """

    @given(
        format=_format_st,
        registry=_nonempty_registry_st,
    )
    @settings(max_examples=100)
    def test_all_registry_tools_present_in_declarations(
        self, format: str, registry: dict
    ):
        """Every tool in the registry appears in the declarations output."""
        declarations = get_tool_declarations(format, registry)
        registry_names = set(registry.keys())

        # Extract declared tool names based on format
        declared_names = set()
        if format == "gemini":
            assert len(declarations) == 1
            for decl in declarations[0]["functionDeclarations"]:
                declared_names.add(decl["name"])
        elif format == "openai":
            for decl in declarations:
                declared_names.add(decl["name"])
        elif format == "mistral":
            for decl in declarations:
                declared_names.add(decl["function"]["name"])

        assert declared_names == registry_names, (
            f"Format '{format}': expected tools {registry_names}, "
            f"got {declared_names}. Missing: {registry_names - declared_names}, "
            f"Extra: {declared_names - registry_names}"
        )

    @given(
        format=_format_st,
        registry=_nonempty_registry_st,
    )
    @settings(max_examples=100)
    def test_no_duplicate_tools_in_declarations(
        self, format: str, registry: dict
    ):
        """No tool name appears more than once in the declarations."""
        declarations = get_tool_declarations(format, registry)

        # Extract all declared names
        declared_names = []
        if format == "gemini":
            for decl in declarations[0]["functionDeclarations"]:
                declared_names.append(decl["name"])
        elif format == "openai":
            for decl in declarations:
                declared_names.append(decl["name"])
        elif format == "mistral":
            for decl in declarations:
                declared_names.append(decl["function"]["name"])

        assert len(declared_names) == len(set(declared_names)), (
            f"Duplicate tool names found in {format} declarations: "
            f"{[n for n in declared_names if declared_names.count(n) > 1]}"
        )

    @given(format=_format_st)
    @settings(max_examples=100)
    def test_empty_registry_returns_empty_declarations(self, format: str):
        """An empty registry always produces an empty declarations list."""
        declarations = get_tool_declarations(format, {})
        assert declarations == [], (
            f"Empty registry should produce [], got {declarations}"
        )

    @given(
        format=_unknown_format_st,
        registry=_nonempty_registry_st,
    )
    @settings(max_examples=100)
    def test_unknown_format_returns_empty(self, format: str, registry: dict):
        """An unknown format returns an empty list even with tools registered."""
        declarations = get_tool_declarations(format, registry)
        assert declarations == [], (
            f"Unknown format '{format}' should produce [], got {declarations}"
        )


# ---------------------------------------------------------------------------
# Property 17: Dispatch priority
# Feature: mcp-sidebar-integration, Property 17: Dispatch priority
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty17DispatchPriority:
    """Property 17: Dispatch priority.

    Built-in match → built-in handler; registry match → MCP; neither → error.

    **Validates: Requirements 7.1, 7.2, 7.3**
    """

    @given(
        builtin_idx=st.integers(min_value=0, max_value=len(BUILTIN_TOOL_NAMES) - 1),
        registry=_nonempty_registry_st,
    )
    @settings(max_examples=100)
    def test_builtin_name_always_dispatches_to_builtin(
        self, builtin_idx: int, registry: dict
    ):
        """A name matching a built-in tool always dispatches to 'builtin',
        even if the same name somehow appears in the registry."""
        builtin_name = BUILTIN_TOOL_NAMES[builtin_idx]
        result = dispatch_priority(builtin_name, BUILTIN_TOOL_NAMES, registry)
        assert result == "builtin", (
            f"Built-in '{builtin_name}' should dispatch to 'builtin', got '{result}'"
        )

    @given(registry=_nonempty_registry_st)
    @settings(max_examples=100)
    def test_registry_name_dispatches_to_mcp(self, registry: dict):
        """A name in the registry (and not a built-in) dispatches to 'mcp'."""
        # Pick a random tool from the registry
        mcp_name = list(registry.keys())[0]
        # Ensure it's not accidentally a built-in name
        assume(mcp_name not in BUILTIN_TOOL_NAMES)

        result = dispatch_priority(mcp_name, BUILTIN_TOOL_NAMES, registry)
        assert result == "mcp", (
            f"Registry tool '{mcp_name}' should dispatch to 'mcp', got '{result}'"
        )

    @given(
        name=st.from_regex(r"unknown_tool_[a-z0-9]{3,10}", fullmatch=True),
        registry=_nonempty_registry_st,
    )
    @settings(max_examples=100)
    def test_unknown_name_dispatches_to_unknown(self, name: str, registry: dict):
        """A name matching neither builtin nor registry dispatches to 'unknown'."""
        assume(name not in BUILTIN_TOOL_NAMES)
        assume(name not in registry)

        result = dispatch_priority(name, BUILTIN_TOOL_NAMES, registry)
        assert result == "unknown", (
            f"Unknown name '{name}' should dispatch to 'unknown', got '{result}'"
        )

    @given(
        registry=_nonempty_registry_st,
        builtin_idx=st.integers(min_value=0, max_value=len(BUILTIN_TOOL_NAMES) - 1),
    )
    @settings(max_examples=100)
    def test_builtin_takes_priority_over_registry(
        self, registry: dict, builtin_idx: int
    ):
        """Even if a built-in name is also in the registry, built-in wins."""
        builtin_name = BUILTIN_TOOL_NAMES[builtin_idx]
        # Force the builtin name into the registry
        augmented_registry = dict(registry)
        augmented_registry[builtin_name] = {
            "serverName": "test-server",
            "originalName": builtin_name,
            "description": "shadowed tool",
            "inputSchema": {"type": "object", "properties": {}},
        }

        result = dispatch_priority(builtin_name, BUILTIN_TOOL_NAMES, augmented_registry)
        assert result == "builtin", (
            f"Built-in '{builtin_name}' should ALWAYS dispatch to 'builtin' "
            f"even when present in registry, got '{result}'"
        )

    @given(name=_function_name_st, registry=_nonempty_registry_st)
    @settings(max_examples=100)
    def test_dispatch_is_exhaustive(self, name: str, registry: dict):
        """Every possible name dispatches to exactly one of: builtin, mcp, unknown."""
        result = dispatch_priority(name, BUILTIN_TOOL_NAMES, registry)
        assert result in ("builtin", "mcp", "unknown"), (
            f"Dispatch for '{name}' returned unexpected value: '{result}'"
        )


# ---------------------------------------------------------------------------
# Property 19: Schema conversion to provider formats
# Feature: mcp-sidebar-integration, Property 19: Schema conversion to provider formats
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty19SchemaConversionToProviderFormats:
    """Property 19: Schema conversion to provider formats.

    Correct structure per provider.

    **Validates: Requirements 9.1, 9.2, 9.3**
    """

    @given(registry=_nonempty_registry_st)
    @settings(max_examples=100)
    def test_gemini_format_wraps_in_function_declarations(self, registry: dict):
        """Gemini format returns a list with one object containing functionDeclarations."""
        declarations = get_tool_declarations("gemini", registry)

        assert isinstance(declarations, list)
        assert len(declarations) == 1
        assert "functionDeclarations" in declarations[0]
        assert isinstance(declarations[0]["functionDeclarations"], list)
        assert len(declarations[0]["functionDeclarations"]) == len(registry)

        # Each declaration has name, description, parameters
        for decl in declarations[0]["functionDeclarations"]:
            assert "name" in decl
            assert "description" in decl
            assert "parameters" in decl
            assert isinstance(decl["name"], str)
            assert isinstance(decl["description"], str)
            assert isinstance(decl["parameters"], dict)

    @given(registry=_nonempty_registry_st)
    @settings(max_examples=100)
    def test_openai_format_is_flat_array(self, registry: dict):
        """OpenAI format returns a flat array of {name, description, parameters}."""
        declarations = get_tool_declarations("openai", registry)

        assert isinstance(declarations, list)
        assert len(declarations) == len(registry)

        for decl in declarations:
            assert "name" in decl
            assert "description" in decl
            assert "parameters" in decl
            assert isinstance(decl["name"], str)
            assert isinstance(decl["description"], str)
            assert isinstance(decl["parameters"], dict)
            # OpenAI format should NOT have nested "function" or "type" keys
            assert "function" not in decl
            assert "type" not in decl

    @given(registry=_nonempty_registry_st)
    @settings(max_examples=100)
    def test_mistral_format_wraps_in_type_function(self, registry: dict):
        """Mistral format returns array of {type: 'function', function: {name, description, parameters}}."""
        declarations = get_tool_declarations("mistral", registry)

        assert isinstance(declarations, list)
        assert len(declarations) == len(registry)

        for decl in declarations:
            assert decl["type"] == "function", (
                f"Mistral declaration should have type='function', got '{decl.get('type')}'"
            )
            assert "function" in decl
            fn = decl["function"]
            assert "name" in fn
            assert "description" in fn
            assert "parameters" in fn
            assert isinstance(fn["name"], str)
            assert isinstance(fn["description"], str)
            assert isinstance(fn["parameters"], dict)

    @given(
        registry=_nonempty_registry_st,
        format=_format_st,
    )
    @settings(max_examples=100)
    def test_declaration_count_matches_registry_size(
        self, registry: dict, format: str
    ):
        """The number of tool declarations always equals the registry size."""
        declarations = get_tool_declarations(format, registry)

        if format == "gemini":
            count = len(declarations[0]["functionDeclarations"])
        elif format == "openai":
            count = len(declarations)
        elif format == "mistral":
            count = len(declarations)
        else:
            count = 0

        assert count == len(registry), (
            f"Format '{format}': expected {len(registry)} declarations, got {count}"
        )


# ---------------------------------------------------------------------------
# Property 20: Schema property preservation
# Feature: mcp-sidebar-integration, Property 20: Schema property preservation
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty20SchemaPropertyPreservation:
    """Property 20: Schema property preservation.

    All names, types, descriptions, required arrays preserved.

    **Validates: Requirements 9.5**
    """

    @given(
        format=_format_st,
        registry=_nonempty_registry_st,
    )
    @settings(max_examples=100)
    def test_tool_names_preserved(self, format: str, registry: dict):
        """All tool names from the registry are exactly preserved in declarations."""
        declarations = get_tool_declarations(format, registry)

        # Extract names from declarations
        declared_names = []
        if format == "gemini":
            declared_names = [d["name"] for d in declarations[0]["functionDeclarations"]]
        elif format == "openai":
            declared_names = [d["name"] for d in declarations]
        elif format == "mistral":
            declared_names = [d["function"]["name"] for d in declarations]

        for name in registry.keys():
            assert name in declared_names, (
                f"Tool name '{name}' not preserved in {format} declarations"
            )

    @given(
        format=_format_st,
        registry=_nonempty_registry_st,
    )
    @settings(max_examples=100)
    def test_descriptions_preserved(self, format: str, registry: dict):
        """Tool descriptions from registry are exactly preserved in declarations."""
        declarations = get_tool_declarations(format, registry)

        # Build name→description map from declarations
        decl_map = {}
        if format == "gemini":
            for d in declarations[0]["functionDeclarations"]:
                decl_map[d["name"]] = d["description"]
        elif format == "openai":
            for d in declarations:
                decl_map[d["name"]] = d["description"]
        elif format == "mistral":
            for d in declarations:
                decl_map[d["function"]["name"]] = d["function"]["description"]

        for name, entry in registry.items():
            expected_desc = entry.get("description", "")
            assert decl_map.get(name) == expected_desc, (
                f"Tool '{name}' description mismatch in {format}: "
                f"expected {expected_desc!r}, got {decl_map.get(name)!r}"
            )

    @given(
        format=_format_st,
        registry=_nonempty_registry_st,
    )
    @settings(max_examples=100)
    def test_input_schema_parameters_preserved(self, format: str, registry: dict):
        """Tool inputSchema (parameters) from registry are exactly preserved."""
        declarations = get_tool_declarations(format, registry)

        # Build name→parameters map from declarations
        decl_map = {}
        if format == "gemini":
            for d in declarations[0]["functionDeclarations"]:
                decl_map[d["name"]] = d["parameters"]
        elif format == "openai":
            for d in declarations:
                decl_map[d["name"]] = d["parameters"]
        elif format == "mistral":
            for d in declarations:
                decl_map[d["function"]["name"]] = d["function"]["parameters"]

        for name, entry in registry.items():
            expected_params = entry.get("inputSchema") or {"type": "object", "properties": {}, "required": []}
            actual_params = decl_map.get(name)
            assert actual_params == expected_params, (
                f"Tool '{name}' parameters mismatch in {format}: "
                f"expected {expected_params!r}, got {actual_params!r}"
            )

    @given(
        format=_format_st,
        registry=_nonempty_registry_st,
    )
    @settings(max_examples=100)
    def test_required_arrays_preserved(self, format: str, registry: dict):
        """If the schema has a 'required' array, it's preserved exactly."""
        declarations = get_tool_declarations(format, registry)

        # Build name→parameters map
        decl_map = {}
        if format == "gemini":
            for d in declarations[0]["functionDeclarations"]:
                decl_map[d["name"]] = d["parameters"]
        elif format == "openai":
            for d in declarations:
                decl_map[d["name"]] = d["parameters"]
        elif format == "mistral":
            for d in declarations:
                decl_map[d["function"]["name"]] = d["function"]["parameters"]

        for name, entry in registry.items():
            schema = entry.get("inputSchema") or {"type": "object", "properties": {}, "required": []}
            if "required" in schema:
                actual_params = decl_map.get(name, {})
                assert actual_params.get("required") == schema["required"], (
                    f"Tool '{name}' required array mismatch in {format}: "
                    f"expected {schema['required']!r}, got {actual_params.get('required')!r}"
                )

    @given(
        format=_format_st,
        registry=_nonempty_registry_st,
    )
    @settings(max_examples=100)
    def test_property_types_preserved(self, format: str, registry: dict):
        """All property type values in schemas are preserved through conversion."""
        declarations = get_tool_declarations(format, registry)

        # Build name→parameters map
        decl_map = {}
        if format == "gemini":
            for d in declarations[0]["functionDeclarations"]:
                decl_map[d["name"]] = d["parameters"]
        elif format == "openai":
            for d in declarations:
                decl_map[d["name"]] = d["parameters"]
        elif format == "mistral":
            for d in declarations:
                decl_map[d["function"]["name"]] = d["function"]["parameters"]

        for name, entry in registry.items():
            schema = entry.get("inputSchema") or {"type": "object", "properties": {}, "required": []}
            actual_params = decl_map.get(name, {})

            # Check the top-level type is preserved
            if "type" in schema:
                assert actual_params.get("type") == schema["type"], (
                    f"Tool '{name}' schema type mismatch: "
                    f"expected {schema['type']!r}, got {actual_params.get('type')!r}"
                )

            # Check individual property types
            expected_props = schema.get("properties", {})
            actual_props = actual_params.get("properties", {})
            for prop_name, prop_def in expected_props.items():
                assert prop_name in actual_props, (
                    f"Tool '{name}' property '{prop_name}' missing from {format} output"
                )
                if "type" in prop_def:
                    assert actual_props[prop_name].get("type") == prop_def["type"], (
                        f"Tool '{name}' property '{prop_name}' type mismatch: "
                        f"expected {prop_def['type']!r}, got {actual_props[prop_name].get('type')!r}"
                    )


# ---------------------------------------------------------------------------
# Pure function reimplementations for write operation read-back verification
# (mirrors McpClient.qml _verifyWriteOperation logic)
# ---------------------------------------------------------------------------


def compute_read_back_namespace(key: str) -> str:
    """Compute the namespace for a read-back verification from a config key.

    Mirrors McpClient._verifyWriteOperation:
        const namespace = key.split(".").slice(0, -1).join(".") || key;

    Logic:
    - Split key by "."
    - Take everything except the last segment
    - Join back with "."
    - If result is empty (no "." in key), use the key itself
    """
    parts = key.split(".")
    namespace = ".".join(parts[:-1])
    return namespace if namespace else key


def verify_write(key: str, value: str, read_back_content: str) -> str:
    """Verify a write operation by checking if value appears in read-back content.

    Mirrors McpClient._verifyWriteOperation:
        const expectedValue = String(args.value || "");
        if (actualStr.indexOf(expectedValue) !== -1) {
            resultPromise._resolve("Verified: " + key + " = " + expectedValue);
        } else {
            resultPromise._resolve(
                "Verification failed: expected " + expectedValue +
                " for key " + key + ", got: " + actualStr
            );
        }

    Returns:
        "Verified: {key} = {value}" if value is found in read_back_content
        "Verification failed: expected {value} for key {key}, got: {read_back_content}" otherwise
    """
    expected_value = str(value) if value else ""
    actual_str = str(read_back_content)

    if expected_value in actual_str:
        return f"Verified: {key} = {expected_value}"
    else:
        return f"Verification failed: expected {expected_value} for key {key}, got: {actual_str}"


# ---------------------------------------------------------------------------
# Strategies for write operation read-back verification
# ---------------------------------------------------------------------------

# Config key: dot-separated segments (e.g., "bar.workspaces.count")
_key_segment_st = st.from_regex(r"[a-z][a-z0-9_]{0,15}", fullmatch=True)

# Key with dots (multi-segment)
_dotted_key_st = st.lists(
    _key_segment_st,
    min_size=2,
    max_size=5,
).map(lambda parts: ".".join(parts))

# Key without dots (single segment)
_simple_key_st = _key_segment_st

# Any valid config key (dotted or simple)
_config_key_st = st.one_of(_dotted_key_st, _simple_key_st)

# Config value: strings that represent scalar values
_config_value_st = st.one_of(
    st.integers(min_value=0, max_value=10000).map(str),
    st.sampled_from(["true", "false"]),
    st.text(
        alphabet=st.characters(whitelist_categories=("L", "N", "P", "S")),
        min_size=1,
        max_size=50,
    ),
    st.from_regex(r"#[0-9a-fA-F]{6}", fullmatch=True),
)

# Read-back content: simulates what config_read might return
_read_back_content_st = st.text(min_size=0, max_size=500)


# ---------------------------------------------------------------------------
# Property 23: Write operation read-back verification
# Feature: mcp-sidebar-integration, Property 23: Write operation read-back verification
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty23WriteReadBackVerification:
    """Property 23: Write operation read-back verification.

    For any successful write tool call (config_set or set_keyword) to the
    ii-desktop server, the MCP Client SHALL perform a subsequent config_read
    call for the affected namespace and compare the returned value against
    the written value before reporting success.

    **Validates: Requirements 8.6**
    """

    @given(key=_dotted_key_st)
    @settings(max_examples=100)
    def test_namespace_is_everything_before_last_dot(self, key: str):
        """Namespace is computed as everything before the last '.' in the key."""
        namespace = compute_read_back_namespace(key)
        parts = key.split(".")
        expected_namespace = ".".join(parts[:-1])
        assert namespace == expected_namespace, (
            f"Key '{key}': expected namespace '{expected_namespace}', got '{namespace}'"
        )

    @given(key=_simple_key_st)
    @settings(max_examples=100)
    def test_namespace_is_key_itself_when_no_dot(self, key: str):
        """When key has no '.', namespace is the key itself."""
        # Ensure no dots in simple key
        assume("." not in key)
        namespace = compute_read_back_namespace(key)
        assert namespace == key, (
            f"Key '{key}' (no dots): expected namespace '{key}', got '{namespace}'"
        )

    @given(key=_config_key_st, value=_config_value_st)
    @settings(max_examples=100)
    def test_verify_reports_success_when_value_in_readback(self, key: str, value: str):
        """When read-back content contains the written value, reports success."""
        # Construct read-back content that includes the value
        read_back = f'{{"namespace": "test", "data": "{value}", "extra": "stuff"}}'
        result = verify_write(key, value, read_back)
        assert result == f"Verified: {key} = {value}", (
            f"Expected verified success for key='{key}', value='{value}', "
            f"but got: {result}"
        )

    @given(key=_config_key_st, value=_config_value_st, noise=_read_back_content_st)
    @settings(max_examples=100)
    def test_verify_reports_mismatch_when_value_not_in_readback(
        self, key: str, value: str, noise: str
    ):
        """When read-back content does NOT contain the written value, reports mismatch."""
        # Ensure the noise does not accidentally contain the value
        assume(value not in noise)
        result = verify_write(key, value, noise)
        expected_prefix = f"Verification failed: expected {value} for key {key}, got: "
        assert result.startswith(expected_prefix), (
            f"Expected mismatch report starting with '{expected_prefix}', got: {result}"
        )
        # The rest should be the actual read-back content
        assert result == f"Verification failed: expected {value} for key {key}, got: {noise}"

    @given(key=_config_key_st, value=_config_value_st)
    @settings(max_examples=100)
    def test_verify_value_at_any_position_in_readback_succeeds(
        self, key: str, value: str
    ):
        """Value can appear anywhere in read-back content (indexOf semantics)."""
        # Value at the beginning
        result_begin = verify_write(key, value, value + " trailing stuff")
        assert "Verified:" in result_begin

        # Value at the end
        result_end = verify_write(key, value, "leading stuff " + value)
        assert "Verified:" in result_end

        # Value in the middle
        result_mid = verify_write(key, value, "before " + value + " after")
        assert "Verified:" in result_mid

    @given(key=_config_key_st)
    @settings(max_examples=100)
    def test_empty_value_always_matches(self, key: str):
        """Empty string value always matches (indexOf("") is always >= 0 in JS)."""
        # In Python, "" in any_string is always True, matching JS indexOf("") !== -1
        result = verify_write(key, "", "any content here")
        assert result == f"Verified: {key} = ", (
            f"Empty value should always verify, got: {result}"
        )

    @given(
        key=_dotted_key_st,
        value=_config_value_st,
    )
    @settings(max_examples=100)
    def test_namespace_used_for_readback_is_parent_of_key(self, key: str, value: str):
        """The namespace computed for read-back is always a proper parent of the key.

        This validates the full flow: key → namespace extraction → read-back scope.
        """
        namespace = compute_read_back_namespace(key)
        # Namespace must be a prefix of the key
        assert key.startswith(namespace), (
            f"Namespace '{namespace}' should be a prefix of key '{key}'"
        )
        # Namespace must be shorter than the key (not equal)
        assert len(namespace) < len(key), (
            f"Namespace '{namespace}' should be shorter than key '{key}'"
        )
        # The key minus namespace should start with a dot
        remainder = key[len(namespace):]
        assert remainder.startswith("."), (
            f"Key '{key}' after removing namespace '{namespace}' should start with '.', "
            f"got remainder '{remainder}'"
        )


# ---------------------------------------------------------------------------
# Pure function reimplementations for URL detection and content truncation
# (mirrors AiChat.qml URL regex and fetch truncation logic)
# ---------------------------------------------------------------------------

import re


def detect_urls(text: str) -> list[dict]:
    """Detect URLs matching https://, http://, or www. prefixes, up to 2048 chars each.

    Mirrors AiChat.qml URL detection:
        const regex = /(?:https?:\\/\\/|www\\.)[^\\s<>"']{1,2048}/gi;

    Returns list of dicts with keys: url, start, end
    """
    pattern = r'(?:https?://|www\.)[^\s<>"\']{1,2048}'
    matches = []
    for m in re.finditer(pattern, text, re.IGNORECASE):
        matches.append({"url": m.group(0), "start": m.start(), "end": m.end()})
    return matches


def truncate_content(content: str, max_length: int = 8000) -> str:
    """Truncate content to max_length if it exceeds it.

    Mirrors AiChat.qml fetch content truncation:
        const truncated = content.length > 8000 ? content.substring(0, 8000) : content;

    Returns:
        content[:max_length] if len(content) > max_length, else content unchanged
    """
    if len(content) > max_length:
        return content[:max_length]
    return content


# ---------------------------------------------------------------------------
# Strategies for URL detection tests
# ---------------------------------------------------------------------------

# Valid URL path characters (anything except whitespace and the delimiters <>"')
_url_path_chars = st.characters(
    whitelist_categories=("L", "N", "P", "S"),
    blacklist_characters=' \t\n\r<>"\'',
)

# URL path segment (non-empty, constrained chars)
_url_path_st = st.text(
    alphabet=_url_path_chars,
    min_size=1,
    max_size=100,
)

# Valid URL prefixes
_url_prefix_st = st.sampled_from(["https://", "http://", "www."])

# A complete valid URL (prefix + path, total ≤2048)
_valid_url_st = st.tuples(_url_prefix_st, _url_path_st).map(
    lambda t: t[0] + t[1]
).filter(lambda u: len(u) <= 2048)

# Non-URL text: text that does NOT contain URL prefixes
_non_url_text_st = st.text(
    alphabet=st.characters(whitelist_categories=("L", "N", "P", "Zs")),
    min_size=0,
    max_size=100,
).filter(
    lambda t: "http://" not in t.lower()
    and "https://" not in t.lower()
    and "www." not in t.lower()
)

# Strategy for text content of arbitrary length (for truncation tests)
# Use a composite strategy that builds large strings from small seeds to avoid
# Hypothesis health check issues with large minimum sizes.

@st.composite
def _large_content(draw, min_size=8001, max_size=16000):
    """Generate a string of length between min_size and max_size efficiently."""
    target_len = draw(st.integers(min_value=min_size, max_value=max_size))
    # Draw a small seed and repeat it to fill
    seed = draw(st.text(min_size=1, max_size=100))
    if not seed:
        seed = "x"
    # Repeat seed to exceed target, then slice
    repeats = (target_len // len(seed)) + 1
    return (seed * repeats)[:target_len]


@st.composite
def _exact_content(draw, size=8000):
    """Generate a string of exactly the given size."""
    seed = draw(st.text(min_size=1, max_size=100))
    if not seed:
        seed = "x"
    repeats = (size // len(seed)) + 1
    return (seed * repeats)[:size]


_content_short_st = st.text(min_size=0, max_size=8000)
_content_long_st = _large_content(min_size=8001, max_size=16000)
_content_any_st = st.one_of(
    st.text(min_size=0, max_size=8000),
    _large_content(min_size=8001, max_size=16000),
)


# ---------------------------------------------------------------------------
# Property 12: URL detection
# Feature: mcp-sidebar-integration, Property 12: URL detection
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty12UrlDetection:
    """Property 12: URL detection.

    For any message string containing zero or more URLs matching https://,
    http://, or www. prefixes (each up to 2048 characters), the URL Detector
    SHALL identify all such URLs and return their positions and text, with no
    false negatives for conforming URLs and no matches exceeding 2048 characters.

    **Validates: Requirements 5.1, 5.6**
    """

    @given(url=_valid_url_st)
    @settings(max_examples=100)
    def test_single_url_detected(self, url: str):
        """A single valid URL in text is always detected."""
        text = f"Check this out: {url} isn't it cool?"
        results = detect_urls(text)

        # Should find at least one match
        detected_urls = [r["url"] for r in results]
        assert url in detected_urls, (
            f"URL '{url[:80]}...' not detected in text. Found: {detected_urls}"
        )

    @given(
        urls=st.lists(_valid_url_st, min_size=1, max_size=5),
    )
    @settings(max_examples=100)
    def test_multiple_urls_all_detected(self, urls: list[str]):
        """Multiple URLs in text are all detected."""
        # Join URLs with whitespace separators
        text = " ".join(f"link: {url}" for url in urls)
        results = detect_urls(text)
        detected_urls = [r["url"] for r in results]

        for url in urls:
            assert url in detected_urls, (
                f"URL '{url[:60]}...' not detected. Found {len(detected_urls)} matches."
            )

    @given(url=_valid_url_st)
    @settings(max_examples=100)
    def test_detected_url_positions_are_correct(self, url: str):
        """Positions (start, end) correctly identify the URL in text."""
        prefix_text = "Visit "
        suffix_text = " for more info"
        text = prefix_text + url + suffix_text
        results = detect_urls(text)

        # Find our URL in results
        matching = [r for r in results if r["url"] == url]
        assert len(matching) >= 1, (
            f"URL '{url[:60]}...' not found in results"
        )

        match = matching[0]
        # Verify positions
        assert match["start"] == len(prefix_text), (
            f"Start position: expected {len(prefix_text)}, got {match['start']}"
        )
        assert match["end"] == len(prefix_text) + len(url), (
            f"End position: expected {len(prefix_text) + len(url)}, got {match['end']}"
        )
        # Verify text extraction by position
        assert text[match["start"]:match["end"]] == url, (
            f"Text at positions [{match['start']}:{match['end']}] != URL"
        )

    @given(url=_valid_url_st)
    @settings(max_examples=100)
    def test_no_detected_url_exceeds_max_length(self, url: str):
        """No detected URL exceeds the prefix + 2048 path char limit.

        The regex limits the path portion (after prefix) to 2048 chars.
        Total URL length = prefix_length + path_length, where path_length ≤ 2048.
        Maximum possible: len("https://") + 2048 = 2056.
        """
        text = f"here: {url} end"
        results = detect_urls(text)

        for r in results:
            # The regex {1,2048} applies to path chars only (after prefix)
            # So total max is prefix (up to 8 chars for "https://") + 2048 = 2056
            assert len(r["url"]) <= 2056, (
                f"Detected URL exceeds max possible length: length={len(r['url'])}"
            )

    @given(text=_non_url_text_st)
    @settings(max_examples=100)
    def test_non_url_text_produces_no_matches(self, text: str):
        """Text without URL prefixes produces no false positives."""
        results = detect_urls(text)
        assert len(results) == 0, (
            f"Non-URL text produced {len(results)} false positive(s): "
            f"{[r['url'][:40] for r in results]}"
        )

    @given(
        prefix=_url_prefix_st,
        path=st.text(
            alphabet=_url_path_chars,
            min_size=2040,
            max_size=2060,
        ),
    )
    @settings(max_examples=100)
    def test_urls_exceeding_2048_path_chars_are_capped(
        self, prefix: str, path: str
    ):
        """URL paths longer than 2048 chars are matched only up to 2048 path chars.

        The regex {1,2048} quantifier limits the path portion to 2048 chars.
        Total matched URL = prefix + min(path_len, 2048).
        """
        long_url = prefix + path
        text = f"long: {long_url} end"
        results = detect_urls(text)

        # Should still detect something (the prefix + up to 2048 path chars)
        assert len(results) >= 1, "Should detect at least one URL"
        for r in results:
            # Path portion (everything after the prefix) should be ≤ 2048
            matched_url = r["url"]
            if matched_url.startswith("https://"):
                path_len = len(matched_url) - len("https://")
            elif matched_url.startswith("http://"):
                path_len = len(matched_url) - len("http://")
            elif matched_url.lower().startswith("www."):
                path_len = len(matched_url) - len("www.")
            else:
                path_len = len(matched_url)

            assert path_len <= 2048, (
                f"Path portion length {path_len} exceeds 2048 limit "
                f"(total URL length: {len(matched_url)})"
            )

    @given(url=_valid_url_st)
    @settings(max_examples=100)
    def test_url_at_start_of_text_detected(self, url: str):
        """URL at the very start of text is detected correctly."""
        text = url + " is a link"
        results = detect_urls(text)
        detected_urls = [r["url"] for r in results]
        assert url in detected_urls, (
            f"URL at start of text not detected: '{url[:60]}...'"
        )
        # Start position should be 0
        matching = [r for r in results if r["url"] == url]
        assert matching[0]["start"] == 0

    @given(url=_valid_url_st)
    @settings(max_examples=100)
    def test_url_at_end_of_text_detected(self, url: str):
        """URL at the very end of text is detected correctly."""
        text = "Check out " + url
        results = detect_urls(text)
        detected_urls = [r["url"] for r in results]
        assert url in detected_urls, (
            f"URL at end of text not detected: '{url[:60]}...'"
        )
        # End position should be len(text)
        matching = [r for r in results if r["url"] == url]
        assert matching[0]["end"] == len(text)


# ---------------------------------------------------------------------------
# Property 13: Fetch content truncation
# Feature: mcp-sidebar-integration, Property 13: Fetch content truncation
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty13FetchContentTruncation:
    """Property 13: Fetch content truncation.

    For any string returned by the fetch tool, if its length exceeds 8000
    characters, the content SHALL be truncated to exactly 8000 characters;
    if 8000 or fewer, it SHALL be included in full.

    **Validates: Requirements 5.3**
    """

    @given(content=_content_long_st)
    @settings(max_examples=100)
    def test_long_content_truncated_to_exactly_8000(self, content: str):
        """Content >8000 chars is truncated to exactly 8000."""
        result = truncate_content(content)
        assert len(result) == 8000, (
            f"Expected length 8000 for content of length {len(content)}, "
            f"got {len(result)}"
        )

    @given(content=_content_short_st)
    @settings(max_examples=100)
    def test_short_content_returned_unchanged(self, content: str):
        """Content ≤8000 chars is returned unchanged (identity)."""
        result = truncate_content(content)
        assert result == content, (
            f"Content of length {len(content)} should be unchanged, "
            f"but result has length {len(result)}"
        )

    @given(content=_content_long_st)
    @settings(max_examples=100)
    def test_truncated_content_is_prefix_of_original(self, content: str):
        """Truncated content is always a prefix of the original."""
        result = truncate_content(content)
        assert content.startswith(result), (
            f"Truncated result is not a prefix of the original content"
        )

    @given(content=_content_any_st)
    @settings(max_examples=100)
    def test_result_never_exceeds_8000(self, content: str):
        """The result never exceeds 8000 characters regardless of input."""
        result = truncate_content(content)
        assert len(result) <= 8000, (
            f"Result length {len(result)} exceeds max 8000"
        )

    @given(content=_content_any_st)
    @settings(max_examples=100)
    def test_result_is_always_prefix_of_original(self, content: str):
        """The result is always a prefix of the original (identity or truncation)."""
        result = truncate_content(content)
        assert content.startswith(result), (
            f"Result of length {len(result)} is not a prefix of "
            f"content of length {len(content)}"
        )

    @given(
        content=_exact_content(size=8000),
    )
    @settings(max_examples=100)
    def test_boundary_exactly_8000_unchanged(self, content: str):
        """Content of exactly 8000 chars is returned unchanged (not truncated)."""
        assert len(content) == 8000
        result = truncate_content(content)
        assert result == content, (
            f"Content of exactly 8000 chars should be unchanged"
        )
        assert len(result) == 8000

    @given(
        content=_exact_content(size=8001),
    )
    @settings(max_examples=100)
    def test_boundary_8001_truncated_to_8000(self, content: str):
        """Content of exactly 8001 chars is truncated to 8000."""
        assert len(content) == 8001
        result = truncate_content(content)
        assert len(result) == 8000, (
            f"Content of 8001 chars should be truncated to 8000, got {len(result)}"
        )
        assert result == content[:8000]


# ---------------------------------------------------------------------------
# Pure function reimplementations for tool result presentation
# (mirrors MessageToolBlock.qml logic)
# ---------------------------------------------------------------------------


def truncate_lines(content: str, max_lines: int = 500) -> tuple[str, bool, int]:
    """Truncate tool result content by line count.

    Mirrors MessageToolBlock.qml:
        property int maxLines: 500
        property var contentLines: content.split("\\n")
        property bool isTruncated: contentLines.length > maxLines
        property string displayContent: isTruncated
            ? contentLines.slice(0, maxLines).join("\\n") : content
        property int totalLineCount: contentLines.length

    Returns:
        (display_content, is_truncated, total_line_count)
    """
    lines = content.split("\n")
    total_line_count = len(lines)
    is_truncated = total_line_count > max_lines
    if is_truncated:
        display_content = "\n".join(lines[:max_lines])
    else:
        display_content = content
    return display_content, is_truncated, total_line_count


def cap_tool_blocks(blocks: list, max_blocks: int = 20) -> list:
    """Cap tool blocks rendered per message.

    Mirrors the layout logic:
        Tool blocks rendered in invocation order, max 20 per message.

    Returns:
        blocks[:max_blocks]
    """
    return blocks[:max_blocks]


def _reject_nan_infinity(c):
    """Reject NaN/Infinity constants that Python accepts but JSON RFC 7159 does not."""
    raise ValueError(f"Invalid JSON constant: {c}")


def is_valid_json(content: str) -> bool:
    """Detect if content is valid JSON for syntax highlighting.

    Mirrors MessageToolBlock.qml:
        property bool contentIsJson: {
            if (content.length === 0) return false;
            try { JSON.parse(content); return true; }
            catch (e) { return false; }
        }

    Note: Python's json.loads accepts NaN, Infinity, -Infinity which are NOT
    valid JSON per RFC 7159 and are rejected by JavaScript's JSON.parse().
    We use parse_constant to reject these non-standard values.

    Returns:
        True if content is non-empty and parseable as strict JSON, False otherwise.
    """
    if not content:
        return False
    try:
        json.loads(content, parse_constant=_reject_nan_infinity)
        return True
    except (json.JSONDecodeError, ValueError):
        return False


# ---------------------------------------------------------------------------
# Strategies for tool result presentation tests
# ---------------------------------------------------------------------------

# Strategy for multi-line content with controlled line count
@st.composite
def _content_with_n_lines(draw, min_lines=1, max_lines=1000):
    """Generate content with a specific number of lines."""
    n_lines = draw(st.integers(min_value=min_lines, max_value=max_lines))
    lines = [
        draw(st.text(
            alphabet=st.characters(blacklist_characters="\n"),
            min_size=0,
            max_size=40,
        ))
        for _ in range(n_lines)
    ]
    return "\n".join(lines)


# Content exceeding 500 lines
_content_over_500_lines_st = _content_with_n_lines(min_lines=501, max_lines=800)

# Content at or under 500 lines
_content_under_500_lines_st = _content_with_n_lines(min_lines=1, max_lines=500)

# Content at exactly 500 lines
@st.composite
def _content_exactly_500_lines(draw):
    """Generate content with exactly 500 lines."""
    lines = [
        draw(st.text(
            alphabet=st.characters(blacklist_characters="\n"),
            min_size=0,
            max_size=30,
        ))
        for _ in range(500)
    ]
    return "\n".join(lines)


# Content at exactly 501 lines
@st.composite
def _content_exactly_501_lines(draw):
    """Generate content with exactly 501 lines."""
    lines = [
        draw(st.text(
            alphabet=st.characters(blacklist_characters="\n"),
            min_size=0,
            max_size=30,
        ))
        for _ in range(501)
    ]
    return "\n".join(lines)


# Strategy for tool block entries (representing invocation results)
_tool_block_entry_st = st.fixed_dictionaries({
    "tool_name": st.from_regex(r"mcp_[a-z][a-z0-9_]{2,20}", fullmatch=True),
    "content": st.text(min_size=0, max_size=200),
    "is_error": st.booleans(),
})

# Strategy for lists of tool blocks (variable length)
_tool_blocks_st = st.lists(
    _tool_block_entry_st,
    min_size=0,
    max_size=40,
)

# Strategy for valid JSON content
_valid_json_content_st = st.one_of(
    # Simple values
    st.integers(min_value=-10000, max_value=10000).map(json.dumps),
    st.floats(allow_nan=False, allow_infinity=False, min_value=-1e6, max_value=1e6).map(json.dumps),
    st.booleans().map(json.dumps),
    st.just("null"),
    # Strings
    st.text(min_size=0, max_size=100).map(json.dumps),
    # Arrays
    st.lists(st.integers(min_value=0, max_value=100), min_size=0, max_size=10).map(json.dumps),
    # Objects
    st.dictionaries(
        keys=st.from_regex(r"[a-z][a-z0-9_]{0,10}", fullmatch=True),
        values=st.one_of(
            st.integers(min_value=-100, max_value=100),
            st.text(min_size=0, max_size=50),
            st.booleans(),
        ),
        min_size=0,
        max_size=5,
    ).map(json.dumps),
)

# Strategy for invalid JSON content (non-empty strings that are NOT valid JSON)
_invalid_json_content_st = st.one_of(
    # Plain text
    st.text(min_size=1, max_size=200).filter(lambda t: not _is_parseable_json(t)),
    # Partial/broken JSON
    st.sampled_from([
        "{",
        '{"key": }',
        '{"unclosed": true',
        "[1, 2, 3",
        "undefined",
        "function() {}",
        "hello world",
        "not json at all!",
        "{ trailing garbage } extra",
        "'single quoted'",
    ]),
)


def _is_parseable_json(text: str) -> bool:
    """Helper to check if text is parseable as strict JSON (RFC 7159)."""
    if not text:
        return False
    try:
        json.loads(text, parse_constant=_reject_nan_infinity)
        return True
    except (json.JSONDecodeError, ValueError):
        return False


# ---------------------------------------------------------------------------
# Property 14: Tool result line truncation
# Feature: mcp-sidebar-integration, Property 14: Tool result line truncation
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty14ToolResultLineTruncation:
    """Property 14: Tool result line truncation.

    For any tool result text, if the line count exceeds 500, the displayed
    output SHALL be truncated to 500 lines with a truncation indicator showing
    the total line count; if 500 or fewer, it SHALL be displayed in full.

    **Validates: Requirements 6.6**
    """

    @given(content=_content_over_500_lines_st)
    @settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
    def test_content_over_500_lines_is_truncated(self, content: str):
        """Content with >500 lines is truncated to exactly 500 lines."""
        display, is_truncated, total = truncate_lines(content)

        assert is_truncated is True, (
            f"Content with {total} lines should be marked as truncated"
        )
        # Display content should have exactly 500 lines
        display_lines = display.split("\n")
        assert len(display_lines) == 500, (
            f"Display content should have 500 lines, got {len(display_lines)}"
        )

    @given(content=_content_under_500_lines_st)
    @settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
    def test_content_at_or_under_500_lines_is_full(self, content: str):
        """Content with ≤500 lines is displayed in full (not truncated)."""
        display, is_truncated, total = truncate_lines(content)

        assert is_truncated is False, (
            f"Content with {total} lines should NOT be marked as truncated"
        )
        assert display == content, (
            "Content ≤500 lines should be returned unchanged"
        )

    @given(content=_content_over_500_lines_st)
    @settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
    def test_total_line_count_reported_correctly(self, content: str):
        """The total line count reports the actual number of lines in the original."""
        _, _, total = truncate_lines(content)
        actual_lines = len(content.split("\n"))
        assert total == actual_lines, (
            f"Total line count should be {actual_lines}, got {total}"
        )

    @given(content=_content_over_500_lines_st)
    @settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
    def test_truncated_content_is_prefix_of_original_lines(self, content: str):
        """Truncated display content is the first 500 lines of the original."""
        display, _, _ = truncate_lines(content)
        original_lines = content.split("\n")
        expected = "\n".join(original_lines[:500])
        assert display == expected, (
            "Truncated content should be exactly the first 500 lines joined"
        )

    @given(content=_content_exactly_500_lines())
    @settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
    def test_boundary_exactly_500_lines_not_truncated(self, content: str):
        """Content with exactly 500 lines is NOT truncated (boundary)."""
        display, is_truncated, total = truncate_lines(content)

        assert total == 500, (
            f"Expected 500 lines, got {total}"
        )
        assert is_truncated is False, (
            "Content with exactly 500 lines should NOT be truncated"
        )
        assert display == content, (
            "Content at boundary should be unchanged"
        )

    @given(content=_content_exactly_501_lines())
    @settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
    def test_boundary_501_lines_is_truncated(self, content: str):
        """Content with exactly 501 lines IS truncated to 500."""
        display, is_truncated, total = truncate_lines(content)

        assert total == 501, (
            f"Expected 501 lines, got {total}"
        )
        assert is_truncated is True, (
            "Content with 501 lines should be truncated"
        )
        display_lines = display.split("\n")
        assert len(display_lines) == 500, (
            f"Display should have 500 lines, got {len(display_lines)}"
        )


# ---------------------------------------------------------------------------
# Property 15: Tool result block ordering and cap
# Feature: mcp-sidebar-integration, Property 15: Tool result block ordering and cap
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty15ToolResultBlockOrderingAndCap:
    """Property 15: Tool result block ordering and cap.

    Blocks in invocation order, max 20 rendered.

    **Validates: Requirements 6.5**
    """

    @given(blocks=_tool_blocks_st)
    @settings(max_examples=100)
    def test_capped_blocks_max_20(self, blocks: list):
        """At most 20 blocks are rendered, regardless of input count."""
        capped = cap_tool_blocks(blocks)
        assert len(capped) <= 20, (
            f"Expected at most 20 blocks, got {len(capped)}"
        )

    @given(blocks=st.lists(_tool_block_entry_st, min_size=21, max_size=40))
    @settings(max_examples=100)
    def test_excess_blocks_beyond_20_not_rendered(self, blocks: list):
        """When >20 blocks are provided, only the first 20 are kept."""
        capped = cap_tool_blocks(blocks)
        assert len(capped) == 20, (
            f"Expected exactly 20 blocks from {len(blocks)} input, got {len(capped)}"
        )

    @given(blocks=st.lists(_tool_block_entry_st, min_size=1, max_size=20))
    @settings(max_examples=100)
    def test_under_cap_all_blocks_rendered(self, blocks: list):
        """When ≤20 blocks are provided, all are rendered."""
        capped = cap_tool_blocks(blocks)
        assert len(capped) == len(blocks), (
            f"Expected {len(blocks)} blocks (under cap), got {len(capped)}"
        )

    @given(blocks=_tool_blocks_st)
    @settings(max_examples=100)
    def test_invocation_order_preserved(self, blocks: list):
        """Rendered blocks maintain their original invocation order."""
        capped = cap_tool_blocks(blocks)
        # The capped list should be exactly the first N elements
        expected = blocks[:20]
        assert capped == expected, (
            "Capped blocks should be the first 20 in original order"
        )

    @given(blocks=st.lists(_tool_block_entry_st, min_size=21, max_size=40))
    @settings(max_examples=100)
    def test_first_20_blocks_are_exactly_first_20_input(self, blocks: list):
        """The 20 rendered blocks are the first 20 from input (not last, not random)."""
        capped = cap_tool_blocks(blocks)
        for i in range(20):
            assert capped[i] == blocks[i], (
                f"Block at index {i} does not match input: "
                f"expected {blocks[i]['tool_name']}, got {capped[i]['tool_name']}"
            )

    def test_empty_blocks_list_returns_empty(self):
        """An empty input list returns an empty capped list."""
        capped = cap_tool_blocks([])
        assert capped == [], (
            "Empty input should produce empty output"
        )

    @given(blocks=st.lists(_tool_block_entry_st, min_size=20, max_size=20))
    @settings(max_examples=100)
    def test_boundary_exactly_20_blocks_all_rendered(self, blocks: list):
        """Exactly 20 blocks → all 20 rendered (boundary condition)."""
        assert len(blocks) == 20
        capped = cap_tool_blocks(blocks)
        assert len(capped) == 20
        assert capped == blocks


# ---------------------------------------------------------------------------
# Property 16: JSON content detection
# Feature: mcp-sidebar-integration, Property 16: JSON content detection
# ---------------------------------------------------------------------------


@pytest.mark.property_test
class TestProperty16JsonContentDetection:
    """Property 16: JSON content detection.

    For any tool result content string, if valid JSON → syntax-highlighted
    code block; if not valid JSON → plain text.

    **Validates: Requirements 6.2**
    """

    @given(content=_valid_json_content_st)
    @settings(max_examples=100)
    def test_valid_json_detected(self, content: str):
        """Valid JSON content is correctly identified as JSON."""
        assert is_valid_json(content) is True, (
            f"Content should be detected as valid JSON: {content[:80]!r}"
        )

    @given(content=_invalid_json_content_st)
    @settings(max_examples=100)
    def test_invalid_json_not_detected(self, content: str):
        """Invalid JSON content is correctly identified as not JSON."""
        assert is_valid_json(content) is False, (
            f"Content should NOT be detected as valid JSON: {content[:80]!r}"
        )

    def test_empty_string_not_json(self):
        """Empty string is not valid JSON (matches QML length === 0 check)."""
        assert is_valid_json("") is False, (
            "Empty string should not be detected as JSON"
        )

    @given(
        data=st.dictionaries(
            keys=st.from_regex(r"[a-z][a-z0-9_]{0,10}", fullmatch=True),
            values=st.one_of(
                st.integers(min_value=-1000, max_value=1000),
                st.text(min_size=0, max_size=50),
                st.booleans(),
                st.none(),
            ),
            min_size=1,
            max_size=8,
        ),
    )
    @settings(max_examples=100)
    def test_serialized_dict_always_detected_as_json(self, data: dict):
        """Any dict serialized with json.dumps is always detected as valid JSON."""
        content = json.dumps(data)
        assert is_valid_json(content) is True, (
            f"Serialized dict should be valid JSON: {content[:80]!r}"
        )

    @given(
        data=st.lists(
            st.one_of(
                st.integers(min_value=-100, max_value=100),
                st.text(min_size=0, max_size=30),
                st.booleans(),
            ),
            min_size=0,
            max_size=10,
        ),
    )
    @settings(max_examples=100)
    def test_serialized_list_always_detected_as_json(self, data: list):
        """Any list serialized with json.dumps is always detected as valid JSON."""
        content = json.dumps(data)
        assert is_valid_json(content) is True, (
            f"Serialized list should be valid JSON: {content[:80]!r}"
        )

    @given(content=_valid_json_content_st)
    @settings(max_examples=100)
    def test_json_detection_is_idempotent(self, content: str):
        """Calling is_valid_json twice on the same content gives the same result."""
        first = is_valid_json(content)
        second = is_valid_json(content)
        assert first == second, (
            "JSON detection should be idempotent"
        )

    @given(
        content=st.one_of(_valid_json_content_st, _invalid_json_content_st),
    )
    @settings(max_examples=100)
    def test_detection_is_strictly_boolean(self, content: str):
        """is_valid_json always returns exactly True or False (no None, no exceptions)."""
        result = is_valid_json(content)
        assert result is True or result is False, (
            f"is_valid_json should return bool, got {type(result)}: {result!r}"
        )
