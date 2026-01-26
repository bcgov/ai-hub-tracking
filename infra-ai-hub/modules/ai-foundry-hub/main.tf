# AI Foundry Hub Module
# Creates a shared Azure AI Foundry account using azapi for latest API features
# Includes optional AI Agent service with network injection capability
#
# IMPORTANT: Resources within this module are serialized via explicit depends_on
# chains to avoid Azure ETag conflicts on concurrent operations against the same
# Cognitive Services account. This allows other modules to run in parallel while
# ensuring AI Foundry operations remain sequential.
#
# Data source for subscription info
data "azurerm_client_config" "current" {}
# -----------------------------------------------------------------------------
# Log Analytics Workspace (optional - or use existing)
# -----------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "this" {
  count = var.log_analytics.enabled && var.log_analytics.workspace_id == null ? 1 : 0

  name                = "${var.name}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.log_analytics.sku
  retention_in_days   = var.log_analytics.retention_days

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

locals {
  # Determine if Log Analytics will be available (for count conditions - must use variables only)
  log_analytics_available = var.log_analytics.enabled || var.log_analytics.workspace_id != null

  # Use existing Log Analytics workspace if provided, otherwise use created one
  log_analytics_workspace_id = var.log_analytics.workspace_id != null ? var.log_analytics.workspace_id : (
    var.log_analytics.enabled ? azurerm_log_analytics_workspace.this[0].id : null
  )

  # AI Foundry location - defaults to var.location if not specified
  # Allows deploying AI services to a different region for model availability
  ai_location = coalesce(var.ai_location, var.location)
}

# -----------------------------------------------------------------------------
# Application Insights (optional)
# Provides monitoring, metrics, and tracing for AI Foundry applications
# -----------------------------------------------------------------------------
resource "azurerm_application_insights" "this" {
  count = var.application_insights.enabled && local.log_analytics_available ? 1 : 0

  name                = coalesce(var.application_insights.name, "${var.name}-appi")
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = local.log_analytics_workspace_id
  application_type    = var.application_insights.application_type

  retention_in_days             = var.application_insights.retention_in_days
  daily_data_cap_in_gb          = var.application_insights.daily_data_cap_in_gb
  sampling_percentage           = var.application_insights.sampling_percentage
  disable_ip_masking            = var.application_insights.disable_ip_masking
  local_authentication_disabled = var.application_insights.local_authentication_disabled

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# -----------------------------------------------------------------------------
# AI Foundry Account (Hub)
# Using azapi for the latest API version and full feature support
# Can be deployed to a different region than the VNet for model availability
# -----------------------------------------------------------------------------
resource "azapi_resource" "ai_foundry" {
  type      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name      = var.name
  location  = local.ai_location # May differ from PE location for model availability
  parent_id = var.resource_group_id

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = var.sku
    }
    properties = {
      customSubDomainName           = var.name
      publicNetworkAccess           = "Disabled"
      disableLocalAuth              = !var.local_auth_enabled
      allowProjectManagement        = true
      restrictOutboundNetworkAccess = false

      networkAcls = {
        defaultAction = var.public_network_access_enabled ? "Allow" : "Deny"
        ipRules       = []
      }
    }
  }

  tags = var.tags

  response_export_values = [
    "properties.endpoint",
    "properties.endpoints",
    "identity.principalId",
    "identity.tenantId"
  ]

  schema_validation_enabled = false

  lifecycle {
    ignore_changes = [tags]
  }
}

# -----------------------------------------------------------------------------
# Private Endpoint for AI Foundry
# DNS zone group is managed by Landing Zone policy - we just create the PE
# -----------------------------------------------------------------------------
resource "azurerm_private_endpoint" "ai_foundry" {
  name                = "${var.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.name}-psc"
    private_connection_resource_id = azapi_resource.ai_foundry.id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags, private_dns_zone_group]
  }
}

# -----------------------------------------------------------------------------
# Wait for policy-managed DNS zone group (uses shared script)
# -----------------------------------------------------------------------------
resource "null_resource" "wait_for_dns" {
  count = var.scripts_dir != "" ? 1 : 0

  triggers = {
    private_endpoint_id = azurerm_private_endpoint.ai_foundry.id
    resource_group_name = var.resource_group_name
    private_endpoint    = azurerm_private_endpoint.ai_foundry.name
    timeout             = var.private_endpoint_dns_wait.timeout
    interval            = var.private_endpoint_dns_wait.poll_interval
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${var.scripts_dir}/wait-for-dns-zone.sh --resource-group ${var.resource_group_name} --private-endpoint-name ${azurerm_private_endpoint.ai_foundry.name} --timeout ${var.private_endpoint_dns_wait.timeout} --interval ${var.private_endpoint_dns_wait.poll_interval}"
  }

  depends_on = [azurerm_private_endpoint.ai_foundry]
}

