variable "app_env" {
  description = "Application environment"
  type        = string
}

variable "app_name" {
  description = "Application name prefix"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Shared resource group name"
  type        = string
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure tenant ID"
  type        = string
  sensitive   = true
}

variable "client_id" {
  description = "Azure client ID"
  type        = string
  sensitive   = true
}

variable "use_oidc" {
  description = "Use OIDC"
  type        = bool
  default     = true
}

variable "vnet_name" {
  description = "Landing zone VNet name"
  type        = string
}

variable "vnet_resource_group_name" {
  description = "Landing zone VNet resource group"
  type        = string
}

variable "target_vnet_address_spaces" {
  description = "Target VNet address spaces"
  type        = list(string)
}

variable "source_vnet_address_space" {
  description = "Source VNet address space"
  type        = string
}

variable "private_endpoint_subnet_name" {
  description = "Private endpoint subnet name"
  type        = string
  default     = "privateendpoints-subnet"
}

variable "shared_config" {
  description = "Shared environment config"
  type        = any
}

variable "defender_enabled" {
  description = "Enable Defender for Cloud plans"
  type        = bool
  default     = false
}

variable "defender_resource_types" {
  description = "Defender for Cloud resource types and subplans"
  type = map(object({
    subplan = optional(string, null)
  }))
  default = {}
}

variable "backend_resource_group" {
  description = "Backend resource group (unused by shared stack logic, accepted for command consistency)"
  type        = string
  default     = ""
}

variable "backend_storage_account" {
  description = "Backend storage account (unused by shared stack logic, accepted for command consistency)"
  type        = string
  default     = ""
}

variable "backend_container_name" {
  description = "Backend container name (unused by shared stack logic, accepted for command consistency)"
  type        = string
  default     = "tfstate"
}
