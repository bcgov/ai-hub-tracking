# =============================================================================
# TENANT CONFIGURATIONS - DEV ENVIRONMENT
# =============================================================================
# This file defines all tenants and their resource configurations.
# Each tenant gets isolated resources within their own AI Foundry project.
#
# To add a new tenant:
# 1. Add a new entry to the tenants map below
# 2. Set enabled = true
# 3. Enable only the resources needed for that tenant
# 4. Run terraform plan to preview changes
# =============================================================================

tenants = {
  # ---------------------------------------------------------------------------
  # Tenant A - Development Team Alpha
  # ---------------------------------------------------------------------------
  # Full-featured tenant with all AI capabilities enabled.
  tenant-a = {
    tenant_name  = "tenant-a"
    display_name = "Development Team Alpha"
    enabled      = true # Set to false to disable without removing

    # Optional: Custom resource group name (defaults to {tenant_name}-rg)
    # resource_group_name = "custom-rg-name"

    # Optional: Additional tags specific to this tenant
    tags = {
      team        = "alpha"
      cost_center = "dev-001"
    }

    # -------------------------------------------------------------------------
    # Key Vault - Secrets and Certificate Management
    # -------------------------------------------------------------------------
    key_vault = {
      enabled = true
      sku     = "standard" # Options: standard, premium

      # Purge protection prevents permanent deletion (required for compliance)
      purge_protection_enabled = true

      # Soft delete retention (7-90 days)
      soft_delete_retention_days = 90
    }

    # -------------------------------------------------------------------------
    # Storage Account - Data Lake for AI/ML
    # -------------------------------------------------------------------------
    storage_account = {
      enabled = true

      account_tier             = "Standard" # Options: Standard, Premium
      account_replication_type = "LRS"      # Dev: LRS is sufficient
      account_kind             = "StorageV2"
      access_tier              = "Hot" # Options: Hot, Cool
    }

    # -------------------------------------------------------------------------
    # Azure AI Search - Vector and Semantic Search
    # -------------------------------------------------------------------------
    ai_search = {
      enabled = true
      sku     = "basic" # Options: free, basic, standard, standard2, standard3

      replica_count   = 1 # Number of replicas (HA requires 2+)
      partition_count = 1 # Number of partitions (scale-out)

      # Semantic search tier
      # Options: disabled, free, standard
      semantic_search = "free"

      # Local auth allows key-based access; disable for Entra-only auth
      local_auth_enabled = true
    }

    # -------------------------------------------------------------------------
    # Cosmos DB - NoSQL Database for AI Applications
    # -------------------------------------------------------------------------
    cosmos_db = {
      enabled = true

      offer_type = "Standard"
      kind       = "GlobalDocumentDB" # Options: GlobalDocumentDB, MongoDB

      # Consistency levels (trade-off between consistency and performance):
      # Strong, BoundedStaleness, Session, ConsistentPrefix, Eventual
      consistency_level = "Session"

      # BoundedStaleness settings (only used when consistency_level = BoundedStaleness)
      max_interval_in_seconds = 5
      max_staleness_prefix    = 100

      # Backup and HA settings (reduce costs in dev)
      geo_redundant_backup_enabled = false
      automatic_failover_enabled   = false

      # Total throughput limit in RU/s (-1 for unlimited)
      total_throughput_limit = 1000
    }

    # -------------------------------------------------------------------------
    # Document Intelligence - Form Processing
    # -------------------------------------------------------------------------
    document_intelligence = {
      enabled = true
      sku     = "S0"             # Options: F0 (free), S0
      kind    = "FormRecognizer" # Service type
    }

    # -------------------------------------------------------------------------
    # Azure OpenAI - LLM Deployments
    # -------------------------------------------------------------------------
    openai = {
      enabled = true
      sku     = "S0" # Standard tier

      # Model deployments for this tenant
      # Each deployment consumes quota from your subscription
      model_deployments = [
        {
          name          = "gpt-4o-mini"
          model_name    = "gpt-4o-mini"
          model_version = "2024-07-18"
          scale_type    = "Standard" # Options: Standard, Provisioned
          capacity      = 10         # TPM in thousands (10 = 10K TPM)
        },
        {
          name          = "text-embedding-ada-002"
          model_name    = "text-embedding-ada-002"
          model_version = "2"
          scale_type    = "Standard"
          capacity      = 10
        }
      ]
    }
  }

  # ---------------------------------------------------------------------------
  # Tenant B - Development Team Beta (Minimal Config Example)
  # ---------------------------------------------------------------------------
  # Lightweight tenant with only essential resources.
  tenant-b = {
    tenant_name  = "tenant-b"
    display_name = "Development Team Beta"
    enabled      = false # Disabled - enable when ready

    tags = {
      team        = "beta"
      cost_center = "dev-002"
    }

    key_vault = {
      enabled                    = true
      sku                        = "standard"
      purge_protection_enabled   = true
      soft_delete_retention_days = 90
    }

    storage_account = {
      enabled                  = true
      account_tier             = "Standard"
      account_replication_type = "LRS"
      account_kind             = "StorageV2"
      access_tier              = "Hot"
    }

    ai_search = {
      enabled            = false # Not needed for this tenant
      sku                = "basic"
      replica_count      = 1
      partition_count    = 1
      semantic_search    = "disabled"
      local_auth_enabled = true
    }

    cosmos_db = {
      enabled                      = false # Not needed for this tenant
      offer_type                   = "Standard"
      kind                         = "GlobalDocumentDB"
      consistency_level            = "Session"
      max_interval_in_seconds      = 5
      max_staleness_prefix         = 100
      geo_redundant_backup_enabled = false
      automatic_failover_enabled   = false
      total_throughput_limit       = 1000
    }

    document_intelligence = {
      enabled = false
      sku     = "S0"
      kind    = "FormRecognizer"
    }

    openai = {
      enabled = true # Only OpenAI enabled
      sku     = "S0"
      model_deployments = [
        {
          name          = "gpt-4o-mini"
          model_name    = "gpt-4o-mini"
          model_version = "2024-07-18"
          scale_type    = "Standard"
          capacity      = 5
        }
      ]
    }
  }
}
