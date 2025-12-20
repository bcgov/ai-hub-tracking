# -----------------------------------------------------------------------------
# Outputs for GitHub Runners on Azure Container Apps
# -----------------------------------------------------------------------------

output "container_app_environment_name" {
  description = "Name of the Container App Environment"
  value       = var.enabled ? module.github_runners[0].name : null
}

output "container_app_environment_id" {
  description = "Resource ID of the Container App Environment"
  value       = var.enabled ? module.github_runners[0].resource_id : null
}

output "container_app_job_name" {
  description = "Name of the Container App Job running the GitHub runner"
  value       = var.enabled ? module.github_runners[0].job_name : null
}

output "container_app_job_id" {
  description = "Resource ID of the Container App Job"
  value       = var.enabled ? module.github_runners[0].job_resource_id : null
}

output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = var.enabled ? module.github_runners[0].container_registry_name : null
}

output "container_registry_login_server" {
  description = "Login server URL of the Azure Container Registry"
  value       = var.enabled ? module.github_runners[0].container_registry_login_server : null
}

output "runner_label" {
  description = "The label to use in workflow runs-on to target these runners (use just 'self-hosted' for AVM-based runners)"
  value       = "self-hosted"
}
