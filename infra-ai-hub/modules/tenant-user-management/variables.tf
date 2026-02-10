# =============================================================================
# MODULE VARIABLES
# =============================================================================
variable "tenant_name" {
  description = "Unique identifier for the tenant (used in group/role names)"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.tenant_name))
    error_message = "tenant_name must be lowercase alphanumeric with hyphens only."
  }
}

variable "display_name" {
  description = "Human-readable display name for the tenant"
  type        = string
  nullable    = false
}

variable "app_env" {
  description = "Application environment (dev, test, prod) — included in group/role names to prevent cross-environment conflicts"
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "test", "prod"], var.app_env)
    error_message = "app_env must be one of: dev, test, prod"
  }
}

variable "resource_group_id" {
  description = "Resource group ID for tenant scope role assignments"
  type        = string
  nullable    = false
}

variable "user_management" {
  description = "Tenant user management configuration (Entra groups + custom roles)"
  type = object({
    enabled      = optional(bool, true)
    group_prefix = optional(string, "ai-hub")
    mail_enabled = optional(bool, false)
    existing_group_ids = optional(object({
      admin = optional(string)
      write = optional(string)
      read  = optional(string)
    }), {})
    seed_members = optional(object({
      admin = optional(list(string), [])
      write = optional(list(string), [])
      read  = optional(list(string), [])
    }), {})
    owner_members = optional(list(string))
  })
  default = {}
}
