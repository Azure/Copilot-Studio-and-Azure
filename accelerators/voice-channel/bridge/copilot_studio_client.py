"""Direct Line 3.0 client for the Copilot Studio 'Microsoft Learn Assistant' agent.

Per-session lifecycle:
  1. Exchange the static Direct Line secret for a short-lived conversation token.
  2. Start a conversation.
  3. Post each user turn as an `activity` and poll / watermark `activities` for
     the bot reply.

Reference: https://learn.microsoft.com/azure/bot-service/rest-api/bot-framework-rest-direct-line-3-0-start-conversation
"""
from __future__ import annotations

import asyncio
import logging
import uuid
from dataclasses import dataclass
from typing import Optional

import httpx

log = logging.getLogger(__name__)

DIRECTLINE_BASE = "https://directline.botframework.com/v3/directline"


@dataclass
class _Conversation:
    conversation_id: str
    token: str
    watermark: Optional[str] = None


class CopilotStudioClient:
    """One instance per voice session."""

    def __init__(self, directline_secret: str, timeout_seconds: int = 20) -> None:
        self._secret = directline_secret
        self._timeout = timeout_seconds
        self._conv: Optional[_Conversation] = None
        self._http = httpx.AsyncClient(timeout=httpx.Timeout(30.0))
        self._user_id = f"voiceuser-{uuid.uuid4().hex[:8]}"

    async def aclose(self) -> None:
        await self._http.aclose()

    # ---------------------------------------------------------------- lifecycle

    async def _ensure_conversation(self) -> _Conversation:
        if self._conv is not None:
            return self._conv

        # Exchange secret → token + conversation
        r = await self._http.post(
            f"{DIRECTLINE_BASE}/tokens/generate",
            headers={"Authorization": f"Bearer {self._secret}"},
        )
        r.raise_for_status()
        token = r.json()["token"]

        r = await self._http.post(
            f"{DIRECTLINE_BASE}/conversations",
            headers={"Authorization": f"Bearer {token}"},
        )
        r.raise_for_status()
        conv_id = r.json()["conversationId"]

        log.info("directline.conversation_started conversation_id=%s", conv_id)
        self._conv = _Conversation(conversation_id=conv_id, token=token)
        return self._conv

    # ----------------------------------------------------------------- turn

    async def ask(self, question: str) -> str:
        """Send `question` and return the bot's text reply (concatenated if multi-part)."""
        conv = await self._ensure_conversation()
        auth = {"Authorization": f"Bearer {conv.token}"}

        # Send the user activity
        activity = {
            "type": "message",
            "from": {"id": self._user_id, "name": "VoiceUser"},
            "text": question,
            "locale": "en-US",
        }
        r = await self._http.post(
            f"{DIRECTLINE_BASE}/conversations/{conv.conversation_id}/activities",
            headers=auth,
            json=activity,
        )
        r.raise_for_status()

        # Poll for replies
        deadline = asyncio.get_running_loop().time() + self._timeout
        collected: list[str] = []

        while asyncio.get_running_loop().time() < deadline:
            params = {"watermark": conv.watermark} if conv.watermark else {}
            r = await self._http.get(
                f"{DIRECTLINE_BASE}/conversations/{conv.conversation_id}/activities",
                headers=auth,
                params=params,
            )
            r.raise_for_status()
            payload = r.json()
            conv.watermark = payload.get("watermark", conv.watermark)

            for act in payload.get("activities", []):
                if act.get("type") != "message":
                    continue
                if act.get("from", {}).get("id") == self._user_id:
                    # echo of our own message
                    continue
                text = (act.get("text") or "").strip()
                if text:
                    collected.append(text)

                # inputHint == 'acceptingInput' signals end-of-turn from MCS
                if act.get("inputHint") == "acceptingInput" and collected:
                    return "\n".join(collected)

            if collected:
                # give a short grace period for follow-up activities
                await asyncio.sleep(0.4)
                if collected:
                    return "\n".join(collected)

            await asyncio.sleep(0.5)

        if collected:
            return "\n".join(collected)
        raise TimeoutError(
            f"No reply from Copilot Studio within {self._timeout}s (conversation {conv.conversation_id})"
        )
