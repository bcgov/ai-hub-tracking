data "azurerm_client_config" "current" {}

data "terraform_remote_state" "shared" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.backend_resource_group
    storage_account_name = var.backend_storage_account
    container_name       = var.backend_container_name
    key                  = "ai-services-hub/${var.app_env}/shared.tfstate"
    subscription_id      = var.subscription_id
    tenant_id            = var.tenant_id
    client_id            = var.client_id
    use_oidc             = var.use_oidc
  }
}

data "terraform_remote_state" "tenant" {
  for_each = local.enabled_tenants
  backend  = "azurerm"
  config = {
    resource_group_name  = var.backend_resource_group
    storage_account_name = var.backend_storage_account
    container_name       = var.backend_container_name
    key                  = "ai-services-hub/${var.app_env}/tenant-${each.key}.tfstate"
    subscription_id      = var.subscription_id
    tenant_id            = var.tenant_id
    client_id            = var.client_id
    use_oidc             = var.use_oidc
  }
}

module "apim" {
  source = "../../modules/apim"
  count  = local.apim_config.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-apim"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  location            = var.location

  sku_name        = lookup(local.apim_config, "sku_name", "StandardV2_1")
  publisher_name  = lookup(local.apim_config, "publisher_name", "AI Hub")
  publisher_email = lookup(local.apim_config, "publisher_email", "admin@example.com")

  public_network_access_enabled = lookup(local.apim_config, "public_network_access_enabled", true)
  enable_vnet_integration       = lookup(local.apim_config, "vnet_injection_enabled", false)
  vnet_integration_subnet_id    = data.terraform_remote_state.shared.outputs.apim_subnet_id

  enable_private_endpoint    = true
  private_endpoint_subnet_id = data.terraform_remote_state.shared.outputs.private_endpoint_subnet_id
  private_dns_zone_ids       = lookup(local.apim_config, "private_dns_zone_ids", [])

  tenant_products            = local.tenant_products
  apis                       = local.tenant_apis
  global_policy_xml          = local.apim_global_policy_xml
  enable_diagnostics         = true
  log_analytics_workspace_id = data.terraform_remote_state.shared.outputs.log_analytics_workspace_id
  tags                       = var.common_tags
  scripts_dir                = "${path.root}/../../scripts"
  private_endpoint_dns_wait = {
    timeout       = var.shared_config.private_endpoint_dns_wait.timeout
    poll_interval = var.shared_config.private_endpoint_dns_wait.poll_interval
  }
}

resource "azurerm_api_management_named_value" "ai_foundry_endpoint" {
  count = local.apim_config.enabled ? 1 : 0

  name                = "ai-foundry-endpoint"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  display_name        = "AI_Foundry_Endpoint"
  value               = data.terraform_remote_state.shared.outputs.ai_foundry_hub_endpoint
  secret              = false
}

resource "azurerm_api_management_named_value" "openai_endpoint" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if length(lookup(config.openai, "model_deployments", [])) > 0 && local.apim_config.enabled
  }

  name                = "${each.key}-openai-endpoint"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  display_name        = "${local.sanitized_display_names[each.key]}_OpenAI_Endpoint"
  value               = data.terraform_remote_state.shared.outputs.ai_foundry_hub_endpoint
  secret              = false
}

resource "azurerm_api_management_named_value" "docint_endpoint" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.document_intelligence.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-docint-endpoint"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  display_name        = "${local.sanitized_display_names[each.key]}_Document_Intelligence_Endpoint"
  value               = data.terraform_remote_state.tenant[each.key].outputs.tenant_document_intelligence[each.key].endpoint
  secret              = false
}

resource "azurerm_api_management_named_value" "storage_endpoint" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.storage_account.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-storage-endpoint"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  display_name        = "${local.sanitized_display_names[each.key]}_Storage_Endpoint"
  value               = data.terraform_remote_state.tenant[each.key].outputs.tenant_storage_accounts[each.key].blob_endpoint
  secret              = false
}

