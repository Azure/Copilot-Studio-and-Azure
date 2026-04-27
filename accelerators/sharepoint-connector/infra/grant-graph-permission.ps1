<#
.SYNOPSIS
    Grants a Microsoft Graph **Application** permission to the Function App's
    managed identity (e.g. GroupMember.Read.All, Sites.Selected).

.DESCRIPTION
    Application permissions on Microsoft Graph cannot be assigned to a
    managed identity from the Azure Portal — the Entra "Grant admin consent"
    button is disabled for MIs because they have no manifest. The supported
    path is the Microsoft Graph PowerShell SDK
    (`New-MgServicePrincipalAppRoleAssignment`), which is what this script
    wraps.

    By default this grants `GroupMember.Read.All`, which the connector's
    /api/search endpoint needs to resolve transitive group memberships at
    query time. Pass `-Permission Sites.Selected` to assign that one
    instead — useful as a one-off before running grant-site-permission.ps1.

    Auto-installs `Microsoft.Graph.Authentication` + `Microsoft.Graph.Applications`
    in the CurrentUser scope on first run (~30 s, ~25 MB).

    Prerequisites to run this script:
        - PowerShell 7+ (Microsoft.Graph SDK requirement)
        - Sign in as Global Administrator (or any role that holds the
          delegated scope `AppRoleAssignment.ReadWrite.All` on Graph —
          Privileged Role Administrator works too).

.PARAMETER FunctionAppName
    Name of the Azure Function App. Its system-assigned managed identity is
    resolved from Entra ID by display name.

.PARAMETER Permission
    The Microsoft Graph application-permission name (the `value` on Graph's
    appRole, e.g. "GroupMember.Read.All", "Sites.Selected", "Sites.Read.All").
    Defaults to "GroupMember.Read.All".

.EXAMPLE
    # Grant GroupMember.Read.All — required for /api/search transitive groups.
    .\grant-graph-permission.ps1 -FunctionAppName "spi-func-cwx3vw"

.EXAMPLE
    # Grant Sites.Selected — prerequisite for grant-site-permission.ps1.
    .\grant-graph-permission.ps1 `
        -FunctionAppName "spi-func-cwx3vw" `
        -Permission "Sites.Selected"

.NOTES
    Idempotent. Re-running returns 400 "Permission being assigned already
    exists" — handled gracefully.
#>

param(
    [Parameter(Mandatory)]
    [string]$FunctionAppName,

    [string]$Permission = "GroupMember.Read.All"
)

$ErrorActionPreference = "Stop"

# ----------------------------------------------------------------------------
# Pre-flight: PowerShell 7+ and the two required Graph sub-modules.
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

Write-Host "`n=== Granting Graph application permission ===" -ForegroundColor Cyan
Write-Host "  Function:    $FunctionAppName"
Write-Host "  Permission:  $Permission`n"

# ----------------------------------------------------------------------------
# Sign in to Graph with the scope this operation needs.
# ----------------------------------------------------------------------------
Connect-MgGraph -Scopes "Application.Read.All", "AppRoleAssignment.ReadWrite.All" -NoWelcome

# ----------------------------------------------------------------------------
# 1) Resolve the Function App's managed-identity service principal
# ----------------------------------------------------------------------------
$miSp = Get-MgServicePrincipal -Filter "displayName eq '$FunctionAppName'" -ErrorAction Stop
if (-not $miSp) {
    throw "Could not find managed-identity service principal for '$FunctionAppName'. Confirm the Function App name and that system-assigned MI is enabled."
}
Write-Host "[1/3] Resolved MI SP id: $($miSp.Id)" -ForegroundColor Green

# ----------------------------------------------------------------------------
# 2) Resolve Microsoft Graph's service principal + the requested app role
# ----------------------------------------------------------------------------
$graphAppId = '00000003-0000-0000-c000-000000000000'
$graphSp = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'" -ErrorAction Stop
$role = $graphSp.AppRoles | Where-Object { $_.Value -eq $Permission }
if (-not $role) {
    throw "App role '$Permission' not found on Microsoft Graph. Check spelling (case-sensitive). Common values: GroupMember.Read.All, Sites.Selected, Sites.Read.All, Files.Read.All."
}
Write-Host "[2/3] Resolved app role '$Permission' id: $($role.Id)" -ForegroundColor Green

# ----------------------------------------------------------------------------
# 3) Assign — POST /servicePrincipals/{mi}/appRoleAssignments
# ----------------------------------------------------------------------------
try {
    $assignment = New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $miSp.Id `
        -PrincipalId $miSp.Id `
        -ResourceId $graphSp.Id `
        -AppRoleId $role.Id

    Write-Host "[3/3] Permission granted (assignment id: $($assignment.Id))" -ForegroundColor Green
}
catch {
    if ($_.Exception.Message -match 'Permission being assigned already exists') {
        Write-Host "[3/3] Permission already granted — nothing to do." -ForegroundColor Yellow
    }
    else {
        throw
    }
}

Write-Host "`nDone. The Function App managed identity now holds '$Permission' (Application) on Microsoft Graph." -ForegroundColor Cyan
