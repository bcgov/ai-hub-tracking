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
  description = "SKU name for APIM (stv2). StandardV2_1-10 for cost-effective, PremiumV2_1-30 for VNet injection and advanced features."
  type        = string
  default     = "StandardV2_1"

  validation {
    condition     = can(regex("^(StandardV2_[1-9]|StandardV2_10|PremiumV2_([1-9]|[12][0-9]|30))$", var.sku_name))
    error_message = "sku_name must be one of: StandardV2_1 through StandardV2_10, PremiumV2_1 through PremiumV2_30"
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

variable "enable_private_endpoint" {
  description = "Whether to create a private endpoint for APIM inbound access. Must be set explicitly to avoid plan-time evaluation issues."
  type        = bool
  default     = false
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for APIM private endpoint (stv2). Required when enable_private_endpoint is true."
  type        = string
  default     = null
}

variable "private_dns_zone_ids" {
  description = "List of private DNS zone IDs to link for APIM private endpoint"
  type        = list(string)
  default     = []
}

# VNet Integration for outbound connectivity (StandardV2/PremiumV2)
variable "enable_vnet_integration" {
  description = "Whether to enable VNet integration for outbound connectivity. Required when backend services have public network access disabled."
  type        = bool
  default     = false
}

variable "vnet_integration_subnet_id" {
  description = "Subnet ID for APIM VNet integration (outbound). Required when enable_vnet_integration is true. Subnet must have delegation to Microsoft.Web/hostingEnvironments."
  type        = string
  default     = null
}

variable "enable_diagnostics" {
  description = "Whether to enable diagnostic settings. Must be set explicitly to avoid plan-time evaluation issues."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for diagnostics. Required when enable_diagnostics is true."
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
