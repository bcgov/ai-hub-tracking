# =============================================================================
# TENANT CONFIGURATIONS - TEST ENVIRONMENT
# =============================================================================
# Test environment tenants - used for integration and pre-production testing.
# =============================================================================

tenants = {
  wlrs-water-form-assistant = {
    tenant_name  = "wlrs-water-form-assistant"
    display_name = "WLRS Water Form Assistant"
    enabled      = true

    tags = {
      ministry    = "WLRS"
      environment = "test"
    }

    key_vault = {
      enabled                    = false
      sku                        = "standard"
      purge_protection_enabled   = true
      soft_delete_retention_days = 30 # Shorter retention for test
    }

    storage_account = {
      enabled                  = true
      account_tier             = "Standard"
      account_replication_type = "LRS"
      account_kind             = "StorageV2"
      access_tier              = "Hot"
    }

    ai_search = {
      enabled            = false
      sku                = "basic"
      replica_count      = 1
      partition_count    = 1
      semantic_search    = "free"
      local_auth_enabled = true
    }

    cosmos_db = {
      enabled                      = false
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
      enabled = true
      sku     = "S0"
      kind    = "FormRecognizer"
    }

    openai = {
      enabled = true
      sku     = "S0"
      model_deployments = [
        {
          name          = "gpt-4o-mini"
          model_name    = "gpt-4o-mini"
          model_version = "2024-07-18"
          scale_type    = "GlobalStandard"
          capacity      = 10
        },
        {
          name          = "text-embedding-ada-002"
          model_name    = "text-embedding-ada-002"
          model_version = "2"
          scale_type    = "GlobalStandard"
          capacity      = 10
        }
      ]
    }
  }
}
