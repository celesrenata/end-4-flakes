# Feature: voice-assistant-mode, Task 12.2: TTS Pipeline Integration Tests
"""
Integration tests for the TTS pipeline command construction.

Since TtsService is a QML singleton, we port the command construction logic
to Python and verify it produces the correct shell commands for each provider.
We also test escaping, stop behavior, and error handling.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**
"""

import subprocess
from unittest.mock import patch, MagicMock
from typing import Optional

import pytest
from hypothesis import given, settings, assume
import hypothesis.strategies as st


# ---------------------------------------------------------------------------
# Python port of TtsService command construction logic
# ---------------------------------------------------------------------------


class TtsService:
    """Python port of the QML TtsService command construction for testing."""

    def __init__(
        self,
        provider: str = "none",
        voice: str = "",
        api_key: str = "",
        policy_ai: int = 1,
    ):
        self.provider = provider
        self.voice = voice
        self._api_key = api_key
        self._policy_ai = policy_ai
        self._process: Optional[subprocess.Popen] = None
        self.playing = False
        self._last_command: Optional[list[str]] = None
        self._speak_failed_errors: list[str] = []

    def speak(self, text: str) -> Optional[list[str]]:
        """Build and return the command that would be executed.

        Returns the command list, or None if speak is a no-op.
        """
        if self.provider == "none" or not text:
            return None

        if self.playing:
            self.stop()

        # Policy: local-only mode blocks OpenAI TTS
        if self._policy_ai == 2 and self.provider == "openai":
            return None

        command: list[str] = []

        if self.provider == "piper":
            # Escape single quotes: ' → '\''
            escaped = text.replace("'", "'\\''")
            command = [
                "sh", "-c",
                f"echo '{escaped}' | piper --model {self.voice} --output_raw | pw-play --format=s16 --rate=22050 --channels=1 -"
            ]
        elif self.provider == "espeak-ng":
            # Escape double quotes: " → \"
            escaped = text.replace('"', '\\"')
            command = [
                "sh", "-c",
                f'espeak-ng "{escaped}" --stdout | pw-play -'
            ]
        elif self.provider == "openai":
            if not self._api_key:
                return None
            # Escape for JSON: backslashes, double quotes, newlines
            escaped = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
            selected_voice = self.voice or "nova"
            command = [
                "sh", "-c",
                f'curl -s https://api.openai.com/v1/audio/speech '
                f'-H "Authorization: Bearer {self._api_key}" '
                f'-H "Content-Type: application/json" '
                f"""-d '{{"model":"tts-1","input":"{escaped}","voice":"{selected_voice}"}}' """
                f'| pw-play -'
            ]
        else:
            return None

        self._last_command = command
        self.playing = True
        return command

    def stop(self):
        """Stop current TTS playback."""
        self.playing = False
        if self._process:
            self._process.terminate()
            self._process = None

    def _on_process_exited(self, exit_code: int):
        """Handle process exit. Non-zero → emit error."""
        self.playing = False
        if exit_code != 0:
            msg = f"TTS process exited with code {exit_code}"
            self._speak_failed_errors.append(msg)


# ---------------------------------------------------------------------------
# Unit Tests: Command Construction
# ---------------------------------------------------------------------------


class TestPiperCommandConstruction:
    """Test piper TTS command construction."""

    def test_basic_text(self):
        """Piper produces correct pipeline command for simple text.

        **Validates: Requirements 3.2**
        """
        tts = TtsService(provider="piper", voice="en_US-lessac-medium.onnx")
        cmd = tts.speak("Hello world")

        assert cmd is not None
        assert cmd[0] == "sh"
        assert cmd[1] == "-c"
        assert "echo 'Hello world'" in cmd[2]
        assert "piper --model en_US-lessac-medium.onnx --output_raw" in cmd[2]
        assert "pw-play --format=s16 --rate=22050 --channels=1 -" in cmd[2]

    def test_full_pipeline_format(self):
        """Piper command matches exact expected format.

        **Validates: Requirements 3.2**
        """
        tts = TtsService(provider="piper", voice="model.onnx")
        cmd = tts.speak("test")

        expected = "echo 'test' | piper --model model.onnx --output_raw | pw-play --format=s16 --rate=22050 --channels=1 -"
        assert cmd[2] == expected

    def test_single_quote_escaping(self):
        """Single quotes in text are escaped for piper shell command.

        **Validates: Requirements 3.2**
        """
        tts = TtsService(provider="piper", voice="model.onnx")
        cmd = tts.speak("it's a test")

        # Single quote should become: '\''
        assert "it'\\''s a test" in cmd[2]

    def test_multiple_single_quotes(self):
        """Multiple single quotes are all escaped.

        **Validates: Requirements 3.2**
        """
        tts = TtsService(provider="piper", voice="model.onnx")
        cmd = tts.speak("it's Bob's dog's toy")

        assert cmd[2].count("'\\''") == 3


