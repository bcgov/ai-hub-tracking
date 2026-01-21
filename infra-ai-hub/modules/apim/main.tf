# API Management Module (stv2)
# Uses Azure Verified Module for APIM v2 with Private Endpoints (not VNet injection)

# =============================================================================
# API MANAGEMENT SERVICE (using AVM) - stv2 platform
# =============================================================================
module "apim" {
  source  = "Azure/avm-res-apimanagement-service/azurerm"
  version = "0.0.6"

  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email

  sku_name = var.sku_name

  # stv2: No VNet injection - use private endpoints instead
  virtual_network_type = "None"

  # Managed identity for Key Vault access
  managed_identities = {
    system_assigned = true
  }

  # Private endpoints for stv2
  private_endpoints = var.private_endpoint_subnet_id != null ? {
    primary = {
      name                          = "${var.name}-pe"
      subnet_resource_id            = var.private_endpoint_subnet_id
      private_dns_zone_resource_ids = var.private_dns_zone_ids

      tags = var.tags
    }
  } : {}

  # Per-tenant products
  products = {
    for tenant_name, config in var.tenant_products : tenant_name => {
      display_name          = config.display_name
      description           = config.description
      subscription_required = config.subscription_required
      approval_required     = config.approval_required
      state                 = config.state
    }
  }

  # APIs
  apis = var.apis

  # Subscriptions
  subscriptions = var.subscriptions

  # Named Values (for secrets and configuration)
  named_values = var.named_values

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

# =============================================================================
# GLOBAL POLICY (optional XML policy at service level)
# =============================================================================
resource "azurerm_api_management_policy" "global" {
  count = var.global_policy_xml != null ? 1 : 0

  api_management_id = module.apim.resource_id
  xml_content       = var.global_policy_xml
}
