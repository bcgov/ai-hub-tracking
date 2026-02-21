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
    # gpt-4.1-mini (2025-04-14) and text-embedding-ada-002 available in Canada East with GlobalStandard deployment
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

    # Disable public network access - all inbound traffic via private endpoint only
    # App Gateway connects to APIM through PE (FQDN resolves via private DNS zone)
    public_network_access_enabled = false

    # VNet integration required for outbound connectivity to private backends
    # Backend services (OpenAI, DocInt, etc.) have public network access disabled
    vnet_injection_enabled = true
    subnet_name            = "apim-subnet"
    subnet_prefix_length   = 27

    private_dns_zone_ids = []

    # Subscription key rotation (managed by GitHub Actions workflow)
    key_rotation = {
      rotation_enabled       = false # Enable rotation in test for validation
      rotation_interval_days = 60    # Must be less than 90 days (APIM max key lifetime)
    }
  }

  # ---------------------------------------------------------------------------
  # Application Gateway (WAF)
  # ---------------------------------------------------------------------------
  app_gateway = {
    enabled = true # Enabled in test to validate WAF rules

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

    # WAF body inspection (CRS 3.2+)
    # enforcement=false lets large payloads through (Doc Intelligence SDK sends multi-MB base64 JSON)
    # WAF still inspects first 128KB for SQLi/XSS threats
    request_body_check               = true
    request_body_enforcement         = false
    request_body_inspect_limit_in_kb = 128
    max_request_body_size_kb         = 2000 # ~2MB (provider max)
    file_upload_limit_mb             = 100

    subnet_name          = "appgw-subnet"
    subnet_prefix_length = 27

    frontend_hostname = "test.aihub.gov.bc.ca"

    # SSL cert name on App GW for HTTPS listener (uploaded via CLI/portal)
    # Enables HTTPS listener + HTTP→HTTPS redirect when set
    ssl_certificate_name = "ai-services-hub-test-cert"
  }

  # ---------------------------------------------------------------------------
  # DNS Zone & Static Public IP
  # ---------------------------------------------------------------------------
  # Managed by Terraform with lifecycle prevent_destroy.
  # Creates: Resource Group, DNS Zone, Static PIP, A record.
  # After first apply, delegate NS records to parent zone (one-time).
  dns_zone = {
    enabled             = true
    zone_name           = "test.aihub.gov.bc.ca"
    resource_group_name = "ai-hub-test-dns"

    # DDoS IP Protection: disabled in test to save cost (~$199/mo)
    # Enable if testing DDoS scenarios
    ddos_protection_enabled = false
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

  # ---------------------------------------------------------------------------
  # Language Service (for PII Detection)
  # ---------------------------------------------------------------------------
  # Azure AI Language Service for enterprise PII detection via APIM policies.
  language_service = {
    enabled                       = true
    sku                           = "S"
    public_network_access_enabled = false
  }

  # ---------------------------------------------------------------------------
  # Monitoring — Resource Health + Service Health alerts → Teams webhook
  # ---------------------------------------------------------------------------
  monitoring = {
    enabled = true

    # Regions to watch for Azure Service Health events.
    # Includes primary deployment region and AI cross-region location.
    service_health_locations = ["Canada Central", "Canada East"]

    # Azure services covered by the service health alert.
    service_health_services = [
      "Azure API Management",
      "Azure AI model inference",
      "Azure OpenAI",
      "Azure Cognitive Services",
      "Azure Key Vault",
      "Application Gateway",
    ]

    # Email addresses to notify on hub health alerts.
    # Teams webhook URL is set via monitoring_webhook_url in sensitive tfvars.
    alert_emails = ["omprakash.2.mishra@gov.bc.ca"]
  }
}

# =============================================================================
# DEFENDER FOR CLOUD
# =============================================================================
# Only manage Defender plans NOT already enabled by central team/Azure Policy.
# Plans already enabled (managed externally): SqlServers, StorageAccounts,
# SqlServerVirtualMachines, KeyVaults, Arm, CosmosDbs, Discovery, FoundationalCspm
#
# Add new plans here only if you want to enable something not already active.
# Note: "AI" plan protects Azure OpenAI and Azure AI Model Inference services
defender_enabled = true
defender_resource_types = {
  "AI"  = { subplan = null }
  "Api" = { subplan = "P1" }
}
