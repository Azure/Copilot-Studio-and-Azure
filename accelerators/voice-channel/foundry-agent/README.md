# Foundry IT Assistant — Voice Live configuration

The "IT Assistant" is **not** a long-lived Foundry object in this accelerator.
It is defined entirely by two files:

| File | Purpose |
|---|---|
| [`it-assistant-instructions.md`](it-assistant-instructions.md) | System prompt. Loaded into `session.instructions`. |
| [`voice-live-session.json`](voice-live-session.json) | Full `session.update` payload (voice, VAD, tools). |

When the bridge web app accepts a new user connection, it:

1. Reads both files.
2. Substitutes `${INSTRUCTIONS}`, `${VOICE_NAME}`, `${MCS_AGENT_NAME}` placeholders with values from app settings.
3. Opens `wss://<foundry>.services.ai.azure.com/voice-live/realtime?api-version=2025-10-01&model=<model>` with a managed-identity bearer token (scope `https://ai.azure.com/.default`).
4. Sends the payload as its first message.

This keeps the IT Assistant identity versioned in Git alongside the bridge code — which means no manual Foundry Portal clicks to update behaviour.

---

## Optional — promote to a first-class Foundry Agent Service agent

If you want the IT Assistant to show up in the **Foundry Portal → Agents** list
(and to be callable by `agent_id` + `project_id` instead of `model=`), create
it using the Azure CLI against your Foundry project:

```powershell
# 1. Find your project ID
az cognitiveservices account show `
    --name <foundry-name> `
    --resource-group <rg> `
    --query 'properties.endpoint' -o tsv

# 2. Create the agent via Foundry Agent Service REST API
$token = az account get-access-token --scope https://ai.azure.com/.default --query accessToken -o tsv
$body  = Get-Content ./voice-live-session.json -Raw `
           | ForEach-Object { $_.Replace('${INSTRUCTIONS}', (Get-Content ./it-assistant-instructions.md -Raw)) `
                                  .Replace('${VOICE_NAME}', 'en-US-Ava:DragonHDLatestNeural') `
                                  .Replace('${MCS_AGENT_NAME}', 'Microsoft Learn Assistant') }

Invoke-RestMethod `
    -Method Post `
    -Uri "https://<foundry>.services.ai.azure.com/api/projects/<project-id>/assistants?api-version=2025-10-01" `
    -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
    -Body @{
        name         = 'IT Assistant'
        model        = 'gpt-realtime-mini'
        instructions = (Get-Content ./it-assistant-instructions.md -Raw)
        tools        = @(@{ type = 'function'; function = @{
            name        = 'ask_microsoft_learn_assistant'
            description = 'Forward question to Copilot Studio Microsoft Learn Assistant.'
            parameters  = @{ type='object'; properties=@{ question=@{ type='string' } }; required=@('question') }
        }})
    } | ConvertTo-Json -Depth 10
```

Then point the bridge at the agent instead of the raw model by setting

```
FOUNDRY_WEBSOCKET_URL=wss://<foundry>.services.ai.azure.com/voice-live/realtime?api-version=2025-10-01&agent_id=<assistant-id>&project_id=<project-id>
```

Note that when you use the agent form, the `instructions` field is ignored in
`session.update` (it is read from the agent record), so you manage instructions
in Foundry rather than in Git. Pick whichever lifecycle fits your team.
