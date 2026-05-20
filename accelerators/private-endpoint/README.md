# Private Endpoint Accelerators for Power Platform

## Overview

This folder is the master entry point for private-endpoint sub-scenarios that show how to keep Azure AI services locked to private networking while still calling them from a Power Platform Managed Environment. The details of Virtual Network support for Power Platform Environments are detailed [here](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview).

Both sub-scenarios use the same core pattern:

![Power Platform → VNet → Azure Content Understanding](https://learn.microsoft.com/en-us/power-platform/admin/media/whitepaper-case-study.png#lightbox)

1. Disable public network access on the Azure service.
2. Expose the service through a Private Endpoint in a VNet.
3. Link `Microsoft.PowerPlatform/enterprisePolicies` (Network Injection) to delegated Power Platform subnets (primary, secondary). Details [here](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure?tabs=existing%2Csingle&pivots=powershell#setup-with-powershell)
4. Call the service from a Power Platform custom connector in flow runtime.

## Sub-Scenarios

### 1. Connecting to Azure AI Content Understanding Private Endpoint in VNET

Use this when you want private Power Platform access to Azure AI Content
Understanding analyzers.

- Scenario folder: [content-server](content-server/README.md)
- Service type: `Microsoft.CognitiveServices/accounts` (kind `AIServices`)
- Connector focus: analyzer list and analyze operations
- Private DNS zones:
  - `privatelink.cognitiveservices.azure.com`
  - `privatelink.openai.azure.com`
  - `privatelink.services.ai.azure.com`

### 2. Connecting to Azure AI Search Private Endpoint in VNET

Use this when you want private Power Platform access to Azure AI Search query APIs.

- Scenario folder: [ai-search](ai-search/README.md)
- Service type: `Microsoft.Search/searchServices`
- Connector focus: index discovery, document query, lookup, and count
- Private DNS zone:
  - `privatelink.search.windows.net`

## Shared Prerequisites

| Requirement | Notes |
|---|---|
| [Azure subscription](https://azure.microsoft.com/free/) with Owner or Contributor role | Required to create networking, AI, and Enterprise Policy resources |
| [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview) | Both sub-scenarios provision a VNet with a private endpoint subnet and a Power Platform delegated subnet |
| [Azure Private Endpoint](https://learn.microsoft.com/azure/private-link/private-endpoint-overview) | Exposes the AI service on a private IP inside the VNet; public network access is disabled |
| [Azure Private DNS Zone](https://learn.microsoft.com/azure/dns/private-dns-overview) | Resolves the service FQDN to the private endpoint IP from inside the VNet |
| [Power Platform Managed Environment](https://learn.microsoft.com/power-platform/admin/managed-environment-overview) | Sandbox environments cannot be linked to an Enterprise Policy; enable Managed Environment in PPAC |
| [Power Platform VNet integration (Enterprise Policy)](https://learn.microsoft.com/power-platform/admin/vnet-support-overview) | Routes Power Platform connector runtime traffic through a delegated subnet into the VNet |
| [Power Platform or Global Administrator](https://learn.microsoft.com/power-platform/admin/use-service-admin-role-manage-tenant) | Required to enable Managed Environment and to link the Enterprise Policy |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) ≥ 2.50 | Used by the scripted deployment path |
| [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (`pwsh`) | Required by all helper scripts |
| [`pac` CLI](https://learn.microsoft.com/power-platform/developer/cli/introduction) signed in to the target environment | Used to push the custom connector via `pac connector create`; verify with `pac auth list` |
| [`Microsoft.PowerPlatform.EnterprisePolicies` PowerShell module](https://www.powershellgallery.com/packages/Microsoft.PowerPlatform.EnterprisePolicies) | Auto-installed by `link-enterprise-policy.ps1`; calls `Enable-SubnetInjection` |

## Quick Start

1. Pick your relevant scenario:
   - [content-server/README.md](content-server/README.md)
   - [ai-search/README.md](ai-search/README.md)
2. Copy that scenario's `.env.example` to `.env` and fill values.
3. Deploy infra via its ARM template or deployment script.
4. Link Enterprise Policy to your Power Platform environment.
5. Push and test the scenario-specific custom connector.

## Notes

- The custom connector designer test page does not use VNet injection.
  Validate connectivity from a real Power Automate flow run.
- If you update Enterprise Policy virtual network bindings, unlink first,
  redeploy, then re-link.
- To find which Azure region your Power Platform environment maps to, run the script below:

  ```powershell
  # Install the module if needed
  Install-Module -Name Microsoft.PowerApps.Administration.PowerShell

  # Sign in
  Add-PowerAppsAccount

  # Retrieve all environments
  $environments = Get-AdminPowerAppEnvironment

  # Format and display the specific Azure region for each
  $environments | Select-Object `
      @{Name="Environment Name"; Expression={$_.DisplayName}}, `
      @{Name="Environment ID"; Expression={$_.EnvironmentName}}, `
      @{Name="Display Region"; Expression={$_.Location}}, `
      @{Name="Specific Azure Region"; Expression={$_.Internal.Properties.azureRegionHint}} | `
      Format-Table -AutoSize
  ```

  Then use the scenario region mapping in
  [`ai-search/infra/main-aisearch.bicep`](ai-search/infra/main-aisearch.bicep)
  or [`content-server/infra/main.bicep`](content-server/infra/main.bicep).
  Example: in the AI Search scenario, `unitedstates` maps to primary
  `westus` and secondary `eastus` (see `regionMap` in
  `main-aisearch.bicep`). In the Content Understanding scenario,
  use the same values by setting `location=westus` and
  `secondaryLocation=eastus` in `main.bicep`/deployment parameters.
- Sample code is provided as-is. Review and adapt for production (naming,
  tags, RBAC, diagnostics, and address-space planning).
