# Real-Time Voice Channel for Copilot Studio (Voice Live + Foundry Agent + MCS)

An accelerator that adds a **real-time, low-latency voice experience** to a Microsoft Copilot Studio agent **without requiring the Omnichannel / Contact Center Engagement Hub license**.

It wires together three Microsoft AI surfaces:

| Layer | Product | Role in this accelerator |
|---|---|---|
| Voice | **Azure AI Foundry — Voice Live API** | Speech-to-speech "IT Assistant" agent. Handles mic input, noise suppression, semantic VAD, barge-in, TTS. |
| Orchestration | **Azure App Service (bridge)** | Python FastAPI app. Opens a WebSocket to Voice Live and routes each user turn to Copilot Studio as a tool/function call. Hosts the browser client and the Teams personal-app manifest. |
| Brain | **Microsoft Copilot Studio — "Microsoft Learn Assistant"** | Agent that answers the actual questions. Grounded via the **Microsoft Learn MCP server** (`https://learn.microsoft.com/api/mcp`). |

The result is a voice-first agent that the user talks to from **Microsoft 365** or **Microsoft Teams**, where all reasoning happens in Copilot Studio and the user pays only for Voice Live usage + App Service + any MCS messages — no Dynamics 365 Contact Center SKU required.

---

## Solution Architecture

```
                      ┌─────────────────────────────────────────────────────┐
                      │              Microsoft Teams / M365                 │
                      │  (Personal app tab hosting the bridge web client)   │
                      └────────────────────────┬────────────────────────────┘
                                               │  WebRTC / mic + speaker
                                               ▼
                  ┌───────────────────────────────────────────────────────┐
                  │        Bridge App  (Azure App Service, Python)        │
                  │  ─ Serves index.html (browser client)                 │
                  │  ─ Opens  wss://…/voice-live/realtime  to Foundry     │
                  │  ─ Handles tool calls → Direct Line → Copilot Studio  │
                  └──────────┬──────────────────────────────┬─────────────┘
                             │ WebSocket                    │ HTTPS (Direct Line 3.0)
                             ▼                              ▼
          ┌──────────────────────────────────┐   ┌─────────────────────────────┐
          │ Azure AI Foundry  (IT Assistant) │   │ Copilot Studio              │
          │  Voice Live  gpt-realtime-mini   │   │  "Microsoft Learn Assistant"│
          │  + azure_semantic_vad            │   │  + Microsoft Learn MCP tool │
          │  + azure_deep_noise_suppression  │   │    https://learn.microsoft  │
          │  + function tool: ask_mcs()      │   │    .com/api/mcp             │
          └──────────────────────────────────┘   └─────────────────────────────┘
```

1. The user joins the Teams / M365 personal app. The browser opens its mic.
2. Audio streams to the bridge app, which relays it to the Voice Live WebSocket on the Foundry resource.
3. Voice Live runs speech-to-text + LLM + text-to-speech in one managed service. It is configured with **one tool function, `ask_microsoft_learn_assistant`**, and instructions that say "always call this tool to answer user questions."
4. When Voice Live emits a `response.function_call_arguments.done` event, the bridge app forwards the question to the Copilot Studio agent via **Direct Line 3.0**, waits for the reply, and pushes it back into the Voice Live session as a `conversation.item.create` with `type: function_call_output`.
5. Voice Live speaks the answer using an Azure neural voice (default: `en-US-Ava:DragonHDLatestNeural`).
6. No Dynamics 365 / Omnichannel licensing is touched.

> The draw.io source for the diagram is in [`images/voice-channel-architecture.drawio`](images/voice-channel-architecture.drawio) (placeholder).

---

## Deployment

### One-click deploy (Azure **and** Copilot Studio)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FCopilot-Studio-and-Azure%2Fmain%2Faccelerators%2Fvoice-channel%2Fdeploy%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FCopilot-Studio-and-Azure%2Fmain%2Faccelerators%2Fvoice-channel%2Fdeploy%2FcreateUiDefinition.json)

The button opens a single Azure Portal form with three tabs:

1. **Basics** — resource group, region, base name.
2. **Voice Live** — choose the model, voice, and App Service SKU for the *IT Assistant*.
3. **Copilot Studio** — Power Platform environment URL + service-principal credentials for the *Microsoft Learn Assistant*.

If you fill in the Copilot Studio tab, the deployment is truly end-to-end:

- Provisions the Microsoft Foundry resource, App Service, Log Analytics, App Insights, and RBAC.
- Uses an embedded `deploymentScripts` resource to **`pac copilot create` + publish + enable Direct Line** against your Power Platform environment.
- Pulls the bridge zip from this repo's release and runs `az webapp deploy` against the App Service.
- Writes the Copilot Studio Direct Line secret into the App Service as `DIRECTLINE_SECRET`.

