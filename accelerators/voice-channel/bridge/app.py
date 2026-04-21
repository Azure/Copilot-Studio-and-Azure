"""FastAPI bridge: browser ↔ Voice Live ↔ Copilot Studio."""
from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager

from azure.identity.aio import DefaultAzureCredential
from fastapi import FastAPI, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from config import BridgeConfig
from copilot_studio_client import CopilotStudioClient
from voice_live_client import VoiceLiveSession

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("bridge")


@asynccontextmanager
async def lifespan(app: FastAPI):
    cfg = BridgeConfig.from_env()
    credential = DefaultAzureCredential()
    app.state.cfg = cfg
    app.state.credential = credential
    log.info(
        "bridge.startup foundry_ws=%s voice=%s mcs_agent=%s",
        cfg.foundry_websocket_url.split("?")[0],
        cfg.voice_name,
        cfg.mcs_agent_name,
    )
    try:
        yield
    finally:
        await credential.close()


app = FastAPI(lifespan=lifespan)

# CORS (configured per deploy; default open for dev)
allowed = os.environ.get("ALLOWED_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in allowed if o.strip()],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/healthz")
async def healthz() -> JSONResponse:
    cfg: BridgeConfig = app.state.cfg
    return JSONResponse({
        "status": "ok",
        "mcs_agent": cfg.mcs_agent_name,
        "voice": cfg.voice_name,
    })


@app.websocket("/ws/voice")
async def voice_socket(ws: WebSocket) -> None:
    await ws.accept()
    cfg: BridgeConfig = app.state.cfg
    credential: DefaultAzureCredential = app.state.credential

    mcs = CopilotStudioClient(
        directline_secret=cfg.directline_secret,
        timeout_seconds=cfg.mcs_timeout_seconds,
    )
    session = VoiceLiveSession(
        browser_ws=ws,
        foundry_ws_url=cfg.foundry_websocket_url,
        voice_name=cfg.voice_name,
        mcs_agent_name=cfg.mcs_agent_name,
        instructions_path=cfg.instructions_path,
        session_template_path=cfg.session_template_path,
        mcs_client=mcs,
        credential=credential,
    )
    try:
        await session.run()
    except Exception:  # noqa: BLE001
        log.exception("voice_socket.fatal")
    finally:
        await mcs.aclose()
        try:
            await ws.close()
        except Exception:  # noqa: BLE001
            pass


# Static browser client served at /
app.mount(
    "/",
    StaticFiles(directory=os.path.join(os.path.dirname(__file__), "static"), html=True),
    name="static",
)
