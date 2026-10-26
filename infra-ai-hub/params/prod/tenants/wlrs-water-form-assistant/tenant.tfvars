# =============================================================================
# TENANT: WLRS Water Form Assistant - PROD ENVIRONMENT
# =============================================================================
# Production environment configuration for WLRS Water Form Assistant.
# Configured for high availability and compliance.
# =============================================================================

tenant = {
  tenant_name  = "wlrs-water-form-assistant"
  display_name = "WLRS Water Form Assistant"
  enabled      = true

  # PE subnet assignment — sticky, do not change after first deploy (destroys/recreates all PEs)
  # Valid keys: privateendpoints-subnet, privateendpoints-subnet-1, privateendpoints-subnet-2, ...
  pe_subnet_key = "privateendpoints-subnet"

  tags = {
    ministry    = "WLRS"
    environment = "prod"
  }

  key_vault = {
    enabled                    = false
    sku                        = "standard"
    purge_protection_enabled   = true
    soft_delete_retention_days = 90 # Longer retention for prod
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
    enabled            = true
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

  # Speech Services - MUST be present even if disabled (map(any) type constraint)
  speech_services = {
    enabled = false
  }

  log_analytics = {
    enabled        = true
    retention_days = 90
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
    #   gpt-5.1=30k, gpt-5.1-codex-mini=10k, o4-mini=10k,
    #   text-embedding-ada-002=10k, text-embedding-3-large=10k,
    #   text-embedding-3-small=10k
    model_deployments = [
      # GPT-4.1 Series
      {
        name           = "gpt-4.1"
        model_name     = "gpt-4.1"
        model_version  = "2025-04-14"
        scale_type     = "GlobalStandard"
        capacity       = 300 # 1% of 30,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "gpt-4.1-mini"
        model_name     = "gpt-4.1-mini"
        model_version  = "2025-04-14"
        scale_type     = "GlobalStandard"
        capacity       = 1500 # 1% of 150,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "gpt-4.1-nano"
        model_name     = "gpt-4.1-nano"
        model_version  = "2025-04-14"
        scale_type     = "GlobalStandard"
        capacity       = 1500 # 1% of 150,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      # GPT-4o Series
      {
        name           = "gpt-4o"
        model_name     = "gpt-4o"
        model_version  = "2024-11-20"
        scale_type     = "GlobalStandard"
        capacity       = 300 # 1% of 30,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      # GPT-5 Series
      {
        name           = "gpt-5-mini"
        model_name     = "gpt-5-mini"
        model_version  = "2025-08-07"
        scale_type     = "GlobalStandard"
        capacity       = 100 # 1% of 10,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "gpt-5-nano"
        model_name     = "gpt-5-nano"
        model_version  = "2025-08-07"
        scale_type     = "GlobalStandard"
        capacity       = 1500 # 1% of 150,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      # GPT-5.1 Series
      {
        name           = "gpt-5.1"
        model_name     = "gpt-5.1"
        model_version  = "2025-11-13"
        scale_type     = "GlobalStandard"
        capacity       = 300 # 1% of 30,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "gpt-5.1-codex-mini"
        model_name     = "gpt-5.1-codex-mini"
        model_version  = "2025-11-13"
        scale_type     = "GlobalStandard"
        capacity       = 100 # 1% of 10,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      # Embeddings
      {
        name           = "text-embedding-ada-002"
        model_name     = "text-embedding-ada-002"
        model_version  = "2"
        scale_type     = "GlobalStandard"
        capacity       = 100 # 1% of 10,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "text-embedding-3-large"
        model_name     = "text-embedding-3-large"
        model_version  = "1"
        scale_type     = "GlobalStandard"
        capacity       = 100 # 1% of 10,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "text-embedding-3-small"
        model_name     = "text-embedding-3-small"
        model_version  = "1"
        scale_type     = "GlobalStandard"
        capacity       = 100 # 1% of 10,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
    ]
  }

  apim_policies = {
    rate_limiting = {
      enabled           = true
      tokens_per_minute = 1000
    }
    pii_redaction = {
      enabled             = true                                                      # Redact emails, phone numbers, addresses, etc.
      fail_closed         = false                                                     # Fail-open: allow requests through if PII service fails
      excluded_categories = ["PersonType", "URL", "Organization", "Location", "City"] # Do not redact these PII categories for WLRS
    }
    usage_logging = {
      enabled = true # Log AI model token usage
    }
    streaming_metrics = {
      enabled = true # Emit metrics for streaming requests
    }
    tracking_dimensions = {
      enabled = true # Extract tracking headers for analytics
    }
    intelligent_routing = {
      enabled = false # Disabled until multi-backend setup
    }
  }

  # Per-tenant APIM Diagnostics - logs go to tenant's own LAW
  apim_diagnostics = {
    sampling_percentage = 100
    verbosity           = "information"
  }

  # APIM Authentication
  apim_auth = {
    mode                 = "subscription_key"
    key_rotation_enabled = false # Per-tenant opt-in for APIM key rotation
  }

  # Tenant user management (applies across environments)
  user_management = {
    seed_members = {
      admin = [
        "tim.csaky@gov.bc.ca",
        "shabari.kunnumel@gov.bc.ca",
        "jatinder.singh@gov.bc.ca",
        "jeff.card@gov.bc.ca",
        "abin.1.antony@gov.bc.ca",
        "andrew.schwenker@gov.bc.ca"
      ]
    }
  }
}