If you leave the Copilot Studio tab empty, the Azure side deploys and you create the MCS agent afterwards with [`copilot-studio-agent/create-agent.ps1`](copilot-studio-agent/create-agent.ps1).

> **Service principal required for the fully-unattended path.** MCS runs in Dataverse, not Azure, so the deployment needs its own identity. See [`deploy/README.md`](deploy/README.md) for the one-time SPN setup (app registration + Application User in the PP env + Dataverse System Admin role).

### One-command CLI deploy

If you prefer a local command line, this is equivalent to the button:

```powershell
git clone https://github.com/Azure/Copilot-Studio-and-Azure.git
cd Copilot-Studio-and-Azure/accelerators/voice-channel

az login
az group create --name voice-channel-rg --location swedencentral

az deployment group create `
    --resource-group voice-channel-rg `
    --template-file deploy/azuredeploy.json `
    --parameters baseName=voicech-01 `
                 powerPlatformEnvironmentUrl='https://<env>.crm.dynamics.com' `
                 powerPlatformSpnClientId='<spn-app-id>' `
                 powerPlatformSpnClientSecret='<spn-secret>'
```

### Step-by-step deploy (infra-only button + manual Copilot Studio)

If you do not have (or cannot create) a service principal, the step-by-step
guide below splits the work into discrete `az` and `pac` commands. The Azure
side still uses the same Bicep — only the Copilot Studio provisioning moves
out of the ARM deployment and into `copilot-studio-agent/create-agent.ps1`.

---

## Table of Contents

