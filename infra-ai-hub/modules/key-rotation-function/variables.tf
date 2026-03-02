# =============================================================================
# Key Rotation Container App Job — Variables
# =============================================================================

# ---------------------------------------------------------------------------
# Resource placement
# ---------------------------------------------------------------------------
variable "name_prefix" {
  description = "Naming prefix (e.g., ai-services-hub-dev)"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for all resources"
  type        = string
}

variable "resource_group_id" {
  description = "Resource group ID (for RBAC scoping)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Container App Environment
# ---------------------------------------------------------------------------
variable "container_app_environment_id" {
  description = "Container App Environment resource ID"
  type        = string
}

# ---------------------------------------------------------------------------
# Container image (GHCR)
# ---------------------------------------------------------------------------
variable "container_registry_url" {
  description = "Container registry URL (e.g., ghcr.io)"
  type        = string
  default     = "ghcr.io"
}

variable "container_image_name" {
  description = "Container image name (e.g., bcgov/ai-hub-tracking/apim-key-rotation)"
  type        = string
}

variable "container_image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}

# ---------------------------------------------------------------------------
# Container resources
# ---------------------------------------------------------------------------
variable "cpu" {
  description = "CPU cores allocated to the container (e.g., 0.5)"
  type        = number
  default     = 0.5
}

variable "memory" {
  description = "Memory allocated to the container (e.g., 1Gi)"
  type        = string
  default     = "1Gi"
}

# ---------------------------------------------------------------------------
# Job scheduling
# ---------------------------------------------------------------------------
variable "cron_expression" {
  description = "Cron expression for the job schedule (e.g., 0 9 * * * for daily 09:00 UTC)"
  type        = string
  default     = "0 9 * * *"
}

variable "replica_timeout_seconds" {
  description = "Maximum seconds a replica can run before being terminated"
  type        = number
  default     = 1800
}

variable "key_propagation_wait_seconds" {
  description = "Seconds to pause after APIM key regeneration for propagation (per tenant)"
  type        = number
  default     = 10
}

variable "replica_retry_limit" {
  description = "Maximum number of retries for a failed replica"
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# APIM + Key Vault references (for RBAC scoping)
# ---------------------------------------------------------------------------
variable "apim_id" {
  description = "APIM resource ID (for RBAC)"
  type        = string
}

variable "apim_name" {
  description = "APIM instance name (passed to job as env var)"
  type        = string
}

variable "hub_keyvault_id" {
  description = "Hub Key Vault resource ID (for RBAC)"
  type        = string
}

variable "hub_keyvault_name" {
  description = "Hub Key Vault name (passed to job as env var)"
  type        = string
}

# ---------------------------------------------------------------------------
# Application config (Pydantic Settings)
# ---------------------------------------------------------------------------
variable "environment" {
  description = "Target environment (dev, test, prod)"
  type        = string
}

variable "app_name" {
  description = "Application name prefix"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "rotation_enabled" {
  description = "Master rotation toggle"
  type        = bool
  default     = true
}

variable "rotation_interval_days" {
  description = "Days between rotations (must be < 90)"
  type        = number
  default     = 7

  validation {
    condition     = var.rotation_interval_days >= 1 && var.rotation_interval_days <= 89
    error_message = "rotation_interval_days must be between 1 and 89 (Key Vault secrets expire at 90 days)."
  }
}

variable "dry_run" {
  description = "When true, logs what would happen without making changes"
  type        = bool
  default     = false
}

variable "included_tenants" {
  description = "Comma-separated list of tenant names to include in rotation (empty = no tenants — safe default)"
  type        = string
  default     = ""
}

variable "secret_expiry_days" {
  description = "Key Vault secret expiry in days (Landing Zone max: 90)"
  type        = number
  default     = 90
}
