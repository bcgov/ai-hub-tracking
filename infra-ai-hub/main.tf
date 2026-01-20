data "azurerm_client_config" "current" {}
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

module "networking" {
  source = "./modules/networking"

  vnet_name                = var.vnet_name
  vnet_resource_group_name = var.vnet_resource_group_name
  tags                     = var.tags
  location                 = var.location
  name_prefix              = var.name_prefix
  vnet_address_spaces      = var.vnet_address_spaces
}
module "monitoring" {
  source = "./modules/monitoring"

  location            = var.location
  resource_group_name = var.resource_group_name
  law_definition      = var.law_definition
}

resource "azapi_resource_action" "purge_ai_foundry" {
  count = var.ai_foundry_definition.purge_on_destroy ? 1 : 0

  method      = "DELETE"
  resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.CognitiveServices/locations/${var.location}/resourceGroups/${azurerm_resource_group.main.name}/deletedAccounts/${local.ai_foundry_name}"
  type        = "Microsoft.Resources/resourceGroups/deletedAccounts@2021-04-30"
  when        = "destroy"

  depends_on = [time_sleep.purge_ai_foundry_cooldown]
}

resource "time_sleep" "purge_ai_foundry_cooldown" {
  count = var.ai_foundry_definition.purge_on_destroy ? 1 : 0

  destroy_duration = "900s" # 10m

  #depends_on = [module.ai_lz_vnet]
}
module "foundry_ptn" {
  source  = "Azure/avm-ptn-aiml-ai-foundry/azurerm"
  version = "0.10.0"

  #configure the base resource
  base_name                  = coalesce(var.name_prefix, "foundry")
  location                   = var.location
  resource_group_resource_id = azurerm_resource_group.main.id

  #pass through the resource definitions
  ai_foundry               = local.foundry_ai_foundry
  ai_model_deployments     = var.ai_foundry_definition.ai_model_deployments
  ai_projects              = var.ai_foundry_definition.ai_projects
  ai_search_definition     = var.ai_foundry_definition.ai_search_definition
  cosmosdb_definition      = var.ai_foundry_definition.cosmosdb_definition
  create_byor              = var.ai_foundry_definition.create_byor
  create_private_endpoints = false # Cannot use module PEs - they must be in same RG/region as resources
  enable_telemetry         = var.enable_telemetry
  key_vault_definition     = var.ai_foundry_definition.key_vault_definition
  # Note: law_definition removed - not supported in 0.10.0. Use diagnostic_settings instead.
  storage_account_definition = var.ai_foundry_definition.storage_account_definition

  depends_on = [azapi_resource_action.purge_ai_foundry]
}

module "capability_hosts" {
  source = "./modules/capability-hosts"

  ai_foundry_definition = var.ai_foundry_definition
  foundry_ptn           = module.foundry_ptn

  depends_on = [module.foundry_ptn]
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
  resource_group_name = azurerm_resource_group.main.name

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
  subscription_id   = var.subscription_id
  client_id         = var.client_id
  tenant_id         = var.tenant_id
}

module "private_endpoints" {
  source = "./modules/private-endpoints"

  enabled               = true
  location              = var.location
  resource_group_name   = azurerm_resource_group.main.name
  subnet_id             = module.networking.private_endpoint_subnet_id
  tags                  = var.tags
  ai_foundry_name       = local.ai_foundry_name
  foundry_ptn           = module.foundry_ptn
  ai_foundry_definition = var.ai_foundry_definition
}
