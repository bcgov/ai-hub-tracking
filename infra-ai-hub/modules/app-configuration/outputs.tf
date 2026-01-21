output "resource_id" {
  description = "Resource ID of the App Configuration store"
  value       = azurerm_app_configuration.this.id
}

output "name" {
  description = "Name of the App Configuration store"
  value       = azurerm_app_configuration.this.name
}

output "endpoint" {
  description = "Endpoint of the App Configuration store"
  value       = azurerm_app_configuration.this.endpoint
}

output "primary_read_key" {
  description = "Primary read key connection string"
  value       = azurerm_app_configuration.this.primary_read_key
  sensitive   = true
}

output "principal_id" {
  description = "Principal ID of the system-assigned managed identity"
  value       = azurerm_app_configuration.this.identity[0].principal_id
}

output "private_endpoint_id" {
  description = "Resource ID of the private endpoint"
  value       = try(azurerm_private_endpoint.app_config[0].id, null)
}
