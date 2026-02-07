# =============================================================================
# LOCAL VALUES
# =============================================================================
# Computed values for the AI Foundry infrastructure.
# Configuration is loaded from params/{app_env}/*.tfvars via -var-file.
# Tenant configurations are merged from individual tfvars files by deploy script.
# =============================================================================

locals {
  # Filter to only enabled tenants
  enabled_tenants = {
    for key, config in var.tenants :
    key => config if config.enabled
  }

  # Sanitized display names for APIM (replace spaces with underscores)
  # APIM display_name can only contain: alphanumeric, periods, underscores, dashes
  sanitized_display_names = {
    for key, config in local.enabled_tenants : key => replace(config.display_name, " ", "_")
  }

  # APIM and App GW configuration shortcuts
  apim_config     = var.shared_config.apim
  appgw_config    = var.shared_config.app_gateway
  dns_zone_config = var.shared_config.dns_zone

  # Application Insights enabled flag - use input variable directly for count expressions
  # This avoids "count depends on resource attributes" errors during destroy
  application_insights_enabled = var.shared_config.log_analytics.enabled

  # =============================================================================
  # PER-TENANT APIM DIAGNOSTICS
  # =============================================================================
  # Default APIM diagnostic settings (can be overridden per tenant)
  default_apim_diagnostics = {
    sampling_percentage       = 100
    always_log_errors         = true
    log_client_ip             = true
    http_correlation_protocol = "W3C"
    verbosity                 = "information"
    frontend_request = {
      body_bytes     = 1024
      headers_to_log = ["X-Tenant-Id", "X-Request-ID", "Content-Type"]
    }
    frontend_response = {
      body_bytes     = 1024
      headers_to_log = ["x-ms-request-id", "x-ratelimit-remaining-tokens", "x-tokens-consumed"]
    }
    backend_request = {
      body_bytes     = 1024
      headers_to_log = ["Authorization", "api-key"]
    }
    backend_response = {
      body_bytes     = 1024
      headers_to_log = ["x-ms-region", "x-ratelimit-remaining-tokens"]
    }
  }

  # Build tenant products for APIM
  tenant_products = {
    for key, config in local.enabled_tenants : key => {
      display_name          = config.display_name
      description           = "API access for ${config.display_name}"
      subscription_required = true
      approval_required     = false
      state                 = "published"
    }
  }

  # =============================================================================
  # APIM POLICY FILES
  # =============================================================================
  # Tenants that opt out of PII redaction (deploy-time decision)
  pii_redaction_opt_out_tenants = [
    for key, config in local.enabled_tenants : key
    if try(config.apim_policies.pii_redaction.enabled, true) == false
  ]

  # Load global policy from file
  # PII redaction is handled by tenant API policies via pii-anonymization fragment
  apim_global_policy_xml = file("${path.module}/params/apim/global_policy.xml")

  # =============================================================================
  # DYNAMIC TENANT API POLICIES (Generated from tenant config)
  # =============================================================================
  # Policies are dynamically generated from the template based on:
  # - Enabled services (openai/ai_model_deployments, document_intelligence, ai_search, storage)
  # - APIM policies config (pii_redaction, usage_logging, etc.)
  # - Token rate limits
  # 
  # This eliminates the need for static per-tenant api_policy.xml files.
  # To add/remove features, just update tenant.tfvars - no XML editing needed.
  # =============================================================================
  tenant_api_policies = {
    for key, config in local.enabled_tenants : key => templatefile(
      "${path.module}/params/apim/api_policy.xml.tftpl",
      {
        tenant_name       = key
        tokens_per_minute = try(config.apim_policies.rate_limiting.tokens_per_minute, 10000)
        # Model deployments for per-model rate limiting (from tenant.tfvars)
        # Supports both legacy openai.model_deployments format and new ai_model_deployments format
        model_deployments = try(config.openai.model_deployments, [])
        # Service routing - based on enabled services in tenant config
        # OpenAI routing is enabled when there are model deployments (either format)
        openai_enabled                = length(try(config.openai.model_deployments, [])) > 0
        document_intelligence_enabled = try(config.document_intelligence.enabled, false)
        ai_search_enabled             = try(config.ai_search.enabled, false)
        speech_services_enabled       = try(config.speech_services.enabled, false)
        storage_enabled               = try(config.storage_account.enabled, false)
        # APIM Policies - feature flags from apim_policies config
        rate_limiting_enabled       = try(config.apim_policies.rate_limiting.enabled, true)
        pii_redaction_enabled       = try(config.apim_policies.pii_redaction.enabled, true) && var.shared_config.language_service.enabled
        usage_logging_enabled       = try(config.apim_policies.usage_logging.enabled, true)
        streaming_metrics_enabled   = try(config.apim_policies.streaming_metrics.enabled, true)
        tracking_dimensions_enabled = try(config.apim_policies.tracking_dimensions.enabled, true)
        # PII Redaction advanced options
        pii_excluded_categories     = try(config.apim_policies.pii_redaction.excluded_categories, [])
        pii_preserve_json_structure = try(config.apim_policies.pii_redaction.preserve_json_structure, true)
        pii_structural_whitelist    = try(config.apim_policies.pii_redaction.structural_whitelist, [])
        pii_detection_language      = try(config.apim_policies.pii_redaction.detection_language, "en")
        pii_fail_closed             = try(config.apim_policies.pii_redaction.fail_closed, false)
      }
    )
  }

  # =============================================================================
  # TENANT POLICY VALIDATION (Simplified - policies are now auto-generated)
  # =============================================================================
  # Since policies are dynamically generated from tenant config, validation
  # is simplified. The tenant_name is injected directly from the config key,
  # so X-Tenant-Id mismatches are impossible.
  # 
  # Service validation is also unnecessary - if a service is disabled in
  # tenant.tfvars, the routing for that service won't be generated.
  # =============================================================================

  # For backwards compatibility, keep empty validation structures
  tenant_policy_validation = {
    for key, policy in local.tenant_api_policies : key => {
      has_policy       = true # Always generated now
      policy_tenant_id = key  # Always matches - injected from config key
      is_valid         = true # Always valid - generated from template
    }
  }

  # No mismatches possible with dynamic generation
  tenant_policy_mismatches = []

  # =============================================================================
  # POLICY SERVICE VALIDATION (Deprecated - services auto-discovered from config)
  # =============================================================================
  # With dynamic policy generation, this validation is no longer needed.
  # Services are only routed if enabled in tenant.tfvars.
  tenant_policy_service_validation = {
    for key, config in local.enabled_tenants : key => {
      has_policy = true
      # Services are auto-detected from tenant config, not parsed from XML
      # OpenAI is enabled when there are model deployments
      openai_enabled    = length(try(config.openai.model_deployments, [])) > 0
      docint_enabled    = try(config.document_intelligence.enabled, false)
      storage_enabled   = try(config.storage_account.enabled, false)
      ai_search_enabled = try(config.ai_search.enabled, false)
      cosmos_enabled    = try(config.cosmos_db.enabled, false)
      # No references to check - policy only includes enabled services
      references_openai    = length(try(config.openai.model_deployments, [])) > 0
      references_docint    = try(config.document_intelligence.enabled, false)
      references_storage   = try(config.storage_account.enabled, false)
      references_ai_search = try(config.ai_search.enabled, false)
      references_cosmos    = try(config.cosmos_db.enabled, false)
    }
  }

  # No missing services possible - policy only includes enabled services
  tenant_policy_missing_services = []

  # =============================================================================
  # APIM APIS
  # =============================================================================
  # Generate one API per tenant with path-based routing
  # Each tenant API handles: /openai/*, /docint/*, /storage/*
  tenant_apis = {
    for tenant_key, tenant_config in local.enabled_tenants : tenant_key => {
      display_name          = "${tenant_config.display_name} API"
      description           = "API gateway for ${tenant_config.display_name} AI services"
      path                  = tenant_key
      protocols             = ["https"]
      subscription_required = true
      api_type              = "http"
      revision              = "1"
      service_url           = null # Set via policy routing
      import                = null
      # Use 'api-key' header for SDK compatibility (Azure OpenAI SDK, Azure AI Search SDK)
      subscription_key_parameter_names = {
        header = "api-key"
        query  = "api-key"
      }
    }
  }

  # =============================================================================
  # APIM AUTHENTICATION
  # =============================================================================
  # Filter tenants by authentication mode
  tenants_with_subscription_key = {
    for key, config in local.enabled_tenants : key => config
    if lookup(lookup(config, "apim_auth", {}), "mode", "subscription_key") == "subscription_key"
  }

  tenants_with_oauth2 = {
    for key, config in local.enabled_tenants : key => config
    if lookup(lookup(config, "apim_auth", {}), "mode", "subscription_key") == "oauth2"
  }

  # Generate subscriptions for tenants using subscription_key mode
  tenant_subscriptions = {
    for key, config in local.tenants_with_subscription_key : "${key}-subscription" => {
      display_name  = "${config.display_name} Subscription"
      scope_type    = "product"
      product_id    = key # Links to tenant product
      state         = "active"
      allow_tracing = var.app_env != "prod" # Enable tracing in non-prod
    }
  }
  # =============================================================================
  # APIM API OPERATIONS (catch-all for path-based routing)
  # Tenant APIs need operations to handle incoming requests
  # APIM requires explicit HTTP methods - wildcard (*) doesn't match all requests
  # =============================================================================
  # HTTP methods needed for OpenAI/Azure AI APIs:
  # - POST, GET, PUT, DELETE, PATCH: Standard REST operations for API calls
  # - OPTIONS: Required for CORS preflight requests from browser-based clients
  # - HEAD: Useful for lightweight health checks and metadata-only probes
  api_methods = ["POST", "GET", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

  # Create a map of tenant + method combinations
  tenant_api_operations = {
    for pair in flatten([
      for tenant_key, config in local.enabled_tenants : [
        for method in local.api_methods : {
          key    = "${tenant_key}-${lower(method)}"
          tenant = tenant_key
          method = method
          config = config
        }
      ] if local.apim_config.enabled
    ]) : pair.key => pair
  }
}

# =============================================================================
# VALIDATION CHECKS
# =============================================================================

# Validate: Tenant policy X-Tenant-Id must match folder name
check "tenant_policy_name_mismatch" {
  assert {
    condition = length(local.tenant_policy_mismatches) == 0
    error_message = <<-EOT
      Tenant policy X-Tenant-Id mismatch detected!
      The following tenant policies have X-Tenant-Id values that don't match their folder names:
      ${join(", ", [for key in local.tenant_policy_mismatches :
    "${key} (policy says: ${local.tenant_policy_validation[key].policy_tenant_id})"
])}
      
      Please update the X-Tenant-Id header in params/apim/tenants/{tenant}/api_policy.xml 
      to match the folder name.
    EOT
}
}

# Validate: Policy must not reference services that are disabled
check "tenant_policy_missing_services" {
  assert {
    condition = length(local.tenant_policy_missing_services) == 0
    error_message = <<-EOT
      Tenant policy references disabled services!
      The following tenant policies reference named values for services that are not enabled:
      ${join("\n", [for item in local.tenant_policy_missing_services :
    "  - ${item.tenant}: missing ${join(", ", item.missing)}"
])}
      
      Either enable the services in the tenant config or remove the references from the policy.
    EOT
}
}
