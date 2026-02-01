output "resource_id" {
  description = "Resource ID of the Container App Environment"
  value       = module.container_app_environment.resource_id
}

output "name" {
  description = "Name of the Container App Environment"
  value       = module.container_app_environment.name
}

output "default_domain" {
  description = "Default domain of the Container App Environment"
  value       = module.container_app_environment.resource.default_domain
}

output "static_ip_address" {
  description = "Static IP address of the Container App Environment"
  value       = module.container_app_environment.resource.static_ip_address
}
