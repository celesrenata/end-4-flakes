"""Shared base classes and configuration for voice agent backends.

Provides BaseVoiceBackend ABC and VoiceAgentConfig dataclass used by both
the main voice-agent-stream.py script and individual backend implementations.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------


@dataclass
class VoiceAgentConfig:
    """Configuration parsed from CLI arguments."""

    backend: str  # "nova-sonic" or "openai-realtime"
    audio_fifo: str  # Path to named FIFO for PCM audio input
    sample_rate: int  # Audio sample rate (16000 or 24000)
    region: str  # AWS region (nova-sonic)
    profile: str  # AWS profile (nova-sonic)
    api_key: str  # API key (openai-realtime)
    system_prompt: str  # System prompt text
    context: str  # Path to session context JSON file
    tools: str  # Path to tools definition JSON file


# ---------------------------------------------------------------------------
# Backend abstraction
# ---------------------------------------------------------------------------


class BaseVoiceBackend(ABC):
    """Abstract base class for streaming voice backends.

    Subclasses implement the actual connection to Nova Sonic (HTTP/2
    bidirectional) or OpenAI Realtime (WebSocket). The main loop delegates
    audio forwarding, tool result delivery, and lifecycle management here.
    """

    config: VoiceAgentConfig

    def __init__(self, config: VoiceAgentConfig) -> None:
        self.config = config

    @abstractmethod
    async def connect(self) -> None:
        """Establish the backend connection.

        Should set up the bidirectional stream and be ready to accept audio.
        The caller emits READY after this returns successfully.
        """
        ...

    @abstractmethod
    async def send_audio(self, chunk: bytes) -> None:
        """Forward a chunk of raw PCM audio to the backend.

        Args:
            chunk: Raw PCM audio bytes (s16, mono, at configured sample rate).
        """
        ...

    @abstractmethod
    async def send_tool_result(
        self, call_id: str, name: str, result: str, is_error: bool = False
    ) -> None:
        """Send a tool execution result back to the backend.

        Args:
            call_id: The unique tool call ID (matches the TOOL_CALL event id).
            name: The tool name.
            result: Serialized result string (or error message).
            is_error: Whether the tool execution failed.
        """
        ...

    @abstractmethod
    async def send_barge_in(self) -> None:
        """Notify the backend that the user interrupted playback.

        The backend should stop generating audio and prepare for new input.
        """
        ...

    @abstractmethod
    async def disconnect(self) -> None:
        """Gracefully close the backend connection."""
        ...
