output "resource_id" {
  description = "Resource ID of the Container Registry"
  value       = module.container_registry.resource_id
}

output "name" {
  description = "Name of the Container Registry"
  value       = module.container_registry.name
}

output "login_server" {
  description = "Login server URL of the Container Registry"
  value       = module.container_registry.resource.login_server
}

output "principal_id" {
  description = "Principal ID of the system-assigned managed identity"
  value       = module.container_registry.system_assigned_mi_principal_id
}

output "private_endpoint_id" {
  description = "Resource ID of the private endpoint"
  value       = try(module.container_registry.private_endpoints["primary"].id, null)
}
