# Voice (Push-to-Talk) for Copilot Studio — Foundry Agent + Microsoft Learn MCP

An accelerator that gives a Microsoft Copilot Studio agent a **voice-capable
Microsoft 365 / Teams surface** without the Omnichannel / Contact Center
Engagement Hub licence — and **without any custom hosting**.

The voice experience is **push-to-talk**, delivered natively by Microsoft 365
Copilot / Teams (the mic icon in the chat composer). There is no bridge app,
no WebSocket relay, no JavaScript client. Every hop is platform-native.

| Layer | Product | Role |
|---|---|---|
| Front | **Microsoft 365 Copilot / Teams** | User-facing channel. Mic button handles speech-to-text + TTS. |
| Agent | **Microsoft Foundry — Agent Service, "IT Assistant"** | Text agent with a custom OpenAPI tool. Published to Teams and M365 via the [publish-copilot flow](https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot). |
| Brain | **Microsoft Copilot Studio — "Microsoft Learn Assistant"** | Answers the actual questions. Grounded via the Microsoft Learn MCP server. Exposed to Foundry via its Direct Line channel. |
| Knowledge | **Microsoft Learn MCP** | `https://learn.microsoft.com/api/mcp` — streamable HTTP, no auth. |

---

## Solution architecture

```
      ┌───────────────────────────────────────────────────────────┐
      │        User in Microsoft Teams / Microsoft 365 Copilot    │
      │              (types or presses the mic icon)              │
      └─────────────────────────────┬─────────────────────────────┘
                                    │
                        ┌───────────▼──────────────┐
                        │   Azure Bot Service      │ ← created by publish-copilot
                        │   (channel plumbing)     │
                        └───────────┬──────────────┘
                                    │
                  ┌─────────────────▼─────────────────────────────┐
                  │  Microsoft Foundry — "IT Assistant"           │
                  │  (Agent Service, gpt-4.1)                     │
                  │  Tool: ask_microsoft_learn_assistant (OpenAPI)│
                  └─────────────────┬─────────────────────────────┘
                                    │  HTTPS (Direct Line 3.0)
                                    ▼
                  ┌───────────────────────────────────────────────┐
                  │  Copilot Studio — "Microsoft Learn Assistant" │
                  │  + Microsoft Learn MCP tool                   │
                  └─────────────────┬─────────────────────────────┘
                                    │  streamable HTTP (MCP)
                                    ▼
                        https://learn.microsoft.com/api/mcp
```

Key design notes:

- The Foundry agent is the **single user-facing identity**. It is the one that shows up in the Teams / M365 agent store as "IT Assistant".
- The Copilot Studio agent is **not** published to Teams or M365 directly — only its Direct Line channel is enabled. It is the knowledge backend.
- Voice is delivered by M365 Copilot's **push-to-talk** mic. The Foundry agent receives already-transcribed text; its replies are spoken back by M365 Copilot's own TTS. There is no Voice Live WebSocket anywhere in this pattern. If you need full-duplex streaming voice with mid-utterance barge-in, this is not the accelerator for you.

---

## Deployment

### One-click deploy (Azure **and** Copilot Studio)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FCopilot-Studio-and-Azure%2Fmain%2Faccelerators%2Fvoice-pushtotalk%2Fdeploy%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FCopilot-Studio-and-Azure%2Fmain%2Faccelerators%2Fvoice-pushtotalk%2Fdeploy%2FcreateUiDefinition.json)

Opens a portal form with four tabs:

1. **Basics** — resource group, region, base name.
2. **Foundry (IT Assistant)** — Foundry text model.
3. **Copilot Studio (Microsoft Learn Assistant)** — PP environment URL + SPN credentials.
4. **Secrets access** — your Entra object ID, so you can read the Direct Line secret from Key Vault afterwards.

If you fill the Copilot Studio tab, the deployment will:

- Provision Microsoft Foundry + Key Vault + Log Analytics + App Insights.
- Run an embedded `deploymentScripts` resource that `pac copilot create`s the MCS agent, enables Direct Line, and writes the secret into Key Vault.

After the portal deployment completes, run these two scripts from your workstation to finish the Foundry side (see [deploy/README.md](deploy/README.md) for SPN prereqs):

```powershell
# 1. Read the Direct Line secret from Key Vault and attach the tool to a Foundry assistant
./foundry-agent/create-foundry-agent.ps1 `
    -FoundryEndpoint 'https://<base>-foundry.services.ai.azure.com' `
    -DirectLineSecret (az keyvault secret show --vault-name <base>-kv --name mcs-directline-secret --query value -o tsv)

# 2. Publish the Foundry assistant to Microsoft 365 and Teams (publish-copilot flow)
./foundry-agent/publish-to-teams.ps1 `
    -FoundryEndpoint 'https://<base>-foundry.services.ai.azure.com' `
    -ProjectId       '<project-id>' `
    -AssistantId     '<assistant-id>'
```

### Step-by-step CLI deploy

If you prefer a local CLI flow:

```powershell
git clone https://github.com/Azure/Copilot-Studio-and-Azure.git
cd Copilot-Studio-and-Azure/accelerators/voice-pushtotalk

# 1. Infra (Foundry + observability)
az login
az group create --name voice-pushtotalk-rg --location swedencentral
./infra/deploy.ps1 -ResourceGroup voice-pushtotalk-rg

# 2. Copilot Studio agent — prints the Direct Line secret
./copilot-studio-agent/create-agent.ps1 `
    -EnvironmentUrl 'https://<your-env>.crm.dynamics.com'

# 3. Foundry agent + Direct Line tool
./foundry-agent/create-foundry-agent.ps1 `
    -FoundryEndpoint 'https://<base>-foundry.services.ai.azure.com' `
    -DirectLineSecret '<secret-from-step-2>'

# 4. Publish to Teams + M365 Copilot
./foundry-agent/publish-to-teams.ps1 `
    -FoundryEndpoint 'https://<base>-foundry.services.ai.azure.com' `
    -ProjectId       '<project-id-from-step-3>' `
    -AssistantId     '<assistant-id-from-step-3>'

