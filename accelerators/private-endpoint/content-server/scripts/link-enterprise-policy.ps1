<#
.SYNOPSIS
  Links a Power Platform Enterprise Policy (vnet / subnet injection) to a
  Managed Power Platform environment, using the official Microsoft module.

.DESCRIPTION
  Uses Microsoft.PowerPlatform.EnterprisePolicies::Enable-SubnetInjection,
  which calls the correct (internal) BAP API surface that the public
  /enterprisePolicies/{kind}/link route does not expose.

  REQUIREMENTS
    - The PP environment is a Managed Environment (protectionLevel=Standard).
    - The signed-in user is a Power Platform / Global admin AND has read
      access to the Azure Enterprise Policy resource.
#>
[CmdletBinding()]
param(
  [string] $EnterprisePolicyArmId,
  [string] $PowerPlatformEnvId,
  [string] $TenantId,
  [string] $ResourceGroup,
  [string] $SubscriptionId,
  [string] $EnvFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env'),
  [switch] $ForceAuth,
  [switch] $UseDeviceCode,
  [switch] $Unlink
)

$ErrorActionPreference = 'Stop'

# Pull defaults from .env (and from scripts/deployment-outputs.json for the
# enterprise policy ARM id) so callers don't need to paste IDs on the CLI.
if (Test-Path $EnvFile) { . (Join-Path $PSScriptRoot 'load-env.ps1') -Path $EnvFile }
if (-not $TenantId)            { $TenantId           = $env:PP_TENANT_ID }
if (-not $PowerPlatformEnvId)  { $PowerPlatformEnvId = $env:PP_ENVIRONMENT_ID }
if (-not $EnterprisePolicyArmId) {
  $outFile = Join-Path $PSScriptRoot 'deployment-outputs.json'
  if (Test-Path $outFile) {
    $EnterprisePolicyArmId = (Get-Content $outFile | ConvertFrom-Json).enterprisePolicyId
  }
}

# Fallback for the ARM-template path: discover the policy from the resource group.
if (-not $ResourceGroup)   { $ResourceGroup   = $env:AZURE_RESOURCE_GROUP }
if (-not $SubscriptionId)  { $SubscriptionId  = $env:AZURE_SUBSCRIPTION_ID }
if (-not $EnterprisePolicyArmId -and $ResourceGroup) {
  if (-not $SubscriptionId) { $SubscriptionId = az account show --query id -o tsv }
  if ($SubscriptionId) { az account set --subscription $SubscriptionId | Out-Null }
  Write-Host "==> Discovering Enterprise Policy in resource group $ResourceGroup" -ForegroundColor Cyan
  $EnterprisePolicyArmId = az resource list -g $ResourceGroup `
      --resource-type 'Microsoft.PowerPlatform/enterprisePolicies' `
      --query '[0].id' -o tsv 2>$null
  if (-not $EnterprisePolicyArmId) {
    throw "No Microsoft.PowerPlatform/enterprisePolicies resource found in '$ResourceGroup'."
  }
  Write-Host "    Found: $EnterprisePolicyArmId"
}

if (-not $TenantId) { $TenantId = az account show --query tenantId -o tsv 2>$null }

foreach ($v in 'EnterprisePolicyArmId','PowerPlatformEnvId','TenantId') {
  if (-not (Get-Variable -Name $v -ValueOnly -ErrorAction SilentlyContinue)) {
    throw "Missing required value '$v'. Set it in $EnvFile (AZURE_RESOURCE_GROUP enables policy discovery), pass it explicitly, or pass -ResourceGroup so the script can discover the Enterprise Policy."
  }
}

if (-not (Get-Module -ListAvailable -Name Microsoft.PowerPlatform.EnterprisePolicies)) {
  Write-Host "==> Installing Microsoft.PowerPlatform.EnterprisePolicies (CurrentUser)" -ForegroundColor Cyan
  Install-Module Microsoft.PowerPlatform.EnterprisePolicies -Scope CurrentUser -Force -AllowClobber
}
Import-Module Microsoft.PowerPlatform.EnterprisePolicies -Force

# Sign in to Azure FIRST so we control the auth flow (the module reuses the
# existing Az context if available). Use device-code when interactive
# WAM/browser fails to surface a window.
if (-not (Get-AzContext)) {
  if ($UseDeviceCode) {
    Write-Host "==> Connect-AzAccount -UseDeviceAuthentication" -ForegroundColor Cyan
    Connect-AzAccount -TenantId $TenantId -UseDeviceAuthentication | Out-Null
  } else {
    Write-Host "==> Connect-AzAccount" -ForegroundColor Cyan
    Connect-AzAccount -TenantId $TenantId | Out-Null
  }
}
$ctx = Get-AzContext
Write-Host "    Signed in as: $($ctx.Account.Id)  (tenant $($ctx.Tenant.Id))"

Write-Host "==> Enable-SubnetInjection" -ForegroundColor Cyan
Write-Host "    EnvironmentId : $PowerPlatformEnvId"
Write-Host "    PolicyArmId   : $EnterprisePolicyArmId"

if ($Unlink) {
  Write-Host "==> Disable-SubnetInjection" -ForegroundColor Yellow
  Disable-SubnetInjection -EnvironmentId $PowerPlatformEnvId
} elseif ($ForceAuth) {
  Enable-SubnetInjection -EnvironmentId $PowerPlatformEnvId -PolicyArmId $EnterprisePolicyArmId -ForceAuth
} else {
  Enable-SubnetInjection -EnvironmentId $PowerPlatformEnvId -PolicyArmId $EnterprisePolicyArmId
}

Write-Host "==> Link request submitted. Track status in PPAC -> environment -> VNet integration." -ForegroundColor Green
