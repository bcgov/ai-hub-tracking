locals {
  enabled_tenants = {
    for key, config in var.tenants : key => config
    if try(config.enabled, false)
  }

  sanitized_display_names = {
    for key, config in local.enabled_tenants : key => replace(config.display_name, " ", "_")
  }

  apim_config = var.shared_config.apim

  key_rotation_config = local.apim_config.key_rotation

  tenants_with_subscription_key = {
    for key, config in local.enabled_tenants : key => config
    if lookup(lookup(config, "apim_auth", {}), "mode", "subscription_key") == "subscription_key"
  }

  tenants_with_key_rotation = {
    for key, config in local.tenants_with_subscription_key : key => config
    if local.key_rotation_config.rotation_enabled && local.apim_config.enabled
  }

  tenants_storing_keys_in_kv = {
    for key, config in local.tenants_with_subscription_key : key => config
    if local.apim_config.enabled && local.key_rotation_config.rotation_enabled
  }

  hub_keyvault_uri = local.key_rotation_config.rotation_enabled && local.apim_config.enabled ? (
    try(data.terraform_remote_state.shared.outputs.hub_key_vault_uri, "")
  ) : ""

  hub_keyvault_name = local.key_rotation_config.rotation_enabled && local.apim_config.enabled ? (
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

  tenant_products = {
    for key, config in local.enabled_tenants : key => {
      display_name          = config.display_name
      description           = "API access for ${config.display_name}"
      subscription_required = true
      approval_required     = false
      state                 = "published"
    }
  }

  apim_global_policy_xml = file("${path.root}/../../params/apim/global_policy.xml")

  tenant_api_policies = {
    for key, config in local.enabled_tenants : key => templatefile(
      "${path.root}/../../params/apim/api_policy.xml.tftpl",
      {
        tenant_name                   = key
        tokens_per_minute             = try(config.apim_policies.rate_limiting.tokens_per_minute, 10000)
        model_deployments             = try(config.openai.model_deployments, [])
        openai_enabled                = length(try(config.openai.model_deployments, [])) > 0
        document_intelligence_enabled = try(config.document_intelligence.enabled, false)
        ai_search_enabled             = try(config.ai_search.enabled, false)
        speech_services_enabled       = try(config.speech_services.enabled, false)
        storage_enabled               = try(config.storage_account.enabled, false)
        rate_limiting_enabled         = try(config.apim_policies.rate_limiting.enabled, true)
        pii_redaction_enabled         = try(config.apim_policies.pii_redaction.enabled, true) && var.shared_config.language_service.enabled
        usage_logging_enabled         = try(config.apim_policies.usage_logging.enabled, true)
        streaming_metrics_enabled     = try(config.apim_policies.streaming_metrics.enabled, true)
        tracking_dimensions_enabled   = try(config.apim_policies.tracking_dimensions.enabled, true)
        backend_timeout_seconds       = try(config.apim_policies.backend_timeout_seconds, 300)
        pii_excluded_categories       = try(config.apim_policies.pii_redaction.excluded_categories, [])
        pii_preserve_json_structure   = try(config.apim_policies.pii_redaction.preserve_json_structure, true)
        pii_structural_whitelist      = try(config.apim_policies.pii_redaction.structural_whitelist, [])
        pii_detection_language        = try(config.apim_policies.pii_redaction.detection_language, "en")
        pii_fail_closed               = try(config.apim_policies.pii_redaction.fail_closed, false)
        key_rotation_enabled          = local.key_rotation_config.rotation_enabled
        keyvault_uri                  = local.hub_keyvault_uri
        tenant_info_enabled           = true
      }
    )
  }

  tenant_apis = {
    for tenant_key, tenant_config in local.enabled_tenants : tenant_key => {
      display_name          = "${tenant_config.display_name} API"
      description           = "API gateway for ${tenant_config.display_name} AI services"
      path                  = tenant_key
      protocols             = ["https"]
      subscription_required = true
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