resource "azurerm_api_management_named_value" "ai_search_endpoint" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.ai_search.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-ai-search-endpoint"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  display_name        = "${local.sanitized_display_names[each.key]}_AI_Search_Endpoint"
  value               = data.terraform_remote_state.tenant[each.key].outputs.tenant_ai_search[each.key].endpoint
  secret              = false
}

resource "azurerm_api_management_named_value" "speech_services_endpoint" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.speech_services.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-speech-endpoint"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  display_name        = "${local.sanitized_display_names[each.key]}_Speech_Services_Endpoint"
  value               = data.terraform_remote_state.tenant[each.key].outputs.tenant_speech_services[each.key].endpoint
  secret              = false
}

resource "azurerm_api_management_named_value" "pii_service_url" {
  count = var.shared_config.language_service.enabled && local.apim_config.enabled ? 1 : 0

  name                = "piiServiceUrl"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  display_name        = "piiServiceUrl"
  value               = trimsuffix(data.terraform_remote_state.shared.outputs.language_service_endpoint, "/")
  secret              = false
}

resource "azurerm_api_management_backend" "ai_foundry" {
  count = local.apim_config.enabled ? 1 : 0

  name                = "ai-foundry-hub"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = data.terraform_remote_state.shared.outputs.ai_foundry_hub_endpoint
  description         = "Shared AI Foundry Hub backend for all tenant model deployments"
}

resource "azurerm_api_management_backend" "openai" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if length(lookup(config.openai, "model_deployments", [])) > 0 && local.apim_config.enabled
  }

  name                = "${each.key}-openai"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = data.terraform_remote_state.shared.outputs.ai_foundry_hub_endpoint
  description         = "OpenAI backend for ${each.value.display_name}"
}

resource "azurerm_api_management_backend" "docint" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.document_intelligence.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-docint"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = data.terraform_remote_state.tenant[each.key].outputs.tenant_document_intelligence[each.key].endpoint
  description         = "Document Intelligence backend for ${each.value.display_name}"
}

resource "azurerm_api_management_backend" "storage" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.storage_account.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-storage"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = data.terraform_remote_state.tenant[each.key].outputs.tenant_storage_accounts[each.key].blob_endpoint
  description         = "Storage backend for ${each.value.display_name}"
}

resource "azurerm_api_management_backend" "ai_search" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.ai_search.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-ai-search"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = data.terraform_remote_state.tenant[each.key].outputs.tenant_ai_search[each.key].endpoint
  description         = "AI Search backend for ${each.value.display_name}"
}

resource "azurerm_api_management_backend" "speech_services_stt" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.speech_services.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-speech-stt"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = data.terraform_remote_state.tenant[each.key].outputs.tenant_speech_services[each.key].endpoint
  description         = "Speech-to-text backend for ${each.value.display_name}"
}

resource "azurerm_api_management_backend" "speech_services_tts" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.speech_services.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-speech-tts"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = data.terraform_remote_state.tenant[each.key].outputs.tenant_speech_services[each.key].endpoint
  description         = "Text-to-speech backend for ${each.value.display_name}"
}

resource "azurerm_api_management_named_value" "speech_services_key" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.speech_services.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-speech-key"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name = module.apim[0].name
  display_name        = "${replace(local.sanitized_display_names[each.key], "-", "_")}_Speech_Services_Key"
  value               = data.terraform_remote_state.tenant[each.key].outputs.tenant_speech_services[each.key].primary_key
  secret              = true
}

resource "azurerm_api_management_logger" "app_insights" {
  count = local.apim_config.enabled && local.application_insights_enabled ? 1 : 0

  name                = "${module.apim[0].name}-appinsights-logger"
  api_management_name = module.apim[0].name
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  resource_id         = data.terraform_remote_state.shared.outputs.application_insights_id

  application_insights {
    connection_string = data.terraform_remote_state.shared.outputs.application_insights_connection_string
  }
}

