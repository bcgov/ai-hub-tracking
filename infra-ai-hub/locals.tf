# ============================================================================
# Naming Conventions
# ============================================================================

locals {
  # AI Foundry hub name with optional prefix and random suffix for global uniqueness
  ai_foundry_name = try(var.ai_foundry_definition.name, null) != null ? var.ai_foundry_definition.name : (var.name_prefix != null ? "${var.name_prefix}-ai-foundry-${random_string.name_suffix.result}" : "ai-foundry-${random_string.name_suffix.result}")

  # Log Analytics Workspace name with optional prefix
  log_analytics_workspace_name = try(var.law_definition.name, null) != null ? var.law_definition.name : (var.name_prefix != null ? "${var.name_prefix}-law" : "ai-alz-law")
}

# ============================================================================
# VNet Configuration with Environment Variable Support
# ============================================================================
# Allows vnet_resource_id to be provided via TF_VAR_landing_zone_vnet_resource_id

locals {
  # Determine if using BYO VNet (from env var or vnet_definition)
  use_existing_vnet = var.landing_zone_vnet_resource_id != null || length(try(var.vnet_definition.existing_byo_vnet, {})) > 0

  # Resolved VNet definition with environment variable override
  # When using existing VNet: construct proper structure with env var taking priority
  # When creating new VNet: pass through vnet_definition as-is
  resolved_vnet_definition = {
    name          = local.use_existing_vnet ? null : try(var.vnet_definition.name, null)
    address_space = local.use_existing_vnet ? null : try(var.vnet_definition.address_space, "192.168.0.0/20")
    dns_servers   = local.use_existing_vnet ? [] : try(var.vnet_definition.dns_servers, [])
    existing_byo_vnet = local.use_existing_vnet ? {
      this_vnet = {
        vnet_resource_id    = coalesce(var.landing_zone_vnet_resource_id, try(values(var.vnet_definition.existing_byo_vnet)[0].vnet_resource_id, null))
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
      # Network injection disabled - requires Azure support enablement
      # network_injections = [{
      #   scenario                   = "agent"
      #   subnetArmId                = data.azurerm_subnet.primary_pe_subnet.id
      #   useMicrosoftManagedNetwork = false
      # }]
      private_dns_zone_resource_ids = [
        module.dns_zones.ai_foundry_zones.openai.resource_id,
        module.dns_zones.ai_foundry_zones.ai_services.resource_id,
        module.dns_zones.ai_foundry_zones.cognitive_services.resource_id
      ]
    }
  )

  # AI Search configuration with DNS zone resource IDs
  foundry_ai_search_definition = { for key, value in var.ai_foundry_definition.ai_search_definition : key => merge(
    var.ai_foundry_definition.ai_search_definition[key], {
      private_dns_zone_resource_id = module.dns_zones.ai_search_zone.resource_id
    }
  ) }

  # Cosmos DB configuration with DNS zone resource IDs
  foundry_cosmosdb_definition = { for key, value in var.ai_foundry_definition.cosmosdb_definition : key => merge(
    var.ai_foundry_definition.cosmosdb_definition[key], {
      private_dns_zone_resource_id = module.dns_zones.cosmos_zone.resource_id
    }
  ) }

  # Key Vault configuration with DNS zone resource IDs
  foundry_key_vault_definition = { for key, value in var.ai_foundry_definition.key_vault_definition : key => merge(
    var.ai_foundry_definition.key_vault_definition[key], {
      private_dns_zone_resource_id = module.dns_zones.key_vault_zone.resource_id
    }
  ) }

  # Storage Account configuration with DNS zone resource IDs for each endpoint type
  foundry_storage_account_definition = { for key, value in var.ai_foundry_definition.storage_account_definition : key => merge(
    var.ai_foundry_definition.storage_account_definition[key], {
      endpoints = {
        for ek, ev in value.endpoints :
        ek => {
          private_dns_zone_resource_id = module.dns_zones.storage_zones[lower(ek)].resource_id
          type                         = lower(ek)
        }
      }
    }
  ) }
}

