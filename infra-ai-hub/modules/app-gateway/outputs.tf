output "id" {
  description = "Resource ID of the Application Gateway"
  value       = azurerm_application_gateway.this.id
}

output "name" {
  description = "Name of the Application Gateway"
  value       = azurerm_application_gateway.this.name
}

output "public_ip_address" {
  description = "Public IP address of the Application Gateway (from the PIP assigned to frontend)"
  value       = var.public_ip_resource_id != null ? null : null # Use dns_zone module output instead
}

output "public_ip_id" {
  description = "Public IP resource ID"
  value       = var.public_ip_resource_id
}

output "backend_address_pools" {
  description = "Backend address pools"
  value       = azurerm_application_gateway.this.backend_address_pool
}

output "principal_id" {
  description = "Principal ID of the App Gateway managed identity (user-assigned)"
  value       = try(azurerm_user_assigned_identity.appgw[0].principal_id, null)
}
