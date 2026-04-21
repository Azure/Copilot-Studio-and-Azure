# Voice Channel server

FastAPI application that:

- Serves the browser UI at `/`
- Relays audio between the browser and **Voice Live** on the `/api/voice` WebSocket
- Connects to Voice Live using the Foundry **IT Assistant** Agent Service agent (via `agent_id` + `project_id`) when those env vars are set, falling back to raw model mode otherwise
- Authenticates to Voice Live using the user-assigned managed identity the Bicep template attaches to the container

## Files

| File | Purpose |
|---|---|
| `app/main.py` | FastAPI entrypoint and routes. |
| `app/voice_live.py` | WebSocket relay logic. |
| `app/config.py` | Loads runtime env vars, builds the Voice Live URL. |
| `app/static/index.html` | Browser UI (markup). |
| `app/static/style.css` | Voice Live demo-style theming. |
| `app/static/client.js` | Mic capture, WS client, playback, transcript. |
| `Dockerfile` | Python 3.11 slim; serves via gunicorn + uvicorn workers. |
| `requirements.txt` | Pinned runtime deps. |

## Local development

```powershell
cd server
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# Use your az login credentials for Entra auth to Voice Live
az login

$env:FOUNDRY_ENDPOINT    = "https://<your-foundry>.services.ai.azure.com"
$env:FOUNDRY_AGENT_ID    = "<assistant-id-from-create-foundry-agent.ps1>"
$env:FOUNDRY_PROJECT_ID  = "<project-id>"
$env:FOUNDRY_VOICE_NAME  = "en-US-Ava:DragonHDLatestNeural"

uvicorn app.main:app --reload --port 8000
```

Then open `http://localhost:8000/`.

## Container deployment

Handled by `azd deploy` (or `azd up`) from the accelerator root. The
Bicep template provisions the Container App with `azd-service-name: server`,
which tells azd to build `Dockerfile` and push the image to ACR, then roll
the Container App to the new tag.

## Environment variables (set by Bicep at deploy time)

| Variable | Required | Default | Description |
|---|---|---|---|
| `FOUNDRY_ENDPOINT` | yes | — | `https://<foundry>.services.ai.azure.com` |
| `FOUNDRY_AGENT_ID` | no | empty | Foundry assistant ID — set by `create-foundry-agent.ps1`. |
| `FOUNDRY_PROJECT_ID` | no | empty | Foundry project ID — set by `create-foundry-agent.ps1`. |
| `VOICE_LIVE_MODEL` | no | `gpt-realtime-mini` | Used only in model mode (if agent vars are empty). |
| `FOUNDRY_VOICE_NAME` | no | `en-US-Ava:DragonHDLatestNeural` | TTS voice. |
| `MCS_AGENT_NAME` | no | `Microsoft Learn Assistant` | Display label in the UI. |
| `AZURE_CLIENT_ID` | no | empty | UAI client ID — DefaultAzureCredential pins to this identity. |
