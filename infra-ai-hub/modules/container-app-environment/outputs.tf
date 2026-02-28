output "resource_id" {
  description = "Resource ID of the Container App Environment"
  value       = azurerm_container_app_environment.main.id
}

output "name" {
  description = "Name of the Container App Environment"
  value       = azurerm_container_app_environment.main.name
}

output "default_domain" {
  description = "Default domain of the Container App Environment"
  value       = azurerm_container_app_environment.main.default_domain
}

output "static_ip_address" {
  description = "Static IP address of the Container App Environment"
  value       = azurerm_container_app_environment.main.static_ip_address
}
