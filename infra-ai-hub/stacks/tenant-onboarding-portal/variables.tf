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

variable "python_version" {
  type    = string
  default = "3.13"
}

variable "startup_command" {
  type    = string
  default = "gunicorn -w 2 -k uvicorn.workers.UvicornWorker src.main:app"
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
