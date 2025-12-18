output "enabled" {
  description = "Whether the runner VM resources are enabled"
  value       = var.enabled
}

output "vm_id" {
  description = "Runner VM resource ID"
  value       = try(azurerm_linux_virtual_machine.runner[0].id, null)
}

output "vm_name" {
  description = "Runner VM name"
  value       = try(azurerm_linux_virtual_machine.runner[0].name, null)
}

output "admin_username" {
  description = "Admin username (random)"
  value       = try(random_string.admin_username[0].result, null)
}

output "private_ip" {
  description = "Runner VM private IP"
  value       = try(azurerm_network_interface.runner[0].ip_configuration[0].private_ip_address, null)
}

output "resource_group_name" {
  description = "Runner VM resource group"
  value       = var.resource_group_name
}
