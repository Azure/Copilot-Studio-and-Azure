# Publishing the IT Assistant to Microsoft 365 (Copilot / M365 Chat)

The same Teams app package used for Teams can also surface in the Microsoft 365
Copilot experience (`https://m365.cloud.microsoft/chat`) and in the "Apps" list
of M365 web apps. This gives the user a single entry point across Outlook, M365
Chat, Teams, and Office on the web.

## Prerequisites

- You have already built `it-assistant-teams-app.zip` as described in [`publishing-to-teams.md`](publishing-to-teams.md).
- You have **Teams Administrator** role on the tenant (or delegated "Teams app catalog" rights).
- Users in scope have a Microsoft 365 Copilot licence *if* you want it to
  appear inside M365 Copilot chat as an agent. The Teams static tab itself
  does not require Copilot — it just needs Teams and the bridge URL.

## Steps

### 1. Upload to the tenant app catalog

1. [Teams Admin Center](https://admin.teams.microsoft.com) → **Teams apps** → **Manage apps** → **Upload new app**.
2. Select `it-assistant-teams-app.zip`. The admin center validates the manifest.
3. On the app's page, set **Publishing status** to **Published** and
   **Permissions** to **Granted**.

Within ~30 minutes the app is available tenant-wide in Teams *and* in the M365
app launcher (waffle menu).

### 2. Make it discoverable in M365 Copilot

Microsoft 365 Copilot reads the same Teams app catalog. To pin the IT Assistant
inside M365 Copilot:

1. M365 Admin Center → **Copilot** → **Agents** → **Integrated apps**.
2. Find **IT Assistant** in the list.
3. Set **Default state** to **Available** and optionally **Pin** for specific
   user groups.

After a sync, users see "IT Assistant" under **Apps** in M365 Chat. Clicking
it opens the static tab — the same voice experience they would get in Teams.

### 3. (Optional) Expose the MCS agent *directly* to M365 Copilot

If you also want the **Microsoft Learn Assistant** MCS agent to be callable
from M365 Copilot as a declarative agent (text, not voice):

1. Open the agent in Copilot Studio → **Channels** → **Microsoft 365 Copilot**.
2. **Turn on**. MCS generates a Copilot manifest and uploads it to your tenant.
3. Users can now `@Microsoft Learn Assistant` inside M365 Chat for a text Q&A
   experience.

Voice remains exclusively through the IT Assistant Foundry agent + bridge
app in this design — M365 Copilot does not yet expose a real-time voice API
that a third-party agent can plug into.

## Governance checklist

Before rolling to production, confirm:

- [ ] Bridge App Service has **AllowedOrigins** restricted to
      `https://teams.microsoft.com,https://*.cloud.microsoft`.
- [ ] App Service is behind a WAF / Azure Front Door if exposed publicly.
- [ ] Foundry resource has `disableLocalAuth: true` (flip in `main.bicep` once
      Entra auth is verified working).
- [ ] Data Loss Prevention (DLP) policy in the target Power Platform env
      lists the Direct Line connector in an **approved** category.
- [ ] Microsoft Learn MCP usage meets the [Microsoft APIs Terms of Use](https://learn.microsoft.com/legal/microsoft-apis/terms-of-use).
- [ ] App Insights logs scrub any user-uttered secrets (see
      `bridge/voice_live_client.py` — transcripts are logged only at DEBUG).