# -----------------------------------------------------------------------------
# Diagnostic Settings
# -----------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "ai_foundry" {
  count = local.log_analytics_available ? 1 : 0

  name                       = "${var.name}-diag"
  target_resource_id         = azapi_resource.ai_foundry.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# =============================================================================
# AI AGENT SERVICE (Optional)
# Azure AI Agent Service with network injection for VNet integration
# https://learn.microsoft.com/en-us/azure/ai-services/agents/
# =============================================================================
resource "azapi_resource" "ai_agent" {
  count = var.ai_agent.enabled ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name      = "${var.name}-agent"
  location  = var.location
  parent_id = azapi_resource.ai_foundry.id

  identity {
    type = "SystemAssigned"
  }

  body = {
    sku = {
      name = "S0"
    }
    properties = {
      displayName = "AI Agent Service"
      description = "Azure AI Agent Service for orchestration and automation"
    }
  }

  tags = var.tags

  response_export_values = [
    "identity.principalId",
    "properties.internalId"
  ]

  schema_validation_enabled = false

  lifecycle {
    ignore_changes = [tags]
  }

  # Serialize AI Foundry operations to avoid Azure ETag conflicts
  depends_on = [azapi_resource.ai_foundry, azurerm_monitor_diagnostic_setting.ai_foundry]
}

# Private endpoint for AI Agent (if network injection is enabled)
resource "azurerm_private_endpoint" "ai_agent" {
  count = var.ai_agent.enabled && var.ai_agent.network_injection_enabled ? 1 : 0

  name                = "${var.name}-agent-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.ai_agent.subnet_id != null ? var.ai_agent.subnet_id : var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.name}-agent-psc"
    private_connection_resource_id = azapi_resource.ai_agent[0].id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags, private_dns_zone_group]
  }

  # Serialize: PE after agent resource to avoid ETag conflicts
  depends_on = [azapi_resource.ai_agent]
}

# =============================================================================
# BING GROUNDING (Optional)
# Bing Web Search resource for grounding AI models with web data
# https://learn.microsoft.com/en-us/azure/ai-services/bing-web-search/
# =============================================================================
resource "azurerm_cognitive_account" "bing_grounding" {
  count = var.bing_grounding.enabled ? 1 : 0

  name                = "${var.name}-bing"
  resource_group_name = var.resource_group_name
  location            = "global" # Bing resources are global
  kind                = "Bing.Search.v7"
  sku_name            = var.bing_grounding.sku

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }

  # Serialize: Bing after AI Agent operations to avoid ETag conflicts on the parent account
  depends_on = [azapi_resource.ai_agent, azurerm_private_endpoint.ai_agent]
}

# =============================================================================
# PURGE ON DESTROY
# Permanently deletes the AI Foundry account, bypassing soft delete retention
# =============================================================================

# Cooldown period to allow Azure to complete soft delete before purging
resource "time_sleep" "purge_ai_foundry_cooldown" {
  count = var.purge_on_destroy ? 1 : 0

  destroy_duration = "90s"

  depends_on = [azapi_resource.ai_foundry]
}

# Purge the soft-deleted AI Foundry account on destroy
# Uses null_resource with local-exec to gracefully handle 404 errors
# (404 means already purged, which is the desired state)
resource "null_resource" "purge_ai_foundry" {
  count = var.purge_on_destroy ? 1 : 0

  triggers = {
    account_name        = var.name
    location            = local.ai_location
    resource_group_name = var.resource_group_name
    subscription_id     = data.azurerm_client_config.current.subscription_id
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = "az cognitiveservices account purge --name \"${self.triggers.account_name}\" --location \"${self.triggers.location}\" --resource-group \"${self.triggers.resource_group_name}\" --subscription \"${self.triggers.subscription_id}\" 2>&1 || true"
    # The '|| true' ensures we don't fail if account is already purged (404)
  }

  depends_on = [time_sleep.purge_ai_foundry_cooldown]
}



