# ============================================================================
# Private Endpoints for AI Foundry and Dependencies
# ============================================================================
# This file orchestrates the creation of private endpoints for AI Foundry
# resources. Supports both same-region and cross-region deployments for
# disaster recovery and multi-region access patterns.

# Data source to extract subnet information from the VNet resource ID
locals {
  # Use vnet_resource_id from private_endpoints block first, fallback to standalone variable
  # Use try() to handle case where both are null (coalesce fails on all-null inputs)
  pe_vnet_resource_id = var.private_endpoints.enabled ? try(
    coalesce(
      var.private_endpoints.vnet_resource_id,
      var.private_endpoints_vnet_resource_id
    ),
    null
  ) : null

  # Use private_dns_zone_rg_id from private_endpoints block first, fallback to standalone variable
  # Use try() to handle case where both are null (coalesce fails on all-null inputs)
  pe_dns_zone_rg_id = var.private_endpoints.enabled ? try(
    coalesce(
      var.private_endpoints.private_dns_zone_rg_id,
      var.private_endpoints_dns_zone_rg_id
    ),
    null
  ) : null
}

data "azurerm_subnet" "subnet" {
  count = var.private_endpoints.enabled ? 1 : 0

  name                 = var.private_endpoints.subnet_name
  virtual_network_name = split("/", local.pe_vnet_resource_id)[8]
  resource_group_name  = split("/", local.pe_vnet_resource_id)[4]

  # Ensure ai_landing_zone creates the subnet before this data source tries to look it up
  depends_on = [module.ai_landing_zone]
}

# Resource group for private endpoints (optional - creates if name specified)
module "resource_group" {
  source = "./modules/resource-group"

  create   = var.private_endpoints.enabled && var.private_endpoints.resource_group_name != null
  name     = var.private_endpoints.resource_group_name
  location = var.private_endpoints.location
  tags     = var.tags
}

locals {
  pe_rg_name = var.private_endpoints.enabled ? (
    var.private_endpoints.resource_group_name != null ? 
      module.resource_group.name : 
      split("/", var.private_endpoints.vnet_resource_id)[4]
  ) : null
  
  location = var.private_endpoints.enabled ? var.private_endpoints.location : null
}

# Private endpoints module - creates all PEs for AI Foundry resources
module "private_endpoints" {
  source = "./modules/private-endpoints"

  enabled                  = var.private_endpoints.enabled
  location                 = local.location
  resource_group_name     = local.pe_rg_name
  subnet_id               = var.private_endpoints.enabled ? data.azurerm_subnet.subnet[0].id : ""
  private_dns_zone_rg_id  = local.pe_dns_zone_rg_id
  tags                    = var.tags
  ai_foundry_name         = local.ai_foundry_name
  foundry_ptn             = module.foundry_ptn
  ai_foundry_definition   = var.ai_foundry_definition
}
