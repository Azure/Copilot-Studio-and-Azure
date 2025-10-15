variable "subscription_id" {
  default = "YOUR SUBSCRIPTION ID"
}   

variable "resource_group_name" {
  default = "aisearch-lab-rg"
}

variable "location" {
  default = "eastus2"
}

variable "location_azopenai" {
  default = "swedencentral"
}

variable "ai_search_name" {
  default = "aisearch-lab-search"
}

variable "virtual_network_name" {
  default = "aisearch-lab-vnet"
}

variable "managed_identity_name" {
  default = "aisearch-lab-id"
}

variable "ai_services_name" {
  default = "aifoundry"
}

variable "ai_foundry_name" {
  default = "aifoundry-hub"
}

variable "ai_foundry_project_name" {
  default = "aifoundry-project"
}

variable "ai_foundry_kv_name" {
  default = "aifoundry-kv"
}

variable "ai_foundry_st_name" {
  default = "aifoundryst"
}

variable "use_random_suffix" {
  default = true
}

variable "enable_entra_id_authentication" {
  default = true
}

variable "allowed_ips" {
  type    = list(string)
  default = []
}
