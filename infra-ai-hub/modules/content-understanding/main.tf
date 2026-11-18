# Description: Per-tenant Foundry (AIServices) account in Canada Central hosting Azure Content Understanding, with its model deployments, private endpoint and diagnostics
# =============================================================================
# Content Understanding Module
# =============================================================================
# Creates a tenant-scoped Microsoft Foundry resource (kind = AIServices) that
# hosts Azure Content Understanding, plus the chat-completion and embedding
# model deployments Content Understanding needs.
#
# Why a separate account (not the shared AI Foundry hub):
# - The shared hub runs in Canada East, which is not on Content Understanding's
#   supported-region list. Canada Central is.
#   https://learn.microsoft.com/azure/ai-services/content-understanding/language-region-support
# - Content Understanding defaults and analyzers are scoped to the account, so a
#   per-tenant account keeps tenants isolated and costs attributable.
#
# NOTE: The private endpoint is created in this module, not by AVM, so that it
# waits for the model deployments (see PRIVATE ENDPOINT below). Its DNS zone
# group is policy-managed in the Azure Landing Zone.
# =============================================================================

# =============================================================================
# FOUNDRY (AIServices) ACCOUNT + MODEL DEPLOYMENTS (using AVM Cognitive Services)
# https://github.com/Azure/terraform-azurerm-avm-res-cognitiveservices-account
# =============================================================================
module "account" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.7.1"

  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "AIServices"
  sku_name            = var.sku

  public_network_access_enabled = false
  local_auth_enabled            = false
  custom_subdomain_name         = var.name

  network_acls = {
    default_action = "Deny"
  }

  managed_identities = {
    system_assigned = true
  }

  cognitive_deployments = local.cognitive_deployments

  # Private endpoint is created below (azurerm_private_endpoint.this), after the
  # model deployments. Do not add it back here; see the PRIVATE ENDPOINT section.
  private_endpoints = {}

  # Diagnostic settings managed separately to control lifecycle and prevent drift
  diagnostic_settings = {}

  tags             = var.tags
  enable_telemetry = false
}

# Warn (without failing the plan) when Canada East is selected. The account and
# deployments can be created there, but Content Understanding API calls will
# fail until Microsoft adds the region.
check "content_understanding_region_supported" {
  assert {
    condition     = local.location_normalized != "canadaeast"
    error_message = "Content Understanding is not listed for Canada East (checked 2026-11-16). Use Canada Central unless https://learn.microsoft.com/azure/ai-services/content-understanding/language-region-support now lists Canada East."
  }
}

# =============================================================================
# DIAGNOSTICS (managed separately from AVM to prevent drift)
# =============================================================================
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.enable_diagnostics ? 1 : 0

  name                           = "${var.name}-diag"
  target_resource_id             = module.account.resource_id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = local.diag_log_groups
    content {
      category_group = enabled_log.value
    }
  }

  dynamic "enabled_log" {
    for_each = local.diag_log_categories
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = local.diag_metric_categories
    content {
      category = enabled_metric.value
    }
  }

  # Ignore drift on log_analytics_destination_type - Azure may reset this
  lifecycle {
    ignore_changes = [log_analytics_destination_type]
  }
}

# =============================================================================
# PRIVATE ENDPOINT
# Created here instead of by the AVM module so that it waits for the model
# deployments. In AVM 0.7.1 both the private endpoint and the deployments depend
# only on the account, so they start at the same time. The first TEST apply
# (2026-11-18) failed that way: the private endpoint got a 400
# AccountProvisioningStateInvalid ("account ... in state Accepted") while the
# deployments were being written, most likely because those writes put the
# account back into Accepted. depends_on = [module.account] makes the private
# endpoint wait for every resource in the AVM module, deployments included.
#
# Name, connection name and settings match what AVM 0.7.1 created, so the
# moved block below relocates existing endpoints without replacing them.
# =============================================================================
resource "azurerm_private_endpoint" "this" {
  name                = "pep-${var.name}"
  location            = var.private_endpoint_location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "pse-${var.name}"
    private_connection_resource_id = module.account.resource_id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  lifecycle {
    # DNS zone group is managed by Azure Policy in the Landing Zone
    ignore_changes = [private_dns_zone_group]
  }

  depends_on = [module.account]
}

# State migration: the private endpoint used to live inside the AVM module.
# Existing endpoints (dev: ai-hub-admin, sdpr-invoice-automation; test:
# sdpr-invoice-automation) move to the new address with no changes. Keep this
# block until every environment has applied it.
moved {
  from = module.account.azurerm_private_endpoint.this_unmanaged_dns_zone_groups["primary"]
  to   = azurerm_private_endpoint.this
}

# =============================================================================
# WAIT FOR POLICY-MANAGED DNS ZONE GROUP
# =============================================================================
resource "null_resource" "wait_for_dns" {
  count = var.scripts_dir != "" ? 1 : 0

  triggers = {
    private_endpoint_id   = azurerm_private_endpoint.this.id
    resource_group_name   = var.resource_group_name
    private_endpoint_name = azurerm_private_endpoint.this.name
    timeout               = var.private_endpoint_dns_wait.timeout
    interval              = var.private_endpoint_dns_wait.poll_interval
    scripts_dir           = var.scripts_dir
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      ${self.triggers.scripts_dir}/wait-for-dns-zone.sh \
        --resource-group ${self.triggers.resource_group_name} \
        --private-endpoint-name ${self.triggers.private_endpoint_name} \
        --timeout ${self.triggers.timeout} \
        --interval ${self.triggers.interval}
    EOT
  }

  depends_on = [azurerm_private_endpoint.this]
}