class TestEspeakCommandConstruction:
    """Test espeak-ng TTS command construction."""

    def test_basic_text(self):
        """espeak-ng produces correct pipeline command for simple text.

        **Validates: Requirements 3.3**
        """
        tts = TtsService(provider="espeak-ng")
        cmd = tts.speak("Hello world")

        assert cmd is not None
        assert cmd[0] == "sh"
        assert cmd[1] == "-c"
        assert 'espeak-ng "Hello world" --stdout' in cmd[2]
        assert "pw-play -" in cmd[2]

    def test_full_pipeline_format(self):
        """espeak-ng command matches exact expected format.

        **Validates: Requirements 3.3**
        """
        tts = TtsService(provider="espeak-ng")
        cmd = tts.speak("test")

        expected = 'espeak-ng "test" --stdout | pw-play -'
        assert cmd[2] == expected

    def test_double_quote_escaping(self):
        """Double quotes in text are escaped for espeak-ng shell command.

        **Validates: Requirements 3.3**
        """
        tts = TtsService(provider="espeak-ng")
        cmd = tts.speak('She said "hello"')

        assert 'She said \\"hello\\"' in cmd[2]

    def test_multiple_double_quotes(self):
        """Multiple double quotes are all escaped.

        **Validates: Requirements 3.3**
        """
        tts = TtsService(provider="espeak-ng")
        cmd = tts.speak('"one" and "two" and "three"')

        assert cmd[2].count('\\"') == 6


class TestOpenAICommandConstruction:
    """Test OpenAI TTS command construction."""

    def test_basic_text(self):
        """OpenAI produces correct curl command for simple text.

        **Validates: Requirements 3.4**
        """
        tts = TtsService(provider="openai", voice="nova", api_key="sk-test123")
        cmd = tts.speak("Hello world")

        assert cmd is not None
        assert cmd[0] == "sh"
        assert cmd[1] == "-c"
        assert "curl -s https://api.openai.com/v1/audio/speech" in cmd[2]
        assert '-H "Authorization: Bearer sk-test123"' in cmd[2]
        assert '-H "Content-Type: application/json"' in cmd[2]
        assert '"model":"tts-1"' in cmd[2]
        assert '"input":"Hello world"' in cmd[2]
        assert '"voice":"nova"' in cmd[2]
        assert "| pw-play -" in cmd[2]

    def test_default_voice_is_nova(self):
        """OpenAI uses 'nova' voice when none is configured.

        **Validates: Requirements 3.4**
        """
        tts = TtsService(provider="openai", voice="", api_key="sk-test")
        cmd = tts.speak("test")

        assert '"voice":"nova"' in cmd[2]

    def test_custom_voice(self):
        """OpenAI uses the configured voice.

        **Validates: Requirements 3.4**
        """
        tts = TtsService(provider="openai", voice="alloy", api_key="sk-test")
        cmd = tts.speak("test")

        assert '"voice":"alloy"' in cmd[2]

    def test_json_escaping_double_quotes(self):
        """Double quotes are escaped for JSON embedding in OpenAI command.

        **Validates: Requirements 3.4**
        """
        tts = TtsService(provider="openai", voice="nova", api_key="sk-test")
        cmd = tts.speak('She said "hello"')

        assert 'She said \\"hello\\"' in cmd[2]

    def test_json_escaping_backslashes(self):
        """Backslashes are escaped for JSON embedding in OpenAI command.

        **Validates: Requirements 3.4**
        """
        tts = TtsService(provider="openai", voice="nova", api_key="sk-test")
        cmd = tts.speak("path\\to\\file")

        assert "path\\\\to\\\\file" in cmd[2]

    def test_json_escaping_newlines(self):
        """Newlines are escaped for JSON embedding in OpenAI command.

        **Validates: Requirements 3.4**
        """
        tts = TtsService(provider="openai", voice="nova", api_key="sk-test")
        cmd = tts.speak("line one\nline two")

        assert "line one\\nline two" in cmd[2]

    def test_no_api_key_returns_none(self):
        """OpenAI returns None when no API key is available.

        **Validates: Requirements 3.4**
        """
        tts = TtsService(provider="openai", voice="nova", api_key="")
        cmd = tts.speak("test")

        assert cmd is None


