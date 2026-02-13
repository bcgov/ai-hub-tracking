# =============================================================================
# AI FOUNDRY MULTI-TENANT INFRASTRUCTURE
# =============================================================================
# This is the root module that orchestrates:
# 1. Network (shared PE subnet, APIM subnet for VNet injection, App GW subnet)
# 2. AI Foundry Hub (shared account)
# 3. APIM (shared, with per-tenant products)
# 4. App Gateway (optional, WAF in front of APIM)
# 5. Tenant resources (per-tenant projects and resources)
#
# Configuration is loaded from params/{app_env}/shared and params/{app_env}/tenants
# See locals.tf for configuration loading logic.
# =============================================================================

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# -----------------------------------------------------------------------------
# Resource Group (shared)
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# -----------------------------------------------------------------------------
# Network Module (PE subnet, APIM subnet, AppGW subnet)
# -----------------------------------------------------------------------------
module "network" {
  source = "./modules/network"

  name_prefix = var.resource_group_name
  location    = var.location
  common_tags = var.common_tags

  vnet_name                = var.vnet_name
  vnet_resource_group_name = var.vnet_resource_group_name

  target_vnet_address_spaces   = var.target_vnet_address_spaces
  source_vnet_address_space    = var.source_vnet_address_space
  private_endpoint_subnet_name = var.private_endpoint_subnet_name

  # APIM subnet (enabled when APIM uses VNet injection - Premium v2)
  # Set enabled = false if APIM uses private endpoints only (stv2 style)
  apim_subnet = {
    enabled       = lookup(local.apim_config, "vnet_injection_enabled", false)
    name          = lookup(local.apim_config, "subnet_name", "apim-subnet")
    prefix_length = lookup(local.apim_config, "subnet_prefix_length", 27)
  }

  # App Gateway subnet (enabled when App GW is enabled, auto-placed after PE/APIM subnets)
  appgw_subnet = {
    enabled       = local.appgw_config.enabled
    name          = lookup(local.appgw_config, "subnet_name", "appgw-subnet")
    prefix_length = lookup(local.appgw_config, "subnet_prefix_length", 27)
  }

  depends_on = [azurerm_resource_group.main]
}

# -----------------------------------------------------------------------------
# AI Foundry Hub (shared)
# -----------------------------------------------------------------------------
module "ai_foundry_hub" {
  source = "./modules/ai-foundry-hub"

  name                = "${var.app_name}-${var.app_env}-${var.shared_config.ai_foundry.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  resource_group_id   = azurerm_resource_group.main.id
  location            = var.location

  sku                           = var.shared_config.ai_foundry.sku
  public_network_access_enabled = var.shared_config.ai_foundry.public_network_access_enabled
  local_auth_enabled            = var.shared_config.ai_foundry.local_auth_enabled

  # Cross-region deployment for model availability
  ai_location = var.shared_config.ai_foundry.ai_location

  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id

  log_analytics = {
    enabled        = var.shared_config.log_analytics.enabled
    retention_days = var.shared_config.log_analytics.retention_days
    sku            = var.shared_config.log_analytics.sku
  }

  # Application Insights configuration (enabled by default if log analytics is enabled)
  application_insights = {
    enabled = var.shared_config.log_analytics.enabled
  }

  private_endpoint_dns_wait = {
    timeout       = var.shared_config.private_endpoint_dns_wait.timeout
    poll_interval = var.shared_config.private_endpoint_dns_wait.poll_interval
  }

  scripts_dir      = "${path.module}/scripts"
  purge_on_destroy = var.shared_config.ai_foundry.purge_on_destroy
  tags             = var.common_tags

  depends_on = [module.network]
}

# -----------------------------------------------------------------------------
# Language Service (shared - for PII detection)
# Azure Cognitive Services Text Analytics for enterprise PII detection
# https://learn.microsoft.com/en-us/azure/ai-services/language-service/
# -----------------------------------------------------------------------------
resource "azurerm_cognitive_account" "language_service" {
  count = var.shared_config.language_service.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-language"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "TextAnalytics"
  sku_name            = var.shared_config.language_service.sku

  public_network_access_enabled = var.shared_config.language_service.public_network_access_enabled
  # Use managed identity only - disables key-based authentication for security
  # IMPORTANT: APIM's managed identity role assignment must complete before PII detection works.
  # Transient failures may occur during initial deployment while role assignment propagates.
  local_auth_enabled    = false
  custom_subdomain_name = "${var.app_name}-${var.app_env}-language"

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Deny"
  }

  tags = var.common_tags

  depends_on = [azurerm_resource_group.main]
}

# Private endpoint for Language Service
resource "azurerm_private_endpoint" "language_service" {
  count = var.shared_config.language_service.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-language-pe"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.network.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.app_name}-${var.app_env}-language-psc"
    private_connection_resource_id = azurerm_cognitive_account.language_service[0].id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  # Let Azure Policy manage DNS zone groups (Landing Zone pattern)
  lifecycle {
    ignore_changes = [tags, private_dns_zone_group]
  }

  tags = var.common_tags

  depends_on = [azurerm_cognitive_account.language_service, module.network]
}

# Wait for Language Service DNS zone to be created by Azure Policy
resource "terraform_data" "language_service_dns_wait" {
  count = var.shared_config.language_service.enabled ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${path.module}/scripts/wait-for-dns-zone.sh --resource-group ${azurerm_resource_group.main.name} --private-endpoint-name ${azurerm_private_endpoint.language_service[0].name} --timeout ${var.shared_config.private_endpoint_dns_wait.timeout} --interval ${var.shared_config.private_endpoint_dns_wait.poll_interval}"
  }

  depends_on = [azurerm_private_endpoint.language_service]
}

# -----------------------------------------------------------------------------
# API Management (shared, with per-tenant products) - stv2 with Private Endpoints
# -----------------------------------------------------------------------------
module "apim" {
  source = "./modules/apim"
  count  = local.apim_config.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-apim"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  sku_name        = lookup(local.apim_config, "sku_name", "StandardV2_1")
  publisher_name  = lookup(local.apim_config, "publisher_name", "AI Hub")
  publisher_email = lookup(local.apim_config, "publisher_email", "admin@example.com")

  # Public network access - disabled to enforce private endpoint only access
  public_network_access_enabled = lookup(local.apim_config, "public_network_access_enabled", true)

  # VNet integration for outbound connectivity to private backends
  # Required because backend services (OpenAI, DocInt, etc.) have public network access disabled
  enable_vnet_integration    = lookup(local.apim_config, "vnet_injection_enabled", false)
  vnet_integration_subnet_id = module.network.apim_subnet_id

  # Private endpoint for inbound APIM access
  enable_private_endpoint    = true
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  private_dns_zone_ids       = lookup(local.apim_config, "private_dns_zone_ids", [])

  # Per-tenant products
  tenant_products = local.tenant_products

  # Per-tenant APIs (one API per tenant with path-based routing)
  apis = local.tenant_apis

  # Global policy with PII redaction and prompt injection protection
  global_policy_xml = local.apim_global_policy_xml

