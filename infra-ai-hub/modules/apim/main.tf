# API Management Module (stv2)
# Uses Azure Verified Module for APIM v2 with Private Endpoints (not VNet injection)

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

  # VNet integration for outbound connectivity to private backends
  # StandardV2/PremiumV2 use "External" type with subnet for outbound VNet injection
  virtual_network_type = var.enable_vnet_integration ? "External" : "None"

  # Subnet ID for VNet integration (required when virtual_network_type is not None)
  virtual_network_subnet_id = var.enable_vnet_integration ? var.vnet_integration_subnet_id : null

  # Managed identity for Key Vault access and backend authentication
  managed_identities = {
    system_assigned = true
  }

  # CRITICAL: Set to false to let Azure Policy manage DNS zone groups
  private_endpoints_manage_dns_zone_group = false

  # Private endpoints for stv2 (using static keys from local)
  private_endpoints = local.private_endpoints

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

  # Diagnostic settings (using static keys from local)
  diagnostic_settings = local.diagnostic_settings

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
