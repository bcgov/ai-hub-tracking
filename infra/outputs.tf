# =============================================================================
# Root Level Outputs - Re-export module outputs
# =============================================================================

# Jumpbox Outputs
output "jumpbox_vm_id" {
  description = "ID of the jumpbox virtual machine"
  value       = module.jumpbox.vm_id
}

output "jumpbox_vm_name" {
  description = "Name of the jumpbox virtual machine"
  value       = module.jumpbox.vm_name
}


output "jumpbox_admin_username" {
  description = "Admin username for SSH access to jumpbox"
  value       = module.jumpbox.admin_username
  sensitive   = false
}


output "jumpbox_auto_shutdown_time" {
  description = "Auto-shutdown time (PST)"
  value       = module.jumpbox.auto_shutdown_time
}

output "jumpbox_auto_start_schedule" {
  description = "Auto-start schedule (PST)"
  value       = module.jumpbox.auto_start_schedule
}

# Bastion Outputs
output "bastion_resource_id" {
  description = "Resource ID of Azure Bastion"
  value       = module.bastion.bastion_resource_id
}

output "bastion_fqdn" {
  description = "FQDN of the Bastion service"
  value       = module.bastion.bastion_fqdn
}

# GitHub Runners on Azure Container Apps outputs
output "github_runners_environment_name" {
  description = "Name of the Container App Environment for GitHub runners"
  value       = module.github_runners_aca.container_app_environment_name
}

output "github_runners_job_name" {
  description = "Name of the Container App Job running the GitHub runner"
  value       = module.github_runners_aca.container_app_job_name
}

output "github_runners_label" {
  description = "The label to use in workflow runs-on to target these runners"
  value       = module.github_runners_aca.runner_label
}

output "github_runners_acr_name" {
  description = "Name of the Azure Container Registry for runner images"
  value       = module.github_runners_aca.container_registry_name
}

