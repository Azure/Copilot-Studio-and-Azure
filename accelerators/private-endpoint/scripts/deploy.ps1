<#
.SYNOPSIS
  End-to-end deployment for Content Understanding behind a Private Endpoint
  with Power Platform VNet integration.

.DESCRIPTION
  Steps:
    1. Ensure resource group rg-prvendtest exists (westus).
    2. Register required RPs.
    3. Deploy infra/main.bicep   (VNet + subnets + AI Services + PE + DNS).
    4. Deploy infra/enterprise-policy.bicep (PP Enterprise Policy).
    5. (Optional) Link the policy to the Power Platform environment.
       Requires Managed Environment + tenant admin.

  Run from repo root.
#>
[CmdletBinding()]
param(
  [string] $EnvFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env'),
  [switch] $LinkEnterprisePolicy
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'load-env.ps1') -Path $EnvFile

$ResourceGroup       = $env:AZURE_RESOURCE_GROUP
$Location            = $env:AZURE_LOCATION
$SecondaryLocation   = $env:AZURE_SECONDARY_LOCATION
$SubscriptionId      = $env:AZURE_SUBSCRIPTION_ID
$PowerPlatformEnvId  = $env:PP_ENVIRONMENT_ID
$PpGeo               = $env:PP_GEO
$BaseName            = $env:BASE_NAME
$EnterprisePolicyName = $env:ENTERPRISE_POLICY_NAME

foreach ($v in 'ResourceGroup','Location','SubscriptionId','BaseName','EnterprisePolicyName','PpGeo') {
  if (-not (Get-Variable -Name $v -ValueOnly -ErrorAction SilentlyContinue)) {
    throw "Missing required value '$v' in $EnvFile"
  }
}

Write-Host "==> Setting subscription $SubscriptionId" -ForegroundColor Cyan
az account set --subscription $SubscriptionId | Out-Null

Write-Host "==> Registering required resource providers" -ForegroundColor Cyan
@(
  'Microsoft.Network',
  'Microsoft.CognitiveServices',
  'Microsoft.PowerPlatform'
) | ForEach-Object {
  az provider register --namespace $_ --wait | Out-Null
  Write-Host "    registered: $_"
}

Write-Host "==> Ensuring resource group $ResourceGroup in $Location" -ForegroundColor Cyan
az group create -n $ResourceGroup -l $Location --tags workload=content-understanding-pe | Out-Null

Write-Host "==> Deploying core infrastructure (VNet + AI Services + PE)" -ForegroundColor Cyan
$infraJson = az deployment group create `
  --resource-group $ResourceGroup `
  --name 'cu-pe-infra' `
  --template-file 'infra/main.bicep' `
  --parameters baseName=$BaseName location=$Location secondaryLocation=$SecondaryLocation `
  --query 'properties.outputs' -o json
if ($LASTEXITCODE -ne 0 -or -not $infraJson) { throw 'Core infra deployment failed (see error above).' }
$infra = $infraJson | ConvertFrom-Json

$aiName        = $infra.aiAccountName.value
$aiEndpoint    = $infra.aiAccountEndpoint.value
$ppSubnetId    = $infra.ppSubnetResourceId.value
$ppSubnetSecId = $infra.ppSubnetSecondaryResourceId.value
Write-Host "    AI Services account: $aiName"
Write-Host "    AI endpoint:         $aiEndpoint"
Write-Host "    PP subnet (primary): $ppSubnetId"
Write-Host "    PP subnet (secondary): $ppSubnetSecId"

Write-Host "==> Deploying Power Platform Enterprise Policy" -ForegroundColor Cyan
$policyJson = az deployment group create `
  --resource-group $ResourceGroup `
  --name 'cu-pe-enterprise-policy' `
  --template-file 'infra/enterprise-policy.bicep' `
  --parameters policyName=$EnterprisePolicyName location=$PpGeo `
               primarySubnetId=$ppSubnetId secondarySubnetId=$ppSubnetSecId `
  --query 'properties.outputs' -o json
if ($LASTEXITCODE -ne 0 -or -not $policyJson) { throw 'Enterprise Policy deployment failed.' }
$policy = $policyJson | ConvertFrom-Json
$policyArmId = $policy.policyId.value
Write-Host "    Enterprise policy ARM ID: $policyArmId"

# ---------------------------------------------------------------------------
# Persist outputs for downstream scripts (connector / tests)
# ---------------------------------------------------------------------------
$outFile = Join-Path $PSScriptRoot 'deployment-outputs.json'
@{
  aiAccountName     = $aiName
  aiAccountEndpoint = $aiEndpoint
  enterprisePolicyId = $policyArmId
  ppEnvironmentId   = $PowerPlatformEnvId
  resourceGroup     = $ResourceGroup
  subscriptionId    = $SubscriptionId
} | ConvertTo-Json | Set-Content $outFile
Write-Host "==> Wrote $outFile" -ForegroundColor Green

if ($LinkEnterprisePolicy) {
  Write-Host "==> Linking Enterprise Policy to PP environment $PowerPlatformEnvId" -ForegroundColor Cyan
  & "$PSScriptRoot/link-enterprise-policy.ps1" `
      -EnterprisePolicyArmId $policyArmId `
      -PowerPlatformEnvId    $PowerPlatformEnvId
} else {
  Write-Host ""
  Write-Host "Skipping policy link. To link later run:" -ForegroundColor Yellow
  Write-Host "  scripts/link-enterprise-policy.ps1 -EnterprisePolicyArmId '$policyArmId' -PowerPlatformEnvId '$PowerPlatformEnvId'" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Deployment complete." -ForegroundColor Green
