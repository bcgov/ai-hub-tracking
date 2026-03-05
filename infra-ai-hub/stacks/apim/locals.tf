locals {
  enabled_tenants = {
    for key, config in var.tenants : key => config
    if try(config.enabled, false)
  }

  sanitized_display_names = {
    for key, config in local.enabled_tenants : key => replace(config.display_name, " ", "_")
  }

  # ---------------------------------------------------------------------------
  # Auth mode validation — fail early on typos instead of silently switching mode
  # Allowed values: "subscription_key" (default), "oauth2"
  # ---------------------------------------------------------------------------
  _validated_auth_modes = {
    for key, config in local.enabled_tenants : key => lookup(lookup(config, "apim_auth", {}), "mode", "subscription_key")
  }
  _invalid_auth_modes = {
    for key, mode in local._validated_auth_modes : key => mode
    if !contains(["subscription_key", "oauth2"], mode)
  }

  apim_config = var.shared_config.apim

  key_rotation_config = local.apim_config.key_rotation

  # ---------------------------------------------------------------------------
  # PE subnet resolution for APIM
  # APIM is pinned — null key uses primary; explicit key must exist in PE pool.
  # Invalid explicit key fails at plan time (no silent fallback).
  # ---------------------------------------------------------------------------
  pe_subnet_ids_by_key = try(
    data.terraform_remote_state.shared.outputs.private_endpoint_subnet_ids_by_key,
    {
      "privateendpoints-subnet" = data.terraform_remote_state.shared.outputs.private_endpoint_subnet_id
    }
  )

  resolved_apim_pe_subnet_id = (
    var.apim_pe_subnet_key == null
    ? data.terraform_remote_state.shared.outputs.private_endpoint_subnet_id
    : local.pe_subnet_ids_by_key[var.apim_pe_subnet_key]
  )

  tenants_with_subscription_key = {
    for key, config in local.enabled_tenants : key => config
    if lookup(lookup(config, "apim_auth", {}), "mode", "subscription_key") == "subscription_key"
  }

  tenants_with_key_rotation = {
    for key, config in local.tenants_with_subscription_key : key => config
    if local.key_rotation_config.rotation_enabled && local.apim_config.enabled && try(config.apim_auth.key_rotation_enabled, false)
  }

  # All subscription-key tenants get their keys stored in the hub Key Vault
  # (decoupled from rotation — every tenant's keys are always available in KV)
  tenants_with_kv_secrets = {
    for key, config in local.tenants_with_subscription_key : key => config
    if local.apim_config.enabled
  }

  # Tenants using Azure AD OAuth2 (Managed Identity) authentication instead of subscription keys
  tenants_with_oauth2 = {
    for key, config in local.enabled_tenants : key => config
    if lookup(lookup(config, "apim_auth", {}), "mode", "subscription_key") == "oauth2"
  }

  # Map of azuread app client IDs keyed by tenant name (populated only for oauth2 tenants)
  oauth2_app_client_ids = {
    for key, app in azuread_application.apim_oauth2 : key => app.client_id
  }

  hub_keyvault_uri = local.apim_config.enabled ? (
    try(data.terraform_remote_state.shared.outputs.hub_key_vault_uri, "")
  ) : ""

  hub_keyvault_name = local.apim_config.enabled ? (
    try(data.terraform_remote_state.shared.outputs.hub_key_vault_name, "")
  ) : ""

  application_insights_enabled = var.shared_config.log_analytics.enabled

  default_apim_diagnostics = {
    sampling_percentage       = 100
    always_log_errors         = true
    log_client_ip             = true
    http_correlation_protocol = "W3C"
    verbosity                 = "information"
    frontend_request = {
      body_bytes     = 1024
      headers_to_log = ["X-Tenant-Id", "X-Request-ID", "Content-Type", "X-Forwarded-For", "X-Real-Client-IP"]
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

  tenant_products = {
    for key, config in local.enabled_tenants : key => {
      display_name = config.display_name
      description  = "API access for ${config.display_name}"
      # oauth2 tenants do not use APIM subscription keys — product does not require one
      subscription_required = lookup(lookup(config, "apim_auth", {}), "mode", "subscription_key") == "subscription_key"
      approval_required     = false
      state                 = "published"
    }
  }

  apim_global_policy_xml = file("${path.root}/../../params/apim/global_policy.xml")

  # ---------------------------------------------------------------------------
  # Tenant-info base URL: App Gateway URL if enabled, otherwise APIM gateway URL
  # Used by the tenant-info endpoint to return correct client-facing URLs
  # ---------------------------------------------------------------------------
  appgw_enabled = try(var.shared_config.app_gateway.enabled, false)
  tenant_info_base_url = local.appgw_enabled ? (
    "https://${lookup(var.shared_config.app_gateway, "frontend_hostname", "")}"
  ) : (local.apim_config.enabled ? module.apim[0].gateway_url : "")

  tenant_api_policies = {
    for key, config in local.enabled_tenants : key => templatefile(
      "${path.root}/../../params/apim/api_policy.xml.tftpl",
      {
        tenant_name                    = key
        tokens_per_minute              = try(config.apim_policies.rate_limiting.tokens_per_minute, 10000)
        model_deployments              = try(config.openai.model_deployments, [])
        openai_enabled                 = length(try(config.openai.model_deployments, [])) > 0
        document_intelligence_enabled  = try(config.document_intelligence.enabled, false)
        ai_search_enabled              = try(config.ai_search.enabled, false)
        speech_services_enabled        = try(config.speech_services.enabled, false)
        storage_enabled                = try(config.storage_account.enabled, false)
        rate_limiting_enabled          = try(config.apim_policies.rate_limiting.enabled, true)
        non_openai_requests_per_minute = try(config.apim_policies.rate_limiting.non_openai_requests_per_minute, 300)
        pii_redaction_enabled          = try(config.apim_policies.pii_redaction.enabled, true) && var.shared_config.language_service.enabled
        usage_logging_enabled          = try(config.apim_policies.usage_logging.enabled, true)
        streaming_metrics_enabled      = try(config.apim_policies.streaming_metrics.enabled, true)
        tracking_dimensions_enabled    = try(config.apim_policies.tracking_dimensions.enabled, true)
        backend_timeout_seconds        = try(config.apim_policies.backend_timeout_seconds, 300)
        pii_excluded_categories        = try(config.apim_policies.pii_redaction.excluded_categories, [])
        pii_preserve_json_structure    = try(config.apim_policies.pii_redaction.preserve_json_structure, true)
        pii_structural_whitelist       = try(config.apim_policies.pii_redaction.structural_whitelist, [])
        pii_detection_language         = try(config.apim_policies.pii_redaction.detection_language, "en")
        pii_fail_closed                = try(config.apim_policies.pii_redaction.fail_closed, false)
        apim_keys_endpoint_enabled     = local.apim_config.enabled && lookup(lookup(config, "apim_auth", {}), "mode", "subscription_key") == "subscription_key"
        key_rotation_enabled           = local.key_rotation_config.rotation_enabled && try(config.apim_auth.key_rotation_enabled, false)
        keyvault_uri                   = local.hub_keyvault_uri
        tenant_info_enabled            = true
        base_url                       = local.tenant_info_base_url
        tenant_display_name            = config.display_name
        # OAuth2 / Managed Identity auth vars (only meaningful when mode != "subscription_key")
        # Access control is managed via RBAC (azuread_app_role_assignment) — not in policy XML.
        oauth2_enabled       = lookup(lookup(config, "apim_auth", {}), "mode", "subscription_key") == "oauth2"
        oauth2_app_client_id = lookup(local.oauth2_app_client_ids, key, "")
        aad_tenant_id        = var.tenant_id
      }
    )
  }

  # Flat map of (tenant, msi_object_id) pairs for azuread_app_role_assignment.
  # Key format: "<tenant_key>-<principal_oid>" — unique and stable.
  oauth2_principal_assignments = {
    for pair in flatten([
      for tenant_key, config in local.tenants_with_oauth2 : [
        for principal_oid in try(config.apim_auth.oauth2.allowed_principals, []) : {
          key           = "${tenant_key}-${principal_oid}"
          tenant_key    = tenant_key
          principal_oid = principal_oid
        }
      ]
    ]) : pair.key => pair
  }

  tenant_apis = {
    for tenant_key, tenant_config in local.enabled_tenants : tenant_key => {
      display_name = "${tenant_config.display_name} API"
      description  = "API gateway for ${tenant_config.display_name} AI services"
      path         = tenant_key
      protocols    = ["https"]
      # oauth2 tenants authenticate via JWT — no APIM subscription key required
      subscription_required = lookup(lookup(tenant_config, "apim_auth", {}), "mode", "subscription_key") == "subscription_key"
      api_type              = "http"
      revision              = "1"
      service_url           = null
      import                = null
      subscription_key_parameter_names = {
        header = "api-key"
        query  = "api-key"
      }
    }
  }

  tenant_subscriptions = {
    for key, config in local.tenants_with_subscription_key : "${key}-subscription" => {
      display_name  = "${config.display_name} Subscription"
      scope_type    = "product"
      product_id    = key
      state         = "active"
      allow_tracing = var.app_env != "prod"
    }
  }

  api_methods = ["POST", "GET", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

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

  # ---------------------------------------------------------------------------
  # Monitoring configuration — mirrors the enabled flag from shared_config
  # ---------------------------------------------------------------------------
  monitoring_config = {
    enabled = lookup(lookup(var.shared_config, "monitoring", {}), "enabled", false)
  }
}

# ---------------------------------------------------------------------------
# Validate tenant auth modes — catch typos at plan time
# ---------------------------------------------------------------------------
check "valid_auth_modes" {
  assert {
    condition     = length(local._invalid_auth_modes) == 0
    error_message = "Invalid apim_auth.mode for tenants: ${join(", ", [for k, v in local._invalid_auth_modes : "${k}=${v}"])}. Allowed values: subscription_key, oauth2."
  }
}
