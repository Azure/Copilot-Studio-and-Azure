"""Runtime configuration for the Voice Channel server.

All values come from environment variables set by the Container App's Bicep
template. Local development reads a .env file at the repo root if present.
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).resolve().parents[2] / ".env")
except ImportError:
    pass


@dataclass(frozen=True)
class ServerConfig:
    # Voice Live
    foundry_endpoint: str       # e.g. https://cog-abc.services.ai.azure.com
    voice_live_model: str       # e.g. gpt-realtime-mini  (fallback when agent_id is empty)
    voice_name: str             # e.g. en-US-Ava:DragonHDLatestNeural

    # Foundry Agent Service — IT Assistant
    foundry_agent_id: str       # populated after `create-foundry-agent.ps1`
    foundry_project_id: str     # populated after `create-foundry-agent.ps1`

    # UI labels
    mcs_agent_name: str

    # Platform
    azure_client_id: str        # managed-identity client ID (for DefaultAzureCredential in the container)

    @classmethod
    def from_env(cls) -> "ServerConfig":
        endpoint = os.environ.get("FOUNDRY_ENDPOINT", "").rstrip("/")
        if not endpoint:
            raise RuntimeError(
                "FOUNDRY_ENDPOINT must be set. Run `azd up` or export it manually."
            )

        return cls(
            foundry_endpoint=endpoint,
            voice_live_model=os.environ.get("VOICE_LIVE_MODEL", "gpt-realtime-mini"),
            voice_name=os.environ.get("FOUNDRY_VOICE_NAME", "en-US-Ava:DragonHDLatestNeural"),
            foundry_agent_id=os.environ.get("FOUNDRY_AGENT_ID", "").strip(),
            foundry_project_id=os.environ.get("FOUNDRY_PROJECT_ID", "").strip(),
            mcs_agent_name=os.environ.get("MCS_AGENT_NAME", "Microsoft Learn Assistant"),
            azure_client_id=os.environ.get("AZURE_CLIENT_ID", ""),
        )

    @property
    def voice_live_ws_url(self) -> str:
        """Build the Voice Live WebSocket URL.

        If FOUNDRY_AGENT_ID + FOUNDRY_PROJECT_ID are set, connect via the
        Foundry Agent Service (the agent's instructions + tools are applied
        automatically). Otherwise fall back to model mode — the server will
        still relay, but it won't call MCS unless you add a tool config.
        """
        host = self.foundry_endpoint.replace("https://", "").split("/")[0]
        base = f"wss://{host}/voice-live/realtime?api-version=2025-10-01"
        if self.foundry_agent_id and self.foundry_project_id:
            return f"{base}&agent_id={self.foundry_agent_id}&project_id={self.foundry_project_id}"
        return f"{base}&model={self.voice_live_model}"

    @property
    def mode(self) -> str:
        return "agent" if self.foundry_agent_id and self.foundry_project_id else "model"
