# =============================================================================
# TENANT: AI Hub Admin
# =============================================================================
# Test environment configuration for AI Hub admin.
# =============================================================================

tenant = {
  tenant_name  = "ai-hub-admin"
  display_name = "AI Hub Admin"
  enabled      = true

  # PE subnet assignment — sticky, do not change after first deploy (destroys/recreates all PEs)
  # Valid keys: privateendpoints-subnet, privateendpoints-subnet-1, privateendpoints-subnet-2, ...
  pe_subnet_key = "privateendpoints-subnet"

  tags = {
    ministry    = "CITZ"
    environment = "test"
    project     = "ai-hub-admin"
    department  = "CSBC - AI Hub"
    info        = "This tenant is for testing and administrative purposes, solely used by AI Hub team only."
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
  # IMPORTANT: This block MUST be present in every tenant (even if disabled) to keep
  # the map(any) type consistent across all tenant entries.
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
    # OpenAI quota limits: gpt-4.1=30k, gpt-4.1-mini=150k, gpt-4.1-nano=150k,
    #   gpt-4o=30k, gpt-4o-mini=150k, gpt-5-mini=10k, gpt-5-nano=150k,
    #   gpt-5.1-chat=5k, gpt-5.1-codex-mini=10k, o1=5k, o3-mini=5k,
    #   o4-mini=10k, text-embedding-ada-002=10k, text-embedding-3-large=10k,
    #   text-embedding-3-small=10k
    # Cohere quota limits: cohere-command-a=1k, Cohere-command-r*=not tracked,
    #   Cohere-embed-v3-*=not tracked, Cohere-rerank-v4.0-pro=3k, Cohere-rerank-v4.0-fast=3k
    # -------------------------------------------------------------------------
    # Content Filters (RAI Policies)
    # -------------------------------------------------------------------------
    # Each deployment MUST have the content_filter key (null or object) so that
    # Terraform's map(any) can infer a uniform type across all tenants.
    #
    #   content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
    #     -> Uses Azure's built-in Microsoft.DefaultV2 policy. No custom resource
    #        is created.
    #
    #   content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [...] }
    #     -> Creates a tenant-scoped raiPolicy resource on the AI Foundry Hub and
    #        attaches it to this deployment.
    #
    # Valid filter names     : hate | violence | sexual | selfharm
    # Valid severity_threshold: Low | Medium | High
    # Valid source           : Prompt | Completion
    # -------------------------------------------------------------------------
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
      {
        name           = "gpt-4o-mini"
        model_name     = "gpt-4o-mini"
        model_version  = "2024-07-18"
        scale_type     = "GlobalStandard"
        capacity       = 1500 # 1% of 150,000
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
        name          = "gpt-5.1-chat"
        model_name    = "gpt-5.1-chat"
        model_version = "2025-11-13"
        scale_type    = "GlobalStandard"
        capacity      = 50 # 1% of 5,000
        # Custom RAI policy: block harmful content at High threshold on all categories.
        content_filter = {
          base_policy_name = "Microsoft.DefaultV2"
          filters = [
            { name = "hate", severity_threshold = "High", source = "Prompt", blocking = true, enabled = true },
            { name = "hate", severity_threshold = "High", source = "Completion", blocking = true, enabled = true },
            { name = "violence", severity_threshold = "High", source = "Prompt", blocking = true, enabled = true },
            { name = "violence", severity_threshold = "High", source = "Completion", blocking = true, enabled = true },
            { name = "sexual", severity_threshold = "High", source = "Prompt", blocking = true, enabled = true },
            { name = "sexual", severity_threshold = "High", source = "Completion", blocking = true, enabled = true },
            { name = "selfharm", severity_threshold = "High", source = "Prompt", blocking = true, enabled = true },
            { name = "selfharm", severity_threshold = "High", source = "Completion", blocking = true, enabled = true },
          ]
        }
      },
      {
        name           = "gpt-5.1-codex-mini"
        model_name     = "gpt-5.1-codex-mini"
        model_version  = "2025-11-13"
        scale_type     = "GlobalStandard"
        capacity       = 100 # 1% of 10,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      # Reasoning Models
      {
        name           = "o1"
        model_name     = "o1"
        model_version  = "2024-12-17"
        scale_type     = "GlobalStandard"
        capacity       = 50 # 1% of 5,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "o3-mini"
        model_name     = "o3-mini"
        model_version  = "2025-01-31"
        scale_type     = "GlobalStandard"
        capacity       = 50 # 1% of 5,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "o4-mini"
        model_name     = "o4-mini"
        model_version  = "2025-04-16"
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
      # Cohere Models (format auto-detected from model name in foundry stack)
      # Excluded models:
      #   Cohere-command-r, Cohere-command-r-plus       — ServiceModelDeprecated (since 06/30/2025)
      #   Cohere-command-r-08-2024, Cohere-command-r-plus-08-2024,
      #   Cohere-embed-v3-english, Cohere-embed-v3-multilingual — not in BC Gov Private Marketplace
      # Command Series
      {
        name           = "cohere-command-a"
        model_name     = "cohere-command-a"
        model_version  = "1"
        scale_type     = "GlobalStandard"
        capacity       = 10 # 1% of 1,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      # Rerank Series
      {
        name           = "Cohere-rerank-v4.0-pro"
        model_name     = "Cohere-rerank-v4.0-pro"
        model_version  = "1"
        scale_type     = "GlobalStandard"
        capacity       = 30 # 1% of 3,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "Cohere-rerank-v4.0-fast"
        model_name     = "Cohere-rerank-v4.0-fast"
        model_version  = "1"
        scale_type     = "GlobalStandard"
        capacity       = 30 # 1% of 3,000
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },

      # Mistral Models (format auto-detected as "MistralAI" via model_format_prefixes in foundry stack)
      # MaaS serverless (pay-per-token) — quota is not tracked; capacity = 10 → 10k TPM APIM rate limit.

      # Chat / Multimodal
      {
        name           = "Mistral-Large-3"
        model_name     = "Mistral-Large-3"
        model_version  = "1"
        scale_type     = "GlobalStandard"
        capacity       = 10 # quota not tracked
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "mistral-medium-2505"
        model_name     = "mistral-medium-2505"
        model_version  = "1"
        scale_type     = "GlobalStandard"
        capacity       = 10 # quota not tracked
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "mistral-small-2503"
        model_name     = "mistral-small-2503"
        model_version  = "1"
        scale_type     = "GlobalStandard"
        capacity       = 10 # quota not tracked
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },

      # Code
      {
        name           = "Codestral-2501"
        model_name     = "Codestral-2501"
        model_version  = "2"
        scale_type     = "GlobalStandard"
        capacity       = 10 # quota not tracked
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },

      # OCR / Document AI
      {
        name           = "mistral-ocr-2503"
        model_name     = "mistral-ocr-2503"
        model_version  = "1"
        scale_type     = "GlobalStandard"
        capacity       = 10 # quota not tracked
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "mistral-document-ai-2505"
        model_name     = "mistral-document-ai-2505"
        model_version  = "1"
        scale_type     = "GlobalStandard"
        capacity       = 10 # quota not tracked
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
      {
        name           = "mistral-document-ai-2512"
        model_name     = "mistral-document-ai-2512"
        model_version  = "1"
        scale_type     = "GlobalStandard"
        capacity       = 10 # quota not tracked
        content_filter = { base_policy_name = "Microsoft.DefaultV2", filters = [] }
      },
    ]
  }

  # APIM Authentication Configuration
  # Controls how clients authenticate to this tenant's APIs
  # Options:
  #   mode = "subscription_key" (default) - Simple API key in header
  #   mode = "oauth2" - Azure AD OAuth2 with JWT tokens
  apim_auth = {
    mode                 = "subscription_key" # Start with subscription key, switch to oauth2 later
    key_rotation_enabled = true               # Per-tenant opt-in for APIM key rotation
  }

  # Tenant user management (applies across environments)
  user_management = {}

  # APIM Policies Configuration
  # Consolidates all APIM policy settings for this tenant
  apim_policies = {
    # IMPORTANT: tokens_per_minute MUST be set when rate_limiting is enabled.
    # Omitting it causes type mismatch with other tenants (map(any) requires identical shapes).
    rate_limiting = {
      enabled           = true
      tokens_per_minute = 1000
    }
    pii_redaction = {
      enabled     = false # Redact emails, phone numbers, addresses, etc.
      fail_closed = false # Fail-open: allow requests through if PII service fails
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
}
