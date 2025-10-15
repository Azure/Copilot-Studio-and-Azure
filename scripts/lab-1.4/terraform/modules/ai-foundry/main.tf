# Create an Azure Key Vault resource
resource "azurerm_key_vault" "kv" {
  name                = var.kv_name             # Name of the Key Vault
  location            = var.location            # Location from the resource group
  resource_group_name = var.resource_group_name # Resource group name
  tenant_id           = var.tenant_id           # Azure tenant ID

  sku_name                 = "standard" # SKU tier for the Key Vault
  purge_protection_enabled = true       # Enables purge protection to prevent accidental deletion
}

# Set an access policy for the Key Vault to allow certain operations
resource "azurerm_key_vault_access_policy" "test" {
  key_vault_id = azurerm_key_vault.kv.id         # Key Vault reference
  tenant_id    = var.tenant_id                   # Tenant ID
  object_id    = var.current_principal_object_id # Object ID of the principal

  key_permissions = [ # List of allowed key permissions
    "Create",
    "Get",
    "Delete",
    "Purge",
    "GetRotationPolicy",
  ]
}

# Create an Azure Storage Account
resource "azurerm_storage_account" "st" {
  name                     = var.st_name             # Storage account name
  location                 = var.location            # Location from the resource group
  resource_group_name      = var.resource_group_name # Resource group name
  account_tier             = "Standard"              # Performance tier
  account_replication_type = "LRS"                   # Locally-redundant storage replication
}

# Deploy Azure AI Services resource
resource "azurerm_ai_services" "ai" {
  name                = var.ai_services_name    # AI Services resource name
  location            = var.location            # Location from the resource group
  resource_group_name = var.resource_group_name # Resource group name
  sku_name            = "S0"                    # Pricing SKU tier
}

resource "azurerm_cognitive_deployment" "gpt4o" {
  name                 = "gpt4o"
  cognitive_account_id = azurerm_ai_services.ai.id
  rai_policy_name      = "Microsoft.Default"
  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = "2024-05-13"
  }
  sku {
    name     = "GlobalStandard"
    capacity = 20
  }
}

resource "azurerm_cognitive_deployment" "embeddings" {
  name                 = "text-embedding-3-large"
  cognitive_account_id = azurerm_ai_services.ai.id
  rai_policy_name      = "Microsoft.Default"
  model {
    format  = "OpenAI"
    name    = "text-embedding-3-large"
    version = "1"
  }
  sku {
    name     = "GlobalStandard"
    capacity = 100
  }
}

# Create Azure AI Foundry service
resource "azurerm_ai_foundry" "ai_foundry" {
  name                = var.ai_foundry_name             # AI Foundry service name
  location            = azurerm_ai_services.ai.location # Location from the AI Services resource
  resource_group_name = var.resource_group_name         # Resource group name
  storage_account_id  = azurerm_storage_account.st.id   # Associated storage account
  key_vault_id        = azurerm_key_vault.kv.id         # Associated Key Vault

  identity {
    type = "SystemAssigned" # Enable system-assigned managed identity
  }

  lifecycle {
    ignore_changes = [ # Ignore changes to the identity block
      tags,
    ]
  }
}

# Create an AI Foundry Project within the AI Foundry service
resource "azurerm_ai_foundry_project" "ai_foundry_project" {
  name               = var.ai_foundry_project_name      # Project name
  location           = var.location                     # Location from the AI Foundry service
  ai_services_hub_id = azurerm_ai_foundry.ai_foundry.id # Associated AI Foundry service

  identity {
    type = "SystemAssigned" # Enable system-assigned managed identity
  }
}

resource "azapi_resource" "ai_services_connection" {
  type                      = "Microsoft.MachineLearningServices/workspaces/connections@2025-01-01-preview" # Resource type and API version
  name                      = "${azurerm_ai_services.ai.name}-connection"                                   # Resource name
  location                  = "global"                                                                      # Resource location
  parent_id                 = azurerm_ai_foundry.ai_foundry.id                                              # Parent resource group
  schema_validation_enabled = false
  body = {
    properties = {
      category      = "AIServices"
      target        = azurerm_ai_services.ai.endpoint
      authType      = "ApiKey"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_ai_services.ai.id
      }
      credentials = {
        key = azurerm_ai_services.ai.primary_access_key
      }
    }
  }
}

resource "azurerm_role_assignment" "ai_foundry_project_developer" {
  scope                = azurerm_ai_foundry_project.ai_foundry_project.id
  role_definition_name = "Azure AI Developer"
  principal_id         = var.aihub_principal_id
}

resource "azurerm_role_assignment" "storage_contributor" {
  scope                = azurerm_storage_account.st.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         =  var.aihub_principal_id
}
