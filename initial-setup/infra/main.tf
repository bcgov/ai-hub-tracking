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
  dev_address_spaces       = var.dev_address_spaces
  test_address_spaces      = var.test_address_spaces
  prod_address_spaces      = var.prod_address_spaces
  depends_on               = [azurerm_resource_group.main]
}
module "monitoring" {
  source = "./modules/monitoring"

  app_name                     = var.app_name
  common_tags                  = var.common_tags
  location                     = var.location
  log_analytics_retention_days = var.log_analytics_retention_days
  log_analytics_sku            = var.log_analytics_sku
  resource_group_name          = azurerm_resource_group.main.name

  depends_on = [azurerm_resource_group.main, module.network]
}
# Azure Bastion + jumpbox are provisioned by the bcgov/action-deployer-vm-bastion-alz
# action in the tools subscription (see .github/workflows/.deployer.yml), not by this root.

# GitHub Self-Hosted Runners on Azure Container Apps (AVM-based)
# These runners auto-scale from 0 based on queued jobs
module "github_runners_aca" {
  source = "./modules/github-runners-aca"
  count  = var.github_runners_aca_enabled ? 1 : 0

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

# The legacy chisel "azure_proxy" App Service has been removed. Private-endpoint reach for
# dev/test/prod deployments now flows through Azure Bastion native tunnelling — see
# .github/workflows/.deployer-using-secure-tunnel.yml and azure-proxy/privoxy/README.md.
