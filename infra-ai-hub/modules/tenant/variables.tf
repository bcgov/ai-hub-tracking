variable "tenant_name" {
  description = "Unique identifier for the tenant (used in resource names)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.tenant_name))
    error_message = "tenant_name must be lowercase alphanumeric with hyphens only."
  }
}

variable "display_name" {
  description = "Human-readable display name for the tenant"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "ai_location" {
  description = "Azure region for AI services (OpenAI, Document Intelligence). Can differ from location for model availability."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Resource Group Configuration
# -----------------------------------------------------------------------------
variable "resource_group_name_override" {
  description = "Optional custom name for the tenant resource group. If not provided, defaults to '{tenant_name}-rg'"
  type        = string
  default     = null
}

variable "ai_foundry_hub_id" {
  description = "Resource ID of the shared AI Foundry hub"
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoints"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of Log Analytics workspace for diagnostics (legacy/shared)"
  type        = string
  default     = null
}

variable "log_analytics" {
  description = "Per-tenant Log Analytics workspace configuration"
  type = object({
    enabled        = bool
    retention_days = optional(number, 30)
    sku            = optional(string, "PerGB2018")
  })
  default = {
    enabled = false
  }
}

variable "private_endpoint_dns_wait" {
  description = "Configuration for waiting on policy-managed DNS zone groups"
  type = object({
    timeout       = optional(string, "12m")
    poll_interval = optional(string, "30s")
  })
  default = {}
}

# -----------------------------------------------------------------------------
# Key Vault Configuration
# -----------------------------------------------------------------------------
variable "key_vault" {
  description = "Key Vault configuration for the tenant"
  type = object({
    enabled                    = bool
    sku                        = optional(string, "standard")
    purge_protection_enabled   = optional(bool, true)
    soft_delete_retention_days = optional(number, 90)
    diagnostics = optional(object({
      log_groups        = optional(list(string), [])
      log_categories    = optional(list(string), [])
      metric_categories = optional(list(string), [])
    }))
  })
  default = {
    enabled = false
  }
}

# -----------------------------------------------------------------------------
# Storage Account Configuration
# -----------------------------------------------------------------------------
variable "storage_account" {
  description = "Storage Account configuration for the tenant"
  type = object({
    enabled                  = bool
    account_tier             = optional(string, "Standard")
    account_replication_type = optional(string, "LRS")
    account_kind             = optional(string, "StorageV2")
    access_tier              = optional(string, "Hot")
    diagnostics = optional(object({
      log_groups        = optional(list(string), [])
      log_categories    = optional(list(string), [])
      metric_categories = optional(list(string), [])
    }))
  })
  default = {
    enabled = false
  }
}

# -----------------------------------------------------------------------------
# AI Search Configuration
# -----------------------------------------------------------------------------
variable "ai_search" {
  description = "Azure AI Search configuration for the tenant"
  type = object({
    enabled            = bool
    sku                = optional(string, "basic")
    replica_count      = optional(number, 1)
    partition_count    = optional(number, 1)
    semantic_search    = optional(string, "disabled")
    local_auth_enabled = optional(bool, true)
    diagnostics = optional(object({
      log_groups        = optional(list(string), [])
      log_categories    = optional(list(string), [])
      metric_categories = optional(list(string), [])
    }))
  })
  default = {
    enabled = false
  }
}

# -----------------------------------------------------------------------------
# Cosmos DB Configuration
# -----------------------------------------------------------------------------
variable "cosmos_db" {
  description = "Cosmos DB configuration for the tenant"
  type = object({
    enabled                      = bool
    offer_type                   = optional(string, "Standard")
    kind                         = optional(string, "GlobalDocumentDB")
    consistency_level            = optional(string, "Session")
    max_interval_in_seconds      = optional(number, 5)
    max_staleness_prefix         = optional(number, 100)
    geo_redundant_backup_enabled = optional(bool, false)
    automatic_failover_enabled   = optional(bool, false)
    total_throughput_limit       = optional(number, 1000)
    database_name                = optional(string, "default") # Database name for project connection
    diagnostics = optional(object({
      log_groups        = optional(list(string), [])
      log_categories    = optional(list(string), [])
      metric_categories = optional(list(string), [])
    }))
  })
  default = {
    enabled = false
  }
}

# -----------------------------------------------------------------------------
# Project Connections Configuration
# Controls which resources are connected to the AI Foundry project
# -----------------------------------------------------------------------------
variable "project_connections" {
  description = "Configure which resources to connect to the AI Foundry project"
  type = object({
    key_vault             = optional(bool, true)
    storage               = optional(bool, true)
    ai_search             = optional(bool, true)
    cosmos_db             = optional(bool, true)
    openai                = optional(bool, true)
    document_intelligence = optional(bool, true)
  })
  default = {}
}

# -----------------------------------------------------------------------------
# Document Intelligence Configuration
# -----------------------------------------------------------------------------
variable "document_intelligence" {
  description = "Document Intelligence configuration for the tenant"
  type = object({
    enabled = bool
    sku     = optional(string, "S0")
    kind    = optional(string, "FormRecognizer")
    diagnostics = optional(object({
      log_groups        = optional(list(string), [])
      log_categories    = optional(list(string), [])
      metric_categories = optional(list(string), [])
    }))
  })
  default = {
    enabled = false
  }
}

# -----------------------------------------------------------------------------
# OpenAI Configuration
# -----------------------------------------------------------------------------
variable "openai" {
  description = "OpenAI configuration for the tenant"
  type = object({
    enabled = bool
    sku     = optional(string, "S0")
    model_deployments = optional(list(object({
      name            = string
      model_name      = string
      model_version   = string
      scale_type      = optional(string, "Standard")
      capacity        = optional(number, 10)
      rai_policy_name = optional(string) # Responsible AI policy name
    })), [])
    diagnostics = optional(object({
      log_groups        = optional(list(string), [])
      log_categories    = optional(list(string), [])
      metric_categories = optional(list(string), [])
    }))
  })
  default = {
    enabled = false
  }
}

variable "tags" {
  description = "Tags to apply to tenant resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Role Assignments Configuration
# Allows custom RBAC assignments to tenant resources
# -----------------------------------------------------------------------------
variable "role_assignments" {
  description = "Custom role assignments for tenant resources"
  type = object({
    resource_group = optional(list(object({
      principal_id         = string
      role_definition_name = string
      principal_type       = optional(string)
      description          = optional(string)
    })), [])
    key_vault = optional(list(object({
      principal_id         = string
      role_definition_name = string
      principal_type       = optional(string)
      description          = optional(string)
    })), [])
    storage = optional(list(object({
      principal_id         = string
      role_definition_name = string
      principal_type       = optional(string)
      description          = optional(string)
    })), [])
    ai_search = optional(list(object({
      principal_id         = string
      role_definition_name = string
      principal_type       = optional(string)
      description          = optional(string)
    })), [])
    openai = optional(list(object({
      principal_id         = string
      role_definition_name = string
      principal_type       = optional(string)
      description          = optional(string)
    })), [])
    cosmos_db = optional(list(object({
      principal_id         = string
      role_definition_name = string
      principal_type       = optional(string)
      description          = optional(string)
    })), [])
  })
  default = {}
}