  # Diagnostics - Boolean flag known at plan time
  enable_diagnostics         = true
  log_analytics_workspace_id = module.ai_foundry_hub.log_analytics_workspace_id

  tags        = var.common_tags
  scripts_dir = "${path.module}/scripts"

  private_endpoint_dns_wait = {
    timeout       = var.shared_config.private_endpoint_dns_wait.timeout
    poll_interval = var.shared_config.private_endpoint_dns_wait.poll_interval
  }

  depends_on = [module.network, module.ai_foundry_hub]
}

# -----------------------------------------------------------------------------
# APIM Named Values (tenant service endpoints)
# Created separately to reference module.tenant outputs
# -----------------------------------------------------------------------------

# AI Foundry Hub endpoint (shared by all tenants with model deployments)
resource "azurerm_api_management_named_value" "ai_foundry_endpoint" {
  count = local.apim_config.enabled ? 1 : 0

  name                = "ai-foundry-endpoint"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  display_name        = "AI_Foundry_Endpoint"
  value               = module.ai_foundry_hub.endpoint
  secret              = false

  depends_on = [module.apim, module.ai_foundry_hub]
}

# Per-tenant AI model endpoint references (all point to shared AI Foundry Hub)
resource "azurerm_api_management_named_value" "openai_endpoint" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if length(lookup(config.openai, "model_deployments", [])) > 0 && local.apim_config.enabled
  }

  name                = "${each.key}-openai-endpoint"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  # display_name can only contain alphanumeric, periods, underscores, dashes
  display_name = "${local.sanitized_display_names[each.key]}_OpenAI_Endpoint"
  # All tenants share the AI Foundry Hub endpoint
  value  = module.ai_foundry_hub.endpoint
  secret = false

  depends_on = [module.apim, module.ai_foundry_hub]
}

# Document Intelligence endpoints
resource "azurerm_api_management_named_value" "docint_endpoint" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.document_intelligence.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-docint-endpoint"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  # display_name can only contain alphanumeric, periods, underscores, dashes
  display_name = "${local.sanitized_display_names[each.key]}_Document_Intelligence_Endpoint"
  value        = module.tenant[each.key].document_intelligence_endpoint
  secret       = false

  depends_on = [module.apim, module.tenant]
}

# Storage endpoints
resource "azurerm_api_management_named_value" "storage_endpoint" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.storage_account.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-storage-endpoint"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  # display_name can only contain alphanumeric, periods, underscores, dashes
  display_name = "${local.sanitized_display_names[each.key]}_Storage_Endpoint"
  value        = module.tenant[each.key].storage_account_primary_blob_endpoint
  secret       = false

  depends_on = [module.apim, module.tenant]
}

# AI Search endpoints
resource "azurerm_api_management_named_value" "ai_search_endpoint" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.ai_search.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-ai-search-endpoint"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  # display_name can only contain alphanumeric, periods, underscores, dashes
  display_name = "${local.sanitized_display_names[each.key]}_AI_Search_Endpoint"
  value        = module.tenant[each.key].ai_search_endpoint
  secret       = false

  depends_on = [module.apim, module.tenant]
}

# Speech Services endpoints
resource "azurerm_api_management_named_value" "speech_services_endpoint" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.speech_services.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-speech-endpoint"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  # display_name can only contain alphanumeric, periods, underscores, dashes
  display_name = "${local.sanitized_display_names[each.key]}_Speech_Services_Endpoint"
  value        = module.tenant[each.key].speech_services_endpoint
  secret       = false

  depends_on = [module.apim, module.tenant]
}


# Language Service endpoint (shared - for PII detection)
resource "azurerm_api_management_named_value" "pii_service_url" {
  count = var.shared_config.language_service.enabled && local.apim_config.enabled ? 1 : 0

  name                = "piiServiceUrl"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  display_name        = "piiServiceUrl"
  # The PII fragment expects the base endpoint without trailing slash
  value  = trimsuffix(azurerm_cognitive_account.language_service[0].endpoint, "/")
  secret = false

  depends_on = [module.apim, azurerm_cognitive_account.language_service, terraform_data.language_service_dns_wait]
}

# -----------------------------------------------------------------------------
# APIM Backends (for path-based routing to tenant services)
# Each backend uses managed identity for authentication
# NOTE: Content safety opt-out is handled via templatefile() at compile-time
# in tenant API policies, not via Named Values
# -----------------------------------------------------------------------------

# AI Foundry Hub backend (shared by all tenants with model deployments)
resource "azurerm_api_management_backend" "ai_foundry" {
  count = local.apim_config.enabled ? 1 : 0

  name                = "ai-foundry-hub"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = module.ai_foundry_hub.endpoint
  description         = "Shared AI Foundry Hub backend for all tenant model deployments"

  # Authentication handled via policy (authentication-managed-identity)
  # No credentials block needed - managed identity token is set in policy

  depends_on = [module.apim, module.ai_foundry_hub, azurerm_api_management_named_value.ai_foundry_endpoint]
}

# Per-tenant AI model backends (all point to shared AI Foundry Hub)
resource "azurerm_api_management_backend" "openai" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if length(lookup(config.openai, "model_deployments", [])) > 0 && local.apim_config.enabled
  }

  name                = "${each.key}-openai"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  protocol            = "http"
  # All tenants share the AI Foundry Hub endpoint
  url         = module.ai_foundry_hub.endpoint
  description = "OpenAI backend for ${each.value.display_name} (via shared AI Foundry Hub)"

  # Authentication handled via policy (authentication-managed-identity)
  # No credentials block needed - managed identity token is set in policy

  depends_on = [module.apim, module.ai_foundry_hub, azurerm_api_management_named_value.openai_endpoint]
}

# Document Intelligence backends
resource "azurerm_api_management_backend" "docint" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.document_intelligence.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-docint"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = module.tenant[each.key].document_intelligence_endpoint
  description         = "Document Intelligence backend for ${each.value.display_name}"

  depends_on = [module.apim, module.tenant]
}

# Storage backends
resource "azurerm_api_management_backend" "storage" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.storage_account.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-storage"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = module.tenant[each.key].storage_account_primary_blob_endpoint
  description         = "Storage backend for ${each.value.display_name}"

  depends_on = [module.apim, module.tenant]
}

# AI Search backends
resource "azurerm_api_management_backend" "ai_search" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.ai_search.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-ai-search"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = module.tenant[each.key].ai_search_endpoint
  description         = "AI Search backend for ${each.value.display_name}"

  depends_on = [module.apim, module.tenant, azurerm_api_management_named_value.ai_search_endpoint]
}

# Speech Services backends (using tenant's custom subdomain endpoint)
# Speech Services with private endpoints require using the custom subdomain endpoint
# Regional endpoints (*.stt.speech.microsoft.com) won't work with private endpoints
resource "azurerm_api_management_backend" "speech_services_stt" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.speech_services.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-speech-stt"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = trimsuffix(module.tenant[each.key].speech_services_endpoint, "/")
  description         = "Speech Services STT backend for ${each.value.display_name}"

  credentials {
    header = {
      "Ocp-Apim-Subscription-Key" = format("{{%s-speech-key}}", each.key)
    }
  }

  depends_on = [module.apim, module.tenant, azurerm_api_management_named_value.speech_services_key]
}

