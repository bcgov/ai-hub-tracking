# -----------------------------------------------------------------------------
# Variables – Tenant Onboarding Portal Module
# -----------------------------------------------------------------------------

variable "app_env" {
  description = "Environment name (dev, test, prod)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "sku_name" {
  description = "App Service Plan SKU (F1, B1, S1, etc.)."
  type        = string
  default     = "B1"
}

variable "container_image" {
  description = "Container image path in GHCR (without tag)."
  type        = string
  default     = "bcgov/ai-hub-tracking/tenant-onboarding-portal"
}

variable "container_tag" {
  description = "Container image tag."
  type        = string
  default     = "latest"
}

variable "secret_key" {
  description = "Session encryption key for the portal."
  type        = string
  sensitive   = true
}

variable "oidc_discovery_url" {
  description = "Keycloak OIDC discovery endpoint URL."
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OIDC client ID for the portal."
  type        = string
  default     = ""
}

variable "oidc_client_secret" {
  description = "OIDC client secret."
  type        = string
  sensitive   = true
  default     = ""
}

variable "table_storage_account_url" {
  description = "Azure Table Storage account URL (https://<account>.table.core.windows.net)."
  type        = string
  default     = ""
}

variable "table_storage_account_id" {
  description = "Azure Storage Account resource ID for RBAC assignment."
  type        = string
  default     = ""
}

variable "admin_emails" {
  description = "Comma-separated list of admin @gov.bc.ca email addresses."
  type        = string
  default     = ""
}

variable "extra_app_settings" {
  description = "Additional app settings to pass to the web app."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
