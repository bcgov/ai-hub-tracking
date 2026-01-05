# =============================================================================
# Root Level Outputs - Re-export module outputs
# =============================================================================

# Jumpbox Outputs
output "jumpbox_vm_id" {
  description = "ID of the jumpbox virtual machine"
  value       = var.enable_jumpbox ? module.jumpbox[0].vm_id : null
}

output "jumpbox_vm_name" {
  description = "Name of the jumpbox virtual machine"
  value       = var.enable_jumpbox ? module.jumpbox[0].vm_name : null
}


output "jumpbox_admin_username" {
  description = "Admin username for SSH access to jumpbox"
  value       = var.enable_jumpbox ? module.jumpbox[0].admin_username : null
  sensitive   = false
}


output "jumpbox_auto_shutdown_time" {
  description = "Auto-shutdown time (PST)"
  value       = var.enable_jumpbox ? module.jumpbox[0].auto_shutdown_time : null
}

output "jumpbox_auto_start_schedule" {
  description = "Auto-start schedule (PST)"
  value       = var.enable_jumpbox ? module.jumpbox[0].auto_start_schedule : null
}

# Bastion Outputs
output "bastion_resource_id" {
  description = "Resource ID of Azure Bastion"
  value       = var.enable_bastion ? module.bastion[0].bastion_resource_id : null
}

output "bastion_fqdn" {
  description = "FQDN of the Bastion service"
  value       = var.enable_bastion ? module.bastion[0].bastion_fqdn : null
}

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

output "proxy_url" {
  description = "URL of the Azure Proxy service"
  value       = var.enable_azure_proxy ? module.azure_proxy[0].proxy_url : null
  sensitive   = true
}
output "proxy_auth" {
  description = "Authentication info for the Azure Proxy service"
  value       = var.enable_azure_proxy ? module.azure_proxy[0].proxy_auth : null
  sensitive   = true
}
