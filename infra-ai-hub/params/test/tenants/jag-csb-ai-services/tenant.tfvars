# =============================================================================
# TENANT: JAG CSB AI Services - TEST ENVIRONMENT
# =============================================================================
# TEST environment configuration for JAG CSB AI Services.
# Service/model baseline mirrors common-gazette-intelligence-service, with
# Azure AI Search disabled and all three gpt-5.6 variants added.
# =============================================================================

tenant = {
  tenant_name  = "jag-csb-ai-services"
  display_name = "JAG CSB AI Services"
  enabled      = true

  # PE subnet assignment - sticky, do not change after first deploy (destroys/recreates all PEs)
  # Valid keys: privateendpoints-subnet, privateendpoints-subnet-1, privateendpoints-subnet-2, ...
  pe_subnet_key = "privateendpoints-subnet"

  tags = {
    ministry    = "JAG"
    environment = "test"
    department  = "Court Services Branch"
  }

  key_vault = {
    enabled                    = true
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

  openai = {
    enabled = true
    sku     = "S0"
    diagnostics = {
      log_groups        = ["allLogs"]
      log_categories    = []
      metric_categories = ["AllMetrics"]
    }
    # content_filter key MUST be present on every deployment across ALL tenants
    # so Terraform's map(any) can infer a uniform element type. Microsoft.DefaultV2
    # with empty filters uses Azure's built-in policy (no custom RAI resource created).
    model_deployments = [
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
        name           = "gpt-5"
        model_name     = "gpt-5"
        model_version  = "2025-08-07"
        scale_type     = "GlobalStandard"
        capacity       = 300 # 1% of 30,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "gpt-5.1"
        model_name     = "gpt-5.1"
        model_version  = "2025-11-13"
        scale_type     = "GlobalStandard"
        capacity       = 300 # 1% of 30,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "gpt-5.4"
        model_name     = "gpt-5.4"
        model_version  = "2026-03-05"
        scale_type     = "GlobalStandard"
        capacity       = 100 # 1% of 10,000 (verified Canada East quota)
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "gpt-5.6-luna"
        model_name     = "gpt-5.6-luna"
        model_version  = "2026-07-09"
        scale_type     = "GlobalStandard"
        capacity       = 100 # 1% of 10,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "gpt-5.6-sol"
        model_name     = "gpt-5.6-sol"
        model_version  = "2026-07-09"
        scale_type     = "GlobalStandard"
        capacity       = 100 # 1% of 10,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "gpt-5.6-terra"
        model_name     = "gpt-5.6-terra"
        model_version  = "2026-07-09"
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

  user_management = {
    seed_members = {
      admin = [
        "kyron.winkelmeyer@gov.bc.ca",
        "richard.fremmerlid@gov.bc.ca",
        "kevin.conn@gov.bc.ca"
      ]
      write = [
        "kyron.winkelmeyer@gov.bc.ca",
        "richard.fremmerlid@gov.bc.ca",
        "kevin.conn@gov.bc.ca",
        "patricia.m.white@gov.bc.ca"
      ]
      read = [
        "kyron.winkelmeyer@gov.bc.ca",
        "richard.fremmerlid@gov.bc.ca",
        "kevin.conn@gov.bc.ca",
        "patricia.m.white@gov.bc.ca"
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
    pii_redaction = {
      enabled             = true
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
