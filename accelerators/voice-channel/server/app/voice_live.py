"""WebSocket bridge: browser client <-> Voice Live agent.

One relay session per browser connection. The browser sends/receives the Voice
Live event JSON directly — the server is only responsible for:

  1. Resolving an Entra token for the Voice Live endpoint.
  2. Opening the upstream WebSocket.
  3. When in *model mode* (no FOUNDRY_AGENT_ID), sending a starter
     session.update with voice + turn_detection. In *agent mode* the agent's
     own instructions + tools are applied by the service — we just forward.
  4. Shuffling frames between the two sockets.

All tool-calling (ask_microsoft_learn_assistant) happens inside the Foundry
agent when running in agent mode, so the server no longer needs to know about
Direct Line or Copilot Studio. That logic moved to the Foundry agent record.
"""
from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, Optional

import websockets
from azure.identity.aio import DefaultAzureCredential
from fastapi import WebSocket, WebSocketDisconnect

log = logging.getLogger(__name__)

_ENTRA_SCOPE = "https://ai.azure.com/.default"


class VoiceLiveRelay:
    """One relay instance per browser connection."""

    def __init__(
        self,
        *,
        browser_ws: WebSocket,
        ws_url: str,
        mode: str,
        voice_name: str,
        credential: DefaultAzureCredential,
    ) -> None:
        self._browser = browser_ws
        self._ws_url = ws_url
        self._mode = mode
        self._voice_name = voice_name
        self._credential = credential
        self._foundry_ws: Optional[websockets.WebSocketClientProtocol] = None

    async def _bearer(self) -> str:
        tok = await self._credential.get_token(_ENTRA_SCOPE)
        return tok.token

    def _starter_session_update(self) -> dict[str, Any]:
        """Only used in model mode. In agent mode Foundry applies the agent record."""
        return {
            "type": "session.update",
            "session": {
                "modalities": ["text", "audio"],
                "voice": {
                    "name": self._voice_name,
                    "type": "azure-standard",
                    "temperature": 0.7,
                },
                "input_audio_sampling_rate": 24000,
                "input_audio_noise_reduction": {"type": "azure_deep_noise_suppression"},
                "input_audio_echo_cancellation": {"type": "server_echo_cancellation"},
                "turn_detection": {
                    "type": "azure_semantic_vad",
                    "threshold": 0.5,
                    "silence_duration_ms": 500,
                    "remove_filler_words": True,
                    "interrupt_response": True,
                },
                "input_audio_transcription": {"model": "azure-speech", "language": "en"},
            },
        }

    async def run(self) -> None:
        token = await self._bearer()
        log.info("voice_live.connecting mode=%s url=%s", self._mode, self._ws_url)

        async with websockets.connect(
            self._ws_url,
            additional_headers={"Authorization": f"Bearer {token}"},
            max_size=None,
        ) as foundry_ws:
            self._foundry_ws = foundry_ws
            log.info("voice_live.connected")

            if self._mode == "model":
                await foundry_ws.send(json.dumps(self._starter_session_update()))

            try:
                await asyncio.gather(
                    self._pump_browser_to_foundry(),
                    self._pump_foundry_to_browser(),
                )
            except WebSocketDisconnect:
                log.info("voice_live.browser_disconnected")
            except websockets.ConnectionClosed as e:
                log.info("voice_live.foundry_closed code=%s reason=%s", e.code, e.reason)

    async def _pump_browser_to_foundry(self) -> None:
        assert self._foundry_ws is not None
        while True:
            msg = await self._browser.receive_text()
            await self._foundry_ws.send(msg)

    async def _pump_foundry_to_browser(self) -> None:
        assert self._foundry_ws is not None
        async for raw in self._foundry_ws:
            try:
                await self._browser.send_text(raw)
            except Exception:  # noqa: BLE001
                return
