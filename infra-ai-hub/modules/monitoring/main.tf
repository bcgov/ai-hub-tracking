# ============================================================================
# Monitoring and Observability Resources
# ============================================================================
# This file contains all monitoring, logging, and observability infrastructure
# including Log Analytics Workspace and future diagnostic settings.

module "log_analytics_workspace" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.4.2"
  count   = var.law_definition.resource_id == null ? 1 : 0

  location                                  = var.location
  name                                      = local.log_analytics_workspace_name
  resource_group_name                       = var.resource_group_name
  enable_telemetry                          = false # dont enable telemetry this is to send usage of module to azure.
  log_analytics_workspace_retention_in_days = var.law_definition.retention
  log_analytics_workspace_sku               = var.law_definition.sku
}
