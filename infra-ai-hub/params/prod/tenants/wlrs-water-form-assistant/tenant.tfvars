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
  }

  document_intelligence = {
    enabled = true
    sku     = "S0"
    kind    = "FormRecognizer"
  }

  openai = {
    enabled = true
    sku     = "S0"
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
