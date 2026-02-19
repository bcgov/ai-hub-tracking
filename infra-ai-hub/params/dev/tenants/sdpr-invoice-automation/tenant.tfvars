# =============================================================================
# TENANT: SDPR Invoice Automation - Dev ENVIRONMENT
# =============================================================================
# Dev environment configuration for SDPR Invoice Automation.
# =============================================================================

tenant = {
  tenant_name  = "sdpr-invoice-automation"
  display_name = "SDPR Invoice Automation"
  enabled      = true

  tags = {
    ministry    = "SDPR"
    environment = "dev"
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
    diagnostics = {
      log_groups        = []
      log_categories    = []
      metric_categories = ["Capacity", "Transaction"]
    }
  }

  ai_search = {
    enabled            = false
    sku                = "basic"
    replica_count      = 1
    partition_count    = 1
    semantic_search    = "free"
    local_auth_enabled = true
  }

  # IMPORTANT: Even when disabled, cosmos_db MUST include all fields to match
  # other tenants' structure. Terraform map(any) requires identical object shapes.
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
    database_name                = "default"
    container_name               = "cosmosContainer"
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

  # Speech Services - disabled by default, enable for text-to-speech/speech-to-text capabilities
  speech_services = {
    enabled = false
  }

  log_analytics = {
    enabled        = true
    retention_days = 30
    sku            = "PerGB2018"
  }

  openai = {
    enabled = true
    sku     = "S0"
    diagnostics = {
      log_groups        = ["allLogs"]
      log_categories    = []
      metric_categories = ["AllMetrics"]
    }
    # Capacity = 1% of regional quota limit per model
    # Quota limits: gpt-4.1=30k, gpt-4.1-mini=150k, gpt-4.1-nano=150k,
    #   gpt-4o=30k, gpt-4o-mini=150k, gpt-5-mini=10k, gpt-5-nano=150k,
    #   gpt-5.1-chat=5k, gpt-5.1-codex-mini=10k, o1=5k, o3-mini=5k,
    #   o4-mini=10k, text-embedding-ada-002=10k, text-embedding-3-large=10k,
    #   text-embedding-3-small=10k
    model_deployments = [
      # GPT-4.1 Series
      {
        name          = "gpt-4.1"
        model_name    = "gpt-4.1"
        model_version = "2025-04-14"
        scale_type    = "GlobalStandard"
        capacity      = 300 # 1% of 30,000
      },
      {
        name          = "gpt-4.1-mini"
        model_name    = "gpt-4.1-mini"
        model_version = "2025-04-14"
        scale_type    = "GlobalStandard"
        capacity      = 1500 # 1% of 150,000
      },
      {
        name          = "gpt-4.1-nano"
        model_name    = "gpt-4.1-nano"
        model_version = "2025-04-14"
        scale_type    = "GlobalStandard"
        capacity      = 1500 # 1% of 150,000
      },
      # GPT-4o Series
      {
        name          = "gpt-4o"
        model_name    = "gpt-4o"
        model_version = "2024-11-20"
        scale_type    = "GlobalStandard"
        capacity      = 300 # 1% of 30,000
      },
      {
        name          = "gpt-4o-mini"
        model_name    = "gpt-4o-mini"
        model_version = "2024-07-18"
        scale_type    = "GlobalStandard"
        capacity      = 1500 # 1% of 150,000
      },
      # GPT-5 Series
      {
        name          = "gpt-5-mini"
        model_name    = "gpt-5-mini"
        model_version = "2025-08-07"
        scale_type    = "GlobalStandard"
        capacity      = 100 # 1% of 10,000
      },
      {
        name          = "gpt-5-nano"
        model_name    = "gpt-5-nano"
        model_version = "2025-08-07"
        scale_type    = "GlobalStandard"
        capacity      = 1500 # 1% of 150,000
      },
      # GPT-5.1 Series
      {
        name          = "gpt-5.1-chat"
        model_name    = "gpt-5.1-chat"
        model_version = "2025-11-13"
        scale_type    = "GlobalStandard"
        capacity      = 50 # 1% of 5,000
      },
      {
        name          = "gpt-5.1-codex-mini"
        model_name    = "gpt-5.1-codex-mini"
        model_version = "2025-11-13"
        scale_type    = "GlobalStandard"
        capacity      = 100 # 1% of 10,000
      },
      # Reasoning Models
      {
        name          = "o1"
        model_name    = "o1"
        model_version = "2024-12-17"
        scale_type    = "GlobalStandard"
        capacity      = 50 # 1% of 5,000
      },
      {
        name          = "o3-mini"
        model_name    = "o3-mini"
        model_version = "2025-01-31"
        scale_type    = "GlobalStandard"
        capacity      = 50 # 1% of 5,000
      },
      {
        name          = "o4-mini"
        model_name    = "o4-mini"
        model_version = "2025-04-16"
        scale_type    = "GlobalStandard"
        capacity      = 100 # 1% of 10,000
      },
      # Embeddings
      {
        name          = "text-embedding-ada-002"
        model_name    = "text-embedding-ada-002"
        model_version = "2"
        scale_type    = "GlobalStandard"
        capacity      = 100 # 1% of 10,000
      },
      {
        name          = "text-embedding-3-large"
        model_name    = "text-embedding-3-large"
        model_version = "1"
        scale_type    = "GlobalStandard"
        capacity      = 100 # 1% of 10,000
      },
      {
        name          = "text-embedding-3-small"
        model_name    = "text-embedding-3-small"
        model_version = "1"
        scale_type    = "GlobalStandard"
        capacity      = 100 # 1% of 10,000
      },
    ]
  }

  # APIM Authentication
  apim_auth = {
    mode              = "subscription_key"
    store_in_keyvault = false
  }

  # Tenant user management (applies across environments)
  user_management = {
    seed_members = {
      admin = [
        "anthony.shivakumar@gov.bc.ca",
        "alex.struk@gov.bc.ca",
        "kaegan.mandryk@gov.bc.ca",
        "justin.hewitt@gov.bc.ca"
      ]
    }
  }

  # APIM Policies Configuration
  # Consolidates all APIM policy settings for this tenant
  apim_policies = {
    rate_limiting = {
      enabled           = true
      tokens_per_minute = 1000
    }
    pii_redaction = {
      enabled     = true
      fail_closed = true # Block requests if PII service fails (not applicable when disabled)
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

  # Per-tenant APIM Diagnostics
  apim_diagnostics = {
    sampling_percentage = 100
    verbosity           = "information"
  }
}