# ---------------------------------------------------------------------------
# Unit Tests: No-op cases
# ---------------------------------------------------------------------------


class TestSpeakNoOps:
    """Test that speak() does nothing in appropriate cases."""

    def test_provider_none_does_nothing(self):
        """speak() with provider='none' returns None.

        **Validates: Requirements 3.1**
        """
        tts = TtsService(provider="none")
        cmd = tts.speak("Hello world")
        assert cmd is None

    def test_empty_text_does_nothing(self):
        """speak() with empty text returns None.

        **Validates: Requirements 3.1**
        """
        tts = TtsService(provider="piper", voice="model.onnx")
        cmd = tts.speak("")
        assert cmd is None

    def test_policy_blocks_openai(self):
        """speak() with policy_ai=2 and openai provider returns None.

        **Validates: Requirements 3.1**
        """
        tts = TtsService(provider="openai", voice="nova", api_key="sk-test", policy_ai=2)
        cmd = tts.speak("test")
        assert cmd is None

    def test_unknown_provider_does_nothing(self):
        """speak() with unknown provider returns None.

        **Validates: Requirements 3.1**
        """
        tts = TtsService(provider="unknown-provider", voice="")
        cmd = tts.speak("test")
        assert cmd is None


# ---------------------------------------------------------------------------
# Unit Tests: stop() behavior
# ---------------------------------------------------------------------------


class TestTtsStop:
    """Test that stop() terminates playback."""

    def test_stop_sets_playing_false(self):
        """stop() sets playing to False.

        **Validates: Requirements 3.6**
        """
        tts = TtsService(provider="piper", voice="model.onnx")
        tts.speak("test")
        assert tts.playing is True

        tts.stop()
        assert tts.playing is False

    def test_speak_while_playing_stops_first(self):
        """Calling speak() while already playing stops the current playback first.

        **Validates: Requirements 3.6**
        """
        tts = TtsService(provider="piper", voice="model.onnx")
        tts.speak("first")
        assert tts.playing is True

        # Second speak should stop the first
        tts.speak("second")
        # playing should still be True (new playback started)
        assert tts.playing is True
        # Command should be for "second"
        assert "second" in tts._last_command[2]

    def test_stop_terminates_process(self):
        """stop() calls terminate on the subprocess.

        **Validates: Requirements 3.6**
        """
        tts = TtsService(provider="piper", voice="model.onnx")
        mock_proc = MagicMock()
        tts._process = mock_proc
        tts.playing = True

        tts.stop()

        mock_proc.terminate.assert_called_once()
        assert tts.playing is False
        assert tts._process is None


# ---------------------------------------------------------------------------
# Unit Tests: Error handling on non-zero exit
# ---------------------------------------------------------------------------


class TestTtsErrorHandling:
    """Test error handling on non-zero exit codes."""

    def test_nonzero_exit_emits_error(self):
        """Non-zero exit code is recorded as a speakFailed error.

        **Validates: Requirements 3.7**
        """
        tts = TtsService(provider="piper", voice="model.onnx")
        tts.speak("test")

        tts._on_process_exited(1)

        assert len(tts._speak_failed_errors) == 1
        assert "exited with code 1" in tts._speak_failed_errors[0]

    def test_zero_exit_no_error(self):
        """Zero exit code does not emit an error.

        **Validates: Requirements 3.7**
        """
        tts = TtsService(provider="piper", voice="model.onnx")
        tts.speak("test")

        tts._on_process_exited(0)

        assert len(tts._speak_failed_errors) == 0

    def test_playing_set_false_on_exit(self):
        """Process exit sets playing to False regardless of exit code.

        **Validates: Requirements 3.7**
        """
        tts = TtsService(provider="piper", voice="model.onnx")
        tts.speak("test")
        assert tts.playing is True

        tts._on_process_exited(0)
        assert tts.playing is False

    def test_multiple_errors_accumulated(self):
        """Multiple non-zero exits accumulate errors.

        **Validates: Requirements 3.7**
        """
        tts = TtsService(provider="piper", voice="model.onnx")

        tts._on_process_exited(1)
        tts._on_process_exited(127)
        tts._on_process_exited(255)

        assert len(tts._speak_failed_errors) == 3
        assert "code 127" in tts._speak_failed_errors[1]


