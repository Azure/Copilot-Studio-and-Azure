# Microsoft Learn Assistant — Copilot Studio agent

The MCS agent that actually answers the user's questions. The voice agent in
Foundry is dumb on purpose: it exists only to speak and listen, and forwards
every turn to this agent via Direct Line.

## Files

| File | Purpose |
|---|---|
| [`agent.yaml`](agent.yaml) | Declarative agent definition (name, description, instructions, tools). |
| [`tools/microsoft-learn-mcp.yaml`](tools/microsoft-learn-mcp.yaml) | MCP tool pointing at `https://learn.microsoft.com/api/mcp`. |
| [`topics/conversation-start.yaml`](topics/conversation-start.yaml) | Short greeting (keeps latency low on first turn). |
| [`create-agent.ps1`](create-agent.ps1) | End-to-end provisioning via pac CLI. |

## Deploy

Prerequisites:

- Power Platform CLI 1.34+  (`dotnet tool install --global Microsoft.PowerApps.CLI.Tool`)
- A Dataverse/Power Platform environment with Copilot Studio enabled

```powershell
./create-agent.ps1 -EnvironmentUrl "https://<your-env>.crm.dynamics.com"
```

The script:

1. Runs `pac auth create` for the target env.
2. Creates the agent from `agent.yaml` (`pac copilot create --file`, falling back to `pac copilot new` + `pac copilot update --file` for older pac versions).
3. Publishes it (`pac copilot publish`).
4. Enables the **Direct Line** channel and prints the secret.
5. Emits a one-liner `az webapp config appsettings set` that wires the secret into the bridge.

## Notes on the MCP tool

Microsoft Learn MCP is:

- A remote **Streamable HTTP** MCP server at `https://learn.microsoft.com/api/mcp`.
- **Unauthenticated** — you do not need to create a connection reference or app registration.
- Subject to the [Microsoft APIs Terms of Use](https://learn.microsoft.com/legal/microsoft-apis/terms-of-use).
- Rate-limited softly by the accelerator to 30 req/min per agent to prevent a runaway voice loop from hammering the server.

It exposes three tools to the agent:

| Tool | Use |
|---|---|
| `microsoft_docs_search` | Semantic search across Learn content. The agent calls this first for most questions. |
| `microsoft_docs_fetch` | Fetches the full body of a specific Learn article by ID. |
| `microsoft_code_sample_search` | Searches Learn code samples (useful for how-to questions). |

## Manual fallback (portal path)

If `pac copilot create` does not work in your tenant (e.g. your environment is
pinned to an older ring), create the agent via the portal:

1. Go to [https://copilotstudio.microsoft.com](https://copilotstudio.microsoft.com).
2. **Create** → **New agent** → **Skip to configure** → name it **Microsoft Learn Assistant**.
3. In **Overview** → **Instructions**, paste the `instructions:` block from `agent.yaml`.
4. **Tools** → **+ Add a tool** → **Model Context Protocol** → URL `https://learn.microsoft.com/api/mcp` → no auth → add.
5. **Channels** → **Direct Line** → **Turn on**. Copy the secret.
6. **Publish**.

Then skip ahead to step 4 of the main README and paste the secret into the App Service settings.
