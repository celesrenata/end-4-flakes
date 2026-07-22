"""Nova Sonic backend implementation using AWS Bedrock bidirectional streaming.

Connects to Amazon Nova Sonic (v1:0) via the aws_sdk_bedrock_runtime smithy SDK,
sending/receiving events over a bidirectional HTTP/2 stream. Audio input is PCM
16kHz mono 16-bit, audio output is PCM 24kHz mono 16-bit (base64-encoded).

Event flow:
    1. sessionStart → promptStart → system prompt (contentStart/textInput/contentEnd)
    2. Optional tool definitions in promptStart
    3. Audio input: contentStart(AUDIO) → audioInput chunks → contentEnd
    4. Responses: textOutput (transcripts), audioOutput (speech), toolUse (tool calls)
    5. Session end: promptEnd → sessionEnd → close stream
"""

from __future__ import annotations

import asyncio
import base64
import json
import sys
import uuid
from typing import Any

from voice_agent_backends.base import BaseVoiceBackend, VoiceAgentConfig


# ---------------------------------------------------------------------------
# Emit helpers (write JSON events to stdout for the QML service)
# ---------------------------------------------------------------------------


def _emit_event(event: dict[str, Any]) -> None:
    """Write a JSON-line event to stdout and flush immediately."""
    _ = sys.stdout.write(json.dumps(event, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def _emit_partial_transcript(text: str) -> None:
    _emit_event({"type": "PARTIAL_TRANSCRIPT", "text": text})


def _emit_turn_end() -> None:
    _emit_event({"type": "TURN_END"})


def _emit_turn_complete(text: str) -> None:
    _emit_event({"type": "TURN_COMPLETE", "text": text})


def _emit_audio_response(audio_b64: str, text: str = "") -> None:
    event: dict[str, Any] = {"type": "AUDIO_RESPONSE", "audio": audio_b64}
    if text:
        event["text"] = text
    _emit_event(event)


def _emit_tool_call(call_id: str, name: str, arguments: str) -> None:
    _emit_event({"type": "TOOL_CALL", "id": call_id, "name": name, "arguments": arguments})


def _emit_error(message: str, fatal: bool = False) -> None:
    _emit_event({"type": "ERROR", "message": message, "fatal": fatal})


# ---------------------------------------------------------------------------
# NovaSonicBackend
# ---------------------------------------------------------------------------


class NovaSonicBackend(BaseVoiceBackend):
    """Amazon Nova Sonic backend via Bedrock bidirectional streaming.

    Uses the aws_sdk_bedrock_runtime smithy SDK for the bidirectional stream.
    The stream carries JSON events in both directions:
      - Input: sessionStart, promptStart, contentStart, textInput, audioInput,
               contentEnd, toolResult, promptEnd, sessionEnd
      - Output: completionStart, contentStart, textOutput, audioOutput,
                toolUse, contentEnd, completionEnd, usageEvent
    """

    MODEL_ID = "amazon.nova-sonic-v1:0"
    INPUT_SAMPLE_RATE = 16000
    OUTPUT_SAMPLE_RATE = 24000

    def __init__(self, config: VoiceAgentConfig) -> None:
        super().__init__(config)
        self._client: Any = None
        self._stream: Any = None
        self._is_active: bool = False
        self._audio_paused: bool = False
        self._response_task: asyncio.Task[None] | None = None

        # Unique IDs for the session (Nova Sonic requires prompt/content tracking)
        self._prompt_name: str = str(uuid.uuid4())
        self._system_content_name: str = str(uuid.uuid4())
        self._audio_content_name: str = str(uuid.uuid4())

        # Track current response context for event routing
        self._current_role: str = ""
        self._current_generation_stage: str = ""
        self._current_content_type: str = ""
        self._accumulated_user_text: str = ""
        self._accumulated_assistant_text: str = ""

        # Tool call tracking
        self._pending_tool_call_id: str | None = None

    # ------------------------------------------------------------------
    # Internal: SDK event sending
    # ------------------------------------------------------------------

    async def _send_event(self, event_json: str) -> None:
        """Send a JSON event string to the bidirectional stream."""
        from aws_sdk_bedrock_runtime.models import (
            BidirectionalInputPayloadPart,
            InvokeModelWithBidirectionalStreamInputChunk,
        )

        chunk = InvokeModelWithBidirectionalStreamInputChunk(
            value=BidirectionalInputPayloadPart(bytes_=event_json.encode("utf-8"))
        )
        await self._stream.input_stream.send(chunk)

    async def _send_event_dict(self, event: dict[str, Any]) -> None:
        """Serialize and send a dict event."""
        await self._send_event(json.dumps(event, separators=(",", ":")))

    # ------------------------------------------------------------------
    # connect()
    # ------------------------------------------------------------------

    async def connect(self) -> None:
        """Establish the bidirectional stream to Nova Sonic.

        Sends: sessionStart → promptStart → system prompt → tool definitions
               → audio content start
        Then launches the response processing background task.
        """
        from aws_sdk_bedrock_runtime.client import (
            BedrockRuntimeClient,
            InvokeModelWithBidirectionalStreamOperationInput,
        )
        from aws_sdk_bedrock_runtime.config import (
            Config,
            HTTPAuthSchemeResolver,
            SigV4AuthScheme,
        )
        from smithy_aws_core.identity import EnvironmentCredentialsResolver

        region = self.config.region or "us-east-1"

        # Initialize client with SigV4 auth
        config = Config(
            endpoint_uri=f"https://bedrock-runtime.{region}.amazonaws.com",
            region=region,
            aws_credentials_identity_resolver=EnvironmentCredentialsResolver(),
            auth_scheme_resolver=HTTPAuthSchemeResolver(),
            auth_schemes={"aws.auth#sigv4": SigV4AuthScheme(service="bedrock")},
        )
        self._client = BedrockRuntimeClient(config=config)

        # Open the bidirectional stream
        self._stream = await self._client.invoke_model_with_bidirectional_stream(
            InvokeModelWithBidirectionalStreamOperationInput(model_id=self.MODEL_ID)
        )
        self._is_active = True

        # 1. Send sessionStart
        await self._send_session_start()

        # 2. Send promptStart (with tool definitions if available)
        await self._send_prompt_start()

        # 3. Send system prompt
        await self._send_system_prompt()

        # 4. Start audio input content
        await self._start_audio_input()

        # 5. Start background response processor
        self._response_task = asyncio.create_task(self._process_responses())

    async def _send_session_start(self) -> None:
        """Send the sessionStart event with inference configuration."""
        await self._send_event_dict({
            "event": {
                "sessionStart": {
                    "inferenceConfiguration": {
                        "maxTokens": 1024,
                        "topP": 0.9,
                        "temperature": 0.7,
                    },
                    "turnDetectionConfiguration": {
                        "endpointingSensitivity": "HIGH",
                    },
                }
            }
        })

    async def _send_prompt_start(self) -> None:
        """Send the promptStart event with output configuration and optional tools."""
        prompt_start: dict[str, Any] = {
            "event": {
                "promptStart": {
                    "promptName": self._prompt_name,
                    "textOutputConfiguration": {
                        "mediaType": "text/plain",
                    },
                    "audioOutputConfiguration": {
                        "mediaType": "audio/lpcm",
                        "sampleRateHertz": self.OUTPUT_SAMPLE_RATE,
                        "sampleSizeBits": 16,
                        "channelCount": 1,
                        "voiceId": "matthew",
                        "encoding": "base64",
                        "audioType": "SPEECH",
                    },
                }
            }
        }

        # Add tool configuration if tools file provided
        tools = self._load_tools()
        if tools:
            prompt_start["event"]["promptStart"]["toolUseConfiguration"] = {
                "tools": tools,
                "toolChoice": {"auto": {}},
            }

        await self._send_event_dict(prompt_start)

    async def _send_system_prompt(self) -> None:
        """Send the system prompt as a TEXT content block."""
        # contentStart for system prompt
        await self._send_event_dict({
            "event": {
                "contentStart": {
                    "promptName": self._prompt_name,
                    "contentName": self._system_content_name,
                    "type": "TEXT",
                    "interactive": True,
                    "role": "SYSTEM",
                    "textInputConfiguration": {
                        "mediaType": "text/plain",
                    },
                }
            }
        })

        # Build system prompt content
        prompt_text = self._build_system_prompt()

        # textInput
        await self._send_event_dict({
            "event": {
                "textInput": {
                    "promptName": self._prompt_name,
                    "contentName": self._system_content_name,
                    "content": prompt_text,
                }
            }
        })

        # contentEnd for system prompt
        await self._send_event_dict({
            "event": {
                "contentEnd": {
                    "promptName": self._prompt_name,
                    "contentName": self._system_content_name,
                }
            }
        })

    async def _start_audio_input(self) -> None:
        """Send contentStart for the audio input stream."""
        await self._send_event_dict({
            "event": {
                "contentStart": {
                    "promptName": self._prompt_name,
                    "contentName": self._audio_content_name,
                    "type": "AUDIO",
                    "interactive": True,
                    "role": "USER",
                    "audioInputConfiguration": {
                        "mediaType": "audio/lpcm",
                        "sampleRateHertz": self.INPUT_SAMPLE_RATE,
                        "sampleSizeBits": 16,
                        "channelCount": 1,
                        "audioType": "SPEECH",
                        "encoding": "base64",
                    },
                }
            }
        })

    # ------------------------------------------------------------------
    # send_audio()
    # ------------------------------------------------------------------

    async def send_audio(self, chunk: bytes) -> None:
        """Forward a PCM audio chunk to Nova Sonic.

        If audio is paused (tool call pending), the chunk is silently dropped.
        """
        if not self._is_active or self._audio_paused:
            return

        audio_b64 = base64.b64encode(chunk).decode("ascii")
        await self._send_event_dict({
            "event": {
                "audioInput": {
                    "promptName": self._prompt_name,
                    "contentName": self._audio_content_name,
                    "content": audio_b64,
                }
            }
        })

    # ------------------------------------------------------------------
    # send_tool_result()
    # ------------------------------------------------------------------

    async def send_tool_result(
        self, call_id: str, name: str, result: str, is_error: bool = False
    ) -> None:
        """Send a tool result back to Nova Sonic and resume audio forwarding.

        Uses a toolResult content block with a unique content name.
        """
        tool_content_name = str(uuid.uuid4())

        # contentStart for tool result
        await self._send_event_dict({
            "event": {
                "contentStart": {
                    "promptName": self._prompt_name,
                    "contentName": tool_content_name,
                    "type": "TOOL_RESULT",
                    "interactive": True,
                    "role": "TOOL",
                    "toolResultInputConfiguration": {
                        "toolUseId": call_id,
                        "type": "TEXT",
                        "textInputConfiguration": {
                            "mediaType": "text/plain",
                        },
                    },
                }
            }
        })

        # Send the tool result content
        content = result if not is_error else json.dumps({"error": result})
        await self._send_event_dict({
            "event": {
                "toolResult": {
                    "promptName": self._prompt_name,
                    "contentName": tool_content_name,
                    "content": content,
                }
            }
        })

        # contentEnd for tool result
        await self._send_event_dict({
            "event": {
                "contentEnd": {
                    "promptName": self._prompt_name,
                    "contentName": tool_content_name,
                }
            }
        })

        # Resume audio forwarding
        self._audio_paused = False
        self._pending_tool_call_id = None

    # ------------------------------------------------------------------
    # send_barge_in()
    # ------------------------------------------------------------------

    async def send_barge_in(self) -> None:
        """Handle barge-in by ending and restarting the audio content.

        Nova Sonic supports barge-in natively — when the user speaks during
        response generation, the model detects it and stops. We just need
        to continue sending audio.
        """
        # Nova Sonic handles barge-in automatically through its VAD.
        # No explicit signal needed — continuing to send audio is sufficient.
        # The model will detect speech and stop generating.
        pass

    # ------------------------------------------------------------------
    # send_end_turn()
    # ------------------------------------------------------------------

    async def send_end_turn(self) -> None:
        """Signal explicit end-of-turn to Nova Sonic.

        Nova Sonic uses server-side VAD, so explicit end-of-turn is handled
        by ending the current audio content and starting a new one. This
        forces the model to process whatever audio has been received so far.

        Requirement: 7.4
        """
        # Nova Sonic relies on server-side VAD for turn boundaries.
        # Sending a brief pause in audio (by not sending frames) combined
        # with the VAD will trigger turn detection. For an explicit commit,
        # we end the audio content and immediately start a new one.
        if self._stream is None or not self._is_active:
            return

        try:
            # End current audio content
            await self._send_event_dict({
                "event": {
                    "contentEnd": {
                        "promptName": self._prompt_name,
                        "contentName": self._audio_content_name,
                    }
                }
            })

            # Start new audio content to continue accepting audio
            self._audio_content_name = f"audio-input-{int(asyncio.get_event_loop().time() * 1000)}"
            await self._send_event_dict({
                "event": {
                    "contentStart": {
                        "promptName": self._prompt_name,
                        "contentName": self._audio_content_name,
                        "type": "AUDIO",
                        "interactive": True,
                        "role": "USER",
                    }
                }
            })
        except Exception as exc:
            print(f"[nova-sonic] send_end_turn error: {exc}", file=sys.stderr)

    # ------------------------------------------------------------------
    # disconnect()
    # ------------------------------------------------------------------

    async def disconnect(self) -> None:
        """Gracefully close the Nova Sonic stream."""
        self._is_active = False

        # Cancel response processing task
        if self._response_task and not self._response_task.done():
            self._response_task.cancel()
            try:
                await self._response_task
            except asyncio.CancelledError:
                pass

        if self._stream is None:
            return

        try:
            # End audio input content
            await self._send_event_dict({
                "event": {
                    "contentEnd": {
                        "promptName": self._prompt_name,
                        "contentName": self._audio_content_name,
                    }
                }
            })

            # End prompt
            await self._send_event_dict({
                "event": {
                    "promptEnd": {
                        "promptName": self._prompt_name,
                    }
                }
            })

            # End session
            await self._send_event_dict({"event": {"sessionEnd": {}}})

            # Close the input stream
            await self._stream.input_stream.close()
        except Exception as exc:
            print(f"[nova-sonic] Disconnect error: {exc}", file=sys.stderr)

    # ------------------------------------------------------------------
    # Response processing (background task)
    # ------------------------------------------------------------------

    async def _process_responses(self) -> None:
        """Continuously process output events from the Nova Sonic stream.

        Parses JSON response events and emits the appropriate protocol events
        on stdout for the QML service to consume.
        """
        try:
            while self._is_active:
                output = await self._stream.await_output()
                result = await output[1].receive()

                if not (result.value and result.value.bytes_):
                    continue

                response_data = result.value.bytes_.decode("utf-8")
                try:
                    json_data: dict[str, Any] = json.loads(response_data)
                except (json.JSONDecodeError, ValueError):
                    continue

                if "event" not in json_data:
                    continue

                event = json_data["event"]
                self._handle_output_event(event)

        except asyncio.CancelledError:
            return
        except Exception as exc:
            if self._is_active:
                _emit_error(f"Nova Sonic stream error: {exc}", fatal=True)

    def _handle_output_event(self, event: dict[str, Any]) -> None:
        """Route a single Nova Sonic output event to the appropriate handler."""
        if "contentStart" in event:
            self._handle_content_start(event["contentStart"])
        elif "textOutput" in event:
            self._handle_text_output(event["textOutput"])
        elif "audioOutput" in event:
            self._handle_audio_output(event["audioOutput"])
        elif "toolUse" in event:
            self._handle_tool_use(event["toolUse"])
        elif "contentEnd" in event:
            self._handle_content_end(event["contentEnd"])
        elif "completionStart" in event:
            # Beginning of a new completion — reset accumulators
            self._accumulated_assistant_text = ""
        elif "completionEnd" in event:
            # Completion finished — emit turn complete if we have user text
            if self._accumulated_user_text:
                _emit_turn_complete(self._accumulated_user_text)
                self._accumulated_user_text = ""

    def _handle_content_start(self, content_start: dict[str, Any]) -> None:
        """Track the current content role and generation stage."""
        self._current_role = content_start.get("role", "")
        self._current_content_type = content_start.get("type", "")

        # Parse additionalModelFields for generation stage
        additional = content_start.get("additionalModelFields", "")
        if additional:
            try:
                fields = json.loads(additional) if isinstance(additional, str) else additional
                self._current_generation_stage = fields.get("generationStage", "")
            except (json.JSONDecodeError, ValueError):
                self._current_generation_stage = ""
        else:
            self._current_generation_stage = ""

    def _handle_text_output(self, text_output: dict[str, Any]) -> None:
        """Handle text output events (user transcription and assistant text)."""
        content: str = text_output.get("content", "")
        if not content:
            return

        if self._current_role == "USER":
            # ASR transcription of user speech (FINAL stage)
            self._accumulated_user_text = content
            _emit_partial_transcript(content)
        elif self._current_role == "ASSISTANT":
            if self._current_generation_stage == "SPECULATIVE":
                # Speculative text — preview of what the model will say
                self._accumulated_assistant_text += content
                _emit_partial_transcript(content)
            elif self._current_generation_stage == "FINAL":
                # Final transcription of what was actually spoken
                _emit_turn_complete(content)

    def _handle_audio_output(self, audio_output: dict[str, Any]) -> None:
        """Handle audio output events — emit AUDIO_RESPONSE with base64 PCM."""
        audio_content: str = audio_output.get("content", "")
        if audio_content:
            # Emit turn end on first audio (transition from thinking to speaking)
            _emit_audio_response(audio_content, text=self._accumulated_assistant_text)
            # Clear accumulated text after first audio chunk pairs it
            self._accumulated_assistant_text = ""

    def _handle_tool_use(self, tool_use: dict[str, Any]) -> None:
        """Handle tool use events — emit TOOL_CALL and pause audio."""
        tool_use_id: str = tool_use.get("toolUseId", "")
        tool_name: str = tool_use.get("toolName", "")
        content: str = tool_use.get("content", "{}")

        # Pause audio forwarding until tool result received
        self._audio_paused = True
        self._pending_tool_call_id = tool_use_id

        _emit_tool_call(tool_use_id, tool_name, content)

    def _handle_content_end(self, content_end: dict[str, Any]) -> None:
        """Handle content end events — detect turn boundaries."""
        # When user audio content ends (VAD detected end of speech), emit TURN_END
        if self._current_role == "USER" and self._current_content_type == "AUDIO":
            _emit_turn_end()

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _build_system_prompt(self) -> str:
        """Build the system prompt string from config and context file."""
        parts: list[str] = []

        # Base system prompt
        if self.config.system_prompt:
            parts.append(self.config.system_prompt)
        else:
            parts.append(
                "You are a helpful voice assistant. Keep your responses concise "
                "and conversational, generally two or three sentences."
            )

        # Load context from file if provided
        if self.config.context:
            context_text = self._load_context()
            if context_text:
                parts.append("\n\n## Conversation Context\n")
                parts.append(context_text)

        return "\n".join(parts)

    def _load_context(self) -> str:
        """Load session context from the JSON file specified in config."""
        if not self.config.context:
            return ""
        try:
            with open(self.config.context, "r", encoding="utf-8") as f:
                context_data = json.load(f)

            # Format context as a conversation summary
            if isinstance(context_data, list):
                lines: list[str] = []
                for msg in context_data:
                    role = msg.get("role", "unknown")
                    content = msg.get("content", "")
                    lines.append(f"{role}: {content}")
                return "\n".join(lines)
            elif isinstance(context_data, dict):
                return json.dumps(context_data, indent=2)
            else:
                return str(context_data)
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            print(f"[nova-sonic] Failed to load context: {exc}", file=sys.stderr)
            return ""

    def _load_tools(self) -> list[dict[str, Any]]:
        """Load tool definitions from the JSON file specified in config.

        Returns a list of tool spec objects suitable for Nova Sonic's
        toolUseConfiguration.tools field.
        """
        if not self.config.tools:
            return []
        try:
            with open(self.config.tools, "r", encoding="utf-8") as f:
                tools_data = json.load(f)

            # Expect either a list of toolSpec objects or a dict with a "tools" key
            if isinstance(tools_data, list):
                return tools_data  # type: ignore[return-value]
            elif isinstance(tools_data, dict) and "tools" in tools_data:
                return tools_data["tools"]  # type: ignore[return-value]
            else:
                return []
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            print(f"[nova-sonic] Failed to load tools: {exc}", file=sys.stderr)
            return []
