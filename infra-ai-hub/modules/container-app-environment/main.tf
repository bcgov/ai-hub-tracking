# Container App Environment Module
# Uses Azure Verified Module for CAE with VNet integration
# https://github.com/Azure/terraform-azurerm-avm-res-app-managedenvironment

# =============================================================================
# CONTAINER APP ENVIRONMENT (using AVM)
# =============================================================================
module "container_app_environment" {
  source  = "Azure/avm-res-app-managedenvironment/azurerm"
  version = "0.3.0"

  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  # VNet integration
  infrastructure_subnet_id = var.infrastructure_subnet_id

  # Workload profiles (optional - enables dedicated workload profiles)
  workload_profile = var.workload_profiles

  # Internal load balancer (private only access)
  internal_load_balancer_enabled = var.internal_load_balancer_enabled

  # Zone redundancy
  zone_redundancy_enabled = var.zone_redundancy_enabled

  # Log Analytics workspace (using resource_id format required by AVM)
  log_analytics_workspace = var.log_analytics_workspace_id != null ? {
    resource_id = var.log_analytics_workspace_id
  } : null

  # mTLS and peer authentication
  peer_authentication_enabled = var.mtls_enabled

  # Diagnostic settings
  diagnostic_settings = var.log_analytics_workspace_id != null ? {
    to_law = {
      name                  = "${var.name}-diag"
      workspace_resource_id = var.log_analytics_workspace_id
      log_groups            = ["allLogs"]
      metric_categories     = ["AllMetrics"]
    }
  } : {}

  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}
