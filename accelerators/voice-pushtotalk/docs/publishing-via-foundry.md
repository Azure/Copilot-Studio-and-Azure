# Publishing the IT Assistant to Microsoft 365 Copilot and Teams

The Foundry `publish-copilot` flow turns the IT Assistant agent into an
**Azure Bot Service**-backed app that users install from Teams (personal app)
or from the Microsoft 365 agent store. No custom hosting, no bridge.

Reference: <https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot>

---

## What the publish produces

When you (or `foundry-agent/publish-to-teams.ps1`) complete the publish:

1. An **Entra ID app registration** is created for the agent identity.
2. An **Azure Bot Service** resource is provisioned in your subscription. This is the channel plumbing between Teams / M365 Copilot and the Foundry agent — it does not host any custom code.
3. A **Teams / M365 package `.zip`** is generated. It contains the manifest, icons, and the bot's Entra app ID. You distribute this zip.

The Foundry agent continues to run in the Foundry Agent Service. The bot service just forwards messages into and out of it.

---

## Prerequisites

- `Azure AI Project Manager` role on the Foundry project (publishes the agent version).
- Permission to create resources in the target Azure subscription (the Bot Service resource).
- `Microsoft.BotService` provider registered (the script does this: `az provider register --namespace Microsoft.BotService`).
- The IT Assistant agent already created and tested in the Foundry portal — i.e. you have run `../foundry-agent/create-foundry-agent.ps1` and you have the `assistantId`.
- An HTTPS URL for **Website**, **Privacy**, and **Terms** (placeholder URLs are fine for dev).

---

## One-command publish

```powershell
../foundry-agent/publish-to-teams.ps1 `
    -FoundryEndpoint 'https://<base>-foundry.services.ai.azure.com' `
    -ProjectId       '<project-id>' `
    -AssistantId     '<assistant-id>'
```

If the publish REST endpoint is not yet GA in your Foundry ring, the script
falls back to printing the exact Portal click-path. Follow it — the end
artefact is the same `.zip`.

Output: `dist/it-assistant-teams-package.zip`.

---

## Portal walkthrough (fallback / reference)

1. Open <https://ai.azure.com> → select your project.
2. Navigate to **Agents** → **IT Assistant** → the version you want to ship.
3. **Publish** → **Publish to Teams and Microsoft 365 Copilot**.
4. **Azure Bot Service** → **Create an Azure Bot Service**.
5. Fill in the metadata:
    - Name: `IT Assistant`
    - Short description: *Ask Microsoft Learn anything — voice or text.*
    - Full description: *IT Assistant answers Microsoft product, Azure, M365, Power Platform, and developer questions using Microsoft Learn.*
    - Publisher: your org
    - Website / Privacy / Terms: HTTPS URLs
6. **Prepare Agent** → wait 1–2 minutes.
7. **Download the package** (or **Continue in-product** if you want Foundry to push to the tenant catalog for you).

---

## Installing in Teams (personal use)

1. Teams → **Apps** → **Manage your apps** → **Upload a custom app** → **Upload a custom app** (for yourself).
2. Select `it-assistant-teams-package.zip`.
3. Click **Add**.
4. Open the app from the left rail. Chat with it or click the mic icon.

## Installing for the whole tenant

1. [Teams Admin Center](https://admin.teams.microsoft.com) → **Teams apps** → **Manage apps** → **Upload new app**.
2. Upload the same zip.
3. Set **Publishing status** = **Published** and **Permissions** = **Granted**.
4. Optional: **Setup policies** → pin **IT Assistant** so it shows in the left rail by default.

## Surfacing in Microsoft 365 Copilot Chat

The same Teams package also surfaces in M365 Copilot.

1. [Microsoft 365 admin center](https://admin.cloud.microsoft) → **Copilot** → **Agents** → **Integrated apps**.
2. Find **IT Assistant** → set **Default state** = **Available**.
3. Users see the agent at <https://m365.cloud.microsoft/chat> under **Apps**.

---

## Voice UX — what users actually experience

- **Microsoft 365 Copilot Chat**: there is a mic button in the composer. Users press it, speak, the utterance is transcribed and sent to the IT Assistant. The reply is spoken back via TTS. This is **push-to-talk** — not full-duplex streaming.
- **Teams (Copilot-enabled tenant)**: same mic affordance inside the personal-app chat.
- **Teams (non-Copilot tenant)**: text-only. Voice mic is a Copilot feature.

If you need mid-utterance barge-in or a true phone-call feel, this publishing
path is not sufficient — you would need the Voice Live + bridge pattern we
deliberately removed, or a Teams Calling bot (separate, heavier build).

---

## Governance checklist

Before rolling to production:

- [ ] The Foundry agent identity has the RBAC it needs on any Azure resources it calls. Publishing creates a **new** identity separate from your project — re-assign roles.
- [ ] Metadata fields contain nothing sensitive (they are visible to users in the store).
- [ ] The Direct Line secret used by the agent's OpenAPI tool is rotated on a schedule (Copilot Studio → Channels → Direct Line → **Regenerate**).
- [ ] DLP policy in the target Power Platform env lists the Direct Line connector in an approved category.
- [ ] Microsoft Learn MCP usage meets [Microsoft APIs Terms of Use](https://learn.microsoft.com/legal/microsoft-apis/terms-of-use).

---

## Known limitations (from the publish-copilot docs)

- Published agents do not stream responses or show citations. The IT Assistant therefore paraphrases; the Learn article titles it cites are included inline as text instead of linked citations.
- File uploads and image generation work in Teams but not in Microsoft 365.
- Private Link is not supported for Teams or Azure Bot Service integrations.