resource "azurerm_api_management_backend" "speech_services_tts" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.speech_services.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-speech-tts"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = trimsuffix(module.tenant[each.key].speech_services_endpoint, "/")
  description         = "Speech Services TTS backend for ${each.value.display_name}"

  credentials {
    header = {
      "Ocp-Apim-Subscription-Key" = format("{{%s-speech-key}}", each.key)
    }
  }

  depends_on = [module.apim, module.tenant, azurerm_api_management_named_value.speech_services_key]
}

# Speech Services keys (for Speech REST/WS auth)
resource "azurerm_api_management_named_value" "speech_services_key" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.speech_services.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-speech-key"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  # display_name can only contain alphanumeric, periods, underscores, dashes
  display_name = "${replace(local.sanitized_display_names[each.key], "-", "_")}_Speech_Services_Key"
  value        = module.tenant[each.key].speech_services_primary_key
  secret       = true

  depends_on = [module.apim, module.tenant]
}

# -----------------------------------------------------------------------------
# APIM Application Insights Logger (for token metrics and request logging)
# Uses connection string with managed identity for secure telemetry
# -----------------------------------------------------------------------------
resource "azurerm_api_management_logger" "app_insights" {
  count = local.apim_config.enabled && local.application_insights_enabled ? 1 : 0

  name                = "${module.apim[0].name}-appinsights-logger"
  api_management_name = module.apim[0].name
  resource_group_name = azurerm_resource_group.main.name
  resource_id         = module.ai_foundry_hub.application_insights_id

  application_insights {
    connection_string = module.ai_foundry_hub.application_insights_connection_string
  }

  depends_on = [module.apim, module.ai_foundry_hub]
}

# APIM Diagnostics - Enable Application Insights logging for all APIs
resource "azurerm_api_management_diagnostic" "app_insights" {
  count = local.apim_config.enabled && local.application_insights_enabled ? 1 : 0

  identifier               = "applicationinsights"
  resource_group_name      = azurerm_resource_group.main.name
  api_management_name      = module.apim[0].name
  api_management_logger_id = azurerm_api_management_logger.app_insights[0].id

  # Sampling settings (100% for debugging, reduce in production)
  sampling_percentage = 100

  # Log settings
  always_log_errors         = true
  log_client_ip             = true
  http_correlation_protocol = "W3C"
  verbosity                 = "information"

  # Request/Response body logging (limit size for performance)
  frontend_request {
    body_bytes = 1024
    headers_to_log = [
      "X-Tenant-Id",
      "X-Request-ID",
      "Content-Type",
      "Authorization"
    ]
  }

  frontend_response {
    body_bytes = 1024
    headers_to_log = [
      "x-ms-request-id",
      "x-ratelimit-remaining-tokens",
      "x-tokens-consumed"
    ]
  }

  backend_request {
    body_bytes = 1024
    headers_to_log = [
      "Authorization",
      "api-key"
    ]
  }

  backend_response {
    body_bytes = 1024
    headers_to_log = [
      "x-ms-region",
      "x-ratelimit-remaining-tokens"
    ]
  }

  depends_on = [azurerm_api_management_logger.app_insights]
}

# -----------------------------------------------------------------------------
# PER-TENANT APIM DIAGNOSTICS
# Creates per-tenant Application Insights loggers for APIM API diagnostics
# When tenant has their own LAW, we use their dedicated App Insights
# This ensures APIM API logs flow to the tenant's Log Analytics Workspace
# -----------------------------------------------------------------------------

# Per-tenant Application Insights loggers (only for tenants with dedicated LAW)
# These loggers use the tenant's own Application Insights which is linked to their LAW
resource "azurerm_api_management_logger" "tenant_app_insights" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if local.apim_config.enabled && lookup(config.log_analytics, "enabled", false)
  }

  name                = "${module.apim[0].name}-${each.key}-appinsights"
  api_management_name = module.apim[0].name
  resource_group_name = azurerm_resource_group.main.name

  # Use tenant's own Application Insights (linked to tenant LAW)
  # This ensures APIM API logs flow directly to the tenant's Log Analytics Workspace
  application_insights {
    instrumentation_key = module.tenant[each.key].application_insights_instrumentation_key
  }

  depends_on = [module.apim, module.tenant, module.ai_foundry_hub]
}

# Per-tenant API diagnostics - routes API logs to tenant's LAW if enabled
# Falls back to central Application Insights logger if tenant LAW is not enabled
resource "azurerm_api_management_api_diagnostic" "tenant" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if local.apim_config.enabled
  }

  identifier          = "applicationinsights"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  api_name            = each.key

  # Use tenant-specific logger if they have their own LAW, otherwise use shared App Insights
  api_management_logger_id = lookup(each.value.log_analytics, "enabled", false) ? (
    azurerm_api_management_logger.tenant_app_insights[each.key].id
    ) : (
    local.application_insights_enabled ? azurerm_api_management_logger.app_insights[0].id : null
  )

  # Get tenant-specific diagnostics config or use defaults
  sampling_percentage       = try(each.value.apim_diagnostics.sampling_percentage, local.default_apim_diagnostics.sampling_percentage)
  always_log_errors         = try(each.value.apim_diagnostics.always_log_errors, local.default_apim_diagnostics.always_log_errors)
  log_client_ip             = try(each.value.apim_diagnostics.log_client_ip, local.default_apim_diagnostics.log_client_ip)
  http_correlation_protocol = try(each.value.apim_diagnostics.http_correlation_protocol, local.default_apim_diagnostics.http_correlation_protocol)
  verbosity                 = try(each.value.apim_diagnostics.verbosity, local.default_apim_diagnostics.verbosity)

  # Frontend request logging
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

  # Frontend response logging
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

  # Backend request logging
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

  # Backend response logging
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

  depends_on = [
    module.apim,
    module.tenant,
    azurerm_api_management_logger.app_insights,
    azurerm_api_management_logger.tenant_app_insights
  ]
}

# -----------------------------------------------------------------------------
# APIM Policy Fragments (reusable policy snippets)
# These can be included in API policies via <include-fragment fragment-id="..." />
# -----------------------------------------------------------------------------
resource "azurerm_api_management_policy_fragment" "cognitive_services_auth" {
  count = local.apim_config.enabled ? 1 : 0

  api_management_id = module.apim[0].id
  name              = "cognitive-services-auth"
  format            = "rawxml"
  value             = file("${path.module}/params/apim/fragments/cognitive-services-auth.xml")

  depends_on = [module.apim]
}

resource "azurerm_api_management_policy_fragment" "storage_auth" {
  count = local.apim_config.enabled ? 1 : 0

  api_management_id = module.apim[0].id
  name              = "storage-auth"
  format            = "rawxml"
  value             = file("${path.module}/params/apim/fragments/storage-auth.xml")

  depends_on = [module.apim]
}

