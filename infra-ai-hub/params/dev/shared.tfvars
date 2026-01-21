# =============================================================================
# SHARED CONFIGURATION - DEV ENVIRONMENT
# =============================================================================
# This file contains shared infrastructure settings for the dev environment.
# All values in this file apply to resources shared across tenants.
# =============================================================================

shared_config = {
  # ---------------------------------------------------------------------------
  # AI Foundry Hub Settings
  # ---------------------------------------------------------------------------
  # The AI Foundry Hub is the central AI/ML workspace that tenants connect to.
  # It provides shared capabilities like model hosting and experiment tracking.
  ai_foundry = {
    name_suffix = "aihub" # Results in: {app_name}-{env}-aihub
    sku         = "Basic" # Options: Basic, Standard

    # Public access should be disabled in prod; enabled in dev for debugging
    public_network_access_enabled = false

    # Local auth allows key-based access; disable in prod for security
    local_auth_enabled = false

    # Cross-region deployment: Set to "Canada East" for model availability
    # Leave null to deploy in the same region as the VNet (Canada Central)
    ai_location = null
  }

  # ---------------------------------------------------------------------------
  # Log Analytics Workspace
  # ---------------------------------------------------------------------------
  # Centralized logging for all resources. Required for diagnostics.
  log_analytics = {
    enabled        = true
    retention_days = 30 # Dev: 30 days is sufficient
    sku            = "PerGB2018"
  }

  # ---------------------------------------------------------------------------
  # Private Endpoint DNS Wait Settings
  # ---------------------------------------------------------------------------
  # In Azure Landing Zones, private DNS zones are policy-managed.
  # These settings control how long to wait for DNS propagation.
  private_endpoint_dns_wait = {
    timeout       = "10m" # Maximum wait time
    poll_interval = "10s" # How often to check
  }

  # ---------------------------------------------------------------------------
  # API Management (APIM)
  # ---------------------------------------------------------------------------
  # Shared API gateway for all tenant APIs. Uses stv2 with private endpoints.
  apim = {
    enabled = true

    # SKU Options:
    # - StandardV2: Cost-effective, private endpoint support
    # - PremiumV2: VNet injection, multi-region, higher scale
    sku_name = "StandardV2"

    # Publisher info (required by APIM)
    publisher_name  = "AI Hub Dev"
    publisher_email = "ai-hub-dev@example.com"

    # VNet injection (Premium v2 only) - leave false for Standard_v2
    vnet_injection_enabled = false
    subnet_name            = "apim-subnet" # Only used if vnet_injection_enabled
    subnet_prefix_length   = 27            # /27 = 32 IPs

    # Private DNS zone IDs for private endpoints
    # Leave empty to let Azure Policy manage DNS (Landing Zone pattern)
    private_dns_zone_ids = []
  }

  # ---------------------------------------------------------------------------
  # Application Gateway (WAF)
  # ---------------------------------------------------------------------------
  # Optional WAF in front of APIM for additional security and SSL termination.
  app_gateway = {
    enabled = false # Disabled in dev to reduce cost

    # WAF_v2 provides Web Application Firewall capabilities
    sku_name = "WAF_v2"
    sku_tier = "WAF_v2"
    capacity = 1 # Fixed capacity (no autoscale in dev)

    # Autoscale (optional) - set to null to use fixed capacity
    # autoscale = {
    #   min_capacity = 1
    #   max_capacity = 3
    # }

    waf_enabled = true
    waf_mode    = "Detection" # Detection only in dev; Prevention in prod

    # Subnet settings
    subnet_name          = "appgw-subnet"
    subnet_prefix_length = 27 # /27 = 32 IPs

    # Frontend hostname (must match SSL certificate)
    frontend_hostname = "api-dev.example.com"

    # SSL certificates from Key Vault
    # ssl_certificates = {
    #   primary = {
    #     name                = "api-cert"
    #     key_vault_secret_id = "https://mykv.vault.azure.net/secrets/api-cert"
    #   }
    # }

    # Key Vault for managed identity access to SSL certs
    # key_vault_id = "/subscriptions/.../resourceGroups/.../providers/Microsoft.KeyVault/vaults/..."
  }

  # ---------------------------------------------------------------------------
  # Container Registry (ACR)
  # ---------------------------------------------------------------------------
  # Shared container registry for storing container images.
  container_registry = {
    enabled = true
    sku     = "Premium" # Premium required for private endpoints

    # Public access for dev debugging; disable in prod
    public_network_access_enabled = false

    # Enable trust policy for signed images (requires Premium)
    enable_trust_policy = false
  }

  # ---------------------------------------------------------------------------
  # Container App Environment
  # ---------------------------------------------------------------------------
  # Serverless container hosting environment.
  container_app_environment = {
    enabled = true

    # Zone redundancy requires /23 subnet and increases cost
    # Disable for dev to save costs
    zone_redundancy_enabled = false

    # Workload profiles (optional) - uses consumption-only if empty
    # workload_profiles = {
    #   "dedicated-d4" = {
    #     workload_profile_type  = "D4"
    #     minimum_count          = 1
    #     maximum_count          = 3
    #   }
    # }
  }

  # ---------------------------------------------------------------------------
  # App Configuration
  # ---------------------------------------------------------------------------
  # Centralized configuration store for feature flags and settings.
  app_configuration = {
    enabled = true
    sku     = "standard" # Options: free, standard

    # Public access for dev debugging; disable in prod
    public_network_access = "Disabled"
  }
}
