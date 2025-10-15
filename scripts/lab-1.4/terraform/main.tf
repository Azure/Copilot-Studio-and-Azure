data "azurerm_subscription" "current" {}

data "azurerm_client_config" "current" {}

data "http" "current_ip" {
  url   = "http://ipv4.icanhazip.com"
  count = 0
}

resource "random_id" "random" {
  byte_length = 8
}

locals {
  allowed_ips             = var.allowed_ips
  sufix                   = var.use_random_suffix ? substr(lower(random_id.random.hex), 1, 5) : ""
  name_sufix              = var.use_random_suffix ? "-${local.sufix}" : ""
  resource_group_name     = "${var.resource_group_name}${local.name_sufix}"

  ai_services_name        = "${var.ai_services_name}${local.name_sufix}"
  ai_foundry_name         = "${var.ai_foundry_name}${local.name_sufix}"
  ai_foundry_project_name = "${var.ai_foundry_project_name}${local.name_sufix}"
  ai_foundry_kv_name      = "${var.ai_foundry_kv_name}${local.name_sufix}"
  ai_foundry_st_name      = "${var.ai_foundry_st_name}${local.sufix}"

  ai_search_name          = "${var.ai_search_name}${local.name_sufix}"

}

resource "azurerm_resource_group" "rg" {
  name     = local.resource_group_name
  location = var.location
}

module "vnet" {
  source               = "./modules/vnet"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = var.virtual_network_name
}

module "mi" {
  source                = "./modules/mi"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  managed_identity_name = var.managed_identity_name
}

resource "azurerm_role_assignment" "id_reader" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Reader"
  principal_id         = module.mi.principal_id
}

module "ai_foundry" {
  source                      = "./modules/ai-foundry"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  resource_group_id           = azurerm_resource_group.rg.id
  ai_foundry_name             = local.ai_foundry_name
  ai_services_name            = local.ai_services_name
  ai_foundry_project_name     = local.ai_foundry_project_name
  kv_name                     = local.ai_foundry_kv_name
  st_name                     = local.ai_foundry_st_name
  subscription_id             = data.azurerm_subscription.current.subscription_id
  tenant_id                   = data.azurerm_subscription.current.tenant_id
  current_principal_object_id = data.azurerm_client_config.current.object_id
  aihub_principal_id          = module.mi.principal_id
}

module "search" {
  source                      = "./modules/search"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  search_name                 = local.ai_search_name
  principal_id                = module.mi.principal_id
  allowed_ips                 = local.allowed_ips
  vnet_id                     = module.vnet.virtual_network_id
}