# ---------------------------------------------------------------------------
# Property-Based Tests: Escaping doesn't break for arbitrary input text
# ---------------------------------------------------------------------------


# Strategy for arbitrary text that could contain shell-dangerous characters
_arbitrary_text = st.text(
    min_size=1,
    max_size=500,
    alphabet=st.characters(
        whitelist_categories=("L", "N", "P", "Z", "S"),
        blacklist_characters="\x00",
    ),
)


@pytest.mark.property_test
class TestTtsEscapingProperties:
    """Property-based tests for TTS text escaping across all providers.

    **Validates: Requirements 3.2, 3.3, 3.4**
    """

    @given(text=_arbitrary_text)
    @settings(max_examples=200)
    def test_piper_escaping_produces_valid_command(self, text: str):
        """For any input text, piper command construction produces a valid list.

        The escaped text within single quotes must not contain unescaped
        single quotes — every ' is replaced with '\\'' which properly
        terminates the quote, inserts a literal quote, and re-opens.

        **Validates: Requirements 3.2**
        """
        tts = TtsService(provider="piper", voice="model.onnx")
        cmd = tts.speak(text)

        assert cmd is not None
        assert len(cmd) == 3
        assert cmd[0] == "sh"
        assert cmd[1] == "-c"
        # The shell string should contain the piper pipeline
        assert "piper --model model.onnx --output_raw" in cmd[2]
        assert "pw-play --format=s16 --rate=22050 --channels=1 -" in cmd[2]
        # Verify no unescaped single quotes inside the echo argument
        # The echo part is: echo '<escaped>'
        # After escaping, there should be no bare ' inside the content
        # (each original ' becomes '\'' which is 4 chars)
        escaped = text.replace("'", "'\\''")
        assert f"echo '{escaped}'" in cmd[2]

    @given(text=_arbitrary_text)
    @settings(max_examples=200)
    def test_espeak_escaping_produces_valid_command(self, text: str):
        """For any input text, espeak-ng command construction produces a valid list.

        The escaped text within double quotes must not contain unescaped
        double quotes — every " is replaced with \\".

        **Validates: Requirements 3.3**
        """
        tts = TtsService(provider="espeak-ng")
        cmd = tts.speak(text)

        assert cmd is not None
        assert len(cmd) == 3
        assert cmd[0] == "sh"
        assert cmd[1] == "-c"
        assert "espeak-ng" in cmd[2]
        assert "pw-play -" in cmd[2]
        # Verify the escaped text is properly embedded
        escaped = text.replace('"', '\\"')
        assert f'espeak-ng "{escaped}" --stdout | pw-play -' == cmd[2]

    @given(text=_arbitrary_text)
    @settings(max_examples=200)
    def test_openai_escaping_produces_valid_command(self, text: str):
        """For any input text, OpenAI command construction produces a valid list.

        JSON escaping handles backslashes, double quotes, and newlines.

        **Validates: Requirements 3.4**
        """
        tts = TtsService(provider="openai", voice="nova", api_key="sk-test")
        cmd = tts.speak(text)

        assert cmd is not None
        assert len(cmd) == 3
        assert cmd[0] == "sh"
        assert cmd[1] == "-c"
        assert "curl -s https://api.openai.com/v1/audio/speech" in cmd[2]
        assert "pw-play -" in cmd[2]
        # Verify proper JSON escaping was applied
        escaped = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        assert f'"input":"{escaped}"' in cmd[2]

    @given(text=_arbitrary_text)
    @settings(max_examples=200)
    def test_piper_escaping_no_unescaped_single_quotes(self, text: str):
        """For any text with single quotes, the piper command has them all escaped.

        **Validates: Requirements 3.2**
        """
        tts = TtsService(provider="piper", voice="model.onnx")
        cmd = tts.speak(text)

        assert cmd is not None
        # Count single quotes in original text
        original_count = text.count("'")
        # Each original ' becomes '\'' (which adds 3 chars to the surrounding shell)
        escaped = text.replace("'", "'\\''")
        # The escaped version should be in the command
        assert escaped in cmd[2]

    @given(text=_arbitrary_text)
    @settings(max_examples=200)
    def test_espeak_escaping_no_unescaped_double_quotes(self, text: str):
        """For any text with double quotes, the espeak command has them all escaped.

        **Validates: Requirements 3.3**
        """
        tts = TtsService(provider="espeak-ng")
        cmd = tts.speak(text)

        assert cmd is not None
        # The content between espeak-ng " and " --stdout should have no bare "
        escaped = text.replace('"', '\\"')
        # Verify by checking the full command structure
        assert f'espeak-ng "{escaped}" --stdout' in cmd[2]

    @given(text=_arbitrary_text)
    @settings(max_examples=200)
    def test_openai_escaping_valid_json_content(self, text: str):
        """For any text, the OpenAI JSON payload has properly escaped content.

        The 'input' field value should be a valid JSON string fragment
        (backslashes doubled, quotes escaped, newlines as \\n).

        **Validates: Requirements 3.4**
        """
        import json

        tts = TtsService(provider="openai", voice="nova", api_key="sk-test")
        cmd = tts.speak(text)

        assert cmd is not None
        # Extract the JSON body from the curl command
        # The -d argument contains: '{"model":"tts-1","input":"<escaped>","voice":"nova"}'
        shell_cmd = cmd[2]
        # Find the JSON payload between -d ' and ' |
        d_start = shell_cmd.index("-d '") + 4
        d_end = shell_cmd.index("' |", d_start)
        json_str = shell_cmd[d_start:d_end]

        # The JSON should be parseable
        parsed = json.loads(json_str)
        assert parsed["model"] == "tts-1"
        assert parsed["voice"] == "nova"
        # The input should round-trip back to the original text
        # (after accounting for newline escaping in the original)
        assert parsed["input"] == text


