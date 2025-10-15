output "project_connection_string" {
  description = "The connection string to the AI Foundry project"
  value       = "${azurerm_ai_foundry_project.ai_foundry_project.location}.api.azureml.ms;${var.subscription_id};${var.resource_group_name};${azurerm_ai_foundry_project.ai_foundry_project.name}"
}

output "deployment_name" {
  value = azurerm_cognitive_deployment.gpt4o.name
}

