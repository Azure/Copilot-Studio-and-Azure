<#
.SYNOPSIS
    Build the Teams app package that embeds the Voice Live web UI as a
    personal tab in Microsoft Teams and Microsoft 365.

.DESCRIPTION
    1. Resolves the Container App FQDN from `azd env get-values` or the
       -Fqdn parameter.
    2. Substitutes <FQDN> and a fresh <APP_ID> GUID into manifest.template.json.
    3. Emits dist/manifest.json and dist/teams-app.zip containing
       manifest.json + color.png + outline.png.

    The resulting zip is what you upload to Teams (personal install) or to
    the Teams Admin Center (tenant-wide rollout, which also surfaces it in
    Microsoft 365 Copilot Chat).

.PARAMETER Fqdn
    Container App FQDN, e.g. ca-xxx.livelyfield-12345.swedencentral.azurecontainerapps.io.
    If omitted, the script reads AZURE_CONTAINER_APP_FQDN from `azd env get-values`.

.PARAMETER AppId
    GUID for the Teams app identity. If omitted, a fresh GUID is generated.
    Reuse the same GUID across rebuilds so Teams treats updates as the same app.

.EXAMPLE
    ./package.ps1
    ./package.ps1 -Fqdn ca-xxx.<env>.azurecontainerapps.io -AppId 12345678-...
#>

param(
    [string]$Fqdn  = '',
    [string]$AppId = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$template    = Join-Path $scriptDir 'manifest.template.json'
$colorPng    = Join-Path $scriptDir 'color.png'
$outlinePng  = Join-Path $scriptDir 'outline.png'
$distDir     = Join-Path $scriptDir 'dist'
$outManifest = Join-Path $distDir 'manifest.json'
$outZip      = Join-Path $distDir 'teams-app.zip'

Write-Host "`n=== Voice Channel — Teams app package ===" -ForegroundColor Cyan

# 1. Resolve FQDN ------------------------------------------------------------
if (-not $Fqdn) {
    Write-Host "[1/4] Reading AZURE_CONTAINER_APP_FQDN from azd..." -ForegroundColor Yellow
    $azdValues = azd env get-values 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $azdValues) {
        Write-Error "No azd environment. Run 'azd up' first, or pass -Fqdn explicitly."
        exit 1
    }
    $fqdnLine = $azdValues | Where-Object { $_ -match '^AZURE_CONTAINER_APP_FQDN=' }
    if (-not $fqdnLine) { Write-Error "AZURE_CONTAINER_APP_FQDN not found in azd outputs."; exit 1 }
    $Fqdn = ($fqdnLine -replace '^[^=]+=', '').Trim('"')
}
Write-Host "  FQDN : $Fqdn" -ForegroundColor Green

# 2. App ID ------------------------------------------------------------------
if (-not $AppId) {
    Write-Host "`n[2/4] Generating fresh App ID..." -ForegroundColor Yellow
    $AppId = [guid]::NewGuid().ToString()
}
Write-Host "  App ID : $AppId" -ForegroundColor Green

# 3. Render manifest ---------------------------------------------------------
Write-Host "`n[3/4] Rendering manifest..." -ForegroundColor Yellow
if (-not (Test-Path $template))   { Write-Error "Template not found: $template"; exit 1 }
if (-not (Test-Path $colorPng))   { Write-Error "Missing color.png. Run generate-icons.ps1 or drop your own 192x192 PNG here.";   exit 1 }
if (-not (Test-Path $outlinePng)) { Write-Error "Missing outline.png. Run generate-icons.ps1 or drop your own 32x32 PNG here."; exit 1 }

New-Item -ItemType Directory -Force -Path $distDir | Out-Null
$rendered = (Get-Content $template -Raw).Replace('<FQDN>', $Fqdn).Replace('<APP_ID>', $AppId)
Set-Content -Path $outManifest -Value $rendered -Encoding UTF8
Write-Host "  Wrote $outManifest" -ForegroundColor Green

# 4. Zip ---------------------------------------------------------------------
Write-Host "`n[4/4] Building teams-app.zip..." -ForegroundColor Yellow
if (Test-Path $outZip) { Remove-Item $outZip -Force }
Compress-Archive -Path @($outManifest, $colorPng, $outlinePng) -DestinationPath $outZip
Write-Host "  Wrote $outZip" -ForegroundColor Green

Write-Host @"

=== Done ==========================================================

  Package : $outZip
  App ID  : $AppId
  FQDN    : $Fqdn

Install options:
  1. Personal: Teams -> Apps -> Manage your apps -> Upload a custom app
               -> choose $outZip. Click the new IT Assistant Voice app
               in the left rail. Grant mic if prompted. Speak.
  2. Tenant:   https://admin.teams.microsoft.com -> Teams apps -> Manage apps
               -> Upload new app. Set Publishing status = Published,
               Permissions = Granted. The app then also surfaces in
               https://m365.cloud.microsoft/chat under Apps.

===================================================================
"@ -ForegroundColor Cyan
