
output "container_instance_subnet_id" {
  description = "The subnet ID for the container instance."
  value       = azapi_resource.container_instance_subnet.id
}

output "app_service_subnet_id" {
  description = "The subnet ID for the App Service."
  value       = azapi_resource.app_service_subnet.id
}

output "private_endpoint_subnet_id" {
  description = "The subnet ID for private endpoints."
  value       = azapi_resource.privateendpoints_subnet.id
}

output "container_apps_subnet_id" {
  description = "The subnet ID for Container Apps Environment."
  value       = azapi_resource.container_apps_subnet.id
}

output "apim_subnet_id" {
  description = "The subnet ID for API Management."
  value       = azapi_resource.apim_subnet.id
}

output "jumpbox_subnet_id" {
  description = "The subnet ID for the Jumpbox VM."
  value       = azapi_resource.jumpbox_subnet.id
}

output "bastion_subnet_id" {
  description = "The subnet ID for Azure Bastion."
  value       = azapi_resource.bastion_subnet.id
}

output "dns_servers" {
  description = "The DNS servers for the virtual network."
  value       = data.azurerm_virtual_network.main.dns_servers
}

