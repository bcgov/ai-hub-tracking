variable "app_env" {
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
  description = "Tenant configurations for the foundry deployment. Kept as any to avoid HCL map type-unification failures when tenants have non-identical nested shapes; stack logic uses try() defaults for optional fields."
  type        = any
  default     = {}

  validation {
    condition     = can(tomap(var.tenants))
    error_message = "tenants must be a map/object of tenant configs."
  }
}

variable "tenant_tags" {
  description = "Per-tenant tags (up to 20 key/value pairs each). Kept separate from var.tenants to avoid HCL structural type unification errors when different tenants have different tag keys."
  type        = map(map(string))
  default     = {}

  validation {
    condition     = alltrue([for t, tags in var.tenant_tags : length(tags) <= 20])
    error_message = "Each tenant may define at most 20 tags."
  }
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