# 5. Upload dist/it-assistant-teams-package.zip in Teams
#    (Apps -> Manage your apps -> Upload a custom app)
```

See [`docs/publishing-via-foundry.md`](docs/publishing-via-foundry.md) for the portal walkthrough and tenant-wide rollout.

---

## Repository layout

```
voice-pushtotalk/
├── README.md                          # This file
│
├── infra/                             # Core infra (no Key Vault, no deployScripts)
│   ├── main.bicep                     # Foundry + Log Analytics + App Insights
│   ├── main.bicepparam                # Edit before deploy
│   └── deploy.ps1                     # az deployment orchestrator
│
├── deploy/                            # One-click button (infra + Key Vault + MCS deployScript)
│   ├── main.bicep
│   ├── azuredeploy.json               # Compiled ARM
│   ├── createUiDefinition.json        # Portal form
│   └── README.md                      # SPN prereqs, ARM rebuild notes
│
├── foundry-agent/                     # IT Assistant (Foundry Agent Service)
│   ├── it-assistant-instructions.md   # System prompt
│   ├── it-assistant.agent.json        # POST body for the Foundry REST API
│   ├── ask-mcs.openapi.yaml           # OpenAPI spec for the Direct Line tool
│   ├── create-foundry-agent.ps1       # Creates assistant + attaches tool
│   ├── publish-to-teams.ps1           # publish-copilot flow
│   └── README.md
│
├── copilot-studio-agent/              # Microsoft Learn Assistant (backend)
│   ├── agent.yaml                     # Declarative agent def (Direct Line only)
│   ├── tools/microsoft-learn-mcp.yaml
│   ├── topics/conversation-start.yaml
│   ├── create-agent.ps1               # pac CLI deploy
│   └── README.md
│
└── docs/
    └── publishing-via-foundry.md      # Publish flow + Teams/M365 distribution
```

---

## Prerequisites

| Requirement | Why |
|---|---|
| **Azure subscription** with rights to create Microsoft Foundry + Azure Bot Service | Publish-copilot creates a Bot Service resource on first publish. |
| **Azure CLI 2.60+** (`az`) | Bicep deployment, RBAC, Key Vault reads. |
| **Power Platform CLI 1.34+** (`pac`) | Creates the MCS agent and enables Direct Line. Install: `dotnet tool install --global Microsoft.PowerApps.CLI.Tool`. |
| **Power Platform environment** with Copilot Studio enabled | Hosts "Microsoft Learn Assistant". |
| **`Azure AI Project Manager` role on the Foundry project** | Required to publish agent applications. |
| **M365 tenant admin** (or delegated Teams app-catalog rights) | To side-load or tenant-publish the Teams app. |

---

## Configuration reference

Everything is set either as Bicep params (`infra/main.bicepparam` or portal form) or as script params. No env vars on the Foundry side — the agent definition lives in Git.

| Parameter | Where | Default | Description |
|---|---|---|---|
| `baseName` | Bicep | `voicech-01` | Seeds Foundry + Key Vault names. 3–18 lowercase chars. |
| `location` | Bicep | `swedencentral` | Any Foundry-supported region. |
| `foundryModel` | Bicep (one-click only) | `gpt-4.1` | Text model used by IT Assistant. |
| `mcsAgentName` | Bicep / create-agent.ps1 | `Microsoft Learn Assistant` | Display name of the MCS backend. |
| `DirectLineSecret` | create-foundry-agent.ps1 | – | Secret from MCS Direct Line channel. Baked into the OpenAPI tool auth. |
| `Model` | create-foundry-agent.ps1 | `gpt-4.1` | Foundry model name. |

---

## Licensing note

- **Microsoft Foundry** — pay-as-you-go model usage (GPT-4.1 etc.) + a tiny amount of Key Vault.
- **Azure Bot Service F0** — free tier is enough for personal / pilot use; upgrade to S1 for production.
- **Copilot Studio messages** — pay-as-you-go or capacity. See [Lab 0.1](../../labs/0.1-enable-payg/0.1-enable-payg.md).
- **Microsoft Learn MCP** — free, unauthenticated.
- **No Dynamics 365 Contact Center / Omnichannel SKU is touched.**

Compared to a Voice Live real-time-streaming pattern: this accelerator trades full-duplex streaming voice for native Microsoft 365 / Teams publishing. You lose mid-utterance barge-in; you gain zero custom hosting, faster time to first deploy, and all of M365 Copilot's accessibility surface for free.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `publish-copilot` fails with "Version starts with 0" | Foundry requires the agent version > 0 | Bump the version in the Foundry portal before publishing. |
| Agent responds in Teams but never calls the tool | Instructions not loaded | Confirm the Foundry assistant's `instructions` field contains the "use `ask_microsoft_learn_assistant` for every factual question" sentence. |
| `401` from Direct Line | Secret rotated | Re-run `copilot-studio-agent/create-agent.ps1` to fetch a fresh secret, then re-run `create-foundry-agent.ps1` to re-attach the tool. |
| No agent reply in M365 Copilot after publish | RBAC not propagated OR published-agent identity missing roles | Wait 5–10 min. Then verify the **published** agent identity has any Azure roles it needs (publishing creates a new identity, separate from your project identity). |
| Teams side-load rejected | Manifest GUID already used | Every publish regenerates the manifest. If you re-publish after a failed first install, uninstall the old app first. |
