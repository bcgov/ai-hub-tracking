# =============================================================================
# CORE VARIABLES
# =============================================================================
variable "app_env" {
  description = "Application environment (dev, test, prod) - used to load params from params/{app_env}/"
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "test", "prod"], var.app_env)
    error_message = "app_env must be one of: dev, test, prod"
  }
}

variable "app_name" {
  description = "Name of the application (used as prefix for resource names)"
  type        = string
  nullable    = false
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "Canada Central"
}

variable "resource_group_name" {
  description = "Resource group name for the AI Hub infrastructure"
  type        = string
  nullable    = false
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# AUTHENTICATION VARIABLES
# =============================================================================
variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure tenant ID"
  type        = string
  sensitive   = true
}

variable "client_id" {
  description = "Azure client ID for the service principal (OIDC)"
  type        = string
  sensitive   = true
}

variable "use_oidc" {
  description = "Use OIDC for authentication"
  type        = bool
  default     = true
}

# =============================================================================
# NETWORKING VARIABLES
# =============================================================================
variable "vnet_name" {
  description = "Name of the existing virtual network (provided by Landing Zone)"
  type        = string
  nullable    = false
}

variable "vnet_resource_group_name" {
  description = "Resource group name where the virtual network exists"
  type        = string
  nullable    = false
}

variable "target_vnet_address_spaces" {
  description = "Address spaces of the target environment VNet. The first entry is used to derive the private endpoint subnet."
  type        = list(string)

  validation {
    condition     = length(var.target_vnet_address_spaces) > 0
    error_message = "target_vnet_address_spaces must contain at least one CIDR."
  }
}

variable "source_vnet_address_space" {
  description = "Address space of the source environment VNet (for NSG allow rules, e.g., tools VNet CIDR)"
  type        = string
}

variable "private_endpoint_subnet_name" {
  description = "Name of the private endpoint subnet to create in the target VNet"
  type        = string
  default     = "privateendpoints-subnet"
}

# =============================================================================
# CONFIGURATION VARIABLES (loaded from params/{env}/ via -var-file)
# =============================================================================
# These complex variables are populated from params/{env}/shared.tfvars and
# params/{env}/tenants.tfvars files passed via -var-file to terraform commands.

