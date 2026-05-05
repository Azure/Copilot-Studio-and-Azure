# Embed the Voice Live web UI in Teams and Microsoft 365

This folder builds a Teams **personal app** that renders the Container App
web UI as a tab. Same zip works in Microsoft 365 (Apps pane in M365 Chat,
Outlook side-pane) once uploaded tenant-wide.

This is a **second** Teams surface alongside the Foundry agent's
publish-copilot bot:

| Teams surface | How it's added | UX |
|---|---|---|
| **This tab** | Upload `dist/teams-app.zip` as a custom Teams app | Voice Live web UI inside Teams — real-time full-duplex streaming, barge-in, HD voice |
| **Chat bot** (existing, see `../foundry-agent/publish-to-teams.ps1`) | Run `publish-to-teams.ps1`, upload that zip | Chat with `@IT Assistant` — text + M365 Copilot's push-to-talk mic |

Install one, the other, or both. They don't conflict.

## Files

| File | Purpose |
|---|---|
| [`manifest.template.json`](manifest.template.json) | Teams manifest v1.19 with `<FQDN>` and `<APP_ID>` placeholders. |
| [`package.ps1`](package.ps1) | Renders the template and zips the package. |
| `color.png`, `outline.png` | Placeholder icons (192×192 + 32×32). Replace before shipping tenant-wide. |

## Build

```powershell
# From the repo root, after `azd up` + `foundry-agent/create-foundry-agent.ps1`
cd accelerators/voice-channel/teams-app
./package.ps1
# -> dist/teams-app.zip (manifest.json + color.png + outline.png)
```

The script reads the Container App FQDN from `azd env get-values` and
generates a fresh app GUID on first run. Pass `-Fqdn` / `-AppId` to override.
Re-running with the same `-AppId` produces an update Teams can install
over the first version.

## Install — personal

1. Teams → **Apps** → **Manage your apps** → **Upload a custom app** → **Upload a custom app** (for yourself).
2. Pick `dist/teams-app.zip`.
3. Click **Add**.
4. Open **IT Assistant Voice** from the left rail. Grant microphone access when prompted. Click **Start talking**. Speak.

## Install — tenant-wide (and Microsoft 365)

Once you have tested the personal install, publish to the whole tenant:

1. [Teams Admin Center](https://admin.teams.microsoft.com) → **Teams apps** → **Manage apps** → **Upload new app**.
2. Upload `dist/teams-app.zip`.
3. On the app page: set **Publishing status** = **Published**, **Permissions** = **Granted**.
4. Optional — pin via **Teams apps** → **Setup policies** so the app lands in the left rail for users in scope.

After the Teams catalog syncs (~30 min), the same app appears in
**Microsoft 365** under the **Apps** pane of
[M365 Chat](https://m365.cloud.microsoft/chat) and in the Outlook side-pane.

## How the embed works

- Teams renders `https://<FQDN>/` (the Container App root) in an iframe.
- The server's `Content-Security-Policy: frame-ancestors …teams.microsoft.com …` header (set in `server/app/main.py`) allows the iframe.
- `devicePermissions: ["media"]` in the manifest silences the per-tab mic prompt — the browser's own `getUserMedia` call still runs and feeds the existing Voice Live pipeline.
- `@microsoft/teams-js` (loaded by `index.html` from the Microsoft CDN) detects the Teams host and hides the header/footer so the tab feels native.

Nothing about the web UI itself forks — the standalone page and the Teams
tab are the same URL.

## Known limitations / future items

| Item | Notes |
|---|---|
| **Placeholder icons** | `color.png` and `outline.png` are placeholder mic glyphs. Replace with your brand before tenant rollout. |
| **No SSO in v1** | The tab runs anonymously (the agent itself authenticates server-side via the Container App's managed identity). To tie sessions to the Teams user, add `webApplicationInfo` + an Entra app reg + Teams SSO flow. |
| **Personal scope only** | The manifest has `staticTabs` with `scopes: ["personal"]`. To surface in a team channel or a group chat, add `configurableTabs` with a small `/teams-config` handler — intentionally out of scope for v1 because it doubles the surface. |
| **Browser compatibility** | Tested in Teams on Chromium (Teams desktop, Edge web). Teams mobile renders iframes but mic permission UX varies by OS — confirm on Android/iOS if you plan to support mobile. |