resource "azurerm_api_management_diagnostic" "app_insights" {
  count = local.apim_config.enabled && local.application_insights_enabled ? 1 : 0

  identifier               = "applicationinsights"
  resource_group_name      = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name      = module.apim[0].name
  api_management_logger_id = azurerm_api_management_logger.app_insights[0].id

  sampling_percentage       = 100
  always_log_errors         = true
  log_client_ip             = true
  http_correlation_protocol = "W3C"
  verbosity                 = "information"

  frontend_request {
    body_bytes     = 1024
    headers_to_log = ["X-Tenant-Id", "X-Request-ID", "Content-Type", "Authorization"]
  }

  frontend_response {
    body_bytes     = 1024
    headers_to_log = ["x-ms-request-id", "x-ratelimit-remaining-tokens", "x-tokens-consumed"]
  }

  backend_request {
    body_bytes     = 1024
    headers_to_log = ["Authorization", "api-key"]
  }

  backend_response {
    body_bytes     = 1024
    headers_to_log = ["x-ms-region", "x-ratelimit-remaining-tokens"]
  }
}

resource "azurerm_api_management_logger" "tenant_app_insights" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if local.apim_config.enabled && lookup(config.log_analytics, "enabled", false)
  }

  name                = "${module.apim[0].name}-${each.key}-appinsights"
  api_management_name = module.apim[0].name
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name

  application_insights {
    instrumentation_key = data.terraform_remote_state.tenant[each.key].outputs.tenant_log_analytics[each.key].instrumentation_key
  }
}

resource "azurerm_api_management_api_diagnostic" "tenant" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if local.apim_config.enabled
  }

  identifier               = "applicationinsights"
  resource_group_name      = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name      = module.apim[0].name
  api_name                 = each.key
  api_management_logger_id = lookup(each.value.log_analytics, "enabled", false) ? azurerm_api_management_logger.tenant_app_insights[each.key].id : (local.application_insights_enabled ? azurerm_api_management_logger.app_insights[0].id : null)

  sampling_percentage       = try(each.value.apim_diagnostics.sampling_percentage, local.default_apim_diagnostics.sampling_percentage)
  always_log_errors         = try(each.value.apim_diagnostics.always_log_errors, local.default_apim_diagnostics.always_log_errors)
  log_client_ip             = try(each.value.apim_diagnostics.log_client_ip, local.default_apim_diagnostics.log_client_ip)
  http_correlation_protocol = try(each.value.apim_diagnostics.http_correlation_protocol, local.default_apim_diagnostics.http_correlation_protocol)
  verbosity                 = try(each.value.apim_diagnostics.verbosity, local.default_apim_diagnostics.verbosity)

  frontend_request {
    body_bytes = try(
      each.value.apim_diagnostics.frontend_request.body_bytes,
      local.default_apim_diagnostics.frontend_request.body_bytes
    )
    headers_to_log = try(
      each.value.apim_diagnostics.frontend_request.headers_to_log,
      local.default_apim_diagnostics.frontend_request.headers_to_log
    )
  }

  frontend_response {
    body_bytes = try(
      each.value.apim_diagnostics.frontend_response.body_bytes,
      local.default_apim_diagnostics.frontend_response.body_bytes
    )
    headers_to_log = try(
      each.value.apim_diagnostics.frontend_response.headers_to_log,
      local.default_apim_diagnostics.frontend_response.headers_to_log
    )
  }

  backend_request {
    body_bytes = try(
      each.value.apim_diagnostics.backend_request.body_bytes,
      local.default_apim_diagnostics.backend_request.body_bytes
    )
    headers_to_log = try(
      each.value.apim_diagnostics.backend_request.headers_to_log,
      local.default_apim_diagnostics.backend_request.headers_to_log
    )
  }

  backend_response {
    body_bytes = try(
      each.value.apim_diagnostics.backend_response.body_bytes,
      local.default_apim_diagnostics.backend_response.body_bytes
    )
    headers_to_log = try(
      each.value.apim_diagnostics.backend_response.headers_to_log,
      local.default_apim_diagnostics.backend_response.headers_to_log
    )
  }
}

