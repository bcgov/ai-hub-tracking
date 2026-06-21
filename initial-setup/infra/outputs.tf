# =============================================================================
# Root Level Outputs - Re-export module outputs
# =============================================================================

# Azure Bastion + jumpbox outputs now come from the bcgov/action-deployer-vm-bastion-alz
# action's own Terraform state (tools subscription), not this root.

# GitHub Runners on Azure Container Apps outputs
output "github_runners_environment_name" {
  description = "Name of the Container App Environment for GitHub runners"
  value       = var.github_runners_aca_enabled ? module.github_runners_aca[0].container_app_environment_name : null
}

output "github_runners_job_name" {
  description = "Name of the Container App Job running the GitHub runner"
  value       = var.github_runners_aca_enabled ? module.github_runners_aca[0].container_app_job_name : null
}

output "github_runners_label" {
  description = "The label to use in workflow runs-on to target these runners"
  value       = var.github_runners_aca_enabled ? module.github_runners_aca[0].runner_label : null
}

output "github_runners_acr_name" {
  description = "Name of the Azure Container Registry for runner images"
  value       = var.github_runners_aca_enabled ? module.github_runners_aca[0].container_registry_name : null
}

