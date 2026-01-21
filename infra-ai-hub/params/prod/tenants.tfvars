# =============================================================================
# TENANT CONFIGURATIONS - PROD ENVIRONMENT
# =============================================================================
# Production tenants - configured for high availability and compliance.
# All resources use production-grade settings.
#
# IMPORTANT: Before adding a production tenant:
# 1. Verify quota availability for OpenAI models
# 2. Confirm cost approval for the resources
# 3. Review security settings with the security team
# =============================================================================

tenants = {
  # ---------------------------------------------------------------------------
  # Production Tenant Example
  # ---------------------------------------------------------------------------
  # This is a template for production tenants. Clone and customize as needed.
  prod-tenant-example = {
    tenant_name  = "prod-tenant"
    display_name = "Production Tenant"
    enabled      = false # Enable when ready for production

    tags = {
      team          = "production"
      cost_center   = "prod-001"
      data_class    = "confidential"
      business_unit = "enterprise"
    }

    # -------------------------------------------------------------------------
    # Key Vault - Production Settings
    # -------------------------------------------------------------------------
    key_vault = {
      enabled = true
      sku     = "standard"

      # COMPLIANCE: Purge protection required in production
      purge_protection_enabled   = true
      soft_delete_retention_days = 90
    }

    # -------------------------------------------------------------------------
    # Storage Account - Production Settings
    # -------------------------------------------------------------------------
    storage_account = {
      enabled = true

      account_tier = "Standard"

      # RELIABILITY: GRS for production data protection
      account_replication_type = "GRS"
      account_kind             = "StorageV2"
      access_tier              = "Hot"
    }

    # -------------------------------------------------------------------------
    # Azure AI Search - Production Settings
    # -------------------------------------------------------------------------
    ai_search = {
      enabled = true

      # Production: standard tier for better performance
      sku = "standard"

      # RELIABILITY: 2+ replicas for HA
      replica_count   = 2
      partition_count = 1

      semantic_search = "standard"

      # SECURITY: Disable local auth in production
      local_auth_enabled = false
    }

    # -------------------------------------------------------------------------
    # Cosmos DB - Production Settings
    # -------------------------------------------------------------------------
    cosmos_db = {
      enabled = true

      offer_type        = "Standard"
      kind              = "GlobalDocumentDB"
      consistency_level = "Session"

      max_interval_in_seconds = 5
      max_staleness_prefix    = 100

      # RELIABILITY: Enable backups and failover in production
      geo_redundant_backup_enabled = true
      automatic_failover_enabled   = true

      # Production throughput limit
      total_throughput_limit = 10000
    }

    # -------------------------------------------------------------------------
    # Document Intelligence - Production Settings
    # -------------------------------------------------------------------------
    document_intelligence = {
      enabled = true
      sku     = "S0"
      kind    = "FormRecognizer"
    }

    # -------------------------------------------------------------------------
    # Azure OpenAI - Production Model Deployments
    # -------------------------------------------------------------------------
    openai = {
      enabled = true
      sku     = "S0"

      model_deployments = [
        {
          name          = "gpt-4o"
          model_name    = "gpt-4o"
          model_version = "2024-11-20"
          scale_type    = "Standard"
          capacity      = 50 # Higher capacity for production
        },
        {
          name          = "gpt-4o-mini"
          model_name    = "gpt-4o-mini"
          model_version = "2024-07-18"
          scale_type    = "Standard"
          capacity      = 100
        },
        {
          name          = "text-embedding-3-large"
          model_name    = "text-embedding-3-large"
          model_version = "1"
          scale_type    = "Standard"
          capacity      = 50
        }
      ]
    }
  }
}