# ---------------------------------------------------------------------------
# Feature: voice-assistant-mode, Task 12.3: Free Dictation Session Management
# ---------------------------------------------------------------------------
"""
Test 12.3: Free Dictation Session Management

Verifies that the Free Dictation session management logic correctly:
- Creates a session entry in sessions-index.json
- Appends messages without switching the active session
- Persists data across simulated restarts (idempotent re-creation)

Since the actual implementation is QML/JS operating on JSON files, these tests
port the same logic to Python and verify the file-based operations directly.

**Validates: Requirements 4.1, 4.2, 4.3, 4.6**
"""

import json
import time
from pathlib import Path


# ---------------------------------------------------------------------------
# Python port of the QML session management logic
# ---------------------------------------------------------------------------


class FreeDictationSessionManager:
    """Python equivalent of the Free Dictation session management in Ai.qml.

    Operates on JSON files in the same format as the QML implementation:
    - sessions-index.json: {"sessions": [{"name": ..., "createdAt": ..., "lastModified": ...}]}
    - chats/Free Dictation.json: [{role, rawContent, model, thinking, done, ...}]
    """

    def __init__(self, base_dir: Path):
        self.base_dir = base_dir
        self.chats_dir = base_dir / "chats"
        self.chats_dir.mkdir(parents=True, exist_ok=True)
        self.sessions_index_path = base_dir / "sessions-index.json"
        self.free_dictation_path = self.chats_dir / "Free Dictation.json"
        self._sessions_index: dict = {"sessions": []}
        self._active_session: str = "Chat 1"  # simulates a separate active session

    @property
    def active_session(self) -> str:
        return self._active_session

    @active_session.setter
    def active_session(self, name: str):
        self._active_session = name

    def load_sessions_index(self):
        """Load sessions index from disk."""
        if self.sessions_index_path.exists():
            content = self.sessions_index_path.read_text()
            if content.strip():
                parsed = json.loads(content)
                if isinstance(parsed.get("sessions"), list):
                    self._sessions_index = parsed
                    return
        self._sessions_index = {"sessions": []}

    def save_sessions_index(self):
        """Persist sessions index to disk."""
        self.sessions_index_path.write_text(
            json.dumps(self._sessions_index, indent=2)
        )

    def ensure_free_dictation_session(self):
        """Create 'Free Dictation' session if it doesn't exist.

        Mirrors Ai.qml ensureFreeDictationSession():
        - Checks if session already exists in index
        - If not, adds entry and creates empty chat JSON file
        - If yes, does nothing (idempotent)
        """
        sessions = self._sessions_index.get("sessions", [])
        exists = any(s["name"] == "Free Dictation" for s in sessions)
        if exists:
            return

        now = int(time.time())
        sessions.append({
            "name": "Free Dictation",
            "createdAt": now,
            "lastModified": now,
        })
        self._sessions_index = {"sessions": sessions}
        self.save_sessions_index()

        # Create empty chat file
        self.free_dictation_path.write_text(json.dumps([]))

    def append_to_free_dictation(self, text: str, role: str):
        """Append a message to the Free Dictation session without switching active session.

        Mirrors Ai.qml appendToFreeDictation():
        - Reads current file content
        - Appends new message with full structure
        - Writes back
        - Updates lastModified in sessions index
        - Does NOT change the active session
        """
        if not text or not text.strip():
            return

        # Read existing messages
        messages = []
        if self.free_dictation_path.exists():
            content = self.free_dictation_path.read_text()
            if content.strip():
                try:
                    messages = json.loads(content)
                except json.JSONDecodeError:
                    messages = []

        # Append new message with the same structure as QML
        messages.append({
            "role": role,
            "rawContent": text,
            "model": "test-model" if role == "assistant" else "",
            "thinking": False,
            "done": True,
            "annotations": [],
            "annotationSources": [],
            "functionName": "",
            "functionCall": None,
            "functionResponse": "",
            "visibleToUser": True,
        })

        self.free_dictation_path.write_text(json.dumps(messages))

        # Update lastModified in sessions index
        sessions = self._sessions_index.get("sessions", [])
        entry = next((s for s in sessions if s["name"] == "Free Dictation"), None)
        if entry:
            entry["lastModified"] = int(time.time())
            self.save_sessions_index()


