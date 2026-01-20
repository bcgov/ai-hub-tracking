# ============================================================================
# Naming Conventions
# ============================================================================

locals {
  # AI Foundry hub name with optional prefix and random suffix for global uniqueness
  ai_foundry_name = "${var.name_prefix}-${var.environment_name}-${var.subscription_name}-foundry-${var.subscription_name}"

  # Log Analytics Workspace name with optional prefix
  log_analytics_workspace_name = "${var.name_prefix}-${var.environment_name}-${var.subscription_name}-law"
}

# ============================================================================
# VNet Configuration with Environment Variable Support
# ============================================================================
# Allows vnet_resource_id to be provided via TF_VAR_landing_zone_vnet_resource_id

locals {
  landing_zone_vnet_resource_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.landing_zone_resource_group_name}/providers/Microsoft.Network/virtualNetworks/${var.subscription_name}-${var.environment_name}-vwan-spoke"
  # Determine if using BYO VNet (from env var or vnet_definition)
  use_existing_vnet = true

  # Resolved VNet definition with environment variable override
  # When using existing VNet: construct proper structure with env var taking priority
  # When creating new VNet: pass through vnet_definition as-is
  resolved_vnet_definition = {
    existing_byo_vnet = local.use_existing_vnet ? {
      this_vnet = {
        vnet_resource_id    = local.landing_zone_vnet_resource_id
        firewall_ip_address = try(values(var.vnet_definition.existing_byo_vnet)[0].firewall_ip_address, null)
      }
    } : {}
  }
}

# ============================================================================
# Landing Zone Private DNS Zones Configuration
# ============================================================================
# Coalesce logic to support both object property and standalone variable/env var

locals {
  # Resolved landing zone DNS zone resource group ID
  # Priority: landing_zone_private_dns_zones.existing_zones_resource_group_resource_id > landing_zone_private_dns_zone_existing_rg_id
  # Use try() to handle case where both are null (coalesce fails on all-null inputs)
  lz_dns_zone_rg_id = try(
    coalesce(
      try(var.landing_zone_private_dns_zones.existing_zones_resource_group_resource_id, null),
      var.landing_zone_private_dns_zone_existing_rg_id
    ),
    null
  )

  # Construct the landing zone private DNS zones object with resolved resource group ID
  resolved_landing_zone_private_dns_zones = {
    existing_zones_resource_group_resource_id = local.lz_dns_zone_rg_id
    allow_internet_resolution_fallback        = try(var.landing_zone_private_dns_zones.allow_internet_resolution_fallback, false)
    network_links                             = try(var.landing_zone_private_dns_zones.network_links, {})
  }
}

# ============================================================================
# AI Foundry Configuration
# ============================================================================
# Configuration transformations for AI Foundry resources,
# injecting DNS zone resource IDs and other required parameters.

locals {
  # AI Foundry Hub configuration with DNS zone resource IDs
  foundry_ai_foundry = merge(
    var.ai_foundry_definition.ai_foundry, {
      name = local.ai_foundry_name
    }
  )

}

