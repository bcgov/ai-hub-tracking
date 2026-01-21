# =============================================================================
# SHARED CONFIGURATION - PROD ENVIRONMENT
# =============================================================================
# Production environment - maximum security and reliability settings.
# All public access is disabled; HA and backup features are enabled.
# =============================================================================

shared_config = {
  # ---------------------------------------------------------------------------
  # AI Foundry Hub Settings
  # ---------------------------------------------------------------------------
  ai_foundry = {
    name_suffix = "aihub"
    sku         = "Basic" # Upgrade to Standard for production workloads

    # SECURITY: All public access disabled in production
    public_network_access_enabled = false
    local_auth_enabled            = false

    # Cross-region deployment: Canada East for GPT-4o availability
    # The AI Foundry Hub will be in Canada East while PEs remain in Canada Central
    ai_location = "Canada East"
  }

  # ---------------------------------------------------------------------------
  # Log Analytics Workspace
  # ---------------------------------------------------------------------------
  log_analytics = {
    enabled        = true
    retention_days = 90 # COMPLIANCE: 90 days for audit requirements
    sku            = "PerGB2018"
  }

  # ---------------------------------------------------------------------------
  # Private Endpoint DNS Wait Settings
  # ---------------------------------------------------------------------------
  private_endpoint_dns_wait = {
    timeout       = "15m" # Longer timeout for prod reliability
    poll_interval = "10s"
  }

  # ---------------------------------------------------------------------------
  # API Management (APIM)
  # ---------------------------------------------------------------------------
  apim = {
    enabled  = true
    sku_name = "PremiumV2_1"

    publisher_name  = "AI Hub Production"
    publisher_email = "ai-hub-prod@example.com"

    # VNet injection for Premium v2 (enhanced security)
    vnet_injection_enabled = false
    subnet_name            = "apim-subnet"
    subnet_prefix_length   = 27

    private_dns_zone_ids = []
  }

  # ---------------------------------------------------------------------------
  # Application Gateway (WAF)
  # ---------------------------------------------------------------------------
  app_gateway = {
    enabled = true

    sku_name = "WAF_v2"
    sku_tier = "WAF_v2"

    # RELIABILITY: Autoscale with minimum 2 instances for HA
    autoscale = {
      min_capacity = 2
      max_capacity = 10
    }

    # SECURITY: WAF in Prevention mode
    waf_enabled = true
    waf_mode    = "Prevention"

    subnet_name          = "appgw-subnet"
    subnet_prefix_length = 27

    frontend_hostname = "api.example.com"

    # SSL certificates (configure with your Key Vault)
    # ssl_certificates = {
    #   primary = {
    #     name                = "api-prod-cert"
    #     key_vault_secret_id = "https://prod-kv.vault.azure.net/secrets/api-cert"
    #   }
    # }

    # key_vault_id = "/subscriptions/.../resourceGroups/.../providers/Microsoft.KeyVault/vaults/prod-kv"
  }

  # ---------------------------------------------------------------------------
  # Container Registry (ACR)
  # ---------------------------------------------------------------------------
  container_registry = {
    enabled = true
    sku     = "Premium" # Premium required for private endpoints

    # SECURITY: No public access in production
    public_network_access_enabled = false

    # SECURITY: Enable content trust for signed images
    enable_trust_policy = true
  }

  # ---------------------------------------------------------------------------
  # Container App Environment
  # ---------------------------------------------------------------------------
  container_app_environment = {
    enabled = true

    # RELIABILITY: Enable zone redundancy in production
    # NOTE: Requires /23 subnet and increases cost
    zone_redundancy_enabled = false # Enable when /23 subnet available

    # Dedicated workload profiles for production workloads
    # workload_profiles = {
    #   "dedicated-d4" = {
    #     workload_profile_type = "D4"
    #     minimum_count         = 2
    #     maximum_count         = 10
    #   }
    # }
  }

  # ---------------------------------------------------------------------------
  # App Configuration
  # ---------------------------------------------------------------------------
  app_configuration = {
    enabled = true
    sku     = "standard"

    # SECURITY: No public access in production
    public_network_access = "Disabled"
  }
}
