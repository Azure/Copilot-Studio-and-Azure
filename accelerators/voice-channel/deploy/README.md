# One-click deployment — Azure + Power Platform

Powers the **Deploy to Azure** button in the main [README](../README.md). This
folder is the self-contained artefact the portal consumes; `azd up` from the
root is still the preferred path for CLI users.

## What the button does

Opens the Azure Portal with a four-tab form:

1. **Basics** — resource group, region, environment name (seeds all resource names).
2. **Foundry + Voice Live** — Voice Live model, TTS voice, MCS agent name.
3. **Server image source** — GitHub URL + branch used by the ACR-build step (defaults: this repo on `main`).
4. **Copilot Studio (optional)** — Power Platform env URL + SPN creds. Fill these to auto-create the "Microsoft Learn Assistant" MCS agent during deployment. Leave blank to create it yourself later.
5. **Secret access** — your Entra object ID, so you can read the Direct Line secret from Key Vault post-deploy.

The deployment then:

1. Provisions **Microsoft Foundry** (AIServices), **Azure Container Registry** (Basic), **Container Apps Environment** + **Container App**, **Key Vault**, **Log Analytics**, **Application Insights**, and a **User-assigned Managed Identity** with the right RBAC on all of them.
2. Runs an embedded `deploymentScripts/build-image` that calls `az acr build` against the GitHub source URL — no local Docker needed. The Container App is then updated to the built image tag.
3. *(If the Copilot Studio tab was filled)* Runs an embedded `deploymentScripts/provision-mcs` that installs `pac` CLI, authenticates with your SPN, creates + publishes the MCS agent, enables the Direct Line channel, and writes the channel secret to Key Vault.

When the portal says "Deployment complete" you have:

- A Container App serving the Voice Live web UI at its FQDN (falls back to **model mode** — speaks but doesn't call MCS until the next step).
- *(Optional)* A Copilot Studio agent and a Direct Line secret sitting in Key Vault.

## What's still manual (two scripts, five minutes)

Running from your workstation after the portal finishes:

```powershell
# 1. Pull the Direct Line secret from Key Vault (skip this if you didn't fill
#    the Copilot Studio tab — use copilot-studio-agent/create-agent.ps1 first)
$dl = az keyvault secret show `
        --vault-name <kv-name-from-outputs> `
        --name mcs-directline-secret `
        --query value -o tsv

# 2. Create the Foundry IT Assistant + attach the Direct Line tool +
#    wire FOUNDRY_AGENT_ID into the Container App
cd ../foundry-agent
./create-foundry-agent.ps1 `
    -FoundryEndpoint  '<foundry-endpoint-from-outputs>' `
    -DirectLineSecret $dl `
    -Model            'gpt-4.1' `
    -ContainerAppName '<container-app-name-from-outputs>' `
    -ResourceGroup    '<rg>'

# 3. Publish the IT Assistant to Teams + Microsoft 365 Copilot
./publish-to-teams.ps1 `
    -FoundryEndpoint '<foundry-endpoint>' `
    -ProjectId       '<project-id-printed-by-step-2>' `
    -AssistantId     '<assistant-id-printed-by-step-2>'
```

## Why these last two aren't in the button

- **IT Assistant creation** needs a Foundry **project** to already exist, and project creation is a Foundry-portal action (no Bicep surface yet). Once that's true, `create-foundry-agent.ps1` takes ~30 s.
- **publish-copilot** hasn't got a fully automatable REST surface in every Foundry ring yet. The script does as much as REST allows and falls back to printing the portal click-path.

## Service principal prerequisite for the Copilot Studio tab

The MCS deployment script needs an identity that can write to your Power
Platform environment. Create one once per tenant:

```powershell
# 1. Create an app registration + secret
$app = New-AzADApplication -DisplayName "voice-channel-deploy"
$sp  = New-AzADServicePrincipal -ApplicationId $app.AppId
$pw  = New-AzADAppCredential -ApplicationId $app.AppId -EndDate (Get-Date).AddYears(1)
Write-Host "Tenant    : $((Get-AzContext).Tenant.Id)"
Write-Host "Client ID : $($app.AppId)"
Write-Host "Secret    : $($pw.SecretText)   # copy — shown once"

# 2. Register the SPN as an Application User in the target PP environment:
#    https://admin.powerplatform.microsoft.com -> Environments -> <env> ->
#    Settings -> Users + permissions -> Application users -> New app user
#    Assign the "System Administrator" Dataverse security role.
```

Paste tenant ID / client ID / secret into the **Copilot Studio** tab.

## Files

| File | Purpose |
|---|---|
| [`main.bicep`](main.bicep) | Source of truth. Infra + both deployment scripts. |
| [`azuredeploy.json`](azuredeploy.json) | Compiled ARM JSON — what the portal button points at. Rebuild after any Bicep change: `az bicep build --file main.bicep --outfile azuredeploy.json`. |
| [`createUiDefinition.json`](createUiDefinition.json) | Portal form (four tabs). |

## Rebuilding the ARM template

```powershell
az bicep build --file main.bicep --outfile azuredeploy.json
```

Commit both files together so the Deploy to Azure button URL always reflects
the current Bicep.