resource "azurerm_api_management_policy_fragment" "keyvault_auth" {
  count = local.apim_config.enabled ? 1 : 0

  api_management_id = module.apim[0].id
  name              = "keyvault-auth"
  format            = "rawxml"
  value             = file("${path.module}/params/apim/fragments/keyvault-auth.xml")

  depends_on = [module.apim]
}

resource "azurerm_api_management_policy_fragment" "openai_usage_logging" {
  count = local.apim_config.enabled ? 1 : 0

  api_management_id = module.apim[0].id
  name              = "openai-usage-logging"
  format            = "rawxml"
  value             = file("${path.module}/params/apim/fragments/openai-usage-logging.xml")

  depends_on = [module.apim]
}

# TODO: Streaming metrics fragment - reserved for future use
# This fragment will be included in outbound policies when streaming response
# detection is implemented. Currently created but not referenced in API policies.
resource "azurerm_api_management_policy_fragment" "openai_streaming_metrics" {
  count = local.apim_config.enabled ? 1 : 0

  api_management_id = module.apim[0].id
  name              = "openai-streaming-metrics"
  format            = "rawxml"
  value             = file("${path.module}/params/apim/fragments/openai-streaming-metrics.xml")

  depends_on = [module.apim]
}

# PII Anonymization fragment via Language Service
# Enabled for tenants with pii_redaction_enabled = true
resource "azurerm_api_management_policy_fragment" "pii_anonymization" {
  count = local.apim_config.enabled ? 1 : 0

  api_management_id = module.apim[0].id
  name              = "pii-anonymization"
  format            = "rawxml"
  value             = file("${path.module}/params/apim/fragments/pii-anonymization.xml")

  depends_on = [module.apim, azurerm_api_management_named_value.pii_service_url]
}

# TODO: Intelligent routing fragment - reserved for future multi-backend support
# This fragment implements priority-based backend selection with throttling awareness.
# Currently created but not referenced in API policies (tenant config has enabled = false by default).
# Will be conditionally included when intelligent_routing.enabled = true in tenant config.
resource "azurerm_api_management_policy_fragment" "intelligent_routing" {
  count = local.apim_config.enabled ? 1 : 0

  api_management_id = module.apim[0].id
  name              = "intelligent-routing"
  format            = "rawxml"
  value             = file("${path.module}/params/apim/fragments/intelligent-routing.xml")

  depends_on = [module.apim]
}

resource "azurerm_api_management_policy_fragment" "tracking_dimensions" {
  count = local.apim_config.enabled ? 1 : 0

  api_management_id = module.apim[0].id
  name              = "tracking-dimensions"
  format            = "rawxml"
  value             = file("${path.module}/params/apim/fragments/tracking-dimensions.xml")

  depends_on = [module.apim]
}

# -----------------------------------------------------------------------------
# APIM API Policies (per-tenant routing policies)
# Applied to each tenant API to route to their services
# -----------------------------------------------------------------------------

resource "azurerm_api_management_api_policy" "tenant" {
  for_each = {
    for key, policy in local.tenant_api_policies : key => policy
    if local.apim_config.enabled
  }

  api_name            = each.key
  api_management_name = module.apim[0].name
  resource_group_name = azurerm_resource_group.main.name
  xml_content         = each.value

  # Dependencies: backends, named values, and fragments must exist before
  # policies reference them. APIM validates backend-id references at policy
  # submission time and returns 400 if they don't exist.
  #
  # depends_on ordering is also correct for destruction: when a backend is
  # removed, Terraform updates the policy first (removing the reference),
  # then destroys the backend.
  depends_on = [
    module.apim,
    # Backends (policy XML references these via set-backend-service backend-id)
    azurerm_api_management_backend.openai,
    azurerm_api_management_backend.docint,
    azurerm_api_management_backend.storage,
    azurerm_api_management_backend.ai_search,
    azurerm_api_management_backend.speech_services_stt,
    azurerm_api_management_backend.speech_services_tts,
    # Named values
    azurerm_api_management_named_value.openai_endpoint,
    azurerm_api_management_named_value.docint_endpoint,
    azurerm_api_management_named_value.storage_endpoint,
    azurerm_api_management_named_value.speech_services_key,
    # Policy fragments
    azurerm_api_management_policy_fragment.cognitive_services_auth,
    azurerm_api_management_policy_fragment.storage_auth,
    azurerm_api_management_policy_fragment.keyvault_auth,
    azurerm_api_management_policy_fragment.openai_usage_logging,
    azurerm_api_management_policy_fragment.openai_streaming_metrics,
    azurerm_api_management_policy_fragment.pii_anonymization,
    azurerm_api_management_policy_fragment.intelligent_routing,
    azurerm_api_management_policy_fragment.tracking_dimensions
  ]
}

# -----------------------------------------------------------------------------
# APIM Managed Identity RBAC Grants (access to tenant resources)
# Grants APIM system-assigned identity access to route requests
# -----------------------------------------------------------------------------

# Cognitive Services OpenAI User - for shared AI Foundry Hub
# All tenant model deployments are on the shared Hub, so only one role assignment is needed
resource "azurerm_role_assignment" "apim_openai_user" {
  count = local.apim_config.enabled ? 1 : 0

  scope                = module.ai_foundry_hub.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.apim[0].principal_id

  depends_on = [module.apim, module.ai_foundry_hub]
}

# Cognitive Services User - for Document Intelligence
resource "azurerm_role_assignment" "apim_docint_user" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.document_intelligence.enabled && local.apim_config.enabled
  }

  scope                = module.tenant[each.key].document_intelligence_id
  role_definition_name = "Cognitive Services User"
  principal_id         = module.apim[0].principal_id

  depends_on = [module.apim, module.tenant]
}

# Storage Blob Data Reader - for Storage endpoints
resource "azurerm_role_assignment" "apim_storage_reader" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.storage_account.enabled && local.apim_config.enabled
  }

  scope                = module.tenant[each.key].storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.apim[0].principal_id

  depends_on = [module.apim, module.tenant]
}

# Search Index Data Contributor - for AI Search endpoints (read/write access)
resource "azurerm_role_assignment" "apim_search_contributor" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.ai_search.enabled && local.apim_config.enabled
  }

  scope                = module.tenant[each.key].ai_search_id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = module.apim[0].principal_id

  depends_on = [module.apim, module.tenant]
}

# Search Service Contributor - for AI Search management operations (list indexes, service stats)
resource "azurerm_role_assignment" "apim_search_service_contributor" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.ai_search.enabled && local.apim_config.enabled
  }

  scope                = module.tenant[each.key].ai_search_id
  role_definition_name = "Search Service Contributor"
  principal_id         = module.apim[0].principal_id

  depends_on = [module.apim, module.tenant]
}

