# -----------------------------------------------------------------------------
# Variables – Tenant Onboarding Portal Infrastructure
# -----------------------------------------------------------------------------

variable "app_env" {
  description = "Environment name used in resource naming and tagging (dev, test, prod, or tools)."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod", "tools"], var.app_env)
    error_message = "app_env must be one of: dev, test, prod, tools."
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

variable "vnet_name" {
  description = "Name of the existing virtual network used for App Service regional VNet integration."
  type        = string
}

variable "vnet_resource_group_name" {
  description = "Name of the resource group containing the target virtual network."
  type        = string
}

variable "app_service_subnet_name" {
  description = "Name of the delegated subnet used for App Service regional VNet integration."
  type        = string
  default     = "app-service-subnet"
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

variable "node_version" {
  description = "Optional Node.js runtime version override for the App Service application stack. Leave blank to derive it from tenant-onboarding-portal/.node-version using the Azure App Service '<major>-lts' format."
  type        = string
  default     = ""
}

variable "startup_command" {
  description = "Startup command for the NestJS runtime. Defaults to the compiled Node entrypoint."
  type        = string
  default     = "node dist/main.js"
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

variable "storage_account_name_override" {
  description = "Override the computed Storage Account name. Leave blank to use the generated 'st<env>portal<suffix>' pattern."
  type        = string
  default     = ""
}

variable "storage_account_replication_type" {
  description = "Replication type for the portal Storage Account. Defaults to LRS to keep dev/test costs down."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "storage_account_replication_type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "enable_table_rbac" {
  description = "Assign Storage Table Data Contributor to the App Service managed identity for the portal Storage Account."
  type        = bool
  default     = true
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

# --- Naming / Service Plan overrides (tools and PR preview deployments) ---

variable "enable_deployment_slot" {
  description = "Create a 'staging' deployment slot to enable zero-downtime slot-swap deployments. Requires a slot-capable App Service Plan (Standard or above). Leave false for dev/test/prod on Basic SKUs or for short-lived PR previews."
  type        = bool
  default     = false
}

variable "app_name_override" {
  description = "Override the computed App Service name. Set to 'ai-hub-onboarding' for the tools environment and 'pr<N>-ai-hub-onboarding' for PR previews. Leave blank (default) to use the conventional 'app-<env>-ai-hub-portal' name used by dev/test/prod."
  type        = string
  default     = ""
}


