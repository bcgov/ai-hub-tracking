# =============================================================================
# TENANT: SDPR Invoice Automation - TEST ENVIRONMENT
# =============================================================================
# Test environment configuration for SDPR Invoice Automation.
# =============================================================================

tenant = {
  tenant_name  = "sdpr-invoice-automation"
  display_name = "SDPR Invoice Automation"
  enabled      = true

  tags = {
    ministry    = "SDPR"
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

  cosmos_db = {
    enabled = false
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
    model_deployments = [
      # GPT-4.1 Series
      {
        name          = "gpt-4.1-mini"
        model_name    = "gpt-4.1-mini"
        model_version = "2025-04-14"
        scale_type    = "GlobalStandard"
        capacity      = 10
      },
      # GPT-5 Series
      {
        name          = "gpt-5-mini"
        model_name    = "gpt-5-mini"
        model_version = "2025-08-07"
        scale_type    = "GlobalStandard"
        capacity      = 10
      },
      {
        name          = "gpt-5-nano"
        model_name    = "gpt-5-nano"
        model_version = "2025-08-07"
        scale_type    = "GlobalStandard"
        capacity      = 10
      },
      # GPT-5.1 Series
      {
        name          = "gpt-5.1-chat"
        model_name    = "gpt-5.1-chat"
        model_version = "2025-11-13"
        scale_type    = "GlobalStandard"
        capacity      = 10
      },
      {
        name          = "gpt-5.1-codex-mini"
        model_name    = "gpt-5.1-codex-mini"
        model_version = "2025-11-13"
        scale_type    = "GlobalStandard"
        capacity      = 10
      },
      # Embeddings
      {
        name          = "text-embedding-ada-002"
        model_name    = "text-embedding-ada-002"
        model_version = "2"
        scale_type    = "GlobalStandard"
        capacity      = 10
      }
    ]
  }

  # APIM Authentication
  apim_auth = {
    mode              = "subscription_key"
    store_in_keyvault = false
  }

  # APIM Policies Configuration
  # Consolidates all APIM policy settings for this tenant
  apim_policies = {
    rate_limiting = {
      enabled           = true
      tokens_per_minute = 10000
    }
    pii_redaction = {
      enabled = false # Disabled - invoices need raw email/phone data
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
