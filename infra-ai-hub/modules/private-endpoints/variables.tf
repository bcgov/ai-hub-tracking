variable "enabled" {
  type        = bool
  description = "Whether private endpoints are enabled."
  nullable    = false
}

variable "location" {
  type        = string
  description = "Azure region where private endpoints will be created."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name for private endpoints."
  nullable    = false
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID where private endpoints will be created."
  nullable    = false
}

variable "private_dns_zone_rg_id" {
  type        = string
  description = "Resource ID of the resource group containing private DNS zones. Null if DNS integration is not needed."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}

variable "ai_foundry_name" {
  type        = string
  description = "Name of the AI Foundry hub."
  nullable    = false
}

variable "foundry_ptn" {
  type = object({
    resource_id       = string
    cosmos_db_id      = map(string)
    ai_search_id      = map(string)
    key_vault_id      = map(string)
    storage_account_id = map(string)
  })
  description = "Outputs from the AI Foundry pattern module."
  nullable    = false
}

variable "ai_foundry_definition" {
  type = object({
    cosmosdb_definition        = optional(map(object({ name = string })), {})
    ai_search_definition       = optional(map(object({ name = string })), {})
    key_vault_definition       = optional(map(object({ name = string })), {})
    storage_account_definition = optional(map(object({ name = string })), {})
  })
  description = "AI Foundry resource definitions for creating private endpoints."
  nullable    = false
}
