"""Bridge configuration — all runtime settings come from env vars."""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class BridgeConfig:
    foundry_websocket_url: str
    voice_name: str
    mcs_agent_name: str
    directline_secret: str
    mcs_timeout_seconds: int
    allowed_origins: list[str]
    instructions_path: Path
    session_template_path: Path

    @classmethod
    def from_env(cls) -> "BridgeConfig":
        ws = os.environ.get("FOUNDRY_WEBSOCKET_URL", "").strip()
        if not ws:
            raise RuntimeError(
                "FOUNDRY_WEBSOCKET_URL is required. "
                "Expected: wss://<foundry>.services.ai.azure.com/voice-live/realtime"
                "?api-version=2025-10-01&model=<model>"
            )

        secret = os.environ.get("DIRECTLINE_SECRET", "").strip()
        if not secret:
            raise RuntimeError(
                "DIRECTLINE_SECRET is required. Run copilot-studio-agent/create-agent.ps1 "
                "and copy the secret into the App Service settings."
            )

        here = Path(__file__).resolve().parent
        return cls(
            foundry_websocket_url=ws,
            voice_name=os.environ.get(
                "FOUNDRY_VOICE_NAME", "en-US-Ava:DragonHDLatestNeural"
            ),
            mcs_agent_name=os.environ.get(
                "MCS_AGENT_NAME", "Microsoft Learn Assistant"
            ),
            directline_secret=secret,
            mcs_timeout_seconds=int(os.environ.get("MCS_TIMEOUT_SECONDS", "20")),
            allowed_origins=[
                o.strip()
                for o in os.environ.get("ALLOWED_ORIGINS", "*").split(",")
                if o.strip()
            ],
            instructions_path=here.parent / "foundry-agent" / "it-assistant-instructions.md",
            session_template_path=here.parent / "foundry-agent" / "voice-live-session.json",
        )