variable "shared_config" {
  description = "Shared infrastructure configuration loaded from params/{env}/shared.tfvars"
  type = object({
    # AI Foundry Hub settings
    ai_foundry = object({
      name_suffix                   = string
      sku                           = string
      public_network_access_enabled = bool
      local_auth_enabled            = bool
      ai_location                   = optional(string) # Cross-region deployment
      purge_on_destroy              = optional(bool, false)
    })

    # Log Analytics settings
    log_analytics = object({
      enabled        = bool
      retention_days = number
      sku            = string
    })

    # DNS wait settings for Landing Zone policy-managed DNS
    private_endpoint_dns_wait = object({
      timeout       = string
      poll_interval = string
    })

    # API Management settings
    apim = object({
      enabled                       = bool
      sku_name                      = optional(string, "StandardV2_1")
      publisher_name                = optional(string, "AI Hub")
      publisher_email               = optional(string, "admin@example.com")
      public_network_access_enabled = optional(bool, true)
      vnet_injection_enabled        = optional(bool, false)
      subnet_name                   = optional(string, "apim-subnet")
      subnet_prefix_length          = optional(number, 27)
      private_dns_zone_ids          = optional(list(string), [])
    })

    # DNS Zone settings (vanity domain + static PIP for App Gateway)
    dns_zone = optional(object({
      enabled             = bool
      zone_name           = string
      resource_group_name = string
      a_record_ttl        = optional(number, 3600)
    }), { enabled = false, zone_name = "", resource_group_name = "" })

    # Application Gateway settings
    app_gateway = object({
      enabled  = bool
      sku_name = optional(string, "WAF_v2")
      sku_tier = optional(string, "WAF_v2")
      capacity = optional(number, 2)
      autoscale = optional(object({
        min_capacity = number
        max_capacity = number
      }))
      waf_enabled        = optional(bool, true)
      waf_mode           = optional(string, "Prevention")
      waf_policy_enabled = optional(bool, true)
      # WAF body inspection settings (CRS 3.2+)
      request_body_check               = optional(bool, true)
      request_body_enforcement         = optional(bool, true)  # false = allow oversized requests through
      request_body_inspect_limit_in_kb = optional(number, 128) # WAF inspects up to this depth
      max_request_body_size_kb         = optional(number, 128) # Hard limit when enforcement=true
      file_upload_limit_mb             = optional(number, 100)
      subnet_name                      = optional(string, "appgw-subnet")
      subnet_prefix_length             = optional(number, 27)
      frontend_hostname                = optional(string, "api.example.com")
      ssl_certificate_name             = optional(string)
      ssl_certificates = optional(map(object({
        name                = string
        key_vault_secret_id = optional(string)
        data                = optional(string)
        password            = optional(string)
      })), {})
      key_vault_id = optional(string)
    })

    # Container Registry settings
    container_registry = optional(object({
      enabled                       = bool
      sku                           = optional(string, "Premium")
      public_network_access_enabled = optional(bool, false)
      enable_trust_policy           = optional(bool, false)
    }), { enabled = false })

    # Container App Environment settings
    container_app_environment = optional(object({
      enabled                 = bool
      zone_redundancy_enabled = optional(bool, false)
      workload_profiles = optional(map(object({
        workload_profile_type = string
        minimum_count         = number
        maximum_count         = number
      })), {})
    }), { enabled = false })

    # App Configuration settings
    app_configuration = optional(object({
      enabled               = bool
      sku                   = optional(string, "standard")
      public_network_access = optional(string, "Disabled")
    }), { enabled = false })

    # Language Service settings (for PII detection via Azure AI Language)
    language_service = optional(object({
      enabled                       = bool
      sku                           = optional(string, "S")
      public_network_access_enabled = optional(bool, false)
    }), { enabled = false })
  })
}

