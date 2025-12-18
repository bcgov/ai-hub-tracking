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

# Ephemeral self-hosted runner VM outputs (used by GitHub Actions)
output "self_hosted_runner_vm_name" {
  description = "Name of the ephemeral self-hosted runner VM"
  value       = module.self_hosted_runner_vm.vm_name
}

output "self_hosted_runner_vm_id" {
  description = "Resource ID of the ephemeral self-hosted runner VM"
  value       = module.self_hosted_runner_vm.vm_id
}