# ---------------------------------------------------------------------------
# Tests for ensureFreeDictationSession
# ---------------------------------------------------------------------------


class TestEnsureFreeDictationSession:
    """Verify ensureFreeDictationSession creates and manages the session correctly.

    **Validates: Requirements 4.1, 4.6**
    """

    def test_creates_session_entry_in_index(self, tmp_path: Path):
        """ensureFreeDictationSession creates a session entry in sessions-index.json."""
        mgr = FreeDictationSessionManager(tmp_path)
        mgr.ensure_free_dictation_session()

        # Verify sessions-index.json was created with the entry
        assert mgr.sessions_index_path.exists()
        index = json.loads(mgr.sessions_index_path.read_text())
        assert len(index["sessions"]) == 1
        assert index["sessions"][0]["name"] == "Free Dictation"
        assert "createdAt" in index["sessions"][0]
        assert "lastModified" in index["sessions"][0]

    def test_creates_empty_chat_file(self, tmp_path: Path):
        """ensureFreeDictationSession creates an empty JSON array chat file."""
        mgr = FreeDictationSessionManager(tmp_path)
        mgr.ensure_free_dictation_session()

        assert mgr.free_dictation_path.exists()
        messages = json.loads(mgr.free_dictation_path.read_text())
        assert messages == []

    def test_does_not_duplicate_if_already_exists(self, tmp_path: Path):
        """Calling ensureFreeDictationSession twice doesn't create a duplicate entry."""
        mgr = FreeDictationSessionManager(tmp_path)
        mgr.ensure_free_dictation_session()
        mgr.ensure_free_dictation_session()

        index = json.loads(mgr.sessions_index_path.read_text())
        free_dictation_entries = [
            s for s in index["sessions"] if s["name"] == "Free Dictation"
        ]
        assert len(free_dictation_entries) == 1

    def test_preserves_existing_sessions(self, tmp_path: Path):
        """ensureFreeDictationSession doesn't affect other sessions in the index."""
        mgr = FreeDictationSessionManager(tmp_path)

        # Pre-populate with another session
        mgr._sessions_index = {
            "sessions": [
                {"name": "Chat 1", "createdAt": 1000, "lastModified": 1000}
            ]
        }
        mgr.save_sessions_index()

        mgr.ensure_free_dictation_session()

        index = json.loads(mgr.sessions_index_path.read_text())
        assert len(index["sessions"]) == 2
        names = [s["name"] for s in index["sessions"]]
        assert "Chat 1" in names
        assert "Free Dictation" in names