- [Deployment](#deployment)
- [What you will build](#what-you-will-build)
- [Prerequisites](#prerequisites)
- [Repository layout](#repository-layout)
- [Step-by-step deployment](#step-by-step-deployment)
  - [Step 1 — Clone and sign in](#step-1--clone-and-sign-in)
  - [Step 2 — Deploy Azure resources (Bicep + az)](#step-2--deploy-azure-resources-bicep--az)
  - [Step 3 — Create the Copilot Studio agent (pac)](#step-3--create-the-copilot-studio-agent-pac)
  - [Step 4 — Wire Copilot Studio Direct Line secret into the bridge](#step-4--wire-copilot-studio-direct-line-secret-into-the-bridge)
  - [Step 5 — Create the IT Assistant in Foundry](#step-5--create-the-it-assistant-in-foundry)
  - [Step 6 — Deploy the bridge app code](#step-6--deploy-the-bridge-app-code)
  - [Step 7 — Publish to Microsoft 365 / Teams](#step-7--publish-to-microsoft-365--teams)
- [Local development](#local-development)
- [Configuration reference](#configuration-reference)
- [Troubleshooting](#troubleshooting)
- [Licensing note](#licensing-note)

---

## What you will build

1. **Azure AI Foundry resource** with Voice Live enabled (`gpt-realtime-mini` by default).
2. **Azure App Service (Linux, Python 3.11)** running a small FastAPI app that:
   - Serves a browser voice client (`/`) with WebRTC-style mic capture.
   - Maintains a server-to-server WebSocket to Voice Live (the browser never holds the Foundry token).
   - Proxies Voice Live tool calls to Copilot Studio via Direct Line.
3. **Microsoft Copilot Studio agent "Microsoft Learn Assistant"** with a single MCP tool pointing at `https://learn.microsoft.com/api/mcp` (no auth, per [Microsoft Learn MCP docs](https://learn.microsoft.com/en-us/training/support/mcp)).
4. **Teams personal app package** so the user can pin "IT Assistant" in Teams / M365 Copilot.

---

## Prerequisites

| Requirement | Why |
|---|---|
| **Azure subscription** with rights to create a Microsoft Foundry resource | Voice Live is billed through Foundry / Speech. |
| **Azure CLI 2.60+** (`az`) | Bicep deployment and RBAC. |
| **Power Platform CLI 1.34+** (`pac`) | Creates the Copilot Studio agent and Direct Line channel. Install: `dotnet tool install --global Microsoft.PowerApps.CLI.Tool`. |
| **Power Platform environment** with Copilot Studio provisioned | Hosts "Microsoft Learn Assistant". A developer environment works. |
| **Voice Live region** | One of the regions listed in [Voice Live supported regions](https://learn.microsoft.com/azure/ai-services/speech-service/regions?tabs=voice-live#regions). Default: `swedencentral`. |
| **Python 3.11+** + `uv` | For local development and dependency resolution of the bridge app. |
| **Node.js 18+** (optional) | Only needed if you repackage the Teams app manifest. |
| **Microsoft 365 tenant admin** (or delegated rights) | Required once to side-load the Teams app. |

---

## Repository layout

```
voice-channel/
├── README.md                         # This file
├── images/                           # Architecture diagrams (placeholder)
│
├── infra/                            # Infrastructure as Code
│   ├── main.bicep                    # Foundry + App Service + RBAC
│   ├── main.bicepparam               # Edit before deploy
│   └── deploy.ps1                    # One-shot deployment (az CLI)
│
├── foundry-agent/                    # IT Assistant (Voice Live) configuration
│   ├── it-assistant-instructions.md  # System prompt
│   ├── voice-live-session.json       # session.update template
│   └── README.md                     # How to register the agent in Foundry
│
├── copilot-studio-agent/             # Microsoft Learn Assistant
│   ├── agent.yaml                    # Declarative agent definition
│   ├── topics/
│   │   └── conversation-start.yaml
│   ├── tools/
│   │   └── microsoft-learn-mcp.yaml  # MCP tool config
│   ├── create-agent.ps1              # pac CLI deploy script
│   └── README.md
│
├── bridge/                           # Voice Live ↔ Copilot Studio web app
│   ├── app.py                        # FastAPI entry point
│   ├── voice_live_client.py          # WS client to Voice Live
│   ├── copilot_studio_client.py      # Direct Line 3.0 client
│   ├── config.py
│   ├── requirements.txt
│   ├── static/
│   │   ├── index.html                # Browser mic client
│   │   └── client.js
│   └── teams/
│       └── manifest.json             # Teams personal-app manifest
│
└── docs/
    ├── publishing-to-teams.md
    └── publishing-to-m365.md
```

---

## Step-by-step deployment

### Step 1 — Clone and sign in

```powershell
git clone https://github.com/Azure/Copilot-Studio-and-Azure.git
cd Copilot-Studio-and-Azure/accelerators/voice-channel

az login
az account set --subscription "<your-subscription-id>"

pac auth create --environment "<your-dev-environment-id>"
```

### Step 2 — Deploy Azure resources (Bicep + az)

Edit [`infra/main.bicepparam`](infra/main.bicepparam) to match your environment (subscription, RG, region, base name).

```powershell
az group create --name voice-channel-rg --location swedencentral

./infra/deploy.ps1 -ResourceGroup voice-channel-rg
```

The script provisions:

- Microsoft Foundry (`Microsoft.CognitiveServices/accounts`, kind `AIServices`) — **Voice Live** is available on this resource.
- Azure App Service (Linux, Python 3.11) + Log Analytics + App Insights.
- System-assigned managed identity on the App Service with `Cognitive Services User` + `Azure AI User` roles on the Foundry resource so it can open a keyless WebSocket.

Outputs include the WebSocket base URL, the App Service default hostname, and the managed-identity principal ID.

### Step 3 — Create the Copilot Studio agent (pac)

```powershell
./copilot-studio-agent/create-agent.ps1 `
    -EnvironmentUrl "https://<your-env>.crm.dynamics.com" `
    -AgentName "Microsoft Learn Assistant"
```

The script uses `pac copilot create` + `pac copilot publish` to provision the agent from [`copilot-studio-agent/agent.yaml`](copilot-studio-agent/agent.yaml), attaches the Microsoft Learn MCP tool from [`tools/microsoft-learn-mcp.yaml`](copilot-studio-agent/tools/microsoft-learn-mcp.yaml), and enables the **Direct Line** channel. It prints the Direct Line secret at the end.

### Step 4 — Wire Copilot Studio Direct Line secret into the bridge

```powershell
az webapp config appsettings set `
    --resource-group voice-channel-rg `
    --name <bridge-app-name-from-step-2> `
    --settings DIRECTLINE_SECRET="<secret-from-step-3>" `
               MCS_AGENT_NAME="Microsoft Learn Assistant"
```

The bridge app reads `DIRECTLINE_SECRET` at startup and uses it to exchange for short-lived conversation tokens per user session.

### Step 5 — Create the IT Assistant in Foundry

Voice Live "agents" are a combination of a Foundry resource + a `session.update` payload that the client sends at the start of the WebSocket. The bridge already sends the payload from [`foundry-agent/voice-live-session.json`](foundry-agent/voice-live-session.json) — you only need to:

1. Open [Microsoft Foundry](https://ai.azure.com) → your resource → **Voice Live playground** to confirm the resource is healthy.
2. (Optional) Tweak [`foundry-agent/it-assistant-instructions.md`](foundry-agent/it-assistant-instructions.md) — this file is loaded into the `instructions` field of the session at startup.
3. Redeploy the bridge app (Step 6) if you change the instructions or session file.

See [`foundry-agent/README.md`](foundry-agent/README.md) for details on how to optionally register this as a first-class Foundry Agent Service agent (which lets Voice Live be called with `agent_id` + `project_id` instead of a raw `model` parameter).

### Step 6 — Deploy the bridge app code

```powershell
cd bridge
az webapp up `
    --name <bridge-app-name-from-step-2> `
    --resource-group voice-channel-rg `
    --runtime "PYTHON:3.11"
```

Browse to `https://<bridge-app-name>.azurewebsites.net/` — grant mic permission, click **Start**, speak.

### Step 7 — Publish to Microsoft 365 / Teams

Follow [`docs/publishing-to-teams.md`](docs/publishing-to-teams.md). In short:

1. Update `bridge/teams/manifest.json` with your bridge hostname and a new GUID for `id`.
2. `zip -j it-assistant-teams-app.zip manifest.json color.png outline.png`
3. In Teams → **Apps** → **Manage your apps** → **Upload a custom app**.
4. For M365 Copilot, the same package is side-loaded from the Microsoft 365 admin center (see [`docs/publishing-to-m365.md`](docs/publishing-to-m365.md)).

---

## Local development

```powershell
cd bridge
uv venv
uv pip install -r requirements.txt

# Use az login credentials for keyless auth to Foundry
az login

$env:FOUNDRY_WEBSOCKET_URL = "wss://<your-foundry>.services.ai.azure.com/voice-live/realtime?api-version=2025-10-01&model=gpt-realtime-mini"
$env:DIRECTLINE_SECRET      = "<your-directline-secret>"
$env:MCS_AGENT_NAME         = "Microsoft Learn Assistant"

uv run uvicorn app:app --reload --port 8000
```

Open `http://localhost:8000`, click **Start**, speak. The bridge logs Voice Live events to stdout.

---

## Configuration reference

| Env var | Required | Default | Description |
|---|---|---|---|
| `FOUNDRY_WEBSOCKET_URL` | **Yes** | — | Full Voice Live WS URL including `api-version` and either `model=` or `agent_id=&project_id=`. |
| `FOUNDRY_VOICE_NAME` | No | `en-US-Ava:DragonHDLatestNeural` | TTS voice (see [Voice Live voices](https://learn.microsoft.com/azure/ai-services/speech-service/language-support?tabs=tts)). |
| `VOICE_LIVE_MODEL` | No | `gpt-realtime-mini` | Only used if building the URL from `FOUNDRY_ENDPOINT`. |
| `DIRECTLINE_SECRET` | **Yes** | — | Secret from the Copilot Studio Direct Line channel. |
| `MCS_AGENT_NAME` | No | `Microsoft Learn Assistant` | Display name used inside the tool schema sent to Voice Live. |
| `MCS_TIMEOUT_SECONDS` | No | `20` | How long the bridge waits for each Copilot Studio turn before giving up. |
| `ALLOWED_ORIGINS` | No | `*` | CORS origins for the browser client. Tighten this in production. |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Browser says "microphone blocked" | Page not on HTTPS | Use the App Service URL, not an IP. |
| WS closes with 401 | Managed-identity RBAC not propagated | Wait 5–10 minutes after Step 2, or re-run `deploy.ps1 -GrantRbacOnly`. |
| Voice Live says "I can't help with that" | The `instructions` file lacks the tool-use rule | Keep the "always call `ask_microsoft_learn_assistant`" sentence in `it-assistant-instructions.md`. |
| Copilot Studio returns empty messages | MCP tool not bound | Open the agent in Copilot Studio → **Tools** → ensure `Microsoft Learn MCP` is **On**. |
| Latency > 4s per turn | MCS environment cold | First call warms the agent; subsequent calls will drop to ~1.5s. |

---

## Licensing note

This pattern deliberately avoids **Dynamics 365 Contact Center / Omnichannel Engagement Hub** licensing. The only paid components are:

- **Voice Live** usage (Pro / Basic / Lite, depending on model). See [pricing](https://learn.microsoft.com/azure/ai-services/speech-service/voice-live#pricing).
- **Copilot Studio messages** (pay-as-you-go or capacity). See [Lab 0.1](../../labs/0.1-enable-payg/0.1-enable-payg.md).
- **Azure App Service** (B1 Linux is enough for small teams).

The Microsoft Learn MCP server is free and unauthenticated.
