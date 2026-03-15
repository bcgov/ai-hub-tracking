# Container App Environment Module
# Raw Terraform — replaces AVM module for reliability.

# =============================================================================
# CONTAINER APP ENVIRONMENT
# =============================================================================
resource "azurerm_container_app_environment" "main" {
  name                               = var.name
  location                           = var.location
  resource_group_name                = var.resource_group_name
  log_analytics_workspace_id         = var.log_analytics_workspace_id
  infrastructure_subnet_id           = var.infrastructure_subnet_id
  infrastructure_resource_group_name = "ME-${var.resource_group_name}"
  internal_load_balancer_enabled     = var.internal_load_balancer_enabled
  zone_redundancy_enabled            = var.zone_redundancy_enabled
  mutual_tls_enabled                 = var.mtls_enabled

  # Consumption workload profile (serverless)
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  # Additional workload profiles (dedicated compute)
  dynamic "workload_profile" {
    for_each = var.workload_profiles
    content {
      name                  = workload_profile.value.name
      workload_profile_type = workload_profile.value.workload_profile_type
      minimum_count         = workload_profile.value.minimum_count
      maximum_count         = workload_profile.value.maximum_count
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# Private Endpoint for Container Apps Environment
# Note: DNS zone association will be automatically managed by Azure Policy
resource "azurerm_private_endpoint" "containerapps" {
  name                = "${var.name}-containerapps-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.name}-containerapps-psc"
    private_connection_resource_id = azurerm_container_app_environment.main.id
    subresource_names              = ["managedEnvironments"]
    is_manual_connection           = false
  }

  tags = var.tags

  # Lifecycle block to ignore DNS zone group changes managed by Azure Policy
  lifecycle {
    ignore_changes = [
      private_dns_zone_group,
      tags
    ]
  }
}

# =============================================================================
# WAIT FOR POLICY-MANAGED DNS ZONE GROUPS
# Uses shared script to wait for Azure Policy to create DNS zone groups
# =============================================================================

# Wait for CAE PE DNS zone group (managed by Azure Policy)
resource "null_resource" "wait_for_dns_cae" {
  count = var.scripts_dir != "" ? 1 : 0

  triggers = {
    private_endpoint_id   = azurerm_private_endpoint.containerapps.id
    resource_group_name   = var.resource_group_name
    private_endpoint_name = azurerm_private_endpoint.containerapps.name
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

  depends_on = [azurerm_private_endpoint.containerapps]
}

# =============================================================================
# DIAGNOSTIC SETTINGS
# =============================================================================
# Environment-level sink that aggregates telemetry for ALL container apps
# running inside this managed environment.
#
# Log categories:
#   ContainerAppConsoleLogs  — stdout/stderr from every container
#     LAW table: ContainerAppConsoleLogs_CL
#   ContainerAppSystemLogs   — platform events (scaling, restarts, health)
#     LAW table: ContainerAppSystemLogs_CL
#   AllMetrics               — replica count, CPU/memory, request concurrency
# =============================================================================
resource "azurerm_monitor_diagnostic_setting" "cae" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "${var.name}-diagnostics"
  target_resource_id         = azurerm_container_app_environment.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerAppConsoleLogs"
  }

  enabled_log {
    category = "ContainerAppSystemLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
