<#
.SYNOPSIS
    Creates (or reuses) the Entra app registration that represents the
    SharePoint Connector's /api/search endpoint.

.DESCRIPTION
    Idempotent — re-running against the same display name returns the
    existing registration instead of creating a duplicate.

    What it does:
        1. Creates an app registration with the given display name (or finds
           it if it already exists).
        2. Exposes an API with an Application ID URI of `api://<clientId>`
           and a delegated scope `access_as_user`.
        3. Adds the Microsoft Graph application permission
           `GroupMember.Read.All` to the app's `requiredResourceAccess`
           manifest. This is what /api/search uses to resolve the caller's
           transitive group memberships during per-user security trimming.

    What it deliberately does NOT do:
        * Grant admin consent for any permission. That is a post-deployment
          step because it requires Global Administrator or Cloud Application
          Administrator, and for security-sensitive orgs it MUST be
          explicitly approved — not silently auto-granted.

    The app registration's client ID is emitted to stdout so the caller can
    capture it and pass it as the `apiAudience` Bicep parameter.

.PARAMETER DisplayName
    Display name to create or reuse. Default: "<baseName> SharePoint Connector API".

.OUTPUTS
    Writes the client ID (GUID) of the app registration to stdout.
    Also returns an object with .ClientId, .ObjectId, .IdentifierUri.

.EXAMPLE
    $clientId = .\create-api-app-registration.ps1 -DisplayName "sp-indexer SharePoint Connector API"
    # Pass $clientId into main.bicep as apiAudience
#>

param(
    [Parameter(Mandatory)]
    [string]$DisplayName
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ----------------------------------------------------------------------------
# 1) Find or create the app registration
# ----------------------------------------------------------------------------
Write-Host "  Looking up app registration '$DisplayName'..." -ForegroundColor Gray

$existing = az ad app list --display-name $DisplayName --query "[?displayName=='$DisplayName'] | [0]" -o json | ConvertFrom-Json

if ($null -ne $existing) {
    $appObjectId = $existing.id
    $clientId = $existing.appId
    Write-Host "  Reusing existing app registration (clientId=$clientId)" -ForegroundColor Gray
} else {
    Write-Host "  Creating new app registration..." -ForegroundColor Gray
    $created = az ad app create --display-name $DisplayName --sign-in-audience AzureADMyOrg -o json | ConvertFrom-Json
    $appObjectId = $created.id
    $clientId = $created.appId
    Write-Host "  Created (clientId=$clientId)" -ForegroundColor Gray
}

# ----------------------------------------------------------------------------
# 2) Expose an API — Application ID URI + access_as_user delegated scope
# ----------------------------------------------------------------------------
$identifierUri = "api://$clientId"
$scopeId = [guid]::NewGuid().ToString()

# Build the `api` block manifest. If a scope already exists we keep its ID
# so consent grants don't need to be re-approved.
$currentApp = az ad app show --id $appObjectId -o json | ConvertFrom-Json
$existingScope = $null
if ($currentApp.api -and $currentApp.api.oauth2PermissionScopes) {
    $existingScope = $currentApp.api.oauth2PermissionScopes | Where-Object { $_.value -eq 'access_as_user' } | Select-Object -First 1
}
if ($existingScope) {
    $scopeId = $existingScope.id
    Write-Host "  Reusing existing access_as_user scope" -ForegroundColor Gray
}

$apiManifest = @{
    oauth2PermissionScopes = @(
        @{
            id                      = $scopeId
            adminConsentDisplayName = "Access SharePoint search on behalf of the signed-in user"
            adminConsentDescription = "Allows Copilot Studio (or another delegated caller) to query the SharePoint Connector's /api/search endpoint on behalf of the signed-in user. Per-user security trimming is enforced server-side."
            userConsentDisplayName  = "Search SharePoint on your behalf"
            userConsentDescription  = "Allows the app to query the SharePoint Connector as you, returning only documents you have access to."
            value                   = "access_as_user"
            type                    = "User"
            isEnabled               = $true
        }
    )
} | ConvertTo-Json -Depth 6 -Compress

# az ad app update wants the manifest as a JSON blob passed via --set api=...
# Use the Graph PATCH endpoint directly for reliability across shells.
$graphBody = @{
    identifierUris = @($identifierUri)
    api            = (ConvertFrom-Json $apiManifest)
} | ConvertTo-Json -Depth 6

$tmp = New-TemporaryFile
Set-Content -Path $tmp -Value $graphBody -Encoding UTF8
az rest --method PATCH `
    --uri "https://graph.microsoft.com/v1.0/applications/$appObjectId" `
    --body "@$tmp" `
    --headers "Content-Type=application/json" | Out-Null
Remove-Item $tmp -ErrorAction SilentlyContinue

Write-Host "  Application ID URI: $identifierUri" -ForegroundColor Gray
Write-Host "  Delegated scope: access_as_user" -ForegroundColor Gray

# ----------------------------------------------------------------------------
# 3) Add Microsoft Graph GroupMember.Read.All (Application) to the manifest
#    — WITHOUT granting admin consent. Admin consent is a post-deploy step.
# ----------------------------------------------------------------------------
# Microsoft Graph well-known IDs
$graphAppId = "00000003-0000-0000-c000-000000000000"
# `GroupMember.Read.All` application-permission role ID:
$groupMemberReadAllRoleId = "98830695-27a2-44f7-8c18-0c3ebc9698f6"

$resourceAccess = @{
    requiredResourceAccess = @(
        @{
            resourceAppId  = $graphAppId
            resourceAccess = @(
                @{
                    id   = $groupMemberReadAllRoleId
                    type = "Role"   # application permission (vs "Scope" = delegated)
                }
            )
        }
    )
} | ConvertTo-Json -Depth 6

$tmp = New-TemporaryFile
Set-Content -Path $tmp -Value $resourceAccess -Encoding UTF8
az rest --method PATCH `
    --uri "https://graph.microsoft.com/v1.0/applications/$appObjectId" `
    --body "@$tmp" `
    --headers "Content-Type=application/json" | Out-Null
Remove-Item $tmp -ErrorAction SilentlyContinue

Write-Host "  Added Graph permission: GroupMember.Read.All (Application, consent REQUIRED post-deploy)" -ForegroundColor Gray

# ----------------------------------------------------------------------------
# 4) Emit the client ID + a result object
# ----------------------------------------------------------------------------
$clientId