# Cognitive Services User - for Speech Services
resource "azurerm_role_assignment" "apim_speech_services_user" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.speech_services.enabled && local.apim_config.enabled
  }

  scope                = module.tenant[each.key].speech_services_id
  role_definition_name = "Cognitive Services User"
  principal_id         = module.apim[0].principal_id

  depends_on = [module.apim, module.tenant]
}

# Cognitive Services User - for Language Service (shared PII detection)
resource "azurerm_role_assignment" "apim_language_service_user" {
  count = var.shared_config.language_service.enabled && local.apim_config.enabled ? 1 : 0

  scope                = azurerm_cognitive_account.language_service[0].id
  role_definition_name = "Cognitive Services User"
  principal_id         = module.apim[0].principal_id

  depends_on = [module.apim, azurerm_cognitive_account.language_service]
}

# =============================================================================
# HUB KEY VAULT (Centralized - stores ALL tenant rotation keys)
# =============================================================================
# A single hub-level Key Vault that holds APIM subscription keys for all
# tenants. This scales to 1000+ tenants without creating per-tenant KVs for
# rotation. Secret naming convention: {tenant-name}-apim-primary-key, etc.
# APIM's managed identity gets a single RBAC assignment on this vault.
# =============================================================================
module "hub_key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.2"
  count   = local.key_rotation_config.rotation_enabled && local.apim_config.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-hkv"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                       = "standard"
  purge_protection_enabled       = true
  soft_delete_retention_days     = 90
  public_network_access_enabled  = false
  legacy_access_policies_enabled = false # Use RBAC instead

  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  # Let Azure Policy manage DNS zone groups (Landing Zone pattern)
  private_endpoints_manage_dns_zone_group = false

  private_endpoints = {
    primary = {
      subnet_resource_id = module.network.private_endpoint_subnet_id
      tags               = var.common_tags
    }
  }

  role_assignments = {
    # Grant the Terraform deployer (current principal) full secrets access
    deployer_secrets_officer = {
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = data.azurerm_client_config.current.object_id
    }
  }

  diagnostic_settings = {}

  tags             = var.common_tags
  enable_telemetry = false

  depends_on = [azurerm_resource_group.main, module.network]
}

# Wait for hub Key Vault DNS zone to be created by Azure Policy
resource "terraform_data" "hub_kv_dns_wait" {
  count = local.key_rotation_config.rotation_enabled && local.apim_config.enabled ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${path.module}/scripts/wait-for-dns-zone.sh --resource-group ${azurerm_resource_group.main.name} --private-endpoint-name ${module.hub_key_vault[0].private_endpoints["primary"].name} --timeout ${var.shared_config.private_endpoint_dns_wait.timeout} --interval ${var.shared_config.private_endpoint_dns_wait.poll_interval}"
  }

  depends_on = [module.hub_key_vault]
}

# Key Vault Secrets User - for APIM to read subscription keys from hub Key Vault
# Required by the /internal/apim-keys policy endpoint (send-request to KV REST API)
# Single RBAC assignment on hub KV (scales to 1000+ tenants vs. per-tenant assignments)
resource "azurerm_role_assignment" "apim_keyvault_secrets_user" {
  count = local.key_rotation_config.rotation_enabled && local.apim_config.enabled ? 1 : 0

  scope                = module.hub_key_vault[0].resource_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.apim[0].principal_id

  depends_on = [module.apim, module.hub_key_vault]
}

# -----------------------------------------------------------------------------
# APIM Subscriptions (for subscription_key auth mode)
# Creates subscription keys for tenants using key-based authentication
# -----------------------------------------------------------------------------
resource "azurerm_api_management_subscription" "tenant" {
  for_each = {
    for key, config in local.tenant_subscriptions : key => config
    if local.apim_config.enabled
  }

  api_management_name = module.apim[0].name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = each.value.display_name
  product_id          = "${module.apim[0].id}/products/${each.value.product_id}"
  state               = each.value.state
  allow_tracing       = each.value.allow_tracing

  # Azure automatically resets allow_tracing to false after ~1 hour for security
  # Ignore this to prevent perpetual drift on every Terraform run
  lifecycle {
    ignore_changes = [allow_tracing]
  }

  depends_on = [module.apim]
}

# Store subscription keys in hub Key Vault (centralized for all tenants).
# When key rotation is enabled, ALL subscription_key tenants get keys stored.
# Otherwise, respects per-tenant apim_auth.store_in_keyvault setting (stored in tenant KV).
# Secret names are tenant-prefixed: {tenant}-apim-primary-key, {tenant}-apim-secondary-key
# The rotation script manages these secrets after initial seed.
resource "azurerm_key_vault_secret" "apim_subscription_primary_key" {
  for_each = local.tenants_storing_keys_in_kv

  name            = "${each.key}-apim-primary-key"
  value           = azurerm_api_management_subscription.tenant["${each.key}-subscription"].primary_key
  key_vault_id    = module.hub_key_vault[0].resource_id
  expiration_date = timeadd(timestamp(), "2160h") # 90 days; compliant with landing zone policy

  # When key rotation is enabled, the rotation script updates this secret.
  # Ignore value changes to avoid Terraform overwriting rotated keys.
  lifecycle {
    ignore_changes = [value, tags, expiration_date]
  }

  depends_on = [module.hub_key_vault, terraform_data.hub_kv_dns_wait, azurerm_api_management_subscription.tenant]
}

resource "azurerm_key_vault_secret" "apim_subscription_secondary_key" {
  for_each = local.tenants_storing_keys_in_kv

  name            = "${each.key}-apim-secondary-key"
  value           = azurerm_api_management_subscription.tenant["${each.key}-subscription"].secondary_key
  key_vault_id    = module.hub_key_vault[0].resource_id
  expiration_date = timeadd(timestamp(), "2160h") # 90 days

  lifecycle {
    ignore_changes = [value, tags, expiration_date]
  }

  depends_on = [module.hub_key_vault, terraform_data.hub_kv_dns_wait, azurerm_api_management_subscription.tenant]
}

# -----------------------------------------------------------------------------
# APIM Key Rotation - Metadata (seeded by Terraform, managed by script)
# -----------------------------------------------------------------------------
# Rotation metadata tracks which slot was last rotated so the script
# alternates between primary and secondary each cycle.
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
  key_vault_id    = module.hub_key_vault[0].resource_id
  content_type    = "application/json"
  expiration_date = timeadd(timestamp(), "2160h") # 90 days

  lifecycle {
    ignore_changes = [value, tags, expiration_date]
  }

  depends_on = [module.hub_key_vault, terraform_data.hub_kv_dns_wait, azurerm_api_management_subscription.tenant]
}

# -----------------------------------------------------------------------------
# Azure AD App Registrations (for oauth2 auth mode)
# TODO
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# DNS Zone (vanity domain + static Public IP for App Gateway)
# Creates DNS zone and static PIP in a separate resource group.
# All resources have prevent_destroy — safe from terraform destroy.
# The static PIP is injected into App Gateway so DNS never breaks.
# -----------------------------------------------------------------------------
module "dns_zone" {
  source = "./modules/dns-zone"
  count  = local.dns_zone_config.enabled ? 1 : 0

