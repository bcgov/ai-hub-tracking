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

  # Public network access - set to false to restrict to private endpoints only
  public_network_access_enabled = var.public_network_access_enabled

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
# -----------------------------------------------------------------------------
# Wait for policy-managed DNS zone group (uses shared script)
# -----------------------------------------------------------------------------
resource "null_resource" "wait_for_dns_apim" {
  count = var.scripts_dir != "" && var.enable_private_endpoint ? 1 : 0

  triggers = {
    # Use AVM module output - private_endpoints is a map keyed by "primary"
    private_endpoint_id = module.apim.private_endpoints["primary"].id
    resource_group_name = var.resource_group_name
    private_endpoint    = module.apim.private_endpoints["primary"].name
    timeout             = var.private_endpoint_dns_wait.timeout
    interval            = var.private_endpoint_dns_wait.poll_interval
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${var.scripts_dir}/wait-for-dns-zone.sh --resource-group ${var.resource_group_name} --private-endpoint-name ${module.apim.private_endpoints["primary"].name} --timeout ${var.private_endpoint_dns_wait.timeout} --interval ${var.private_endpoint_dns_wait.poll_interval}"
  }

  depends_on = [module.apim]
}
