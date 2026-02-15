variable "app_env" {
  type = string
}

variable "app_name" {
  type = string
}

variable "location" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
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

variable "shared_config" {
  type = any
}

variable "tenants" {
  type    = map(any)
  default = {}
}

variable "defender_enabled" {
  type    = bool
  default = false
}

variable "defender_resource_types" {
  type = map(object({
    subplan = optional(string, null)
  }))
  default = {}
}

variable "backend_resource_group" {
  type = string
}

variable "backend_storage_account" {
  type = string
}

variable "backend_container_name" {
  type    = string
  default = "tfstate"
}
