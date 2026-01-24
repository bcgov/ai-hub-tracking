# =============================================================================
# TENANT: WLRS Water Form Assistant - TEST ENVIRONMENT
# =============================================================================
# Test environment configuration for WLRS Water Form Assistant.
# =============================================================================

tenant = {
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
    diagnostics = {
      log_groups        = ["allLogs"]
      log_categories    = []
      metric_categories = ["AllMetrics"]
    }
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
      # GPT-5 Series (No registration required)
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
      # GPT-5.1 Series (No registration required)
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

  # APIM Authentication Configuration
  # Controls how clients authenticate to this tenant's APIs
  # Options:
  #   mode = "subscription_key" (default) - Simple API key in header
  #   mode = "oauth2" - Azure AD OAuth2 with JWT tokens
  #   store_in_keyvault = false (default) - Do NOT store in KV (avoids auto-rotation issues)
  apim_auth = {
    mode              = "subscription_key" # Start with subscription key, switch to oauth2 later
    store_in_keyvault = false              # Keep false if KV has auto-rotation policies!
  }

  # Content Safety Configuration
  # Controls PII redaction - enabled by default
  content_safety = {
    pii_redaction_enabled = true # Redact emails, phone numbers, addresses, etc.
  }

  # Per-tenant APIM Diagnostics - logs go to tenant's own LAW
  apim_diagnostics = {
    sampling_percentage = 100
    verbosity           = "information"
  }
}