resource "azurerm_api_management_policy_fragment" "cognitive_services_auth" {
  count             = local.apim_config.enabled ? 1 : 0
  api_management_id = module.apim[0].id
  name              = "cognitive-services-auth"
  format            = "rawxml"
  value             = file("${path.root}/../../params/apim/fragments/cognitive-services-auth.xml")
}

resource "azurerm_api_management_policy_fragment" "storage_auth" {
  count             = local.apim_config.enabled ? 1 : 0
  api_management_id = module.apim[0].id
  name              = "storage-auth"
  format            = "rawxml"
  value             = file("${path.root}/../../params/apim/fragments/storage-auth.xml")
}

resource "azurerm_api_management_policy_fragment" "keyvault_auth" {
  count             = local.apim_config.enabled ? 1 : 0
  api_management_id = module.apim[0].id
  name              = "keyvault-auth"
  format            = "rawxml"
  value             = file("${path.root}/../../params/apim/fragments/keyvault-auth.xml")
}

resource "azurerm_api_management_policy_fragment" "openai_usage_logging" {
  count             = local.apim_config.enabled ? 1 : 0
  api_management_id = module.apim[0].id
  name              = "openai-usage-logging"
  format            = "rawxml"
  value             = file("${path.root}/../../params/apim/fragments/openai-usage-logging.xml")
}

resource "azurerm_api_management_policy_fragment" "openai_streaming_metrics" {
  count             = local.apim_config.enabled ? 1 : 0
  api_management_id = module.apim[0].id
  name              = "openai-streaming-metrics"
  format            = "rawxml"
  value             = file("${path.root}/../../params/apim/fragments/openai-streaming-metrics.xml")
}

resource "azurerm_api_management_policy_fragment" "pii_anonymization" {
  count             = local.apim_config.enabled ? 1 : 0
  api_management_id = module.apim[0].id
  name              = "pii-anonymization"
  format            = "rawxml"
  value             = file("${path.root}/../../params/apim/fragments/pii-anonymization.xml")
  depends_on        = [azurerm_api_management_named_value.pii_service_url]
}

resource "azurerm_api_management_policy_fragment" "intelligent_routing" {
  count             = local.apim_config.enabled ? 1 : 0
  api_management_id = module.apim[0].id
  name              = "intelligent-routing"
  format            = "rawxml"
  value             = file("${path.root}/../../params/apim/fragments/intelligent-routing.xml")
}

resource "azurerm_api_management_policy_fragment" "tracking_dimensions" {
  count             = local.apim_config.enabled ? 1 : 0
  api_management_id = module.apim[0].id
  name              = "tracking-dimensions"
  format            = "rawxml"
  value             = file("${path.root}/../../params/apim/fragments/tracking-dimensions.xml")
}

resource "azurerm_api_management_api_policy" "tenant" {
  for_each = {
    for key, policy in local.tenant_api_policies : key => policy
    if local.apim_config.enabled
  }

  api_name            = each.key
  api_management_name = module.apim[0].name
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  xml_content         = each.value

  # Policy XML references fragments, backends, and named values by name.
  # Terraform can't infer these from XML strings, so explicit depends_on is needed.
  depends_on = [
    azurerm_api_management_policy_fragment.cognitive_services_auth,
    azurerm_api_management_policy_fragment.storage_auth,
    azurerm_api_management_policy_fragment.keyvault_auth,
    azurerm_api_management_policy_fragment.openai_usage_logging,
    azurerm_api_management_policy_fragment.openai_streaming_metrics,
    azurerm_api_management_policy_fragment.pii_anonymization,
    azurerm_api_management_policy_fragment.intelligent_routing,
    azurerm_api_management_policy_fragment.tracking_dimensions,
    azurerm_api_management_backend.ai_foundry,
    azurerm_api_management_backend.openai,
    azurerm_api_management_backend.docint,
    azurerm_api_management_backend.storage,
    azurerm_api_management_backend.ai_search,
    azurerm_api_management_backend.speech_services_stt,
    azurerm_api_management_backend.speech_services_tts,
    azurerm_api_management_named_value.ai_foundry_endpoint,
    azurerm_api_management_named_value.openai_endpoint,
    azurerm_api_management_named_value.docint_endpoint,
    azurerm_api_management_named_value.storage_endpoint,
    azurerm_api_management_named_value.ai_search_endpoint,
    azurerm_api_management_named_value.speech_services_endpoint,
    azurerm_api_management_named_value.pii_service_url,
    azurerm_api_management_named_value.speech_services_key,
  ]
}