  name_prefix         = "${var.app_name}-${var.app_env}"
  location            = var.location
  dns_zone_name       = local.dns_zone_config.zone_name
  resource_group_name = local.dns_zone_config.resource_group_name
  a_record_ttl        = lookup(local.dns_zone_config, "a_record_ttl", 3600)

  tags = var.common_tags
}

# -----------------------------------------------------------------------------
# WAF Policy (mandatory for WAF_v2 - replaces legacy WAF configuration)
# Azure Advisor recommends migrating from legacy WAF config to WAF policies for
# newer managed rule sets, custom rules, per-rule exclusions, and bot protection.
# -----------------------------------------------------------------------------

module "waf_policy" {
  source = "./modules/waf-policy"
  count  = local.appgw_config.enabled && lookup(local.appgw_config, "waf_policy_enabled", true) ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-waf-policy"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  enabled                          = lookup(local.appgw_config, "waf_enabled", true)
  mode                             = lookup(local.appgw_config, "waf_mode", "Prevention")
  request_body_check               = lookup(local.appgw_config, "request_body_check", true)
  request_body_enforcement         = lookup(local.appgw_config, "request_body_enforcement", true)
  request_body_inspect_limit_in_kb = lookup(local.appgw_config, "request_body_inspect_limit_in_kb", 128)
  max_request_body_size_kb         = lookup(local.appgw_config, "max_request_body_size_kb", 128)
  file_upload_limit_mb             = lookup(local.appgw_config, "file_upload_limit_mb", 100)

  # Rule set overrides for API gateway use case
  # Default OWASP 3.2 + Bot Manager rules trigger false positives on JSON API bodies
  managed_rule_sets = [
    {
      type    = "OWASP"
      version = "3.2"
      rule_group_overrides = [
        {
          # General rules - body parsing errors that false-positive on JSON payloads
          rule_group_name = "General"
          rules = [
            { id = "200002", enabled = false }, # REQBODY_ERROR  — WAF can't parse JSON as form data
            { id = "200003", enabled = false }, # MULTIPART_STRICT_ERROR — not multipart
          ]
        }
      ]
    },
    {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
      rule_group_overrides = [
        {
          # API clients (curl, SDKs) aren't browsers — disable bot detection
          rule_group_name = "UnknownBots"
          rules = [
            { id = "300700", enabled = false }, # Generic unknown bot
            { id = "300300", enabled = false }, # curl user-agent
            { id = "300100", enabled = false }, # Missing common browser headers
          ]
        }
      ]
    }
  ]

  # Keep managed rules enabled by default; use path/header-scoped allow rules
  # for known false positives to avoid broad global exclusions.
  exclusions = []

  # Custom rules with "Allow" action bypass all managed rules for matched traffic.
  # Each service gets its own scoped rule requiring the api-key header so only
  # APIM-authenticated requests skip OWASP/Bot inspection. Unauthenticated
  # requests still receive full managed rule protection.
  #
  # Why per-service Allow rules instead of broad exclusions:
  #   - OpenAI: user prompts trigger SQLi (942xxx), XSS (941xxx), RCE (932xxx), LFI (930xxx)
  #   - Doc Intel JSON: base64Source triggers random OWASP signatures
  #   - AI Search: vectorSearch.profiles.* triggers 930120 (LFI); queries trigger SQLi
  #   - Speech: SSML XML can trigger XSS rules
  custom_rules = [
    {
      # Document Intelligence file uploads (binary content types)
      # No api-key gate needed: content-type filter is already specific enough
      name      = "AllowDocIntelFileUploads"
      priority  = 1
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Contains"
          match_values   = ["documentintelligence", "formrecognizer"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "Content-Type"
          operator       = "Contains"
          match_values = [
            "application/octet-stream",
            "image/",
            "application/pdf",
            "multipart/form-data"
          ]
          transforms = ["Lowercase"]
        }
      ]
    },
    {
      # Document Intelligence JSON requests (base64Source payloads)
      # base64-encoded document bytes match random OWASP patterns
      name      = "AllowDocIntelJsonWithApiKey"
      priority  = 2
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Contains"
          match_values   = ["documentintelligence", "formrecognizer", "documentmodels"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "Content-Type"
          operator       = "Contains"
          match_values   = ["application/json"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "api-key"
          operator       = "Regex"
          match_values   = [".+"]
        }
      ]
    },
    {
      # OpenAI / GPT chat completions and embeddings
      # User prompts routinely contain SQL fragments, HTML, shell commands —
      # all valid LLM input that triggers OWASP SQLi/XSS/RCE/LFI rules
      name      = "AllowOpenAiWithApiKey"
      priority  = 10
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Contains"
          match_values   = ["/openai/"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "api-key"
          operator       = "Regex"
          match_values   = [".+"]
        }
      ]
    },
    {
      # AI Search: index schema, queries, and vector search operations
      # vectorSearch.profiles.* triggers 930120 (LFI); search text triggers SQLi
      name      = "AllowAiSearchWithApiKey"
      priority  = 11
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Contains"
          match_values   = ["/ai-search/"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "api-key"
          operator       = "Regex"
          match_values   = [".+"]
        }
      ]
    },
    {
      # Speech Services: TTS (SSML/XML) and STT (audio binary)
      # SSML <speak> tags can trigger XSS rules
      name      = "AllowSpeechWithApiKey"
      priority  = 12
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Contains"
          match_values   = ["cognitiveservices", "speech/synthesis", "speech/recognition"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "api-key"
          operator       = "Regex"
          match_values   = [".+"]
        }
      ]
    }
  ]

  tags = var.common_tags
}

# -----------------------------------------------------------------------------
# Application Gateway (optional, WAF in front of APIM)
# When enabled, APIM becomes internal-only and App GW is the public entry point.
# Uses static PIP from dns_zone module when dns_zone is enabled.
# -----------------------------------------------------------------------------
module "app_gateway" {
  source = "./modules/app-gateway"
  count  = local.appgw_config.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-appgw"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  subnet_id = module.network.appgw_subnet_id

  sku = {
    name     = lookup(local.appgw_config, "sku_name", "WAF_v2")
    tier     = lookup(local.appgw_config, "sku_tier", "WAF_v2")
    capacity = lookup(local.appgw_config, "capacity", 2)
  }

  autoscale = lookup(local.appgw_config, "autoscale", null) != null ? {
    min_capacity = local.appgw_config.autoscale.min_capacity
    max_capacity = local.appgw_config.autoscale.max_capacity
  } : null

  waf_enabled   = lookup(local.appgw_config, "waf_policy_enabled", true) ? false : lookup(local.appgw_config, "waf_enabled", true)
  waf_mode      = lookup(local.appgw_config, "waf_mode", "Prevention")
  waf_policy_id = lookup(local.appgw_config, "waf_policy_enabled", true) && length(module.waf_policy) > 0 ? module.waf_policy[0].resource_id : null

  # SSL certificate name for HTTPS listener (cert uploaded via CLI/portal)
  # Convention: ai-services-hub-<env>-cert — only set when cert exists on App GW
  ssl_certificate_name = lookup(local.appgw_config, "ssl_certificate_name", null)

