# =============================================================================
# LOCAL VALUES
# =============================================================================
# Computed values for the AI Foundry infrastructure.
# Configuration is loaded from params/{app_env}/*.tfvars via -var-file.
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
  apim_config  = var.shared_config.apim
  appgw_config = var.shared_config.app_gateway

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
    if try(config.content_safety.pii_redaction_enabled, true) == false
  ]

  # Load global policy from template (PII redaction)
  apim_global_policy_xml = templatefile("${path.module}/params/apim/global_policy.xml", {
    pii_redaction_opt_out_tenants = local.pii_redaction_opt_out_tenants
  })

  # Load tenant-specific API policies from files (if they exist)
  # Each tenant can have: params/apim/tenants/{tenant-name}/api_policy.xml
  tenant_api_policies = {
    for key, config in local.enabled_tenants : key => (
      fileexists("${path.module}/params/apim/tenants/${key}/api_policy.xml")
      ? file("${path.module}/params/apim/tenants/${key}/api_policy.xml")
      : null
    )
  }

  # =============================================================================
  # TENANT POLICY VALIDATION
  # =============================================================================
  # Check that tenant policies reference the correct tenant name
  # Extracts X-Tenant-Id header value from policy and compares to folder name
  tenant_policy_validation = {
    for key, policy in local.tenant_api_policies : key => {
      has_policy = policy != null
      # Extract tenant ID from X-Tenant-Id header in policy (if present)
      policy_tenant_id = policy != null ? (
        can(regex("<set-header name=\"X-Tenant-Id\"[^>]*>\\s*<value>([^<]+)</value>", policy))
        ? regex("<set-header name=\"X-Tenant-Id\"[^>]*>\\s*<value>([^<]+)</value>", policy)[0]
        : null
      ) : null
      # Check if the tenant ID in policy matches the folder name
      is_valid = policy == null ? true : (
        can(regex("<set-header name=\"X-Tenant-Id\"[^>]*>\\s*<value>([^<]+)</value>", policy))
        ? regex("<set-header name=\"X-Tenant-Id\"[^>]*>\\s*<value>([^<]+)</value>", policy)[0] == key
        : true # No X-Tenant-Id header found, skip validation
      )
    }
  }

  # List of tenants with mismatched policy files
  tenant_policy_mismatches = [
    for key, validation in local.tenant_policy_validation : key
    if !validation.is_valid
  ]

  # =============================================================================
  # POLICY SERVICE VALIDATION
  # =============================================================================
  # Detect named value references in policies and validate services are enabled
  tenant_policy_service_validation = {
    for key, policy in local.tenant_api_policies : key => {
      has_policy = policy != null
      # Check which service endpoints are referenced in the policy
      references_openai  = policy != null ? can(regex("\\{\\{[^}]*-openai-endpoint\\}\\}", policy)) : false
      references_docint  = policy != null ? can(regex("\\{\\{[^}]*-docint-endpoint\\}\\}", policy)) : false
      references_storage = policy != null ? can(regex("\\{\\{[^}]*-storage-endpoint\\}\\}", policy)) : false
      # Check if the referenced services are enabled for this tenant
      openai_enabled  = lookup(local.enabled_tenants[key].openai, "enabled", false)
      docint_enabled  = lookup(local.enabled_tenants[key].document_intelligence, "enabled", false)
      storage_enabled = lookup(local.enabled_tenants[key].storage_account, "enabled", false)
    } if contains(keys(local.enabled_tenants), key)
  }

  # Find policies that reference disabled services
  tenant_policy_missing_services = [
    for key, v in local.tenant_policy_service_validation : {
      tenant = key
      missing = compact([
        v.references_openai && !v.openai_enabled ? "openai" : "",
        v.references_docint && !v.docint_enabled ? "document_intelligence" : "",
        v.references_storage && !v.storage_enabled ? "storage_account" : ""
      ])
    }
    if length(compact([
      v.references_openai && !v.openai_enabled ? "openai" : "",
      v.references_docint && !v.docint_enabled ? "document_intelligence" : "",
      v.references_storage && !v.storage_enabled ? "storage_account" : ""
    ])) > 0
  ]

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
  # HTTP methods needed for OpenAI/Azure AI APIs
  api_methods = ["POST", "GET", "PUT", "DELETE", "PATCH"]

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
