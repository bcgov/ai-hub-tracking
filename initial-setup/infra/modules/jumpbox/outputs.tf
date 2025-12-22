# -----------------------------------------------------------------------------
# Jumpbox Module Outputs
# -----------------------------------------------------------------------------

output "vm_id" {
  description = "ID of the jumpbox virtual machine"
  value       = azurerm_linux_virtual_machine.jumpbox.id
}

output "vm_name" {
  description = "Name of the jumpbox virtual machine"
  value       = azurerm_linux_virtual_machine.jumpbox.name
}

output "private_ip_address" {
  description = "Private IP address of the jumpbox VM"
  value       = azurerm_network_interface.jumpbox.private_ip_address
}

output "admin_username" {
  description = "Admin username for SSH access"
  value       = random_string.admin_username.result
}

output "principal_id" {
  description = "Principal ID of the VM's managed identity"
  value       = azurerm_linux_virtual_machine.jumpbox.identity[0].principal_id
}

output "ssh_public_key_id" {
  description = "Resource ID of the SSH public key in Azure"
  value       = azapi_resource.ssh_public_key.id
}

output "ssh_private_key_path" {
  description = "Local path to the SSH private key file"
  value       = local_sensitive_file.ssh_private_key.filename
}

output "automation_account_id" {
  description = "ID of the Azure Automation Account for VM scheduling"
  value       = azurerm_automation_account.jumpbox.id
}

output "auto_shutdown_time" {
  description = "Auto-shutdown time (PST)"
  value       = "7:00 PM PST (daily)"
}

output "auto_start_schedule" {
  description = "Auto-start schedule"
  value       = "8:00 AM PST (Monday-Friday only)"
}
