variable "name" {
  description = "Name of the App Configuration store"
  type        = string
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
  description = "SKU for App Configuration (free or standard)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["free", "standard"], var.sku)
    error_message = "sku must be 'free' or 'standard'"
  }
}

variable "public_network_access_enabled" {
  description = "Enable public network access"
  type        = bool
  default     = false
}

variable "local_auth_enabled" {
  description = "Enable local authentication (access keys)"
  type        = bool
  default     = false
}

variable "purge_protection_enabled" {
  description = "Enable purge protection"
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Soft delete retention in days (1-7)"
  type        = number
  default     = 7
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoint"
  type        = string
  default     = null
}

variable "encryption" {
  description = "Customer-managed key encryption configuration"
  type = object({
    enabled            = optional(bool, false)
    key_vault_key_id   = optional(string)
    identity_client_id = optional(string)
  })
  default = {
    enabled = false
  }
}

variable "replicas" {
  description = "Geo-replication configuration (Standard SKU only)"
  type = list(object({
    name     = string
    location = string
  }))
  default = []
}

variable "feature_flags" {
  description = "Feature flags to create"
  type = map(object({
    description = optional(string)
    enabled     = bool
    label       = optional(string)
    targeting = optional(object({
      default_percentage = number
      group_name         = string
      group_percentage   = number
    }))
  }))
  default = {}
}

variable "configuration_keys" {
  description = "Configuration key-value pairs"
  type = map(object({
    value               = optional(string)
    type                = optional(string, "kv") # kv or vault
    label               = optional(string)
    content_type        = optional(string)
    vault_key_reference = optional(string)
  }))
  default = {}
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for diagnostics"
  type        = string
  default     = null
}

variable "scripts_dir" {
  description = "Path to shared scripts directory for DNS wait operations"
  type        = string
  default     = ""
}

variable "private_endpoint_dns_wait" {
  description = "Configuration for waiting on policy-managed DNS zone groups"
  type = object({
    timeout       = optional(string, "12m")
    poll_interval = optional(string, "30s")
  })
  default = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
