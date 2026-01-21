# =============================================================================
# SHARED CONFIGURATION - TEST ENVIRONMENT
# =============================================================================
# Test environment configuration - mirrors dev with adjustments for testing.
# Used for integration testing and pre-production validation.
# =============================================================================

shared_config = {
  # ---------------------------------------------------------------------------
  # AI Foundry Hub Settings
  # ---------------------------------------------------------------------------
  ai_foundry = {
    name_suffix = "foundry"
    sku         = "S0" # Only valid SKU for AIServices kind

    # Disabled in test to simulate prod-like environment
    public_network_access_enabled = false
    local_auth_enabled            = false

    # Cross-region deployment: Canada East for model availability
    # gpt-4o-mini and text-embedding-ada-002 require Canada East with Standard deployment
    ai_location = "Canada East"
    # Permanently purge AI Foundry account on destroy to avoid lingering resources
    purge_on_destroy = true
  }

  # ---------------------------------------------------------------------------
  # Log Analytics Workspace
  # ---------------------------------------------------------------------------
  log_analytics = {
    enabled        = true
    retention_days = 30
    sku            = "PerGB2018"
  }

  # ---------------------------------------------------------------------------
  # Private Endpoint DNS Wait Settings
  # ---------------------------------------------------------------------------
  private_endpoint_dns_wait = {
    timeout       = "15m"
    poll_interval = "10s"
  }

  # ---------------------------------------------------------------------------
  # API Management (APIM)
  # ---------------------------------------------------------------------------
  apim = {
    enabled  = true
    sku_name = "StandardV2_1"

    publisher_name  = "AI Hub Test"
    publisher_email = "ai-hub-test@example.com"

    vnet_injection_enabled = false
    subnet_name            = "apim-subnet"
    subnet_prefix_length   = 27

    private_dns_zone_ids = []
  }

  # ---------------------------------------------------------------------------
  # Application Gateway (WAF)
  # ---------------------------------------------------------------------------
  app_gateway = {
    enabled = false # Enabled in test to validate WAF rules

    sku_name = "WAF_v2"
    sku_tier = "WAF_v2"
    capacity = 1

    # Autoscale for test environment
    autoscale = {
      min_capacity = 1
      max_capacity = 2
    }

    waf_enabled = true
    waf_mode    = "Prevention" # Test WAF in Prevention mode

    subnet_name          = "appgw-subnet"
    subnet_prefix_length = 27

    frontend_hostname = "api-test.example.com"
  }

  # ---------------------------------------------------------------------------
  # Container Registry (ACR)
  # ---------------------------------------------------------------------------
  container_registry = {
    enabled                       = true
    sku                           = "Basic"
    public_network_access_enabled = true
    enable_trust_policy           = false
  }

  # ---------------------------------------------------------------------------
  # Container App Environment
  # ---------------------------------------------------------------------------
  container_app_environment = {
    enabled                 = true
    zone_redundancy_enabled = false # Keep disabled for cost in test
  }

  # ---------------------------------------------------------------------------
  # App Configuration
  # ---------------------------------------------------------------------------
  app_configuration = {
    enabled               = true
    sku                   = "standard"
    public_network_access = "Disabled"
  }
}
