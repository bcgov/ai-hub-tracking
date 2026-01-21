variable "name" {
  description = "Name of the Container Registry"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.name))
    error_message = "Container registry name must be 5-50 alphanumeric characters only (no hyphens)."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "sku" {
  description = "SKU for Container Registry. Premium required for private endpoints and geo-replication."
  type        = string
  default     = "Premium"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "SKU must be Basic, Standard, or Premium."
  }
}

variable "public_network_access_enabled" {
  description = "Enable public network access. Set to true for public ACR, false for private-only."
  type        = bool
  default     = true
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoints. Required if public_network_access_enabled is false."
  type        = string
  default     = null
}

variable "admin_enabled" {
  description = "Enable admin user for the registry"
  type        = bool
  default     = false
}

variable "quarantine_policy_enabled" {
  description = "Enable quarantine policy for images"
  type        = bool
  default     = false
}

variable "data_endpoint_enabled" {
  description = "Enable dedicated data endpoints for each region"
  type        = bool
  default     = false
}

variable "export_policy_enabled" {
  description = "Enable export policy (allows images to be exported)"
  type        = bool
  default     = true
}

variable "zone_redundancy_enabled" {
  description = "Enable zone redundancy (Premium only)"
  type        = bool
  default     = true
}

variable "enable_trust_policy" {
  description = "Enable content trust / image signing (Premium only)"
  type        = bool
  default     = false
}

variable "retention_policy_days" {
  description = "Days to retain untagged manifests (0 = disabled)"
  type        = number
  default     = 7
}

variable "georeplications" {
  description = "Geo-replication configuration for Premium SKU"
  type = map(object({
    location                  = string
    zone_redundancy_enabled   = optional(bool, true)
    regional_endpoint_enabled = optional(bool, false)
  }))
  default = {}
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for diagnostics"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "enable_telemetry" {
  description = "Enable AVM telemetry"
  type        = bool
  default     = false
}
