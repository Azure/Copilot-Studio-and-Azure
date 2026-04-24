# Voice Channel for Copilot Studio — Foundry IT Assistant across Teams, M365, and Web

An accelerator that gives a Microsoft Copilot Studio agent a **real-time voice
experience** and **native Teams / Microsoft 365 Copilot distribution** —
without the Omnichannel / Contact Center Engagement Hub licence.

Adapted from
[Azure-Samples/call-center-voice-agent-accelerator](https://github.com/Azure-Samples/call-center-voice-agent-accelerator)
with three additions:

- **Three user-facing channels** from one agent (custom web UI, Microsoft Teams, Microsoft 365 Copilot Chat)
- **Voice Live in "agent mode"** — the WebSocket connects by `agent_id`, so the Foundry IT Assistant agent's instructions and tools apply automatically on every session
- **Copilot Studio + Microsoft Learn MCP backend** for grounded answers

## Solution architecture

The editable source lives in [`images/voice-channel-architecture.drawio`](images/voice-channel-architecture.drawio). Open it at [app.diagrams.net](https://app.diagrams.net) to edit, then export a PNG alongside it.

```
┌─────────────────┐ ┌────────────────┐ ┌────────────────────────┐
│ Microsoft Teams │ │ M365 Copilot   │ │ Custom Web UI          │
│ (text + mic)    │ │ (text + mic)   │ │ (Voice Live streaming) │
└───────┬─────────┘ └───────┬────────┘ └──────────┬─────────────┘
        │  Azure Bot Service  │                   │  wss → Voice Live
        └──────────┬──────────┘                   │
                   ▼                              ▼
        ┌─────────────────────────────────────────────────┐
        │  Microsoft Foundry Agent Service — IT Assistant │
        │  instructions + ask_microsoft_learn_assistant   │
        │  (OpenAPI tool, Direct Line 3.0)                │
        └─────────────────────┬───────────────────────────┘
                              │ HTTPS
                              ▼
        ┌─────────────────────────────────────────────────┐
        │  Copilot Studio — "Microsoft Learn Assistant"   │
        │  + Microsoft Learn MCP tool                     │
        └─────────────────────┬───────────────────────────┘
                              │ streamable HTTP
                              ▼
                https://learn.microsoft.com/api/mcp
```

| Surface | Transport | Voice UX |
|---|---|---|
| Web UI (Container App) | Voice Live WebSocket, browser mic → PCM16 | Real-time full-duplex streaming, barge-in, HD voices |
| Microsoft Teams | Azure Bot Service (publish-copilot) | Text + M365 Copilot's push-to-talk mic |
| M365 Copilot Chat | Azure Bot Service (same app package) | Text + M365 Copilot's push-to-talk mic |

The Foundry IT Assistant agent is **the same one** across all three surfaces —
same instructions, same Microsoft Learn MCP backend.

---

## One-click deploy (Azure + Power Platform)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FCopilot-Studio-and-Azure%2Fmain%2Faccelerators%2Fvoice-channel%2Fdeploy%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FCopilot-Studio-and-Azure%2Fmain%2Faccelerators%2Fvoice-channel%2Fdeploy%2FcreateUiDefinition.json)

The button walks you through a four-tab portal form (Basics / Foundry + Voice Live / Server image source / Copilot Studio / Secret access). It provisions every Azure resource, builds the server container from this repo's source via **ACR Tasks** (no local Docker needed), and — if you provide a Power Platform SPN — also creates the **Microsoft Learn Assistant** Copilot Studio agent and writes the Direct Line secret into Key Vault in the same deployment.

Two PowerShell scripts still need to run from your workstation after the button completes: `foundry-agent/create-foundry-agent.ps1` (creates the IT Assistant agent) and `foundry-agent/publish-to-teams.ps1` (publishes to Teams + M365). See [`deploy/README.md`](deploy/README.md) for the SPN prerequisite and the exact follow-up commands.

---

## Embed the web UI in Teams and Microsoft 365

The accelerator ships **two complementary Teams surfaces** that you can install independently:

| Teams surface | What the user sees | How it's installed |
|---|---|---|
| **Embedded tab** (real-time voice) | The Voice Live web UI rendered inside Teams — full-duplex streaming, barge-in, HD voice | Build [`teams-app/dist/teams-app.zip`](teams-app/) with `teams-app/package.ps1`, upload via **Teams → Apps → Upload a custom app** |
| **Chat bot** (text / push-to-talk) | Chat with `@IT Assistant` in Teams | Run [`foundry-agent/publish-to-teams.ps1`](foundry-agent/publish-to-teams.ps1), upload that package |

The embedded tab is a **Teams personal app** with `staticTabs` pointing at your Container App URL. One Compress-Archive call packs `manifest.json + color.png + outline.png` into the zip users install. When the tenant admin uploads the same zip through the Teams Admin Center, it also surfaces in **Microsoft 365** under **Apps** in [M365 Chat](https://m365.cloud.microsoft/chat) and the Outlook side-pane.

The server already sets the `Content-Security-Policy: frame-ancestors …teams.microsoft.com …microsoft365.com …cloud.microsoft` header (see [`server/app/main.py`](server/app/main.py)) so the iframe renders, and the browser client detects the Teams host via `@microsoft/teams-js` to suppress the header/footer and honour the Teams dark / high-contrast theme.

See [`teams-app/README.md`](teams-app/README.md) for the full build + install walkthrough, including the tenant-wide rollout via the Teams Admin Center.

---

## Repository layout

```
voice-channel/
├── azure.yaml                          # azd service map
├── README.md                           # this file
│
├── infra/
│   ├── main.bicep                      # Foundry + Container App + ACR + Key Vault + LA + App Insights
│   ├── main.bicepparam                 # azd-aware parameter file
│   └── abbreviations.json              # azd naming convention
│
├── server/                             # Container App service (Python FastAPI)
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── README.md
│   └── app/
│       ├── main.py                     # FastAPI entrypoint
│       ├── voice_live.py               # WS relay (agent mode)
│       ├── config.py
│       └── static/                     # Voice Live-style web UI
│           ├── index.html
│           ├── style.css
│           └── client.js
│
├── foundry-agent/                      # IT Assistant Foundry Agent
│   ├── it-assistant-instructions.md    # System prompt
│   ├── it-assistant.agent.json         # REST body template
│   ├── ask-mcs.openapi.yaml            # OpenAPI tool → MCS Direct Line
│   ├── create-foundry-agent.ps1        # Creates agent + attaches tool + updates Container App
│   ├── publish-to-teams.ps1            # publish-copilot flow → Teams package
│   └── README.md
│
└── copilot-studio-agent/               # Microsoft Learn Assistant (knowledge backend)
    ├── agent.yaml                      # Declarative agent def (Direct Line only)
    ├── tools/microsoft-learn-mcp.yaml  # MCP tool config
    ├── topics/conversation-start.yaml
    ├── create-agent.ps1                # pac CLI deploy
    └── README.md
```

---

## Prerequisites

| Requirement | Why |
|---|---|
| **Azure subscription** + rights to create Foundry, Container Apps, ACR, Azure Bot Service | All of these are provisioned. |
| **[Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) (`azd`) 1.9+** | One-command `azd up` deployment. |
| **[Docker](https://www.docker.com/products/docker-desktop/) or the [Buildpack](https://buildpacks.io/) integration** | `azd deploy` builds the server image. Docker Desktop is the easy path. |
| **Azure CLI 2.60+** (`az`) | Token acquisition + Container App env-var updates. |
| **Power Platform CLI 1.34+** (`pac`) | Creates the MCS agent and enables Direct Line. Install: `dotnet tool install --global Microsoft.PowerApps.CLI.Tool`. |
| **Power Platform environment** with Copilot Studio enabled | Hosts "Microsoft Learn Assistant". |
| **`Azure AI Project Manager`** role on the Foundry project | Required to publish agent applications. |
| **M365 tenant admin** (or delegated app-catalog rights) | To side-load or tenant-publish the Teams app. |

---

## Deployment — `azd up` + two PowerShell scripts

> If you prefer a portal experience, use the [**Deploy to Azure button**](#one-click-deploy-azure--power-platform) above — it runs the infra + the container-image build + (optionally) the MCS agent creation in one go. The CLI flow below is identical in scope but gives you step-by-step control.

### 1. Provision infra and deploy the web UI

```powershell
git clone https://github.com/Azure/Copilot-Studio-and-Azure.git
cd Copilot-Studio-and-Azure/accelerators/voice-channel

azd auth login
azd init                # first time only — pick a region (swedencentral is the default)
azd up                  # provisions Foundry, Container Apps, ACR, Key Vault, LA, App Insights
                        # + builds server/Dockerfile, pushes to ACR, deploys to Container App
```

After this step the web UI is live at the Container App FQDN, but it runs in
**model mode** (it can talk, but won't call MCS — there's no agent yet).

### 2. Create the Copilot Studio backend

```powershell
./copilot-studio-agent/create-agent.ps1 `
    -EnvironmentUrl 'https://<your-env>.crm.dynamics.com'
```

Prints a **Direct Line secret**. Copy it — you need it in the next step.

### 3. Create the Foundry "IT Assistant" agent + attach MCS as a tool

```powershell
# azd has already exported these to your environment
azd env get-values | Out-File -Encoding ascii .env.azd

./foundry-agent/create-foundry-agent.ps1 `
    -FoundryEndpoint  $env:FOUNDRY_ENDPOINT `
    -DirectLineSecret '<secret-from-step-2>' `
    -Model            'gpt-4.1'
```

This script:
- creates the "IT Assistant" agent in your Foundry project
- attaches `ask_microsoft_learn_assistant` (OpenAPI tool with the Direct Line secret baked into bearer auth)
- writes `FOUNDRY_AGENT_ID` + `FOUNDRY_PROJECT_ID` to the Container App, which triggers a revision restart

The web UI is now in **agent mode**. Visit the Container App URL and speak.

### 4. Publish to Teams + Microsoft 365 Copilot

```powershell
./foundry-agent/publish-to-teams.ps1 `
    -FoundryEndpoint $env:FOUNDRY_ENDPOINT `
    -ProjectId       '<project-id-from-step-3>' `
    -AssistantId     '<assistant-id-from-step-3>'
```

This runs the [publish-copilot](https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot)
flow. It creates an Azure Bot Service resource and produces
`dist/it-assistant-teams-package.zip`.

Side-load the zip: **Teams → Apps → Manage your apps → Upload a custom app**.
For tenant-wide rollout, upload to the Teams Admin Center instead and flip
**Publishing status** to **Published**. The same package surfaces the agent
under **Integrated apps** in the M365 admin center.

---

## Testing the three channels

| Channel | Test |
|---|---|
| **Web UI** | Open `https://<app>.<env>.<region>.azurecontainerapps.io`, click **Start talking**, say *"What is Azure Functions Flex Consumption?"*. Answer speaks back in ~1 second with real-time VAD. |
| **Teams** | Install the zip, open the app in the left rail, type the same question. Voice replies use M365 Copilot's mic (click the mic in the composer). |
| **M365 Copilot Chat** | `@IT Assistant` in M365 Chat, ask the same question. |

App Insights (`log-*-<hash>` workspace) captures every turn with end-to-end latency; expect ~500 ms for the web UI, 1.5–3 s for Teams/M365.

---

## Why this shape

| Decision | Rationale |
|---|---|
| **azd + Container Apps** (not App Service) | Matches the `call-center-voice-agent-accelerator` pattern. Container Apps has first-class websockets, scales to multiple replicas, and deploys from a `Dockerfile`. |
| **Agent mode, not model mode** | The same Foundry agent serves the web UI (by `agent_id`) and Teams/M365 (by `publish-copilot`). One instruction set, one tool, three surfaces. |
| **Direct Line OpenAPI tool** | The user asked for "Foundry → MCS"; Direct Line is MCS's stable, documented interop. OpenAPI is the Foundry-native way to wrap it. |
| **Microsoft Learn MCP**, not a private index | Learn is the canonical source for Microsoft products. Free, no auth, no ingestion step. |
| **Key Vault provisioned but optional in the default scripts** | The secret handling is simple for the CLI flow. The vault is there ready for a production-grade upgrade (read the secret at deploy time; rotate on a schedule). |

---

## Licensing note

- **Microsoft Foundry** — pay-as-you-go on the model (GPT-4.1 / gpt-realtime-mini / etc.) and the Voice Live minutes.
- **Azure Container Apps** — ~$40/month for one vCPU + 2 GiB replica running 24×7. Scales to zero is off because cold starts hurt voice latency.
- **Azure Container Registry** — Basic SKU, under $5/month.
- **Azure Bot Service** — F0 free tier handles personal and pilot usage; upgrade to S1 for production.
- **Copilot Studio messages** — pay-as-you-go or capacity. See [Lab 0.1](../../labs/0.1-enable-payg/0.1-enable-payg.md).
- **Microsoft Learn MCP** — free.
- **No Dynamics 365 Contact Center / Omnichannel SKU is touched.**

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `azd up` fails on ACR pull | Managed-identity role propagation (2–5 min) | Wait, then `azd deploy server`. |
| Web UI connects but never hears audio back | Still in model mode | Run `create-foundry-agent.ps1` (Step 3) so Voice Live gets `agent_id`. |
| `401` on tool call | Direct Line secret rotated | Re-run `create-agent.ps1`, copy new secret, re-run `create-foundry-agent.ps1`. |
| Teams publish fails with REST 404 | `publish-copilot` endpoint not GA on your Foundry ring | Follow the portal click-path the script prints. |
| No sound in web UI, page is on `http://` | Browsers block mic on non-HTTPS | Use the Container App HTTPS URL, not a rewritten IP. |
| Agent answers without calling the tool | Instructions not loaded | Check the Foundry portal — the `instructions` field should include the "use `ask_microsoft_learn_assistant` for every factual question" sentence. |
