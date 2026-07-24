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
  description = "Tenant configurations for the foundry deployment. Each tenant requires specific resource settings. Using optional() attributes with defaults ensures consistent type inference across all tenants and prevents 'all map elements must have the same type' errors."

  type = map(object({
    # Identity and basic configuration
    tenant_name  = optional(string, "")
    display_name = optional(string, "")
    enabled      = optional(bool, true)
    pe_subnet_key = optional(string, "privateendpoints-subnet")

    # Tags for all tenant resources
    tags = optional(map(string), {})

    # Service configurations (using any for flexibility in nested structure)
    key_vault              = optional(any, {})
    storage_account        = optional(any, {})
    ai_search              = optional(any, {})
    cosmos_db              = optional(any, {})
    document_intelligence  = optional(any, {})
    speech_services        = optional(any, {})
    log_analytics          = optional(any, {})
    openai                 = optional(any, {})

    # APIM Authentication
    apim_auth = optional(object({
      mode                 = optional(string, "subscription_key")
      key_rotation_enabled = optional(bool, true)
    }), {
      mode                 = "subscription_key"
      key_rotation_enabled = true
    })

    # APIM Policies with standardized nested structure
    apim_policies = optional(object({
      rate_limiting = optional(object({
        enabled           = optional(bool, true)
        tokens_per_minute = optional(number, 1000)
      }), {
        enabled           = true
        tokens_per_minute = 1000
      })
      pii_redaction = optional(object({
        enabled             = optional(bool, false)
        fail_closed         = optional(bool, false)
        excluded_categories = optional(list(string), [])
      }), {
        enabled             = false
        fail_closed         = false
        excluded_categories = []
      })
      usage_logging = optional(object({
        enabled = optional(bool, true)
      }), {
        enabled = true
      })
      streaming_metrics = optional(object({
        enabled = optional(bool, true)
      }), {
        enabled = true
      })
      tracking_dimensions = optional(object({
        enabled = optional(bool, true)
      }), {
        enabled = true
      })
      intelligent_routing = optional(object({
        enabled = optional(bool, false)
      }), {
        enabled = false
      })
    }), {})

    # APIM Diagnostics
    apim_diagnostics = optional(object({
      sampling_percentage = optional(number, 100)
      verbosity           = optional(string, "information")
    }), {
      sampling_percentage = 100
      verbosity           = "information"
    })

    # Tenant user management
    user_management = optional(any, {})
  }))

  default = {}
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