resource "azurerm_role_assignment" "apim_openai_user" {
  count = local.apim_config.enabled ? 1 : 0

  scope                = data.terraform_remote_state.shared.outputs.ai_foundry_hub_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.apim[0].principal_id
}

resource "azurerm_role_assignment" "apim_docint_user" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.document_intelligence.enabled && local.apim_config.enabled
  }

  scope                = data.terraform_remote_state.tenant[each.key].outputs.tenant_document_intelligence[each.key].id
  role_definition_name = "Cognitive Services User"
  principal_id         = module.apim[0].principal_id
}

resource "azurerm_role_assignment" "apim_storage_reader" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.storage_account.enabled && local.apim_config.enabled
  }

  scope                = data.terraform_remote_state.tenant[each.key].outputs.tenant_storage_accounts[each.key].id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.apim[0].principal_id
}

resource "azurerm_role_assignment" "apim_search_contributor" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.ai_search.enabled && local.apim_config.enabled
  }

  scope                = data.terraform_remote_state.tenant[each.key].outputs.tenant_ai_search[each.key].id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = module.apim[0].principal_id
}

resource "azurerm_role_assignment" "apim_search_service_contributor" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.ai_search.enabled && local.apim_config.enabled
  }

  scope                = data.terraform_remote_state.tenant[each.key].outputs.tenant_ai_search[each.key].id
  role_definition_name = "Search Service Contributor"
  principal_id         = module.apim[0].principal_id
}

resource "azurerm_role_assignment" "apim_speech_services_user" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.speech_services.enabled && local.apim_config.enabled
  }

  scope                = data.terraform_remote_state.tenant[each.key].outputs.tenant_speech_services[each.key].id
  role_definition_name = "Cognitive Services User"
  principal_id         = module.apim[0].principal_id
}

resource "azurerm_role_assignment" "apim_language_service_user" {
  count = var.shared_config.language_service.enabled && local.apim_config.enabled ? 1 : 0

  scope                = data.terraform_remote_state.shared.outputs.language_service_id
  role_definition_name = "Cognitive Services User"
  principal_id         = module.apim[0].principal_id
}

resource "azurerm_role_assignment" "apim_keyvault_secrets_user" {
  count = local.key_rotation_config.rotation_enabled && local.apim_config.enabled && try(data.terraform_remote_state.shared.outputs.hub_key_vault_id, null) != null ? 1 : 0

  scope                = data.terraform_remote_state.shared.outputs.hub_key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.apim[0].principal_id
}

resource "azurerm_api_management_subscription" "tenant" {
  for_each = {
    for key, config in local.tenant_subscriptions : key => config
    if local.apim_config.enabled
  }

  api_management_name = module.apim[0].name
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  display_name        = each.value.display_name
  product_id          = "${module.apim[0].id}/products/${each.value.product_id}"
  state               = each.value.state
  allow_tracing       = each.value.allow_tracing

  # Wait for the entire apim module so that newly-created products are fully
  # provisioned before we create subscriptions against them. Without this,
  # module.apim[0].id is known at plan time (APIM service already exists) and
  # Terraform creates subscriptions in parallel with product creation, causing
  # transient 400 ValidationError from Azure's control plane.
  depends_on = [module.apim]

  lifecycle {
    ignore_changes = [allow_tracing]
  }
}

resource "azurerm_key_vault_secret" "apim_subscription_primary_key" {
  for_each = local.tenants_storing_keys_in_kv

  name            = "${each.key}-apim-primary-key"
  value           = azurerm_api_management_subscription.tenant["${each.key}-subscription"].primary_key
  key_vault_id    = data.terraform_remote_state.shared.outputs.hub_key_vault_id
  expiration_date = timeadd(timestamp(), "2160h")

  lifecycle {
    ignore_changes = [value, tags, expiration_date]
  }
}

