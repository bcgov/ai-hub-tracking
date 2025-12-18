# -----------------------------------------------------------------------------
# GitHub Self-Hosted Runners on Azure Container Apps
# Uses the Azure Verified Module (AVM) for CI/CD Agents and Runners
# https://registry.terraform.io/modules/Azure/avm-ptn-cicd-agents-and-runners/azurerm/latest
# -----------------------------------------------------------------------------

module "github_runners" {
  count   = var.enabled ? 1 : 0
  source  = "Azure/avm-ptn-cicd-agents-and-runners/azurerm"
  version = "0.4.1"

  # Required inputs
  postfix                             = var.postfix
  location                            = var.location
  version_control_system_type         = "github"
  version_control_system_organization = var.github_organization

  # GitHub authentication (PAT-based)
  version_control_system_authentication_method = "pat"
  version_control_system_personal_access_token = var.github_runner_pat

  # Runner scope and target
  version_control_system_runner_scope = "repo"
  version_control_system_repository   = var.github_repository

  # Runner naming - this affects the runner name in GitHub
  version_control_system_agent_name_prefix = "aca-${var.github_repository}"

  # Compute type: Azure Container Apps with KEDA auto-scaling
  compute_types = ["azure_container_app"]

  # Use existing resource group
  resource_group_creation_enabled = false
  resource_group_name             = var.resource_group_name

  # Use existing virtual network and subnets
  virtual_network_creation_enabled = false
  virtual_network_id               = var.vnet_id

  # Container Apps subnet (must be delegated to Microsoft.App/environments)
  container_app_subnet_id = var.container_app_subnet_id

  # Container Registry with private endpoint (no DNS zone creation - policy handles it)
  container_registry_creation_enabled                  = true
  use_private_networking                               = true
  container_registry_private_dns_zone_creation_enabled = false
  container_registry_private_endpoint_subnet_id        = var.private_endpoint_subnet_id

  # Use default container image from Microsoft
  use_default_container_image = true

  # Container App configuration
  container_app_container_cpu    = var.container_cpu
  container_app_container_memory = var.container_memory

  # Scaling configuration
  container_app_min_execution_count      = 0 # Scale to zero when idle
  container_app_max_execution_count      = var.max_runners
  container_app_polling_interval_seconds = 30
  container_app_replica_timeout          = 1800 # 30 minutes max job time

  # Log Analytics - create new one for runner logs
  log_analytics_workspace_creation_enabled  = true
  log_analytics_workspace_retention_in_days = 30

  # Disable NAT Gateway and Public IP (using existing network infrastructure)
  nat_gateway_creation_enabled = false
  public_ip_creation_enabled   = false

  # Disable telemetry
  enable_telemetry = false

  tags = var.common_tags
}