variable "tenants" {
  description = <<-EOT
    Tenant configurations. Individual tenant configs are stored in 
    params/{env}/tenants/{tenant-name}/tenant.tfvars and merged by the deploy script.
  EOT
  type = map(object({
    tenant_name         = string
    display_name        = string
    enabled             = bool
    resource_group_name = optional(string)
    tags                = optional(map(string), {})

    # Tenant Log Analytics configuration (optional)
    log_analytics = optional(object({
      enabled        = bool
      retention_days = optional(number, 30)
      sku            = optional(string, "PerGB2018")
    }), { enabled = false })

    # Key Vault configuration
    key_vault = object({
      enabled                    = bool
      sku                        = optional(string, "standard")
      purge_protection_enabled   = optional(bool, true)
      soft_delete_retention_days = optional(number, 90)
      diagnostics = optional(object({
        log_groups        = optional(list(string), [])
        log_categories    = optional(list(string), [])
        metric_categories = optional(list(string), [])
      }))
    })

    # Storage Account configuration
    storage_account = object({
      enabled                  = bool
      account_tier             = optional(string, "Standard")
      account_replication_type = optional(string, "LRS")
      account_kind             = optional(string, "StorageV2")
      access_tier              = optional(string, "Hot")
      diagnostics = optional(object({
        log_groups        = optional(list(string), [])
        log_categories    = optional(list(string), [])
        metric_categories = optional(list(string), [])
      }))
    })

    # AI Search configuration
    ai_search = object({
      enabled            = bool
      sku                = optional(string, "basic")
      replica_count      = optional(number, 1)
      partition_count    = optional(number, 1)
      semantic_search    = optional(string, "disabled")
      local_auth_enabled = optional(bool, true)
      diagnostics = optional(object({
        log_groups        = optional(list(string), [])
        log_categories    = optional(list(string), [])
        metric_categories = optional(list(string), [])
      }))
    })

    # Cosmos DB configuration
    cosmos_db = object({
      enabled                      = bool
      offer_type                   = optional(string, "Standard")
      kind                         = optional(string, "GlobalDocumentDB")
      consistency_level            = optional(string, "Session")
      max_interval_in_seconds      = optional(number, 5)
      max_staleness_prefix         = optional(number, 100)
      geo_redundant_backup_enabled = optional(bool, false)
      automatic_failover_enabled   = optional(bool, false)
      total_throughput_limit       = optional(number, 1000)
      diagnostics = optional(object({
        log_groups        = optional(list(string), [])
        log_categories    = optional(list(string), [])
        metric_categories = optional(list(string), [])
      }))
    })

    # Document Intelligence configuration
    document_intelligence = object({
      enabled = bool
      sku     = optional(string, "S0")
      kind    = optional(string, "FormRecognizer")
      diagnostics = optional(object({
        log_groups        = optional(list(string), [])
        log_categories    = optional(list(string), [])
        metric_categories = optional(list(string), [])
      }))
    })

    # Speech Services configuration
    speech_services = optional(object({
      enabled = bool
      sku     = optional(string, "S0")
      diagnostics = optional(object({
        log_groups        = optional(list(string), [])
        log_categories    = optional(list(string), [])
        metric_categories = optional(list(string), [])
      }))
    }), { enabled = false })

    # OpenAI configuration
    openai = object({
      enabled = bool
      sku     = optional(string, "S0")
      model_deployments = optional(list(object({
        name          = string
        model_name    = string
        model_version = string
        scale_type    = optional(string, "Standard")
        capacity      = optional(number, 10)
      })), [])
      diagnostics = optional(object({
        log_groups        = optional(list(string), [])
        log_categories    = optional(list(string), [])
        metric_categories = optional(list(string), [])
      }))
    })

    # APIM Authentication configuration
    # Controls how clients authenticate to this tenant's APIs
    apim_auth = optional(object({
      # Auth mode: "subscription_key" (simple API key) or "oauth2" (Azure AD)
      mode = optional(string, "subscription_key")
      # Store credentials in Key Vault (default: false)
      # WARNING: Set to false if Key Vault has auto-rotation policies!
      # Auto-rotated secrets would break APIM keys since the new value
      # won't match the actual APIM subscription key.
      store_in_keyvault = optional(bool, false)
      # OAuth2 settings (only used when mode = "oauth2")
      oauth2 = optional(object({
        # If existing_app_id is set, use that instead of creating a new one
        existing_app_id = optional(string)
        # Token expiration in hours (for created secrets)
        secret_expiry_hours = optional(number, 8760) # 1 year
      }), {})
    }), { mode = "subscription_key", store_in_keyvault = false })

    # ==========================================================================
    # APIM POLICIES CONFIGURATION
    # ==========================================================================
    # Consolidated configuration for all APIM policy features.
    # Each feature can be enabled/disabled per tenant.
    # Policy XML is auto-generated based on these settings.
    # ==========================================================================
    apim_policies = optional(object({
      # ---- Rate Limiting ----
      # Token-based rate limiting for LLM endpoints
      rate_limiting = optional(object({
        enabled           = optional(bool, true)
        tokens_per_minute = optional(number, 10000)
      }), { enabled = true, tokens_per_minute = 10000 })

      # ---- Content Safety ----
      # PII redaction using Azure Language Service
      pii_redaction = optional(object({
        enabled              = optional(bool, true)
        confidence_threshold = optional(number, 0.8)
        entity_exclusions    = optional(string, "") # Deprecated: use excluded_categories
        detection_language   = optional(string, "en")
        # Option 2: Exclude certain PII categories from detection
        # Available categories: Person, PersonType, Location, Organization, Email, PhoneNumber,
        #                      Address, DateTime, Quantity, IPAddress, URL, SSN, CreditCardNumber, etc.
        # Example: ["Person", "PersonType", "Organization"]
        excluded_categories = optional(list(string), [])
        # Option 3: Preserve JSON structure fields (restore after PII anonymization)
        # Set to true to automatically restore common OpenAI structural values
        # like "user", "system", "assistant" that may be incorrectly detected as PII
        preserve_json_structure = optional(bool, true)
        # Custom structural values to preserve (in addition to defaults)
        # Default preserves: user, system, assistant, function, tool, developer
        structural_whitelist = optional(list(string), [])
        # Fail-closed behavior: if true, block requests when PII redaction fails
        # (Language Service unavailable, non-200 response, or invalid response body)
        # Default: false (fail-open - allows requests through with original content on error)
        fail_closed = optional(bool, false)
        }), {
        enabled                 = true
        confidence_threshold    = 0.8
        entity_exclusions       = ""
        detection_language      = "en"
        excluded_categories     = []
        preserve_json_structure = true
        structural_whitelist    = []
        fail_closed             = false
      })

      # ---- Usage Logging ----
      # OpenAI token usage logging to App Insights
      usage_logging = optional(object({
        enabled = optional(bool, true)
      }), { enabled = true })

      # ---- Streaming Metrics ----
      # Enhanced metrics for streaming responses
      streaming_metrics = optional(object({
        enabled = optional(bool, true)
      }), { enabled = true })

      # ---- Tracking Dimensions ----
      # Extract custom dimensions from headers for analytics
      tracking_dimensions = optional(object({
        enabled = optional(bool, true)
      }), { enabled = true })

      # ---- Intelligent Routing ----
      # Multi-backend load balancing and failover (future use)
      intelligent_routing = optional(object({
        enabled = optional(bool, false)
      }), { enabled = false })

      }), {
      rate_limiting       = { enabled = true, tokens_per_minute = 10000 }
      pii_redaction       = { enabled = true, confidence_threshold = 0.8, entity_exclusions = "", detection_language = "en", excluded_categories = [], preserve_json_structure = true, structural_whitelist = [], fail_closed = false }
      usage_logging       = { enabled = true }
      streaming_metrics   = { enabled = true }
      tracking_dimensions = { enabled = true }
      intelligent_routing = { enabled = false }
    })

    # Per-tenant APIM Diagnostics configuration (optional)
    # Overrides default diagnostic settings for this tenant's API
    # If tenant has log_analytics.enabled = true, logs go to tenant LAW
    # Otherwise, logs go to central Application Insights
    apim_diagnostics = optional(object({
      sampling_percentage       = optional(number, 100)
      always_log_errors         = optional(bool, true)
      log_client_ip             = optional(bool, true)
      http_correlation_protocol = optional(string, "W3C")
      verbosity                 = optional(string, "information") # error, information, verbose
      frontend_request = optional(object({
        body_bytes     = optional(number, 1024)
        headers_to_log = optional(list(string), ["X-Tenant-Id", "X-Request-ID", "Content-Type"])
      }))
      frontend_response = optional(object({
        body_bytes     = optional(number, 1024)
        headers_to_log = optional(list(string), ["x-ms-request-id", "x-ratelimit-remaining-tokens", "x-tokens-consumed"])
      }))
      backend_request = optional(object({
        body_bytes     = optional(number, 1024)
        headers_to_log = optional(list(string), ["Authorization", "api-key"])
      }))
      backend_response = optional(object({
        body_bytes     = optional(number, 1024)
        headers_to_log = optional(list(string), ["x-ms-region", "x-ratelimit-remaining-tokens"])
      }))
    }))
  }))
  default = {}
}

# =============================================================================
# DEFENDER FOR CLOUD VARIABLES
# =============================================================================
variable "defender_enabled" {
  description = "Enable Microsoft Defender for Cloud subscription pricing"
  type        = bool
  default     = false
}

variable "defender_resource_types" {
  description = <<-EOT
    Map of Defender for Cloud resource types to enable.
    Keys are resource type names, values are objects with optional subplan.
    
    Example:
      defender_resource_types = {
        Api             = { subplan = "P1" }  # P1 or P2
        StorageAccounts = {}                   # No subplan needed
        KeyVaults       = {}
      }
    
    Valid resource types: Api, AppServices, Arm, CloudPosture, ContainerRegistry,
    Containers, CosmosDbs, Dns, KeyVaults, KubernetesService,
    OpenSourceRelationalDatabases, SqlServers, SqlServerVirtualMachines,
    StorageAccounts, VirtualMachines
  EOT
  type = map(object({
    subplan = optional(string, null)
  }))
  default = {}
}
