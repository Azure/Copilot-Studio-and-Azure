"""FastAPI entrypoint for the Voice Channel server.

Routes:
  GET  /                 - static web UI
  GET  /api/config       - runtime config for the browser (agent name, voice, mode)
  GET  /healthz          - health probe
  WS   /api/voice        - relay to Voice Live
"""
from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

from azure.identity.aio import DefaultAzureCredential
from fastapi import FastAPI, Request, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from fastapi.staticfiles import StaticFiles

from app.config import ServerConfig
from app.voice_live import VoiceLiveRelay

# Hosts we allow to iframe this page — Teams + Microsoft 365 surfaces.
# Anything else gets the default `frame-ancestors 'self'`, which blocks framing.
_TEAMS_FRAME_ANCESTORS = " ".join([
    "'self'",
    "https://teams.microsoft.com",
    "https://*.teams.microsoft.com",
    "https://*.cloud.microsoft",
    "https://*.office.com",
    "https://*.microsoft365.com",
])

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("voice-channel")


@asynccontextmanager
async def lifespan(app: FastAPI):
    cfg = ServerConfig.from_env()
    credential = DefaultAzureCredential(
        # Pin to the user-assigned MI so DefaultAzureCredential doesn't try
        # the system-assigned identity when both exist on the container.
        managed_identity_client_id=cfg.azure_client_id or None,
    )
    app.state.cfg = cfg
    app.state.credential = credential
    log.info(
        "startup mode=%s agent_id=%s project_id=%s model=%s voice=%s",
        cfg.mode,
        cfg.foundry_agent_id or "-",
        cfg.foundry_project_id or "-",
        cfg.voice_live_model,
        cfg.voice_name,
    )
    try:
        yield
    finally:
        await credential.close()


app = FastAPI(title="Voice Channel — IT Assistant", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def security_headers(request: Request, call_next) -> Response:
    """Allow Teams + M365 to iframe the web UI; leave other responses alone.

    Without `frame-ancestors`, browsers inside Teams refuse to render this
    page (Teams sandboxes its tabs in an iframe, so same-origin doesn't
    apply). `X-Frame-Options` is intentionally NOT set — the CSP directive
    supersedes it, and a conflicting `X-Frame-Options: SAMEORIGIN` would
    block Teams.
    """
    response: Response = await call_next(request)
    response.headers["Content-Security-Policy"] = f"frame-ancestors {_TEAMS_FRAME_ANCESTORS}"
    return response


@app.get("/healthz")
async def healthz() -> JSONResponse:
    cfg: ServerConfig = app.state.cfg
    return JSONResponse({
        "status": "ok",
        "mode": cfg.mode,
        "mcs_agent_name": cfg.mcs_agent_name,
        "voice": cfg.voice_name,
    })


@app.get("/api/config")
async def api_config() -> JSONResponse:
    cfg: ServerConfig = app.state.cfg
    return JSONResponse({
        "mode": cfg.mode,
        "mcsAgentName": cfg.mcs_agent_name,
        "voice": cfg.voice_name,
        "model": cfg.voice_live_model,
    })


@app.websocket("/api/voice")
async def voice_socket(ws: WebSocket) -> None:
    await ws.accept()
    cfg: ServerConfig = app.state.cfg
    credential: DefaultAzureCredential = app.state.credential

    relay = VoiceLiveRelay(
        browser_ws=ws,
        ws_url=cfg.voice_live_ws_url,
        mode=cfg.mode,
        voice_name=cfg.voice_name,
        credential=credential,
    )
    try:
        await relay.run()
    except Exception:  # noqa: BLE001
        log.exception("voice_socket.fatal")
    finally:
        try:
            await ws.close()
        except Exception:  # noqa: BLE001
            pass


# Static UI — mount AFTER the API routes so /api paths aren't shadowed.
_static_dir = Path(__file__).resolve().parent / "static"
app.mount("/", StaticFiles(directory=str(_static_dir), html=True), name="static")
