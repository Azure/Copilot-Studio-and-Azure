"""WebSocket client that bridges a browser voice session to Azure Voice Live.

Wire format:

  Browser  <-- ws -->  BridgeApp  <-- ws -->  Voice Live

The browser sends/receives JSON text frames only (base64-encoded PCM16 audio
for input and output). The bridge does two things:

  1. Forwards every inbound event to Voice Live after sending a custom
     ``session.update`` at connect time.
  2. Watches for ``response.function_call_arguments.done`` events and, when one
     arrives for ``ask_microsoft_learn_assistant``, calls Copilot Studio via
     Direct Line and injects the result back into the Voice Live session.

Reference events: https://learn.microsoft.com/azure/ai-foundry/openai/realtime-audio-reference
"""
from __future__ import annotations

import asyncio
import json
import logging
import string
from pathlib import Path
from typing import Any, Optional

import websockets
from azure.identity.aio import DefaultAzureCredential
from fastapi import WebSocket, WebSocketDisconnect

from copilot_studio_client import CopilotStudioClient

log = logging.getLogger(__name__)

_ENTRA_SCOPE = "https://ai.azure.com/.default"


class VoiceLiveSession:
    """One instance per connected browser client."""

    def __init__(
        self,
        *,
        browser_ws: WebSocket,
        foundry_ws_url: str,
        voice_name: str,
        mcs_agent_name: str,
        instructions_path: Path,
        session_template_path: Path,
        mcs_client: CopilotStudioClient,
        credential: DefaultAzureCredential,
    ) -> None:
        self._browser = browser_ws
        self._foundry_url = foundry_ws_url
        self._voice_name = voice_name
        self._mcs_agent_name = mcs_agent_name
        self._instructions_path = instructions_path
        self._session_template_path = session_template_path
        self._mcs = mcs_client
        self._credential = credential
        self._foundry_ws: Optional[websockets.WebSocketClientProtocol] = None

    # ---------------------------------------------------------------- helpers

    def _build_session_update(self) -> dict[str, Any]:
        template = self._session_template_path.read_text(encoding="utf-8")
        instructions = self._instructions_path.read_text(encoding="utf-8").strip()
        # Use string.Template-style substitution that won't fail on $ in JSON
        rendered = (
            template
            .replace("${INSTRUCTIONS}", json.dumps(instructions)[1:-1])
            .replace("${VOICE_NAME}", self._voice_name)
            .replace("${MCS_AGENT_NAME}", self._mcs_agent_name)
        )
        payload = json.loads(rendered)
        # Strip informational comment fields
        payload.pop("_comment", None)
        return payload

    async def _bearer(self) -> str:
        tok = await self._credential.get_token(_ENTRA_SCOPE)
        return tok.token

    # ---------------------------------------------------------------- main

    async def run(self) -> None:
        token = await self._bearer()
        log.info("voice_live.connecting url=%s", self._foundry_url)

        async with websockets.connect(
            self._foundry_url,
            additional_headers={"Authorization": f"Bearer {token}"},
            max_size=None,
        ) as foundry_ws:
            self._foundry_ws = foundry_ws
            log.info("voice_live.connected")

            # Step 1 — send session.update before any audio flows
            await foundry_ws.send(json.dumps(self._build_session_update()))

            # Step 2 — run two pumps concurrently
            try:
                await asyncio.gather(
                    self._pump_browser_to_foundry(),
                    self._pump_foundry_to_browser(),
                )
            except WebSocketDisconnect:
                log.info("voice_live.browser_disconnected")
            except websockets.ConnectionClosed as e:
                log.info("voice_live.foundry_closed code=%s reason=%s", e.code, e.reason)

    # ----------------------------------------------------------- browser -> foundry

    async def _pump_browser_to_foundry(self) -> None:
        assert self._foundry_ws is not None
        while True:
            msg = await self._browser.receive_text()
            await self._foundry_ws.send(msg)

    # ----------------------------------------------------------- foundry -> browser

    async def _pump_foundry_to_browser(self) -> None:
        assert self._foundry_ws is not None
        async for raw in self._foundry_ws:
            # Forward every event to the browser so the UI can render transcripts,
            # play audio deltas, etc.
            try:
                await self._browser.send_text(raw)
            except Exception:  # noqa: BLE001
                return

            # Intercept function-call completions
            try:
                evt = json.loads(raw)
            except json.JSONDecodeError:
                continue

            if evt.get("type") == "response.function_call_arguments.done":
                # Handle asynchronously so we don't block the pump
                asyncio.create_task(self._handle_tool_call(evt))

    # ---------------------------------------------------------------- tool call

    async def _handle_tool_call(self, evt: dict[str, Any]) -> None:
        assert self._foundry_ws is not None

        name = evt.get("name") or ""
        call_id = evt.get("call_id") or ""
        args_raw = evt.get("arguments") or "{}"

        if name != "ask_microsoft_learn_assistant":
            log.warning("tool.unknown name=%s call_id=%s", name, call_id)
            return

        try:
            args = json.loads(args_raw)
        except json.JSONDecodeError:
            args = {}
        question = (args.get("question") or "").strip() or "(empty question)"

        log.info("tool.ask_mcs call_id=%s q=%r", call_id, _truncate(question, 120))

        try:
            answer = await self._mcs.ask(question)
            payload = json.dumps({"answer": answer})
        except TimeoutError as e:
            log.warning("tool.ask_mcs timeout: %s", e)
            payload = json.dumps({"error": "timeout", "message": str(e)})
        except Exception as e:  # noqa: BLE001
            log.exception("tool.ask_mcs failed")
            payload = json.dumps({"error": "error", "message": str(e)})

        # Inject the tool output as a conversation item
        await self._foundry_ws.send(json.dumps({
            "type": "conversation.item.create",
            "item": {
                "type": "function_call_output",
                "call_id": call_id,
                "output": payload,
            },
        }))
        # Ask the model to generate a spoken response using the new tool output
        await self._foundry_ws.send(json.dumps({"type": "response.create"}))


def _truncate(s: str, n: int) -> str:
    return s if len(s) <= n else s[: n - 1] + "…"
