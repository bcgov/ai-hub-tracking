# -------------
# Root Level Terraform Configuration
# -------------
# Create the main resource group for all application resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.common_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# -------------
# Modules based on Dependency
# -------------
module "network" {
  source = "./modules/network"

  common_tags              = var.common_tags
  resource_group_name      = azurerm_resource_group.main.name
  vnet_address_space       = var.vnet_address_space
  vnet_name                = var.vnet_name
  vnet_resource_group_name = var.vnet_resource_group_name

  depends_on = [azurerm_resource_group.main]
}

module "bastion" {
  source = "./modules/bastion"

  app_name            = var.app_name
  common_tags         = var.common_tags
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  bastion_subnet_id   = module.network.bastion_subnet_id
  bastion_sku         = "Basic"

  depends_on = [module.network]
}
module "jumpbox" {
  source = "./modules/jumpbox"

  app_name            = var.app_name
  common_tags         = var.common_tags
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.network.jumpbox_subnet_id
  depends_on          = [module.network]
}

# Shared user-assigned managed identity for GitHub runners (avoids ACR<->runner cycles)
resource "azurerm_user_assigned_identity" "github_runners" {
  count = var.github_runners_aca_enabled ? 1 : 0

  name                = "uami-${var.app_name}-github-runners"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.common_tags

  depends_on = [azurerm_resource_group.main]
}

# GitHub Self-Hosted Runners on Azure Container Apps (AVM-based)
# These runners auto-scale from 0 based on queued jobs
module "github_runners_aca" {
  source = "./modules/github-runners-aca"

  enabled             = var.github_runners_aca_enabled
  postfix             = var.app_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  common_tags         = var.common_tags

  # GitHub configuration
  github_organization = var.github_organization
  github_repository   = var.github_repository
  github_runner_pat   = var.github_runner_pat

  # Networking - use existing subnets
  vnet_id                    = module.network.vnet_id
  container_app_subnet_id    = module.network.container_apps_subnet_id
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id

  # Container configuration
  container_cpu    = var.github_runners_container_cpu
  container_memory = var.github_runners_container_memory
  max_runners      = var.github_runners_max_count

  log_analytics_workspace_creation_enabled = var.github_runners_log_analytics_workspace_creation_enabled
  log_analytics_workspace_id               = var.github_runners_log_analytics_workspace_id

  depends_on = [module.network]
}