  # SSL certificates from Key Vault
  ssl_certificates = {
    for k, v in lookup(local.appgw_config, "ssl_certificates", {}) : k => {
      name                = v.name
      key_vault_secret_id = v.key_vault_secret_id
    }
  }

  # Backend pointing to APIM — FQDN resolves to PE IP via private DNS zone
  # (privatelink.azure-api.net linked to VNet by Azure Landing Zone policy)
  backend_apim = {
    fqdn       = local.apim_config.enabled ? trimsuffix(replace(module.apim[0].gateway_url, "https://", ""), "/") : ""
    https_port = 443
    probe_path = "/status-0123456789abcdef"
  }

  frontend_hostname = lookup(local.appgw_config, "frontend_hostname", "api.example.com")

  # Rewrite rule set to forward original host header to APIM
  # Critical for APIM to rewrite Operation-Location headers correctly for Document Intelligence
  rewrite_rule_set = {
    forward_original_host = {
      name = "forward-original-host"
      rewrite_rules = {
        map_ocp_apim_key_to_api_key = {
          name          = "map-ocp-apim-key-to-api-key"
          rule_sequence = 90
          conditions = {
            ocp_apim_subscription_key_present = {
              variable    = "http_req_Ocp-Apim-Subscription-Key"
              pattern     = ".+"
              ignore_case = false
              negate      = false
            }
          }
          request_header_configurations = {
            api_key = {
              header_name  = "api-key"
              header_value = "{http_req_Ocp-Apim-Subscription-Key}"
            }
          }
        }
        add_x_forwarded_host = {
          name          = "add-x-forwarded-host"
          rule_sequence = 100
          request_header_configurations = {
            x_forwarded_host = {
              header_name  = "X-Forwarded-Host"
              header_value = "{var_host}"
            }
          }
        }
      }
    }
  }

  # Key Vault for SSL cert access
  key_vault_id = lookup(local.appgw_config, "key_vault_id", null)

  # Static PIP from dns-zone module (zero-downtime DNS)
  # When dns_zone is enabled, App GW uses the static PIP instead of creating its own
  public_ip_resource_id = local.dns_zone_config.enabled ? module.dns_zone[0].public_ip_id : null

  # Diagnostics
  enable_diagnostics         = var.shared_config.log_analytics.enabled
  log_analytics_workspace_id = module.ai_foundry_hub.log_analytics_workspace_id

  tags = var.common_tags

  # Ensure DNS zone is fully created before App Gateway references its public IP
  depends_on = [module.network, module.apim, module.waf_policy, module.dns_zone]
}

# ------------------------------------------------------------------------------
# Defender for Cloud
# ------------------------------------------------------------------------------
module "defender" {
  source = "./modules/defender"
  count  = var.defender_enabled ? 1 : 0

  resource_types = var.defender_resource_types
}

# -----------------------------------------------------------------------------
# Tenant Resources (per tenant)
# -----------------------------------------------------------------------------
# CONCURRENCY NOTE: Tenant AI model deployments to the shared AI Foundry Hub 
# can cause ETag conflicts (HTTP 409) when run in parallel. The deploy script
# handles this by running the tenant module with -parallelism=1 during Phase 2.
# See: scripts/deploy-terraform.sh apply-phased

module "tenant" {
  source   = "./modules/tenant"
  for_each = local.enabled_tenants

  tenant_name  = each.value.tenant_name
  display_name = each.value.display_name

  # Optional custom RG name (defaults to {tenant_name}-rg)
  resource_group_name_override = lookup(each.value, "resource_group_name", null)
  location                     = var.location
  ai_location                  = var.shared_config.ai_foundry.ai_location

  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  # Only pass shared LAW if tenant doesn't have their own LAW enabled
  # When tenant has log_analytics.enabled = true, pass null to use tenant's own LAW
  log_analytics_workspace_id = lookup(each.value.log_analytics, "enabled", false) ? null : module.ai_foundry_hub.log_analytics_workspace_id

  private_endpoint_dns_wait = {
    timeout       = var.shared_config.private_endpoint_dns_wait.timeout
    poll_interval = var.shared_config.private_endpoint_dns_wait.poll_interval
  }

  scripts_dir = "${path.module}/scripts"

  log_analytics = {
    enabled        = lookup(each.value.log_analytics, "enabled", false)
    retention_days = lookup(each.value.log_analytics, "retention_days", 30)
    sku            = lookup(each.value.log_analytics, "sku", "PerGB2018")
  }

  # Resource configurations from tenant config file
  key_vault = {
    enabled                    = lookup(each.value.key_vault, "enabled", false)
    sku                        = lookup(each.value.key_vault, "sku", "standard")
    purge_protection_enabled   = lookup(each.value.key_vault, "purge_protection_enabled", true)
    soft_delete_retention_days = lookup(each.value.key_vault, "soft_delete_retention_days", 90)
    diagnostics                = lookup(each.value.key_vault, "diagnostics", null)
  }

  storage_account = {
    enabled                  = lookup(each.value.storage_account, "enabled", false)
    account_tier             = lookup(each.value.storage_account, "account_tier", "Standard")
    account_replication_type = lookup(each.value.storage_account, "account_replication_type", "LRS")
    account_kind             = lookup(each.value.storage_account, "account_kind", "StorageV2")
    access_tier              = lookup(each.value.storage_account, "access_tier", "Hot")
    diagnostics              = lookup(each.value.storage_account, "diagnostics", null)
  }

  ai_search = {
    enabled            = lookup(each.value.ai_search, "enabled", false)
    sku                = lookup(each.value.ai_search, "sku", "basic")
    replica_count      = lookup(each.value.ai_search, "replica_count", 1)
    partition_count    = lookup(each.value.ai_search, "partition_count", 1)
    semantic_search    = lookup(each.value.ai_search, "semantic_search", "disabled")
    local_auth_enabled = lookup(each.value.ai_search, "local_auth_enabled", true)
    diagnostics        = lookup(each.value.ai_search, "diagnostics", null)
  }

  cosmos_db = {
    enabled                      = lookup(each.value.cosmos_db, "enabled", false)
    offer_type                   = lookup(each.value.cosmos_db, "offer_type", "Standard")
    kind                         = lookup(each.value.cosmos_db, "kind", "GlobalDocumentDB")
    consistency_level            = lookup(each.value.cosmos_db, "consistency_level", "Session")
    max_interval_in_seconds      = lookup(each.value.cosmos_db, "max_interval_in_seconds", 5)
    max_staleness_prefix         = lookup(each.value.cosmos_db, "max_staleness_prefix", 100)
    geo_redundant_backup_enabled = lookup(each.value.cosmos_db, "geo_redundant_backup_enabled", false)
    automatic_failover_enabled   = lookup(each.value.cosmos_db, "automatic_failover_enabled", false)
    total_throughput_limit       = lookup(each.value.cosmos_db, "total_throughput_limit", 1000)
    diagnostics                  = lookup(each.value.cosmos_db, "diagnostics", null)
  }

