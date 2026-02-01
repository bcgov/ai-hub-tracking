variable "name" {
  description = "Name of the Application Gateway"
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

variable "subnet_id" {
  description = "Subnet ID for the Application Gateway"
  type        = string
}

variable "sku" {
  description = "SKU configuration for App Gateway"
  type = object({
    name     = optional(string, "WAF_v2")
    tier     = optional(string, "WAF_v2")
    capacity = optional(number, 2)
  })
  default = {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }
}

variable "autoscale" {
  description = "Autoscale configuration (if set, overrides sku.capacity)"
  type = object({
    min_capacity = number
    max_capacity = number
  })
  default = null
}

variable "waf_enabled" {
  description = "Enable Web Application Firewall"
  type        = bool
  default     = true
}

variable "waf_mode" {
  description = "WAF mode: Detection or Prevention"
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "waf_mode must be Detection or Prevention"
  }
}

variable "ssl_certificates" {
  description = "SSL certificates from Key Vault"
  type = map(object({
    name                = string
    key_vault_secret_id = string
  }))
  default = {}
}

variable "backend_apim" {
  description = "APIM backend configuration"
  type = object({
    fqdn        = string
    http_port   = optional(number, 80)
    https_port  = optional(number, 443)
    host_header = optional(string)
    probe_path  = optional(string, "/status-0123456789abcdef")
  })
}

variable "frontend_hostname" {
  description = "Frontend hostname for the listener"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for diagnostics"
  type        = string
  default     = null
}

variable "key_vault_id" {
  description = "Key Vault ID for SSL certificate access"
  type        = string
  default     = null
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

variable "zones" {
  description = "Availability zones for App Gateway"
  type        = set(string)
  default     = ["1", "2", "3"]
}

# -----------------------------------------------------------------------------
# URL Path Maps (for path-based routing)
# -----------------------------------------------------------------------------
variable "url_path_map_configurations" {
  description = "URL path maps for path-based routing"
  type = map(object({
    name                                = string
    default_backend_address_pool_name   = optional(string)
    default_backend_http_settings_name  = optional(string)
    default_redirect_configuration_name = optional(string)
    default_rewrite_rule_set_name       = optional(string)
    path_rules = map(object({
      name                        = string
      paths                       = list(string)
      backend_address_pool_name   = optional(string)
      backend_http_settings_name  = optional(string)
      redirect_configuration_name = optional(string)
      rewrite_rule_set_name       = optional(string)
      firewall_policy_id          = optional(string)
    }))
  }))
  default = null
}

# -----------------------------------------------------------------------------
# Rewrite Rule Sets
# -----------------------------------------------------------------------------
variable "rewrite_rule_set" {
  description = "Rewrite rule sets for header and URL manipulation"
  type = map(object({
    name = string
    rewrite_rules = optional(map(object({
      name          = string
      rule_sequence = number
      conditions = optional(map(object({
        ignore_case = optional(bool)
        negate      = optional(bool)
        pattern     = string
        variable    = string
      })))
      request_header_configurations = optional(map(object({
        header_name  = string
        header_value = string
      })))
      response_header_configurations = optional(map(object({
        header_name  = string
        header_value = string
      })))
      url = optional(object({
        components   = optional(string)
        path         = optional(string)
        query_string = optional(string)
        reroute      = optional(bool)
      }))
    })))
  }))
  default = null
}

# -----------------------------------------------------------------------------
# WAF Policy
# -----------------------------------------------------------------------------
variable "waf_policy_id" {
  description = "Resource ID of WAF policy to associate with App Gateway"
  type        = string
  default     = null
}