resource "azurerm_key_vault_secret" "apim_subscription_secondary_key" {
  for_each = local.tenants_storing_keys_in_kv

  name            = "${each.key}-apim-secondary-key"
  value           = azurerm_api_management_subscription.tenant["${each.key}-subscription"].secondary_key
  key_vault_id    = data.terraform_remote_state.shared.outputs.hub_key_vault_id
  expiration_date = timeadd(timestamp(), "2160h")

  lifecycle {
    ignore_changes = [value, tags, expiration_date]
  }
}

resource "azurerm_key_vault_secret" "apim_rotation_metadata" {
  for_each = {
    for key, config in local.tenants_with_key_rotation : key => config
  }

  name = "${each.key}-apim-rotation-metadata"
  value = jsonencode({
    last_rotated_slot = "none"
    last_rotation_at  = "never"
    next_rotation_at  = "pending"
    rotation_number   = 0
    safe_slot         = "primary"
  })
  key_vault_id    = data.terraform_remote_state.shared.outputs.hub_key_vault_id
  content_type    = "application/json"
  expiration_date = timeadd(timestamp(), "2160h")

  lifecycle {
    ignore_changes = [value, tags, expiration_date]
  }
}

resource "azurerm_api_management_api" "landing_page" {
  count = local.apim_config.enabled ? 1 : 0

  name                  = "landing-page"
  resource_group_name   = data.terraform_remote_state.shared.outputs.resource_group_name
  api_management_name   = module.apim[0].name
  revision              = "1"
  display_name          = "Landing Page"
  description           = "Static landing page served at the API gateway root URL"
  path                  = ""
  protocols             = ["https"]
  subscription_required = false
  api_type              = "http"
}

resource "azurerm_api_management_api_operation" "landing_page_get" {
  count = local.apim_config.enabled ? 1 : 0

  operation_id        = "get-landing-page"
  api_name            = azurerm_api_management_api.landing_page[0].name
  api_management_name = module.apim[0].name
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  display_name        = "Landing Page"
  method              = "GET"
  url_template        = "/"
  description         = "Returns the AI Services Hub landing page"

  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_policy" "landing_page" {
  count = local.apim_config.enabled ? 1 : 0

  api_name            = azurerm_api_management_api.landing_page[0].name
  api_management_name = module.apim[0].name
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  xml_content         = file("${path.root}/../../params/apim/landing_page_policy.xml")
}

resource "azurerm_api_management_api_operation" "tenant_methods" {
  for_each = local.tenant_api_operations

  operation_id        = "catchall-${lower(each.value.method)}"
  api_name            = each.value.tenant
  api_management_name = module.apim[0].name
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  display_name        = "Catch All ${each.value.method}"
  method              = each.value.method
  url_template        = "/*"
  description         = "Catch-all ${each.value.method} operation for path-based routing to tenant services"

  # Wait for the entire apim module so that newly-created APIs are fully
  # provisioned before we add operations to them. Without this,
  # module.apim[0].name is known at plan time and Terraform creates operations
  # in parallel with API creation, causing transient 400 ValidationError.
  depends_on = [module.apim]

  response {
    status_code = 200
  }
}

resource "azurerm_api_management_product_api" "tenant" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if local.apim_config.enabled
  }

  api_name            = each.key
  product_id          = each.key
  api_management_name = module.apim[0].name
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name

  # Wait for the entire apim module so that newly-created products and APIs are
  # fully provisioned before we associate them. Without this, both api_name and
  # product_id are string literals resolved at plan time, giving Terraform no
  # apply-time dependency on module.apim, causing transient 404 Not Found.
  depends_on = [module.apim]
}

resource "azapi_resource" "defender_api_collection" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if local.apim_config.enabled && var.defender_enabled
  }

  type      = "Microsoft.Security/apiCollections@2023-11-15"
  name      = each.key
  parent_id = module.apim[0].id
  body      = {}
}
