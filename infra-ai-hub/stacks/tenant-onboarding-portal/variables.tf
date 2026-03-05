# -----------------------------------------------------------------------------
# Variables – Tenant Onboarding Portal Stack
# -----------------------------------------------------------------------------

variable "app_env" {
  type = string
}

variable "location" {
  type = string
}

variable "subscription_id" {
  type      = string
  sensitive = true
}

variable "tenant_id" {
  type      = string
  sensitive = true
}

variable "client_id" {
  type      = string
  sensitive = true
}

variable "use_oidc" {
  type    = bool
  default = true
}

variable "resource_group_name" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "sku_name" {
  type    = string
  default = "B1"
}

variable "container_image" {
  type    = string
  default = "bcgov/ai-hub-tracking/tenant-onboarding-portal"
}

variable "container_tag" {
  type    = string
  default = "latest"
}

variable "secret_key" {
  type      = string
  sensitive = true
}

variable "oidc_discovery_url" {
  type    = string
  default = ""
}

variable "oidc_client_id" {
  type    = string
  default = ""
}

variable "oidc_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "table_storage_account_url" {
  type    = string
  default = ""
}

variable "table_storage_account_id" {
  type    = string
  default = ""
}

variable "admin_emails" {
  type    = string
  default = ""
}
