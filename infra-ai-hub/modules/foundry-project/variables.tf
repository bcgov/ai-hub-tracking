# =============================================================================
# AI Foundry Project Module - Variables
# =============================================================================
# Input variables for creating AI Foundry projects and connections.
# =============================================================================

variable "tenant_name" {
  description = "Name of the tenant (used for resource naming)"
  type        = string
}

variable "location" {
  description = "Azure region for the project"
  type        = string
}

variable "ai_location" {
  description = "Azure region for AI resources (can differ from project location for model availability)"
  type        = string
}

variable "ai_foundry_hub_id" {
  description = "Resource ID of the parent AI Foundry hub"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# TENANT RESOURCE REFERENCES
# These are outputs from the tenant module, used for connections and RBAC
# =============================================================================

variable "key_vault" {
  description = "Key Vault configuration from tenant module"
  type = object({
    enabled     = bool
    resource_id = optional(string)
    vault_uri   = optional(string)
  })
  default = {
    enabled = false
  }
}

variable "storage_account" {
  description = "Storage account configuration from tenant module"
  type = object({
    enabled           = bool
    resource_id       = optional(string)
    name              = optional(string)
    blob_endpoint_url = optional(string)
  })
  default = {
    enabled = false
  }
}

variable "ai_search" {
  description = "AI Search configuration from tenant module"
  type = object({
    enabled     = bool
    resource_id = optional(string)
  })
  default = {
    enabled = false
  }
}

variable "cosmos_db" {
  description = "Cosmos DB configuration from tenant module"
  type = object({
    enabled       = bool
    resource_id   = optional(string)
    database_name = optional(string)
  })
  default = {
    enabled = false
  }
}

variable "document_intelligence" {
  description = "Document Intelligence configuration from tenant module"
  type = object({
    enabled     = bool
    resource_id = optional(string)
    endpoint    = optional(string)
  })
  default = {
    enabled = false
  }
}

# NOTE: openai variable removed - model deployments are on the parent Hub
# The project automatically inherits access to all models on its parent Hub.
# No separate connection or role assignment is needed.

# =============================================================================
# AI MODEL DEPLOYMENTS
# Model deployments are created on the parent AI Foundry Hub
# =============================================================================

variable "ai_model_deployments" {
  description = "AI model deployments to create on the shared AI Foundry Hub (prefixed with tenant name)"
  type = map(object({
    name                   = string
    rai_policy_name        = optional(string) # Explicit policy name override; null = resolved by locals
    version_upgrade_option = optional(string, "OnceNewDefaultVersionAvailable")
    model = object({
      format  = optional(string, "OpenAI")
      name    = string
      version = string
    })
    scale = object({
      type     = string
      capacity = number
    })
    # When filters is non-empty, a custom raiPolicy resource is created on the Hub.
    # Use filters = [] (empty) to keep Microsoft.DefaultV2 (Azure built-in default).
    content_filter = optional(object({
      base_policy_name = optional(string, "Microsoft.DefaultV2")
      filters = optional(list(object({
        name               = string # hate | violence | sexual | selfharm
        severity_threshold = string # Low | Medium | High
        blocking           = optional(bool, true)
        enabled            = optional(bool, true)
        source             = string # Prompt | Completion
      })), [])
    }), { base_policy_name = "Microsoft.DefaultV2", filters = [] })
  }))
  default = {}

  validation {
    condition = alltrue([
      for deployment in values(var.ai_model_deployments) :
      alltrue([
        for f in deployment.content_filter.filters :
        contains(["hate", "violence", "sexual", "selfharm"], f.name)
      ])
    ])
    error_message = "content_filter.filters[*].name must be one of: hate, violence, sexual, selfharm."
  }

  validation {
    condition = alltrue([
      for deployment in values(var.ai_model_deployments) :
      alltrue([
        for f in deployment.content_filter.filters :
        contains(["Low", "Medium", "High"], f.severity_threshold)
      ])
    ])
    error_message = "content_filter.filters[*].severity_threshold must be one of: Low, Medium, High."
  }

  validation {
    condition = alltrue([
      for deployment in values(var.ai_model_deployments) :
      alltrue([
        for f in deployment.content_filter.filters :
        contains(["Prompt", "Completion"], f.source)
      ])
    ])
    error_message = "content_filter.filters[*].source must be one of: Prompt, Completion."
  }
}

# =============================================================================
# CONNECTION TOGGLES
# Allow enabling/disabling specific project connections
# =============================================================================

variable "project_connections" {
  description = "Toggle which project connections to create"
  type = object({
    key_vault             = optional(bool, true)
    storage               = optional(bool, true)
    ai_search             = optional(bool, true)
    cosmos_db             = optional(bool, true)
    document_intelligence = optional(bool, true)
    # openai toggle removed - models on Hub are implicitly accessible
  })
  default = {}
}
