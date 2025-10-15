resource "azurerm_search_service" "search" {
  name                = var.search_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "standard"
  semantic_search_sku = "free"
  allowed_ips          = null

  local_authentication_enabled = false
}

resource "azurerm_role_assignment" "search_reader" {
  scope                = azurerm_search_service.search.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = var.principal_id
}

resource "azurerm_role_assignment" "search_data_contributor" {
  scope                = azurerm_search_service.search.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = var.principal_id
}

resource "azurerm_role_assignment" "search_service_contributor" {
  scope                = azurerm_search_service.search.id
  role_definition_name = "Search Service Contributor"
  principal_id         = var.principal_id
}

