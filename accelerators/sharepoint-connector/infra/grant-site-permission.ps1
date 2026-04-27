<#
.SYNOPSIS
    Grants the Function App's managed identity least-privilege access to ONE
    SharePoint site via Microsoft Graph `Sites.Selected`.

.DESCRIPTION
    Recommended security posture for this accelerator. Instead of tenant-wide
    `Sites.Read.All` + `Files.Read.All`, the managed identity gets only the
    narrower `Sites.Selected` permission, and an admin uses this script to
    grant READ on just the specific site(s) the indexer needs to see.

    Uses the Microsoft Graph PowerShell SDK (NOT `az rest`) because the
    Graph operation `POST /sites/{id}/permissions` requires the
    `Sites.FullControl.All` delegated scope — which the Azure CLI's
    first-party app does not carry. `Connect-MgGraph -Scopes ...` lets the
    user consent to the right scopes interactively.

    The script auto-installs the two required Graph sub-modules in the
    CurrentUser scope on first run (~30 s, ~25 MB) — no admin shell needed.

    Prerequisites on the managed identity (admin consent required, one-time):
        - Microsoft Graph -> Sites.Selected (Application)
          (Grant via the Graph Explorer "Manual alternative" steps in
           the README, or via `New-MgServicePrincipalAppRoleAssignment`.)

    Prerequisites to run this script:
        - PowerShell 7+ (Microsoft.Graph SDK requirement)
        - Internet access to PSGallery (for first-run install)
        - Sign in as an account that holds:
            * Application.Read.All       (to look up the MI)
            * Sites.FullControl.All      (to write /sites/{id}/permissions)
          In practice that means SharePoint Administrator or Global
          Administrator.

.PARAMETER SiteUrl
    Full SharePoint site URL, e.g. https://contoso.sharepoint.com/sites/Finance

.PARAMETER FunctionAppName
    Name of the Azure Function App. Its system-assigned managed identity is
    resolved from Entra ID by display name.

.PARAMETER Role
    One of "read" (default) or "write". The indexer only needs "read".

.EXAMPLE
    .\grant-site-permission.ps1 `
        -SiteUrl "https://contoso.sharepoint.com/sites/Finance" `
        -FunctionAppName "sp-indexer-func"

.NOTES
    Idempotent. Re-running is safe - Graph deduplicates on the target identity.
#>

param(
    [Parameter(Mandatory)]
    [string]$SiteUrl,

    [Parameter(Mandatory)]
    [string]$FunctionAppName,

    [ValidateSet("read", "write")]
    [string]$Role = "read"
)

$ErrorActionPreference = "Stop"

# ----------------------------------------------------------------------------
# Pre-flight: PowerShell 7+ and the two required Graph sub-modules.
# Auto-install in the CurrentUser scope when missing.
# ----------------------------------------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 or newer is required. Detected: $($PSVersionTable.PSVersion). Install from https://aka.ms/powershell."
}

$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Applications'
)

foreach ($m in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Host "Installing missing module '$m' (CurrentUser scope, first-run only)..." -ForegroundColor Yellow
        Install-Module -Name $m -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
    }
    Import-Module $m -ErrorAction Stop
}

Write-Host "`n=== Granting Sites.Selected access ===" -ForegroundColor Cyan
Write-Host "  Site:        $SiteUrl"
Write-Host "  Function:    $FunctionAppName"
Write-Host "  Role:        $Role`n"

# ----------------------------------------------------------------------------
# Sign in to Graph with the scopes this operation needs.
# Connect-MgGraph prompts for interactive consent in the browser the first
# time. Re-runs reuse the cached token until it expires.
# ----------------------------------------------------------------------------
Connect-MgGraph -Scopes "Application.Read.All", "Sites.FullControl.All" -NoWelcome

# ----------------------------------------------------------------------------
# 1) Resolve the Function App's managed-identity service principal -> appId
# ----------------------------------------------------------------------------
$sp = Get-MgServicePrincipal -Filter "displayName eq '$FunctionAppName'" -ErrorAction Stop
if (-not $sp) {
    throw "Could not find managed-identity service principal for '$FunctionAppName'. Confirm the Function App name and that system-assigned MI is enabled."
}
$mi = @{
    id          = $sp.AppId
    displayName = $sp.DisplayName
}
Write-Host "[1/3] Resolved MI app ID: $($mi.id)" -ForegroundColor Green

# ----------------------------------------------------------------------------
# 2) Resolve the SharePoint site to a Graph site ID
# ----------------------------------------------------------------------------
$parsed   = [System.Uri]$SiteUrl
$hostname = $parsed.Host                          # contoso.sharepoint.com
$sitePath = $parsed.AbsolutePath.TrimEnd("/")     # /sites/Finance

# Graph path syntax:  /sites/{hostname}:{site-path}
$site = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/sites/$($hostname):$sitePath"
$siteId = $site.id
if (-not $siteId) {
    throw "Failed to resolve site '$SiteUrl' via Graph."
}
Write-Host "[2/3] Resolved site ID: $siteId" -ForegroundColor Green

# ----------------------------------------------------------------------------
# 3) Grant permission via POST /sites/{id}/permissions
# ----------------------------------------------------------------------------
$body = @{
    roles = @($Role)
    grantedToIdentities = @(
        @{ application = $mi }
    )
}

$grant = Invoke-MgGraphRequest `
    -Method POST `
    -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/permissions" `
    -Body ($body | ConvertTo-Json -Depth 5) `
    -ContentType "application/json"

Write-Host "[3/3] Permission granted (permission ID: $($grant.id))" -ForegroundColor Green
Write-Host "`nDone. The Function App managed identity now has '$Role' access on $SiteUrl only - no other sites are reachable." -ForegroundColor Cyan
