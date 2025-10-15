terraform {
  required_version = ">= 1.4.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
    }
    azapi = {
      source = "Azure/azapi"
    }
  }
}
