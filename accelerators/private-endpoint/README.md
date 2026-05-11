# Private Endpoint Accelerators for Power Platform

## Overview

This folder is the master entry point for private-endpoint sub-scenarios that
show how to keep Azure AI services locked to private networking while still
calling them from a Power Platform Managed Environment.

Both sub-scenarios use the same core pattern:

1. Disable public network access on the Azure service.
2. Expose the service through a Private Endpoint in a VNet.
3. Link `Microsoft.PowerPlatform/enterprisePolicies` (Network Injection) to
   delegated Power Platform subnets.
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

Use this when you want private Power Platform access to Azure AI Search query
APIs.

- Scenario folder: [ai-search](ai-search/README.md)
- Service type: `Microsoft.Search/searchServices`
- Connector focus: index discovery, document query, lookup, and count
- Private DNS zone:
  - `privatelink.search.windows.net`

## Shared Prerequisites

- Azure subscription where you can create networking and AI resources.
- Power Platform target environment is a Managed Environment.
- Power Platform or Global admin rights for Enterprise Policy linking.
- Azure CLI, PowerShell 7+, and `pac` CLI for scripted deployment and connector creation.

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
- Sample code is provided as-is. Review and adapt for production (naming,
  tags, RBAC, diagnostics, and address-space planning).
