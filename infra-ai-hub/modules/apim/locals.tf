# =============================================================================
# LOCAL VARIABLES - Use boolean flags known at plan time for for_each keys
# =============================================================================
locals {
  # Private endpoints - use boolean flag (known at plan time) to control creation
  # NOTE: private_dns_zone_resource_ids omitted - Azure Policy manages DNS zone groups
  private_endpoints = var.enable_private_endpoint ? {
    primary = {
      name               = "${var.name}-pe"
      subnet_resource_id = var.private_endpoint_subnet_id
      tags               = var.tags
    }
  } : {}

  # Diagnostic settings - use boolean flag (known at plan time) to control creation
  diagnostic_settings = var.enable_diagnostics ? {
    to_law = {
      name                  = "${var.name}-diag"
      workspace_resource_id = var.log_analytics_workspace_id
      log_groups            = ["allLogs"]
      metric_categories     = ["AllMetrics"]
    }
  } : {}
}
