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
  local_auth_enabled            = false # Use managed identity only
  custom_subdomain_name         = "${var.app_name}-${var.app_env}-language"

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

# OpenAI endpoints
resource "azurerm_api_management_named_value" "openai_endpoint" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.openai.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-openai-endpoint"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  # display_name can only contain alphanumeric, periods, underscores, dashes
  display_name = "${local.sanitized_display_names[each.key]}_OpenAI_Endpoint"
  value        = module.tenant[each.key].openai_endpoint
  secret       = false

  depends_on = [module.apim, module.tenant]
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

  name                = "pii-service-url"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  display_name        = "PII_Service_URL"
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

# OpenAI backends
resource "azurerm_api_management_backend" "openai" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.openai.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-openai"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = module.tenant[each.key].openai_endpoint
  description         = "OpenAI backend for ${each.value.display_name}"

  # Authentication handled via policy (authentication-managed-identity)
  # No credentials block needed - managed identity token is set in policy

  depends_on = [module.apim, module.tenant, azurerm_api_management_named_value.openai_endpoint]
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

# Speech Services backends
resource "azurerm_api_management_backend" "speech_services" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.speech_services.enabled && local.apim_config.enabled
  }

  name                = "${each.key}-speech"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = module.apim[0].name
  protocol            = "http"
  url                 = module.tenant[each.key].speech_services_endpoint
  description         = "Speech Services backend for ${each.value.display_name}"

  depends_on = [module.apim, module.tenant, azurerm_api_management_named_value.speech_services_endpoint]
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
    if policy != null && local.apim_config.enabled
  }

  api_name            = each.key
  api_management_name = module.apim[0].name
  resource_group_name = azurerm_resource_group.main.name
  xml_content         = each.value

  depends_on = [
    module.apim,
    azurerm_api_management_named_value.openai_endpoint,
    azurerm_api_management_named_value.docint_endpoint,
    azurerm_api_management_named_value.storage_endpoint,
    azurerm_api_management_named_value.speech_services_endpoint,
    azurerm_api_management_backend.openai,
    azurerm_api_management_backend.docint,
    azurerm_api_management_backend.storage,
    azurerm_api_management_backend.speech_services,
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

# Cognitive Services OpenAI User - for OpenAI endpoints
resource "azurerm_role_assignment" "apim_openai_user" {
  for_each = {
    for key, config in local.enabled_tenants : key => config
    if config.openai.enabled && local.apim_config.enabled
  }

  scope                = module.tenant[each.key].openai_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.apim[0].principal_id

  depends_on = [module.apim, module.tenant]
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

# Store subscription keys in tenant Key Vault (optional - disabled by default)
# WARNING: Only enable if Key Vault does NOT have auto-rotation policies!
# Auto-rotated secrets would break APIM keys since the new value
# won't match the actual APIM subscription key.
resource "azurerm_key_vault_secret" "apim_subscription_primary_key" {
  for_each = {
    for key, config in local.tenants_with_subscription_key : key => config
    if config.key_vault.enabled && local.apim_config.enabled && lookup(lookup(config, "apim_auth", {}), "store_in_keyvault", false)
  }

  name         = "apim-subscription-primary-key"
  value        = azurerm_api_management_subscription.tenant["${each.key}-subscription"].primary_key
  key_vault_id = module.tenant[each.key].key_vault_id

  depends_on = [module.tenant, azurerm_api_management_subscription.tenant]
}

resource "azurerm_key_vault_secret" "apim_subscription_secondary_key" {
  for_each = {
    for key, config in local.tenants_with_subscription_key : key => config
    if config.key_vault.enabled && local.apim_config.enabled && lookup(lookup(config, "apim_auth", {}), "store_in_keyvault", false)
  }

  name         = "apim-subscription-secondary-key"
  value        = azurerm_api_management_subscription.tenant["${each.key}-subscription"].secondary_key
  key_vault_id = module.tenant[each.key].key_vault_id

  depends_on = [module.tenant, azurerm_api_management_subscription.tenant]
}

# -----------------------------------------------------------------------------
# Azure AD App Registrations (for oauth2 auth mode)
# TODO
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Application Gateway (optional, WAF in front of APIM)
# When enabled, APIM becomes internal-only and App GW is the public entry point
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

  waf_enabled = lookup(local.appgw_config, "waf_enabled", true)
  waf_mode    = lookup(local.appgw_config, "waf_mode", "Prevention")

  # SSL certificates from Key Vault
  ssl_certificates = {
    for k, v in lookup(local.appgw_config, "ssl_certificates", {}) : k => {
      name                = v.name
      key_vault_secret_id = v.key_vault_secret_id
    }
  }

  # Backend pointing to APIM
  backend_apim = {
    fqdn       = local.apim_config.enabled ? module.apim[0].gateway_url : ""
    https_port = 443
    probe_path = "/status-0123456789abcdef"
  }

  frontend_hostname = lookup(local.appgw_config, "frontend_hostname", "api.example.com")

  # Key Vault for SSL cert access
  key_vault_id = lookup(local.appgw_config, "key_vault_id", null)

  # Diagnostics
  log_analytics_workspace_id = module.ai_foundry_hub.log_analytics_workspace_id

  tags = var.common_tags

  depends_on = [module.network, module.apim]
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

  openai = {
    enabled = lookup(each.value.openai, "enabled", false)
    sku     = lookup(each.value.openai, "sku", "S0")
    model_deployments = [
      for deployment in lookup(each.value.openai, "model_deployments", []) : {
        name          = deployment.name
        model_name    = deployment.model_name
        model_version = deployment.model_version
        scale_type    = lookup(deployment, "scale_type", "Standard")
        capacity      = lookup(deployment, "capacity", 10)
      }
    ]
    diagnostics = lookup(each.value.openai, "diagnostics", null)
  }

  tags = merge(var.common_tags, lookup(each.value, "tags", {}))

  depends_on = [module.ai_foundry_hub]
}

# -----------------------------------------------------------------------------
# AI Foundry Projects (per tenant)
# This module creates AI Foundry projects and their connections AFTER tenant
# resources are ready. Projects all modify the shared AI Foundry hub.
#
# NOTE: With the current structure, all foundry projects may be created in parallel.
# To avoid ETag conflicts, the connections within each project are serialized.
# If ETag conflicts still occur across tenants, use -parallelism=1 for the targeted
# apply: terraform apply -target=module.foundry_project -parallelism=1
# -----------------------------------------------------------------------------
module "foundry_project" {
  source   = "./modules/foundry-project"
  for_each = local.enabled_tenants

  tenant_name       = each.value.tenant_name
  ai_foundry_hub_id = module.ai_foundry_hub.id
  location          = var.location
  ai_location       = var.shared_config.ai_foundry.ai_location

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

  openai = {
    enabled     = lookup(each.value.openai, "enabled", false)
    resource_id = module.tenant[each.key].openai_id
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
