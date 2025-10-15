output "mi_id" {
  value = azurerm_user_assigned_identity.mi.id
}

output "principal_id" {
  value = azurerm_user_assigned_identity.mi.principal_id
}

output "client_id" {
  value = azurerm_user_assigned_identity.mi.client_id
}
