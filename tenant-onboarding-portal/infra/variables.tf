# -----------------------------------------------------------------------------
# Variables – Tenant Onboarding Portal Infrastructure
# -----------------------------------------------------------------------------

variable "app_env" {
  description = "Environment name: dev, test, or prod."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.app_env)
    error_message = "app_env must be one of: dev, test, prod."
  }
}

variable "location" {
  description = "Azure region (e.g. canadacentral)."
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure AD tenant ID."
  type        = string
  sensitive   = true
}

variable "client_id" {
  description = "Service principal / OIDC client ID used by the AzureRM provider."
  type        = string
  sensitive   = true
}

variable "use_oidc" {
  description = "Use OIDC (Workload Identity Federation) for the AzureRM provider. Set false only for local runs."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy into."
  type        = string
}

variable "common_tags" {
  description = "Tags applied to every resource. Policy may add additional tags; lifecycle ignores drift."
  type        = map(string)
  default     = {}
}

variable "sku_name" {
  description = "App Service Plan SKU (e.g. B1, S1). Use F1 for free-tier dev; set enable_always_on = false accordingly."
  type        = string
  default     = "B1"
}

variable "enable_always_on" {
  description = "Keep the App Service always warm. Must be false for free-tier (F1/D1) SKUs."
  type        = bool
  default     = true
}

variable "python_version" {
  description = "Python runtime version for the App Service application stack."
  type        = string
  default     = "3.13"
}

variable "startup_command" {
  description = "Gunicorn startup command. Matches the FastAPI ASGI app entry-point."
  type        = string
  default     = "gunicorn -w 2 -k uvicorn.workers.UvicornWorker src.main:app"
}

# --- Secrets ---

variable "secret_key" {
  description = "Session encryption key for Starlette SessionMiddleware. Must be ≥ 32 random bytes."
  type        = string
  sensitive   = true
}

# --- OIDC / Keycloak ---

variable "oidc_discovery_url" {
  description = "BCGov Keycloak OIDC discovery endpoint (.well-known/openid-configuration). Leave blank to enable dev auto-login mode."
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OIDC client ID registered in Keycloak."
  type        = string
  default     = ""
}

variable "oidc_client_secret" {
  description = "OIDC client secret for the Keycloak confidential client."
  type        = string
  sensitive   = true
  default     = ""
}

variable "oidc_client_audience" {
  description = "Expected value of the 'aud' claim in the OIDC id_token. Defaults to oidc_client_id inside the app when left blank."
  type        = string
  default     = ""
}

variable "oidc_admin_role" {
  description = "Keycloak role name that grants portal admin access. Mapped via realm_access.roles or resource_access.<client_id>.roles."
  type        = string
  default     = "portal-admin"
}

# --- Azure Table Storage ---

variable "table_storage_account_url" {
  description = "Azure Table Storage account URL (https://<account>.table.core.windows.net). Used by the app for password-less auth via managed identity."
  type        = string
  default     = ""
}

variable "enable_table_rbac" {
  description = "Assign Storage Table Data Contributor to the App Service managed identity. Requires table_storage_account_id to be set."
  type        = bool
  default     = false
}

variable "table_storage_account_id" {
  description = "Azure Storage Account resource ID. Required when enable_table_rbac = true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_table_rbac || var.table_storage_account_id != ""
    error_message = "table_storage_account_id must be provided when enable_table_rbac = true."
  }
}

# --- Admin allow-list ---

variable "admin_emails" {
  description = "Comma-separated @gov.bc.ca email addresses for the secondary admin allow-list. Role-based check (oidc_admin_role) takes precedence."
  type        = string
  default     = ""
}

variable "extra_app_settings" {
  description = "Additional App Service application settings merged with the defaults."
  type        = map(string)
  default     = {}
}