  document_intelligence = {
    enabled     = lookup(each.value.document_intelligence, "enabled", false)
    sku         = lookup(each.value.document_intelligence, "sku", "S0")
    kind        = lookup(each.value.document_intelligence, "kind", "FormRecognizer")
    diagnostics = lookup(each.value.document_intelligence, "diagnostics", null)
  }

  speech_services = {
    enabled     = lookup(each.value.speech_services, "enabled", false)
    sku         = lookup(each.value.speech_services, "sku", "S0")
    diagnostics = lookup(each.value.speech_services, "diagnostics", null)
  }

  # AI Foundry Hub ID (for reference in outputs)
  ai_foundry_hub_id = module.ai_foundry_hub.id

  tags = merge(var.common_tags, lookup(each.value, "tags", {}))

  depends_on = [module.ai_foundry_hub]
}

# -----------------------------------------------------------------------------
# AI Foundry Projects (per tenant)
# This module creates AI Foundry projects, connections, AND model deployments.
# All Hub-modifying resources are in this module so it can run serially.
#
# CONCURRENCY NOTE: This module is applied with -parallelism=1 to avoid ETag
# conflicts when multiple tenants modify the shared AI Foundry Hub.
# See: scripts/deploy-terraform.sh apply-phased
# -----------------------------------------------------------------------------
module "foundry_project" {
  source   = "./modules/foundry-project"
  for_each = local.enabled_tenants

  tenant_name       = each.value.tenant_name
  ai_foundry_hub_id = module.ai_foundry_hub.id
  location          = var.location
  ai_location       = var.shared_config.ai_foundry.ai_location

  # AI Model Deployments (AVM-style map format)
  # Convert from openai.model_deployments config format to ai_model_deployments map format
  ai_model_deployments = {
    for deployment in lookup(each.value.openai, "model_deployments", []) :
    deployment.name => {
      name                   = deployment.name
      rai_policy_name        = lookup(deployment, "rai_policy_name", null)
      version_upgrade_option = lookup(deployment, "version_upgrade_option", "OnceNewDefaultVersionAvailable")
      model = {
        format  = lookup(deployment, "model_format", "OpenAI")
        name    = deployment.model_name
        version = deployment.model_version
      }
      scale = {
        type     = lookup(deployment, "scale_type", "Standard")
        capacity = lookup(deployment, "capacity", 10)
      }
    }
  }

  # Resource references from tenant module (for role assignments and connections)
  # Note: enabled flags come from config (not resource outputs) to ensure plan works
  key_vault = {
    enabled     = lookup(each.value.key_vault, "enabled", false)
    resource_id = module.tenant[each.key].key_vault_id
  }

  storage_account = {
    enabled           = lookup(each.value.storage_account, "enabled", false)
    resource_id       = module.tenant[each.key].storage_account_id
    name              = module.tenant[each.key].storage_account_name
    blob_endpoint_url = module.tenant[each.key].storage_account_primary_blob_endpoint
  }

  ai_search = {
    enabled     = lookup(each.value.ai_search, "enabled", false)
    resource_id = module.tenant[each.key].ai_search_id
  }

  cosmos_db = {
    enabled       = lookup(each.value.cosmos_db, "enabled", false)
    resource_id   = module.tenant[each.key].cosmos_db_id
    database_name = lookup(each.value.cosmos_db, "database_name", "default")
  }


  document_intelligence = {
    enabled     = lookup(each.value.document_intelligence, "enabled", false)
    resource_id = module.tenant[each.key].document_intelligence_id
    endpoint    = module.tenant[each.key].document_intelligence_endpoint
  }

  # Connection toggles (which resources to connect to the project)
  project_connections = lookup(each.value, "project_connections", {})

  tags = merge(var.common_tags, lookup(each.value, "tags", {}))

  depends_on = [
    module.tenant,
    module.ai_foundry_hub
  ]
}

# =============================================================================
# APIM LANDING PAGE - Static HTML at root path
# Serves a branded landing page when users visit the custom domain root URL
# instead of returning a 404. No subscription key required.
# =============================================================================
resource "azurerm_api_management_api" "landing_page" {
  count = local.apim_config.enabled ? 1 : 0

  name                  = "landing-page"
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = module.apim[0].name
  revision              = "1"
  display_name          = "Landing Page"
  description           = "Static landing page served at the API gateway root URL"
  path                  = ""
  protocols             = ["https"]
  subscription_required = false
  api_type              = "http"

  depends_on = [module.apim]
}

resource "azurerm_api_management_api_operation" "landing_page_get" {
  count = local.apim_config.enabled ? 1 : 0

  operation_id        = "get-landing-page"
  api_name            = azurerm_api_management_api.landing_page[0].name
  api_management_name = module.apim[0].name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Landing Page"
  method              = "GET"
  url_template        = "/"
  description         = "Returns the AI Services Hub landing page"

  response {
    status_code = 200
  }

  depends_on = [azurerm_api_management_api.landing_page]
}

resource "azurerm_api_management_api_policy" "landing_page" {
  count = local.apim_config.enabled ? 1 : 0

  api_name            = azurerm_api_management_api.landing_page[0].name
  api_management_name = module.apim[0].name
  resource_group_name = azurerm_resource_group.main.name
  xml_content         = file("${path.module}/params/apim/landing_page_policy.xml")

  depends_on = [azurerm_api_management_api_operation.landing_page_get]
}


resource "azurerm_api_management_api_operation" "tenant_methods" {
  for_each = local.tenant_api_operations

  operation_id        = "catchall-${lower(each.value.method)}"
  api_name            = each.value.tenant
  api_management_name = module.apim[0].name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Catch All ${each.value.method}"
  method              = each.value.method
  url_template        = "/*"
  description         = "Catch-all ${each.value.method} operation for path-based routing to tenant services"

  response {
    status_code = 200
  }

  depends_on = [module.apim]
}

# =============================================================================
# APIM PRODUCT-API LINKS
# Links each tenant's API to their product so subscription keys work
# =============================================================================
resource "azurerm_api_management_product_api" "tenant" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if local.apim_config.enabled
  }

  api_name            = each.key
  product_id          = each.key
  api_management_name = module.apim[0].name
  resource_group_name = azurerm_resource_group.main.name

  depends_on = [module.apim]
}

# =============================================================================
# DEFENDER FOR APIS - ONBOARD APIM APIs
# Onboards each tenant API to Microsoft Defender for APIs for security monitoring
# This resolves: "Azure API Management APIs should be onboarded to Defender for APIs"
# =============================================================================
resource "azapi_resource" "defender_api_collection" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if local.apim_config.enabled && var.defender_enabled
  }

  type = "Microsoft.Security/apiCollections@2023-11-15"
  name = each.key

  # Parent is the APIM service - the API ID is in the name
  parent_id = module.apim[0].id

  body = {}

  depends_on = [
    module.apim,
    module.defender,
    azurerm_api_management_product_api.tenant
  ]
}
