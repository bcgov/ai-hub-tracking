output "name" {
  description = "The name of the resource group."
  value       = var.create ? azurerm_resource_group.this[0].name : null
}

output "id" {
  description = "The resource ID of the resource group."
  value       = var.create ? azurerm_resource_group.this[0].id : null
}

output "location" {
  description = "The location of the resource group."
  value       = var.create ? azurerm_resource_group.this[0].location : null
}
