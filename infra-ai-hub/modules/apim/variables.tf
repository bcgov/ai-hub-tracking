variable "name" {
  description = "Name of the API Management instance"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "sku_name" {
  description = "SKU name for APIM (stv2). StandardV2 for cost-effective, PremiumV2 for VNet injection and advanced features."
  type        = string
  default     = "StandardV2"

  validation {
    condition     = contains(["StandardV2", "PremiumV2"], var.sku_name)
    error_message = "sku_name must be either StandardV2 or PremiumV2"
  }
}

variable "publisher_name" {
  description = "Publisher name for APIM"
  type        = string
}

variable "publisher_email" {
  description = "Publisher email for APIM"
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for APIM private endpoint (stv2)"
  type        = string
  default     = null
}

variable "private_dns_zone_ids" {
  description = "List of private DNS zone IDs to link for APIM private endpoint"
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for diagnostics"
  type        = string
  default     = null
}

variable "tenant_products" {
  description = "Map of tenant names to their product configurations"
  type = map(object({
    display_name          = string
    description           = optional(string)
    subscription_required = optional(bool, true)
    approval_required     = optional(bool, false)
    state                 = optional(string, "published")
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "enable_telemetry" {
  description = "Enable AVM telemetry"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# APIs Configuration
# -----------------------------------------------------------------------------
variable "apis" {
  description = "Map of APIs to create in APIM"
  type = map(object({
    display_name          = string
    description           = optional(string)
    path                  = string
    protocols             = optional(list(string), ["https"])
    subscription_required = optional(bool, true)
    api_type              = optional(string, "http")
    revision              = optional(string, "1")
    service_url           = optional(string)
    import = optional(object({
      content_format = string # swagger-json, swagger-link-json, openapi, openapi+json, openapi-link, wadl-xml, wadl-link-json, wsdl, wsdl-link
      content_value  = string
    }))
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Subscriptions Configuration
# -----------------------------------------------------------------------------
variable "subscriptions" {
  description = "Map of subscriptions to create"
  type = map(object({
    display_name  = string
    scope_type    = string # product or api
    product_id    = optional(string)
    api_id        = optional(string)
    state         = optional(string, "active")
    allow_tracing = optional(bool, false)
    primary_key   = optional(string)
    secondary_key = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Named Values (for secrets and configuration)
# -----------------------------------------------------------------------------
variable "named_values" {
  description = "Map of named values (properties) for APIM"
  type = map(object({
    display_name = string
    value        = optional(string)
    secret       = optional(bool, false)
    key_vault = optional(object({
      secret_id          = string
      identity_client_id = optional(string)
    }))
    tags = optional(list(string), [])
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Policy Fragments (reusable policy snippets)
# -----------------------------------------------------------------------------
variable "policy_fragments" {
  description = "Map of reusable policy fragments"
  type = map(object({
    description = optional(string)
    format      = optional(string, "xml") # xml or rawxml
    value       = string
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Global Policy
# -----------------------------------------------------------------------------
variable "global_policy_xml" {
  description = "XML content for the global API Management policy"
  type        = string
  default     = null
}
