# Foundry IT Assistant — Agent Service + publish-copilot

The "IT Assistant" is a Microsoft Foundry **Agent Service** agent — a text
assistant with a custom OpenAPI tool that calls the Copilot Studio
"Microsoft Learn Assistant" over Direct Line.

Voice is handled entirely by the channel (Microsoft 365 Copilot / Teams),
not by this agent. See the top-level
[`../README.md`](../README.md) for the tradeoffs.

## Files

| File | Purpose |
|---|---|
| [`it-assistant-instructions.md`](it-assistant-instructions.md) | System prompt. Loaded into the Foundry assistant's `instructions` field. |
| [`it-assistant.agent.json`](it-assistant.agent.json) | Request body template for `POST /api/projects/{id}/assistants`. |
| [`ask-mcs.openapi.yaml`](ask-mcs.openapi.yaml) | OpenAPI 3.0 spec for the custom tool. Targets Direct Line 3.0. |
| [`create-foundry-agent.ps1`](create-foundry-agent.ps1) | Creates the assistant + attaches the tool. |
| [`publish-to-teams.ps1`](publish-to-teams.ps1) | Runs the `publish-copilot` flow; outputs the Teams `.zip`. |

## End-to-end flow

```
User (Teams / M365 Copilot)
   │  press mic or type
   ▼
Azure Bot Service  (created by publish-to-teams.ps1)
   │
   ▼
Foundry Agent Service — IT Assistant
   │
   │  OpenAPI tool: startConversation / postActivity / getActivities
   ▼
Copilot Studio — Microsoft Learn Assistant (Direct Line channel)
   │
   ▼  streamable HTTP MCP
Microsoft Learn  https://learn.microsoft.com/api/mcp
```

## Deploy

Prerequisites:

- Azure CLI (`az login`), role `Azure AI Project Manager` on the Foundry project
- The Copilot Studio agent already created (run `../copilot-studio-agent/create-agent.ps1` first; it prints the Direct Line secret)
- A Foundry project on the Foundry resource from `../infra/main.bicep` (create one in the [Foundry portal](https://ai.azure.com) if you haven't)

```powershell
# 1. Create the Foundry agent + attach the Direct Line OpenAPI tool
./create-foundry-agent.ps1 `
    -FoundryEndpoint 'https://<base>-foundry.services.ai.azure.com' `
    -DirectLineSecret '<secret-from-create-agent.ps1>' `
    -Model 'gpt-4.1'

# 2. Publish to Microsoft 365 Copilot + Teams
./publish-to-teams.ps1 `
    -FoundryEndpoint 'https://<base>-foundry.services.ai.azure.com' `
    -ProjectId       '<project-id-printed-by-step-1>' `
    -AssistantId     '<assistant-id-printed-by-step-1>'
```

Step 2 produces `dist/it-assistant-teams-package.zip`. Side-load it in Teams
(Apps → Manage your apps → Upload a custom app) for personal testing, or push
it to the tenant app catalogue via the Teams Admin Center. Full walkthrough in
[`../docs/publishing-via-foundry.md`](../docs/publishing-via-foundry.md).

## How the Direct Line secret is authenticated

Direct Line accepts the static channel secret as a bearer token on the
conversation / activity endpoints. `create-foundry-agent.ps1` patches the
secret into the tool's `auth.credentials.bearer_token` field when it attaches
the OpenAPI spec to the assistant. From that point on the Foundry agent
carries it as `Authorization: Bearer <secret>` on every call — no further
configuration required.

> ⚠️ The channel secret is a **long-lived** credential. For production,
> replace it with the Direct Line token-exchange flow (the REST spec already
> exposes a `/tokens/generate` endpoint you could wire up). Also rotate
> secrets on a schedule via the Copilot Studio **Channels → Direct Line**
> pane.

## Updating the agent

If you change either the instructions or the OpenAPI spec, re-run
`create-foundry-agent.ps1` against a **new agent version** (Foundry requires
monotonic agent versioning) or edit the existing assistant via the Foundry
portal. Changes to the tool spec do **not** require re-publishing the Teams
package unless the tool signature changes in a way that affects user-facing
behaviour.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `401` on tool call | Direct Line secret wrong / rotated | Re-run `../copilot-studio-agent/create-agent.ps1` to read a fresh secret, then re-run `create-foundry-agent.ps1`. |
| Agent answers from its own knowledge instead of calling the tool | Instructions not loaded | Confirm the `instructions` field on the assistant via the Foundry portal — it should contain the "Use the `ask_microsoft_learn_assistant` tool for every factual question" line. |
| Tool call loops forever | `getActivities` not using the latest watermark | Make sure the agent is passing the `watermark` query param returned from the previous call. This is declared in the OpenAPI spec; check the portal's tool-invocation trace. |
| `publish-to-teams.ps1` fails with "REST endpoint not found" | Programmatic publish not GA in your Foundry ring | The script falls back to printing the portal click-path. Follow it. |
