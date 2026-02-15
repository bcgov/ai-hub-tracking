variable "app_env" {
  description = "Application environment (dev, test, prod)"
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "test", "prod"], var.app_env)
    error_message = "app_env must be one of: dev, test, prod"
  }
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
  description = "Azure client ID for the service principal (OIDC)"
  type        = string
  sensitive   = true
}

variable "use_oidc" {
  description = "Use OIDC for authentication"
  type        = bool
  default     = true
}

variable "tenants" {
  description = "Tenant configurations (reuses the same tfvars as the main config)"
  type        = any
  default     = {}
}

variable "backend_resource_group" {
  description = "Backend resource group (accepted for shared deploy command contract)"
  type        = string
  default     = ""
}

variable "backend_storage_account" {
  description = "Backend storage account (accepted for shared deploy command contract)"
  type        = string
  default     = ""
}

variable "backend_container_name" {
  description = "Backend container name (accepted for shared deploy command contract)"
  type        = string
  default     = "tfstate"
}