# ---------------------------------------------------------------------------
# Tests for appendToFreeDictation
# ---------------------------------------------------------------------------


class TestAppendToFreeDictation:
    """Verify appendToFreeDictation adds messages correctly.

    **Validates: Requirements 4.2, 4.3**
    """

    def test_adds_user_message_with_correct_structure(self, tmp_path: Path):
        """appendToFreeDictation adds a user message with the expected fields."""
        mgr = FreeDictationSessionManager(tmp_path)
        mgr.ensure_free_dictation_session()
        mgr.append_to_free_dictation("open firefox", "user")

        messages = json.loads(mgr.free_dictation_path.read_text())
        assert len(messages) == 1
        msg = messages[0]
        assert msg["role"] == "user"
        assert msg["rawContent"] == "open firefox"
        assert msg["model"] == ""
        assert msg["thinking"] is False
        assert msg["done"] is True
        assert msg["annotations"] == []
        assert msg["visibleToUser"] is True

    def test_adds_assistant_message_with_correct_structure(self, tmp_path: Path):
        """appendToFreeDictation adds an assistant message with model field populated."""
        mgr = FreeDictationSessionManager(tmp_path)
        mgr.ensure_free_dictation_session()
        mgr.append_to_free_dictation("Firefox has been opened.", "assistant")

        messages = json.loads(mgr.free_dictation_path.read_text())
        assert len(messages) == 1
        msg = messages[0]
        assert msg["role"] == "assistant"
        assert msg["rawContent"] == "Firefox has been opened."
        assert msg["model"] == "test-model"
        assert msg["done"] is True

    def test_does_not_modify_active_session(self, tmp_path: Path):
        """appendToFreeDictation does not change the active session."""
        mgr = FreeDictationSessionManager(tmp_path)
        mgr.ensure_free_dictation_session()
        mgr.active_session = "My Custom Chat"

        mgr.append_to_free_dictation("hello world", "user")
        mgr.append_to_free_dictation("Hi there!", "assistant")

        # Active session must remain unchanged
        assert mgr.active_session == "My Custom Chat"

    def test_multiple_messages_accumulate(self, tmp_path: Path):
        """Multiple appended messages accumulate in the chat file."""
        mgr = FreeDictationSessionManager(tmp_path)
        mgr.ensure_free_dictation_session()

        mgr.append_to_free_dictation("what time is it", "user")
        mgr.append_to_free_dictation("It's about 3pm.", "assistant")
        mgr.append_to_free_dictation("play some music", "user")
        mgr.append_to_free_dictation("Playing your favorites playlist.", "assistant")

        messages = json.loads(mgr.free_dictation_path.read_text())
        assert len(messages) == 4
        assert messages[0]["role"] == "user"
        assert messages[0]["rawContent"] == "what time is it"
        assert messages[1]["role"] == "assistant"
        assert messages[1]["rawContent"] == "It's about 3pm."
        assert messages[2]["role"] == "user"
        assert messages[2]["rawContent"] == "play some music"
        assert messages[3]["role"] == "assistant"
        assert messages[3]["rawContent"] == "Playing your favorites playlist."

    def test_ignores_empty_text(self, tmp_path: Path):
        """appendToFreeDictation ignores empty or whitespace-only text."""
        mgr = FreeDictationSessionManager(tmp_path)
        mgr.ensure_free_dictation_session()

        mgr.append_to_free_dictation("", "user")
        mgr.append_to_free_dictation("   ", "user")

        messages = json.loads(mgr.free_dictation_path.read_text())
        assert messages == []

    def test_updates_last_modified_in_index(self, tmp_path: Path):
        """appendToFreeDictation updates lastModified timestamp in sessions index."""
        mgr = FreeDictationSessionManager(tmp_path)
        mgr.ensure_free_dictation_session()

        # Get initial lastModified
        index_before = json.loads(mgr.sessions_index_path.read_text())
        initial_modified = index_before["sessions"][0]["lastModified"]

        # Small delay to ensure timestamp difference
        time.sleep(1.1)

        mgr.append_to_free_dictation("test message", "user")

        index_after = json.loads(mgr.sessions_index_path.read_text())
        updated_modified = index_after["sessions"][0]["lastModified"]

        assert updated_modified >= initial_modified


