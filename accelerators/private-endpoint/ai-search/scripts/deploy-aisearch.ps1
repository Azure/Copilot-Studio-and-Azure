<#
.SYNOPSIS
  Deploys Azure AI Search behind a Private Endpoint with Power Platform VNet integration.

.DESCRIPTION
  Steps:
    1. Register required resource providers.
    2. Ensure the resource group exists.
    3. Deploy infra/main-aisearch.bicep (VNet + optional AI Search + PE + DNS + Enterprise Policy).
    4. Persist outputs to scripts/deployment-outputs-aisearch.json for downstream scripts.
    5. (Optional) Link the Enterprise Policy to the Power Platform environment.

  Run from the accelerators/private-endpoint/ai-search/ directory.

.PARAMETER EnvFile
  Path to the .env file. Defaults to .env in the parent (ai-search/) directory.

.PARAMETER LinkEnterprisePolicy
  If specified, calls the parent link-enterprise-policy.ps1 after deployment.

.EXAMPLE
  # Basic deploy (reads .env)
  ./scripts/deploy-aisearch.ps1

  # Deploy and immediately link the Enterprise Policy
  ./scripts/deploy-aisearch.ps1 -LinkEnterprisePolicy
#>
[CmdletBinding()]
param(
  [string] $EnvFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env'),
  [switch] $LinkEnterprisePolicy
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Load .env
# ---------------------------------------------------------------------------
$parentScripts = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts'
. (Join-Path $parentScripts 'load-env.ps1') -Path $EnvFile

$ResourceGroup        = $env:AZURE_RESOURCE_GROUP
$SubscriptionId       = $env:AZURE_SUBSCRIPTION_ID
$BaseName             = $env:BASE_NAME
$PpGeo                = $env:PP_GEO
$PowerPlatformEnvId   = $env:PP_ENVIRONMENT_ID
$EnterprisePolicyName = $env:ENTERPRISE_POLICY_NAME
$ProvisionAiSearch    = if ($env:PROVISION_AI_SEARCH -eq 'false') { 'false' } else { 'true' }
$ExistingAiSearchId   = if ($env:EXISTING_AI_SEARCH_RESOURCE_ID) { $env:EXISTING_AI_SEARCH_RESOURCE_ID } else { '' }
$AiSearchSku          = if ($env:AI_SEARCH_SKU) { $env:AI_SEARCH_SKU } else { 'basic' }

foreach ($v in 'ResourceGroup', 'SubscriptionId', 'BaseName', 'PpGeo', 'EnterprisePolicyName') {
  if (-not (Get-Variable -Name $v -ValueOnly -ErrorAction SilentlyContinue)) {
    throw "Missing required variable '$v' in $EnvFile"
  }
}

if ($ProvisionAiSearch -eq 'false' -and -not $ExistingAiSearchId) {
  throw "PROVISION_AI_SEARCH=false but EXISTING_AI_SEARCH_RESOURCE_ID is not set in $EnvFile"
}

Write-Host "==> Setting subscription $SubscriptionId" -ForegroundColor Cyan
az account set --subscription $SubscriptionId | Out-Null

Write-Host "==> Registering required resource providers" -ForegroundColor Cyan
@(
  'Microsoft.Network',
  'Microsoft.Search',
  'Microsoft.PowerPlatform'
) | ForEach-Object {
  az provider register --namespace $_ --wait | Out-Null
  Write-Host "    registered: $_"
}

Write-Host "==> Ensuring resource group $ResourceGroup" -ForegroundColor Cyan
az group create -n $ResourceGroup --tags workload=aisearch-pe | Out-Null

# ---------------------------------------------------------------------------
# Build parameter overrides
# ---------------------------------------------------------------------------
$params = @(
  "baseName=$BaseName",
  "powerPlatformRegion=$PpGeo",
  "powerPlatformEnvironmentId=$PowerPlatformEnvId",
  "provisionAiSearch=$ProvisionAiSearch",
  "aiSearchSku=$AiSearchSku",
  "enterprisePolicyName=$EnterprisePolicyName"
)

if ($ExistingAiSearchId) {
  $params += "existingAiSearchResourceId=$ExistingAiSearchId"
}

Write-Host "==> Deploying AI Search private endpoint infrastructure" -ForegroundColor Cyan
Write-Host "    provisionAiSearch = $ProvisionAiSearch"

$templateFile = Join-Path $PSScriptRoot '..\infra\main-aisearch.bicep'
$depJson = az deployment group create `
    --resource-group $ResourceGroup `
    --name 'aisearch-pe-infra' `
    --template-file $templateFile `
    --parameters @params `
    --query 'properties.outputs' -o json

if ($LASTEXITCODE -ne 0 -or -not $depJson) {
  throw 'Infrastructure deployment failed (see error above).'
}

$dep = $depJson | ConvertFrom-Json
$searchName      = $dep.searchServiceName.value
$searchEndpoint  = $dep.searchServiceEndpoint.value
$policyId        = $dep.enterprisePolicyId.value
$ppSubnetId      = $dep.ppSubnetResourceId.value
$ppSubnetSecId   = $dep.ppSubnetSecondaryResourceId.value

Write-Host "    AI Search name:     $searchName"
Write-Host "    AI Search endpoint: $searchEndpoint"
Write-Host "    Enterprise policy:  $policyId"

# ---------------------------------------------------------------------------
# Persist outputs for connector + test scripts
# ---------------------------------------------------------------------------
$outFile = Join-Path $PSScriptRoot 'deployment-outputs-aisearch.json'
@{
  searchServiceName    = $searchName
  searchServiceEndpoint = $searchEndpoint
  enterprisePolicyId   = $policyId
  ppSubnetResourceId   = $ppSubnetId
  ppSubnetSecondaryResourceId = $ppSubnetSecId
  resourceGroup        = $ResourceGroup
  subscriptionId       = $SubscriptionId
  ppEnvironmentId      = $PowerPlatformEnvId
} | ConvertTo-Json | Set-Content $outFile
Write-Host "==> Wrote $outFile" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Optional: link Enterprise Policy
# ---------------------------------------------------------------------------
if ($LinkEnterprisePolicy) {
  Write-Host "==> Linking Enterprise Policy to PP environment $PowerPlatformEnvId" -ForegroundColor Cyan
  $linkScript = Join-Path $parentScripts 'link-enterprise-policy.ps1'
  & $linkScript `
      -EnterprisePolicyArmId $policyId `
      -PowerPlatformEnvId    $PowerPlatformEnvId
} else {
  Write-Host ""
  Write-Host "Skipping Enterprise Policy link. To link later:" -ForegroundColor Yellow
  Write-Host "  cd .." -ForegroundColor Yellow
  Write-Host "  ./scripts/link-enterprise-policy.ps1 -EnterprisePolicyArmId '$policyId' -PowerPlatformEnvId '$PowerPlatformEnvId'" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Deployment complete." -ForegroundColor Green
