data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  location = var.location
  name     = var.resource_group_name
  tags     = var.tags
}

# used to randomize resource names that are globally unique
resource "random_string" "name_suffix" {
  length  = 4
  special = false
  upper   = false
}

locals {
  # Use existing_zones_resource_group_resource_id from private_dns_zones block first, fallback to standalone variable
  # Use try() to handle case where both are null (coalesce fails on all-null inputs)
  dns_zones_rg_id = try(
    coalesce(
      var.private_dns_zones.existing_zones_resource_group_resource_id,
      var.private_dns_zones_rg_id
    ),
    null
  )
}

# DNS Zones Module - manages private DNS zone references
module "dns_zones" {
  source = "./modules/dns-zones"

  use_platform_landing_zone                 = var.flag_platform_landing_zone
  existing_zones_resource_group_resource_id = local.dns_zones_rg_id
}

# TODO: If using platform landing zone (flag_platform_landing_zone = true), 
# add your private DNS zones creation module here

module "foundry_ptn" {
  source  = "Azure/avm-ptn-aiml-ai-foundry/azurerm"
  version = "0.10.0"

  #configure the base resource
  base_name                  = coalesce(var.name_prefix, "foundry")
  location                   = azurerm_resource_group.this.location
  resource_group_resource_id = azurerm_resource_group.this.id
  #pass through the resource definitions
  ai_foundry               = local.foundry_ai_foundry
  ai_model_deployments     = var.ai_foundry_definition.ai_model_deployments
  ai_projects              = var.ai_foundry_definition.ai_projects
  ai_search_definition     = local.foundry_ai_search_definition
  cosmosdb_definition      = local.foundry_cosmosdb_definition
  create_byor              = var.ai_foundry_definition.create_byor
  create_private_endpoints = false # Cannot use module PEs - they must be in same RG/region as resources
  enable_telemetry         = var.enable_telemetry
  key_vault_definition     = local.foundry_key_vault_definition
  # Note: law_definition removed - not supported in 0.10.0. Use diagnostic_settings instead.
  storage_account_definition = local.foundry_storage_account_definition

  depends_on = [azapi_resource_action.purge_ai_foundry]
}

module "capability_hosts" {
  source = "./modules/capability-hosts"

  ai_foundry_definition = var.ai_foundry_definition
  foundry_ptn           = module.foundry_ptn

  depends_on = [module.foundry_ptn]
}

resource "azapi_resource_action" "purge_ai_foundry" {
  count = var.ai_foundry_definition.purge_on_destroy ? 1 : 0

  method      = "DELETE"
  resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.CognitiveServices/locations/${azurerm_resource_group.this.location}/resourceGroups/${azurerm_resource_group.this.name}/deletedAccounts/${local.ai_foundry_name}"
  type        = "Microsoft.Resources/resourceGroups/deletedAccounts@2021-04-30"
  when        = "destroy"

  depends_on = [time_sleep.purge_ai_foundry_cooldown]
}

resource "time_sleep" "purge_ai_foundry_cooldown" {
  count = var.ai_foundry_definition.purge_on_destroy ? 1 : 0

  destroy_duration = "900s" # 10m

  #depends_on = [module.ai_lz_vnet]
}

# ============================================================================
# AI Landing Zone Module
# ============================================================================
# Provisions the full AI/ML Landing Zone infrastructure including:
# - Virtual Network with subnets
# - Azure Bastion
# - Azure Firewall (optional)
# - Application Gateway (optional)
# - GenAI services (Container Registry, Container Apps, etc.)
# - Knowledge sources (AI Search, Bing Grounding)
# - Jump and Build VMs
# - Private DNS Zones
#
# NOTE: This module contains local provider configurations, so count/for_each cannot be used.
# Set var.deploy_landing_zone = true and configure the component variables to deploy.
# Each component has its own deploy flag (e.g., bastion_definition.deploy = true).

module "ai_landing_zone" {
  source = "git::https://github.com/bcgov/AI-Service-Hub.git?ref=feat/bcgov-landing-zone-changes-1"

  # Required variables
  location            = var.landing_zone_location != null ? var.landing_zone_location : var.location
  resource_group_name = var.landing_zone_resource_group_name != null ? var.landing_zone_resource_group_name : "${var.resource_group_name}-lz"

  # Virtual Network configuration (supports BYO VNet via env var or vnet_definition)
  vnet_definition = local.resolved_vnet_definition

  # Optional naming and tagging
  name_prefix      = var.name_prefix
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  # Platform Landing Zone flag
  flag_platform_landing_zone = var.flag_platform_landing_zone

  # AI Foundry configuration
  ai_foundry_definition = var.landing_zone_ai_foundry_definition

  # Networking components
  bastion_definition     = var.bastion_definition
  firewall_definition    = var.firewall_definition
  app_gateway_definition = var.app_gateway_definition

  # GenAI services
  genai_container_registry_definition  = var.genai_container_registry_definition
  container_app_environment_definition = var.container_app_environment_definition
  genai_app_configuration_definition   = var.genai_app_configuration_definition
  genai_key_vault_definition           = var.genai_key_vault_definition
  genai_storage_account_definition     = var.genai_storage_account_definition
  genai_cosmosdb_definition            = var.genai_cosmosdb_definition

  # Knowledge sources
  ks_ai_search_definition      = var.ks_ai_search_definition
  ks_bing_grounding_definition = var.ks_bing_grounding_definition

  # Virtual machines
  jumpvm_definition  = var.jumpvm_definition
  buildvm_definition = var.buildvm_definition

  # API Management
  apim_definition = var.apim_definition

  # Private DNS zones - use resolved local with coalesce fallback
  private_dns_zones = local.resolved_landing_zone_private_dns_zones
}
