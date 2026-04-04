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
      display_name          = config.display_name
      description           = "API access for ${config.display_name}"
      subscription_required = true
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

  provisioned_scale_types = toset([
    "GlobalProvisionedManaged",
    "DataZoneProvisionedManaged",
    "ProvisionedManaged",
  ])

  # Azure OpenAI provisioned throughput uses model-specific input TPM per PTU,
  # and some models weight output tokens more heavily than input tokens.
  # Sources:
  # - https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/provisioned-throughput-onboarding#latest-azure-openai-models
  # - https://azure.microsoft.com/en-ca/pricing/details/cognitive-services/openai-service/
  provisioned_capacity_metadata_by_model = {
    "gpt-5.1" = {
      input_tpm_per_ptu            = 4750
      output_tokens_to_input_ratio = 8
    }
  }

  tenant_model_deployments = {
    for key, config in local.enabled_tenants : key => [
      for _m in [
        for deployment in try(config.openai.model_deployments, []) : merge(deployment, {
          # Quota-backed deployments report capacity directly in k TPM; provisioned deployments use PTU.
          capacity_unit = contains(local.provisioned_scale_types, try(deployment.scale_type, "")) ? "PTU" : "k TPM"
          # Preserve the legacy k TPM field for quota-backed deployments only.
          capacity_k_tpm = contains(local.provisioned_scale_types, try(deployment.scale_type, "")) ? null : try(deployment.capacity, null)
          # PTU metadata is model-specific and comes from the lookup table above.
          input_tpm_per_ptu            = contains(local.provisioned_scale_types, try(deployment.scale_type, "")) ? try(local.provisioned_capacity_metadata_by_model[try(deployment.model_name, deployment.name)].input_tpm_per_ptu, null) : null
          output_tokens_to_input_ratio = contains(local.provisioned_scale_types, try(deployment.scale_type, "")) ? try(local.provisioned_capacity_metadata_by_model[try(deployment.model_name, deployment.name)].output_tokens_to_input_ratio, null) : null
          # Foundry PTU throughput is tracked in input-equivalent TPM, not raw prompt+completion tokens.
          input_equivalent_tokens_per_minute = contains(local.provisioned_scale_types, try(deployment.scale_type, "")) ? (
            try(deployment.capacity, 0) * try(local.provisioned_capacity_metadata_by_model[try(deployment.model_name, deployment.name)].input_tpm_per_ptu, 1000)
          ) : (try(deployment.capacity, 0) * 1000)
          # APIM can only rate-limit raw tokens, so convert the PTU ceiling into a conservative
          # raw-token cap by dividing the input-equivalent ceiling by the output weighting ratio.
          apim_raw_tokens_per_minute = contains(local.provisioned_scale_types, try(deployment.scale_type, "")) ? floor(
            (
              try(deployment.capacity, 0) *
              try(local.provisioned_capacity_metadata_by_model[try(deployment.model_name, deployment.name)].input_tpm_per_ptu, 1000)
              ) / max(
              1,
              try(local.provisioned_capacity_metadata_by_model[try(deployment.model_name, deployment.name)].output_tokens_to_input_ratio, 1)
            )
          ) : (try(deployment.capacity, 0) * 1000)
        })
        ] : merge(_m, {
          # Track whether APIM enforces this model via raw-token caps or weighted actual usage.
          token_limit_strategy = _m.capacity_unit == "PTU" ? "response_weighted_actual_tokens" : "raw_tokens_per_minute"
          # PTU models use prompt x1 + completion xN weighting; quota-backed models stay 1:1.
          prompt_tokens_weight       = 1
          completion_tokens_weight   = _m.capacity_unit == "PTU" ? coalesce(_m.output_tokens_to_input_ratio, 1) : 1
          weighted_tokens_per_minute = _m.capacity_unit == "PTU" ? _m.input_equivalent_tokens_per_minute : _m.apim_raw_tokens_per_minute
          # Dedicated backend entity isolates PTU circuit-breaking from the shared quota-backed path.
          openai_backend_id = _m.capacity_unit == "PTU" ? "${key}-openai-ptu" : "${key}-openai"
          # Legacy alias: kept aligned with the actual APIM-enforced raw-token cap.
          tokens_per_minute = _m.apim_raw_tokens_per_minute
      })
    ]
  }

  tenant_backend_routing_is_valid = {
    for key, deployments in local.tenant_model_deployments : key => alltrue([
      for deployment in deployments : (
        deployment.capacity_unit == "PTU"
        ? deployment.openai_backend_id == "${key}-openai-ptu"
        : deployment.openai_backend_id == "${key}-openai"
      )
    ])
  }

  tenant_api_policies = {
    for key, config in local.enabled_tenants : key => templatefile(
      "${path.root}/../../params/apim/api_policy.xml.tftpl",
      {
        tenant_name                    = key
        tokens_per_minute              = try(config.apim_policies.rate_limiting.tokens_per_minute, 10000)
        model_deployments              = local.tenant_model_deployments[key]
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
        pii_detection_language         = try(config.apim_policies.pii_redaction.detection_language, "en")
        pii_fail_closed                = try(config.apim_policies.pii_redaction.fail_closed, false)
        pii_scan_roles                 = jsonencode(try(config.apim_policies.pii_redaction.scan_roles, ["user", "assistant", "tool"]))
        pii_external_redaction_url = (
          try(data.terraform_remote_state.pii_redaction.outputs.pii_redaction_service.container_app_fqdn, null) != null
          ? "https://${data.terraform_remote_state.pii_redaction.outputs.pii_redaction_service.container_app_fqdn}"
          : try(config.apim_policies.pii_redaction.external_redaction_url, "")
        )
        apim_keys_endpoint_enabled = local.apim_config.enabled && lookup(lookup(config, "apim_auth", {}), "mode", "subscription_key") == "subscription_key"
        key_rotation_enabled       = local.key_rotation_config.rotation_enabled && try(config.apim_auth.key_rotation_enabled, false)
        keyvault_uri               = local.hub_keyvault_uri
        tenant_info_enabled        = true
        base_url                   = local.tenant_info_base_url
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

# Advisory check: warn if a provisioned deployment references a model not in
# the provisioned_capacity_metadata_by_model lookup table (silent fallback to
# 1000 / 1 would produce incorrect rate-limit values).
check "provisioned_model_metadata_coverage" {
  assert {
    condition = alltrue([
      for key, config in local.enabled_tenants : alltrue([
        for deployment in try(config.openai.model_deployments, []) :
        !contains(local.provisioned_scale_types, try(deployment.scale_type, "")) ||
        contains(keys(local.provisioned_capacity_metadata_by_model), try(deployment.model_name, deployment.name))
      ])
    ])
    error_message = "One or more provisioned deployments reference a model not in provisioned_capacity_metadata_by_model. Add the model's input_tpm_per_ptu and output_tokens_to_input_ratio to the lookup table in locals.tf."
  }
}

check "provisioned_backend_routing_alignment" {
  assert {
    condition     = alltrue(values(local.tenant_backend_routing_is_valid))
    error_message = "One or more OpenAI deployments render with the wrong APIM backend id. PTU deployments must use <tenant>-openai-ptu and non-PTU deployments must use <tenant>-openai."
  }
}
