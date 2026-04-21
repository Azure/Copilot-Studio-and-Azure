# One-click deployment

This folder holds the artefacts powering the **Deploy to Azure** button in the
main [README.md](../README.md).

## Files

| File | Purpose |
|---|---|
| [`main.bicep`](main.bicep) | Source of truth — infra + bridge-code deploymentScript + optional MCS deploymentScript. |
| [`azuredeploy.json`](azuredeploy.json) | ARM JSON compiled from `main.bicep`. This is what the portal button points at. Rebuild after any bicep change: `az bicep build --file main.bicep --outfile azuredeploy.json`. |
| [`createUiDefinition.json`](createUiDefinition.json) | Portal form — groups the Voice Live and Copilot Studio parameters into tabs. |

## What the button does

When the user clicks it, Azure Portal:

1. Renders the form from `createUiDefinition.json` (Basic step + **Voice Live** tab + **Copilot Studio** tab).
2. Submits both outputs to `azuredeploy.json`, which deploys:
   - **Microsoft Foundry** (`AIServices`) with Voice Live
   - **App Service** (Linux, Python 3.11) + plan + App Insights + Log Analytics
   - **RBAC** (Cognitive Services User + Azure AI User) for the App Service MI on Foundry
   - A **user-assigned managed identity** with Website Contributor on the RG (used by the deployment scripts)
   - A **bridge-code `deploymentScripts` resource** that pulls the zipped `bridge/` folder from the GitHub release and runs `az webapp deploy --type zip`
   - *(optional)* A **Copilot Studio `deploymentScripts` resource** that installs `pac` CLI, authenticates with the SPN you supplied, creates the MCS agent from inline YAML, publishes it, enables Direct Line, and writes the secret into the App Service as `DIRECTLINE_SECRET`

If the user leaves the Power Platform fields empty, the MCS script is skipped
— they can run [`../copilot-studio-agent/create-agent.ps1`](../copilot-studio-agent/create-agent.ps1) manually afterwards.

## Prerequisites for the fully-unattended path

To get the one-click experience to also create the Copilot Studio agent, you
need an Entra service principal with:

- **Application User** in the target Power Platform environment
- **System Administrator** Dataverse security role

Set this up once per tenant:

```powershell
# 1. Create an app registration + secret
$app = New-AzADApplication -DisplayName "voice-channel-deploy"
$sp  = New-AzADServicePrincipal -ApplicationId $app.AppId
$pw  = New-AzADAppCredential -ApplicationId $app.AppId -EndDate (Get-Date).AddYears(1)
Write-Host "Tenant    : $((Get-AzContext).Tenant.Id)"
Write-Host "Client ID : $($app.AppId)"
Write-Host "Secret    : $($pw.SecretText)  # copy — shown once"

# 2. Register the SPN as an Application User in the Power Platform env
#    (Power Platform admin center -> Environments -> <env> -> Settings ->
#     Users + permissions -> Application users -> New app user)
#    Assign System Administrator role.
```

Paste the Tenant ID, Client ID, and Secret into the **Copilot Studio** tab of
the Deploy to Azure form.

## Rebuilding the ARM template

```powershell
az bicep build --file main.bicep --outfile azuredeploy.json
```

Commit both files together so the "Deploy to Azure" button always reflects
the current bicep.
