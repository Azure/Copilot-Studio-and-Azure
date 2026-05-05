# Foundry IT Assistant

The IT Assistant is a **Microsoft Foundry Agent Service** agent. Because it
lives as a first-class agent object (not just a session config), the same
agent serves all three user-facing channels:

| Channel | Transport | How it reaches the agent |
|---|---|---|
| Custom Web UI | Voice Live WebSocket (full-duplex audio) | `?agent_id={id}&project_id={proj}` on the Voice Live URL |
| Microsoft Teams | Azure Bot Service (text + M365 Copilot mic) | created by `publish-to-teams.ps1` |
| M365 Copilot Chat | Azure Bot Service (text + M365 Copilot mic) | same package as Teams |

The agent has one custom tool — `ask_microsoft_learn_assistant` — which calls
the Copilot Studio backend over Direct Line. That tool + the instructions in
[`it-assistant-instructions.md`](it-assistant-instructions.md) are applied on
every call, no matter which channel.

## Files

| File | Purpose |
|---|---|
| `it-assistant-instructions.md` | System prompt. |
| `it-assistant.agent.json` | Request body template for `POST /api/projects/{id}/assistants`. |
| `ask-mcs.openapi.yaml` | OpenAPI 3.0 spec for the Direct Line tool. |
| `create-foundry-agent.ps1` | Creates the assistant, attaches the tool, wires the agent ID into the Container App. |
| `publish-to-teams.ps1` | Runs the publish-copilot flow → Teams + M365 package zip. |

## Deploy

Prerequisites:

- `azd up` has completed (provisions Foundry + Container App)
- `../copilot-studio-agent/create-agent.ps1` has run and printed the Direct Line secret
- You have `Azure AI Project Manager` on the Foundry project
- A Foundry **project** exists inside the Foundry resource (create one in the [Foundry portal](https://ai.azure.com) if not)

```powershell
# Pull azd outputs into your shell
azd env get-values | Out-File -Encoding ascii .env.azd
# (Container App name and Foundry endpoint are among the outputs.)

# 1. Create the Foundry agent + attach Direct Line tool + update Container App
./create-foundry-agent.ps1 `
    -FoundryEndpoint  $env:FOUNDRY_ENDPOINT `
    -DirectLineSecret '<secret-from-create-agent.ps1>' `
    -Model            'gpt-4.1'

# 2. Publish to Teams / M365 Copilot
./publish-to-teams.ps1 `
    -FoundryEndpoint $env:FOUNDRY_ENDPOINT `
    -ProjectId       '<project-id-printed-by-step-1>' `
    -AssistantId     '<assistant-id-printed-by-step-1>'
```

## How Voice Live reaches the agent

Once `create-foundry-agent.ps1` has run, the Container App has:

```
FOUNDRY_AGENT_ID=<assistant-id>
FOUNDRY_PROJECT_ID=<project-id>
```

The server builds the Voice Live URL as:

```
wss://<foundry>.services.ai.azure.com/voice-live/realtime
  ?api-version=2025-10-01
  &agent_id=<assistant-id>
  &project_id=<project-id>
```

Voice Live then applies the agent's instructions and tools automatically on
every session — the server doesn't have to send a `session.update` with
tools/instructions.

## How Teams and M365 reach the agent

`publish-to-teams.ps1` uses the Foundry publish-copilot flow, which:

1. Creates an Entra app registration for the agent identity.
2. Provisions an Azure Bot Service resource wired to that identity.
3. Builds a Teams app package (`.zip`) with bot ID, manifest, icons.

Users install the `.zip` in Teams (or the tenant admin publishes it tenant-wide
from the Teams Admin Center). Teams/M365 routes each chat activity as text
to the Foundry agent via the Bot Service, and replies flow back the same way.
Voice on this path is M365 Copilot's native mic + TTS (push-to-talk) — not
Voice Live streaming.

## Direct Line secret handling

- The secret is a long-lived static credential. Rotate it periodically in
  Copilot Studio → **Channels → Direct Line → Regenerate**, then re-run
  `create-foundry-agent.ps1` to re-attach the tool with the new secret.
- For production, store the secret in the Key Vault provisioned by
  `infra/main.bicep` and update both scripts to read from there.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `401` on tool call | Direct Line secret rotated | Re-run `../copilot-studio-agent/create-agent.ps1`, copy the new secret, re-run `create-foundry-agent.ps1`. |
| Agent answers from its own memory, never calls the tool | Instructions not loaded | Check the agent's `instructions` field in the Foundry portal. |
| `publish-to-teams.ps1` fails with 404 | Publish REST not GA on your ring | Follow the portal click-path the script prints. |
| Tool loops forever | `getActivities` not using latest watermark | Check the portal's tool-invocation trace. |
