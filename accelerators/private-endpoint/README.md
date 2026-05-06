# Azure Content Understanding behind Private Endpoint + Power Platform

## Objective

Provide an end-to-end accelerator for hosting **Azure AI Content Understanding**
behind a **Private Endpoint** (no public network access) and consuming it from
a **Power Platform** Managed Environment via [Enterprise Policy / VNet
injection](https://learn.microsoft.com/power-platform/admin/vnet-support-setup-configure?tabs=existing%2Csingle&pivots=powershell#setup-with-powershell).

> Azure AI Services lets you set `publicNetworkAccess=Disabled`, but Power
> Platform is **not** a "trusted Microsoft service" for Cognitive Services —
> `bypass=AzureServices` alone won't let Power Platform reach a private-endpoint-locked
> account. A Power Platform Enterprise Policy linked to a delegated subnet is
> the supported way to bridge that gap.

What you get when you finish the steps below:

* `Microsoft.CognitiveServices/accounts` (kind `AIServices`) with `publicNetworkAccess=Disabled`, custom subdomain, and a Private Endpoint into a dedicated subnet.
* Three Private DNS zones linked to the primary VNet:
  `privatelink.cognitiveservices.azure.com`, `privatelink.openai.azure.com`,
  `privatelink.services.ai.azure.com`.
* Two delegated subnets in paired Azure regions for Power Platform VNet injection (multi-region PP geos like `unitedstates` require subnets in two regions).
* `Microsoft.PowerPlatform/enterprisePolicies` (kind `vnet`) referencing both delegated subnets, linked to your Managed PP environment.
* A Power Platform custom connector for the Content Understanding REST API plus a connectivity test.

## Architecture

![Power Platform → VNet → Azure Content Understanding](docs/ppvnet-acu-solution-architecture.png)

Repo layout:

```
infra/
  deploy.bicep              # one-click unified template (source of azuredeploy.json)
  azuredeploy.json          # compiled ARM template used by the Deploy to Azure button
  main.bicep                # modular VNet + AI Services + PE + DNS template
  main.bicepparam           # default address spaces (no env-specific values)
  enterprise-policy.bicep   # Microsoft.PowerPlatform/enterprisePolicies (vnet)
powerplatform/
  contentunderstanding-connector.swagger.json   # OpenAPI 2.0 source
  apiProperties.json                            # connection params / branding
scripts/
  load-env.ps1                     # parses .env into env vars
  deploy.ps1                       # deploys infra/* using values from .env
  link-enterprise-policy.ps1       # Enable/Disable subnet injection on PP env
  create-and-test-connector.ps1    # pac connector create + connectivity test
.env.example                       # copy to .env and fill in
```

## Getting Started

### Video Walkthrough

> 🎥 *Coming soon.* A short walkthrough of one-click deployment, linking the
> Enterprise Policy, and validating connectivity from a Power Automate flow.
>
> Speaker script / transcript: [docs/video-walkthrough.md](docs/video-walkthrough.md).

### Prerequisites

| Requirement | Notes |
| --- | --- |
| Azure subscription Owner / Contributor | RG, networking, AI Services, PE, DNS, Enterprise Policy |
| Azure CLI ≥ `2.50` | only required for the scripted path |
| PowerShell 7+ (`pwsh`) | for the helper scripts |
| `pac` CLI signed in to the target PP environment | `pac auth list` |
| `Microsoft.PowerPlatform.EnterprisePolicies` PowerShell module | auto-installed by `link-enterprise-policy.ps1` |
| Power Platform / Global Administrator | required to enable Managed Environment + link the policy |
| Target environment is a **Managed Environment** | Sandbox is not allowed; enable in PPAC |

### Deployment

You have two options. Pick **one** of them, then continue with the linking step.

#### Option A — One-click ARM deploy (recommended)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fgokseloral%2Faccelerator-privateendpoint%2Fmain%2Finfra%2Fazuredeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fgokseloral%2Faccelerator-privateendpoint%2Fmain%2Finfra%2Fazuredeploy.json)

The portal blade collects:

| Parameter | Description | Example |
| --- | --- | --- |
| `baseName` | 3–11 chars, lowercase alphanumerics, used to derive resource names | `prvendcu` |
| `location` | Primary Azure region (Content Understanding-supported) | `westus`, `swedencentral`, `australiaeast` |
| `secondaryLocation` | Paired Azure region for the second PP-delegated subnet | `eastus` (paired with `westus`) |
| `powerPlatformGeo` | PP geo for the Enterprise Policy resource location (NOT an Azure region) | `unitedstates`, `europe`, `asia`, `australia` |
| `powerPlatformEnvironmentId` | GUID of the target PP environment (NOT the org URL) | `00000000-0000-0000-0000-000000000000` |
| `vnetAddressPrefix` / `peSubnetPrefix` / `ppSubnetPrefix` | Primary VNet + subnet CIDRs | `10.50.0.0/16` / `10.50.1.0/24` / `10.50.2.0/24` |
| `secondaryVnetAddressPrefix` / `secondaryPpSubnetPrefix` | Secondary VNet + delegated subnet CIDRs (must NOT overlap primary) | `10.51.0.0/16` / `10.51.2.0/24` |
| `enterprisePolicyName` | Name of the `Microsoft.PowerPlatform/enterprisePolicies` resource | `ep-vnet-prvendcu` |

Tenant ID, subscription ID, and the signed-in identity come from the portal
session — you don't need to enter them.

**Region-pair reference** (pick `secondaryLocation` from the [Azure paired regions list](https://learn.microsoft.com/azure/reliability/cross-region-replication-azure#azure-paired-regions)):

| Primary (`location`) | Paired (`secondaryLocation`) | PP geo (`powerPlatformGeo`) |
| --- | --- | --- |
| `westus` | `eastus` | `unitedstates` |
| `swedencentral` | `swedensouth` | `europe` |
| `australiaeast` | `australiasoutheast` | `australia` |

#### Option B — Scripted (`.env` + PowerShell)

```powershell
# 1. Copy .env.example -> .env and fill in the values for your tenant
Copy-Item .env.example .env
# edit .env (PP_ENVIRONMENT_ID, PP_TENANT_ID, AZURE_SUBSCRIPTION_ID, ...)

# 2. Provision Azure infra + Enterprise Policy
./scripts/deploy.ps1
```

`.env` is gitignored; `.env.example` is the only file checked in.

#### Final step — link the Enterprise Policy to your PP environment

The ARM template (and the scripted path) stops at provisioning. Linking the
policy to the Power Platform environment requires Power Platform admin auth
that ARM cannot perform, so it runs locally:

```powershell
# Make sure .env has PP_ENVIRONMENT_ID and PP_TENANT_ID set
./scripts/link-enterprise-policy.ps1 -UseDeviceCode
```

To unlink later (e.g. before changing the policy's subnets):

```powershell
./scripts/link-enterprise-policy.ps1 -Unlink
```

## Testing

### 1. Push the custom connector + run the connectivity check

```powershell
./scripts/create-and-test-connector.ps1
```

The script calls `GET /contentunderstanding/analyzers?api-version=<preview>`
directly against the AI Services endpoint and reports the result:

| Run from | Expected | Meaning |
| --- | --- | --- |
| Your laptop (public internet) | `403 Public access is disabled` | ✅ lockdown is working |
| VM inside `snet-pe` (use `-InsideVnetTest`) | `200 OK` | ✅ private endpoint + DNS working |
| Power Automate flow in linked env | `200 OK` | ✅ end-to-end PP → PE working |

> The "Test operation" button in the **custom connector designer** routes
> through the connector authoring host (`*.azure-apihub.net`) and **does not
> use VNet injection**. Always validate from a real flow run.

### 2. Verify the Enterprise Policy link

```powershell
. ./scripts/load-env.ps1
$tok = az account get-access-token --resource 'https://service.powerapps.com/' --query accessToken -o tsv
$uri = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$env:PP_ENVIRONMENT_ID" + '?api-version=2019-10-01&$expand=properties.enterprisePolicies'
Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $tok" } |
  Select-Object -ExpandProperty properties |
  Select-Object -ExpandProperty enterprisePolicies |
  ConvertTo-Json -Depth 10
```
![PowerShell Command To Check Linked Status](image-1.png)
Look for `"linkStatus": "Linked"` inside the `vNets` object — that confirms
the policy is bound to the environment. (PowerShell's default table view
truncates this nested field, so we pipe to `ConvertTo-Json` to see it in full.)

### 3. End-to-end test from a Power Automate flow

1. In the linked PP environment, create a flow with an **Instant** trigger.
2. Add an action from the custom connector (e.g. **List Analyzers**).
3. Create a new connection — supply the Cognitive Services key as the API key.
4. Run the flow. A `200` response confirms Power Platform → delegated subnet → Private Endpoint → Azure AI Services is fully wired.

![Testing Custom Connector connection to VNET via  Power Automate Flow](image.png)

### Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| `404` from `enterprisePolicies/vnet/link` | Environment is not a Managed Environment yet. Enable it in PPAC, then re-run. |
| `Environment location 'unitedstates' does not match the enterprise policy location 'westus'` | The Enterprise Policy resource's `location` must be the PP geo (`unitedstates`), not an Azure region. The provided template handles this; redeploy if you set it manually. |
| `EnterprisePolicyUpdateNotAllowed` when redeploying the policy | Policy is currently linked to an environment. Run `link-enterprise-policy.ps1 -Unlink`, redeploy, then re-link. |
| Custom connector test from PP flow returns `403 ThrowExceptionDueToTrafficDenied` | Connection cached from before the policy link. Delete the connection (Power Apps → Connections), re-create it, retry. |
| Custom connector doesn't appear in flow designer's **Custom** tab | Add the connector to a Dataverse solution (`pac connector update --solution-unique-name <name>`), then refresh. |

### Cleanup

```powershell
./scripts/link-enterprise-policy.ps1 -Unlink
az group delete -n $env:AZURE_RESOURCE_GROUP --yes --no-wait
```
