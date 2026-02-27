# =============================================================================
# Key Rotation Function App — Variables
# =============================================================================

# ---------------------------------------------------------------------------
# Resource placement
# ---------------------------------------------------------------------------
variable "name_prefix" {
  description = "Naming prefix (e.g., ai-services-hub-dev)"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for all function resources"
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
# Container image (GHCR)
# ---------------------------------------------------------------------------
variable "container_image_name" {
  description = "GHCR image name (e.g., bcgov/ai-hub-tracking/functions/apim-key-rotation)"
  type        = string
}

variable "container_image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}

# ---------------------------------------------------------------------------
# Networking (optional VNet integration)
# ---------------------------------------------------------------------------
variable "vnet_subnet_id" {
  description = "Subnet ID for VNet integration (optional). If provided, Functions can reach private endpoints."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------
variable "application_insights_connection_string" {
  description = "Application Insights connection string"
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------------------------
# APIM + Key Vault references (for RBAC scoping)
# ---------------------------------------------------------------------------
variable "apim_id" {
  description = "APIM resource ID (for RBAC)"
  type        = string
}

variable "apim_name" {
  description = "APIM instance name (passed to function as app setting)"
  type        = string
}

variable "hub_keyvault_id" {
  description = "Hub Key Vault resource ID (for RBAC)"
  type        = string
}

variable "hub_keyvault_name" {
  description = "Hub Key Vault name (passed to function as app setting)"
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

variable "rotation_cron_schedule" {
  description = "NCRONTAB expression for the timer trigger (6-part: sec min hour day month weekday)"
  type        = string
  default     = "0 0 9 * * *"
}

variable "dry_run" {
  description = "When true, logs what would happen without making changes"
  type        = bool
  default     = false
}

variable "secret_expiry_days" {
  description = "Key Vault secret expiry in days (Landing Zone max: 90)"
  type        = number
  default     = 90
}
