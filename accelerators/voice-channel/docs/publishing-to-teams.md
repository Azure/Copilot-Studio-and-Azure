# Publishing the IT Assistant to Microsoft Teams

After the bridge App Service is live and the MCS agent is published, package
the bridge as a Teams **personal app** so users can pin the IT Assistant in
Teams and talk to it from the left rail.

## What gets published

A Teams personal app is a zip containing:

- `manifest.json` — app metadata + a `staticTabs` entry pointing at the bridge URL.
- `color.png` — 192×192 icon.
- `outline.png` — 32×32 transparent outline icon.

The user loads the tab; the tab hosts the browser client from
[`bridge/static/index.html`](../bridge/static/index.html); the client opens a
WebSocket back to the bridge, which bridges to Voice Live.

## Steps

### 1. Fill in the manifest

Open [`bridge/teams/manifest.json`](../bridge/teams/manifest.json). Replace
every `REPLACE-WITH-…` placeholder:

| Placeholder | Value |
|---|---|
| `REPLACE-WITH-NEW-GUID` | Generate a fresh GUID (`New-Guid` in PowerShell). |
| `REPLACE-WITH-BRIDGE-HOSTNAME` | The App Service hostname, e.g. `voicech-01-bridge.azurewebsites.net`. Do **not** include the `https://` in `validDomains`. |

### 2. Create the icons

Teams requires two PNGs:

| File | Size | Notes |
|---|---|---|
| `color.png` | 192×192 | Full-color, opaque background, no transparency. |
| `outline.png` | 32×32 | Solid white-on-transparent line art. |

Any "microphone" icon will do for a first prototype. Drop both files next to
`manifest.json` in `bridge/teams/`.

### 3. Zip the package

```powershell
cd bridge/teams
Compress-Archive -Path manifest.json, color.png, outline.png -DestinationPath it-assistant-teams-app.zip -Force
```

### 4. Side-load into Teams (dev / personal use)

1. Open Teams → **Apps** → **Manage your apps** → **Upload a custom app** → **Upload a custom app** (for yourself).
2. Select `it-assistant-teams-app.zip`.
3. Click **Add** when the install dialog appears.
4. The **IT Assistant** tab appears in the left rail. Click it. The browser
   client loads inside Teams, asks for mic permission (Teams proxies this to
   the OS), then connects.

### 5. Publish tenant-wide (optional, admin path)

Once you have tested side-loading, publish to the whole tenant:

1. [Teams Admin Center](https://admin.teams.microsoft.com) → **Teams apps** → **Manage apps** → **Upload new app**.
2. Upload the same zip.
3. Once approved, go to **Setup policies** → pin the **IT Assistant** so it
   appears by default for users in scope.

### 6. Microsoft 365 Copilot distribution

See [`publishing-to-m365.md`](publishing-to-m365.md) for pushing the same app
package into M365 Copilot chat.

---

## Known limitations

- Teams enforces **Content Security Policy** on hosted tabs. The bridge sets
  its own CSP via FastAPI defaults, but if you front it with Azure Front Door
  / API Management, ensure the tab URL still responds with
  `Content-Security-Policy-Report-Only` or no CSP at all for the initial
  prototype. Teams can't render the page if CSP blocks `connect-src 'self'
  wss://<bridge-host>`.
- Teams does **not** natively stream voice to a personal app tab — the mic is
  captured inside the tab's own iframe (standard `getUserMedia`). That means
  the conversation only runs while the tab is in the foreground. This is fine
  for a personal assistant experience. For always-on / call-based voice you
  would need a Teams Calling bot instead, which is a larger build outside the
  scope of this accelerator.
- Sound playback is routed through the tab's `<audio>` element / WebAudio
  context — not Teams' system audio mixer — so the user hears it through the
  same device they selected in Teams' device settings.