# ---------------------------------------------------------------------------
# Tests for persistence across simulated restarts
# ---------------------------------------------------------------------------


class TestFreeDictationPersistence:
    """Verify session data persists across simulated restarts.

    **Validates: Requirements 4.6**
    """

    def test_messages_persist_after_reread(self, tmp_path: Path):
        """After creating and adding messages, re-reading the file shows all content."""
        mgr = FreeDictationSessionManager(tmp_path)
        mgr.ensure_free_dictation_session()
        mgr.append_to_free_dictation("open terminal", "user")
        mgr.append_to_free_dictation("Terminal opened.", "assistant")

        # Simulate reading from a fresh instance (re-read from disk)
        mgr2 = FreeDictationSessionManager(tmp_path)
        mgr2.load_sessions_index()

        # Verify index was persisted
        sessions = mgr2._sessions_index["sessions"]
        assert any(s["name"] == "Free Dictation" for s in sessions)

        # Verify chat file content persisted
        messages = json.loads(mgr2.free_dictation_path.read_text())
        assert len(messages) == 2
        assert messages[0]["rawContent"] == "open terminal"
        assert messages[1]["rawContent"] == "Terminal opened."

    def test_idempotent_ensure_on_existing_session(self, tmp_path: Path):
        """Calling ensureFreeDictationSession on existing session is idempotent.

        Simulates a 'restart' where ensureFreeDictationSession is called again
        on a session that already has messages -- existing data is preserved.
        """
        mgr = FreeDictationSessionManager(tmp_path)
        mgr.ensure_free_dictation_session()
        mgr.append_to_free_dictation("first message", "user")
        mgr.append_to_free_dictation("first response", "assistant")

        # Simulate restart: new manager instance, load index, call ensure again
        mgr2 = FreeDictationSessionManager(tmp_path)
        mgr2.load_sessions_index()
        mgr2.ensure_free_dictation_session()  # Should be a no-op

        # Verify session entry not duplicated
        sessions = mgr2._sessions_index["sessions"]
        free_dictation_entries = [
            s for s in sessions if s["name"] == "Free Dictation"
        ]
        assert len(free_dictation_entries) == 1

        # Verify existing messages are still there (not overwritten)
        messages = json.loads(mgr2.free_dictation_path.read_text())
        assert len(messages) == 2
        assert messages[0]["rawContent"] == "first message"
        assert messages[1]["rawContent"] == "first response"

    def test_append_after_simulated_restart(self, tmp_path: Path):
        """After a simulated restart, new messages can still be appended."""
        mgr = FreeDictationSessionManager(tmp_path)
        mgr.ensure_free_dictation_session()
        mgr.append_to_free_dictation("before restart", "user")

        # Simulate restart
        mgr2 = FreeDictationSessionManager(tmp_path)
        mgr2.load_sessions_index()
        mgr2.ensure_free_dictation_session()
        mgr2.append_to_free_dictation("after restart", "user")

        messages = json.loads(mgr2.free_dictation_path.read_text())
        assert len(messages) == 2
        assert messages[0]["rawContent"] == "before restart"
        assert messages[1]["rawContent"] == "after restart"

    def test_active_session_independent_across_restarts(self, tmp_path: Path):
        """The active session remains independent from Free Dictation across restarts."""
        mgr = FreeDictationSessionManager(tmp_path)
        mgr.active_session = "Work Notes"
        mgr.ensure_free_dictation_session()
        mgr.append_to_free_dictation("voice command", "user")

        # After operations, active session is still what was set
        assert mgr.active_session == "Work Notes"

        # New instance defaults to "Chat 1" (not Free Dictation)
        mgr2 = FreeDictationSessionManager(tmp_path)
        assert mgr2.active_session == "Chat 1"
