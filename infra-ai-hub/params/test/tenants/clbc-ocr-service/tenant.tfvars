# =============================================================================
# TENANT: CLBC OCR Service - TEST ENVIRONMENT
# =============================================================================
# TEST environment configuration for CLBC OCR Service.
# Document Intelligence + Storage only. Key Vault, AI Search, Cosmos DB,
# Speech and OpenAI model deployments are disabled. Every block keeps its full
# shape (even when disabled) for map(any) element-type uniformity across tenants.
# =============================================================================

tenant = {
  tenant_name  = "clbc-ocr-service"
  display_name = "CLBC OCR Service"
  enabled      = true

  # PE subnet assignment - sticky, do not change after first deploy (destroys/recreates all PEs)
  # Valid keys: privateendpoints-subnet, privateendpoints-subnet-1, privateendpoints-subnet-2, ...
  pe_subnet_key = "privateendpoints-subnet"

  tags = {
    ministry    = "CLBC"
    environment = "test"
    department  = "Community Living BC"
  }

  # Key Vault not required by this tenant.
  key_vault = {
    enabled                    = false
    sku                        = "standard"
    purge_protection_enabled   = true
    soft_delete_retention_days = 30
  }

  storage_account = {
    enabled                  = true
    account_tier             = "Standard"
    account_replication_type = "LRS"
    account_kind             = "StorageV2"
    access_tier              = "Hot"
    diagnostics = {
      log_groups        = []
      log_categories    = []
      metric_categories = ["Capacity", "Transaction"]
    }
  }

  # Azure AI Search not required by this tenant. Full shape retained (even when
  # disabled) for map(any) element-type uniformity across all tenants.
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
    # Required for map(any) shape uniformity across all tenants (even when disabled)
    database_name  = "default"
    container_name = "cosmosContainer"
  }

  document_intelligence = {
    enabled = true
    sku     = "S0"
    kind    = "FormRecognizer"
    diagnostics = {
      log_groups        = ["allLogs"]
      log_categories    = []
      metric_categories = ["AllMetrics"]
    }
  }

  # Speech Services - MUST be present even if disabled (map(any) type constraint)
  speech_services = {
    enabled = false
  }

  log_analytics = {
    enabled        = true
    retention_days = 30
    sku            = "PerGB2018"
  }

  # No model deployments - this tenant uses Document Intelligence only. APIM keys
  # OpenAI routing off length(model_deployments), so no /openai backend is created.
  openai = {
    enabled = false
    sku     = "S0"
    diagnostics = {
      log_groups        = ["allLogs"]
      log_categories    = []
      metric_categories = ["AllMetrics"]
    }
    model_deployments = []
  }

  user_management = {
    seed_members = {
      admin = [
        "pushkar.purohit@gov.bc.ca",
        "mohinder.sasan@gov.bc.ca"
      ]
      write = [
        "kaushik.gummaraju@gov.bc.ca",
        "daniela.mitre@gov.bc.ca",
        "blair.davies@gov.bc.ca"
      ]
      read = [
        "abitinder.dhindsa@gov.bc.ca"
      ]
    }
  }

  # APIM Authentication - present on all tenants for map(any) shape uniformity
  apim_auth = {
    mode                 = "subscription_key"
    key_rotation_enabled = false
  }

  apim_policies = {
    rate_limiting = {
      enabled           = true
      tokens_per_minute = 1000
    }
    # PII redaction only runs on /openai routes; no effect without model deployments
    pii_redaction = {
      enabled             = false
      fail_closed         = false
      excluded_categories = []
    }
    usage_logging = {
      enabled = true
    }
    streaming_metrics = {
      enabled = true
    }
    tracking_dimensions = {
      enabled = true
    }
    intelligent_routing = {
      enabled = false
    }
  }

  # Per-tenant APIM Diagnostics - logs go to tenant's own LAW
  apim_diagnostics = {
    sampling_percentage = 100
    verbosity           = "information"
  }
}
