<#
.SYNOPSIS
    Grants the Function App's managed identity least-privilege access to ONE
    SharePoint site via Microsoft Graph `Sites.Selected`.

.DESCRIPTION
    The recommended security posture for this accelerator. Instead of the
    tenant-wide `Sites.Read.All` + `Files.Read.All` app permissions, the
    managed identity gets the narrower `Sites.Selected` permission, and an
    admin uses this script to grant READ on just the specific site(s) the
    indexer needs to see.

    Prerequisites on the managed identity (admin consent required, one-time):
        - Microsoft Graph → Sites.Selected (Application)

    Prerequisites to run this script:
        - Microsoft Graph PowerShell SDK installed (Install-Module Microsoft.Graph)
        - An account with "Privileged Role Administrator" (or higher)
        - The signed-in account must have:
            * Application.Read.All       (to look up the MI)
            * Sites.FullControl.All      (to write /sites/{id}/permissions)

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
    Idempotent. Re-running is safe — Graph deduplicates on the target identity.
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
# Sign in to Graph
# ----------------------------------------------------------------------------
Import-Module Microsoft.Graph.Applications -ErrorAction Stop
Import-Module Microsoft.Graph.Sites        -ErrorAction Stop

Write-Host "`n=== Granting Sites.Selected access ===" -ForegroundColor Cyan
Write-Host "  Site:        $SiteUrl"
Write-Host "  Function:    $FunctionAppName"
Write-Host "  Role:        $Role`n"

Connect-MgGraph -Scopes "Application.Read.All", "Sites.FullControl.All" -NoWelcome

# ----------------------------------------------------------------------------
# 1) Find the Function App's managed identity service principal + app ID
# ----------------------------------------------------------------------------
$sp = Get-MgServicePrincipal -Filter "displayName eq '$FunctionAppName'" -ErrorAction Stop
if (-not $sp) {
    throw "Could not find managed-identity service principal for '$FunctionAppName'. " +
          "Check the Function App name and confirm system-assigned MI is enabled."
}
$mi = @{
    id          = $sp.AppId
    displayName = $sp.DisplayName
}
Write-Host "[1/3] Resolved MI app ID: $($mi.id)" -ForegroundColor Green

# ----------------------------------------------------------------------------
# 2) Resolve the SharePoint site to a Graph site ID
# ----------------------------------------------------------------------------
$parsed = [System.Uri]$SiteUrl
$hostname = $parsed.Host                 # e.g. contoso.sharepoint.com
$sitePath = $parsed.AbsolutePath.TrimEnd("/")   # e.g. /sites/Finance

# Graph path syntax:  /sites/{hostname}:{site-path}
$siteLookupPath = "/sites/$($hostname):$sitePath"
$site = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0$siteLookupPath"
$siteId = $site.id
Write-Host "[2/3] Resolved site ID: $siteId" -ForegroundColor Green

# ----------------------------------------------------------------------------
# 3) Grant permission — POST /sites/{id}/permissions
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
Write-Host "`nDone. The Function App managed identity now has '$Role' access " `
          "on $SiteUrl only — no other sites are reachable." -ForegroundColor Cyan
