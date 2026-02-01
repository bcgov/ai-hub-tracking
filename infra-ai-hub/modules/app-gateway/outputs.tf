output "id" {
  description = "Resource ID of the Application Gateway"
  value       = module.app_gateway.resource_id
}

output "name" {
  description = "Name of the Application Gateway"
  value       = module.app_gateway.application_gateway_name
}

output "public_ip_address" {
  description = "Public IP address of the Application Gateway"
  value       = module.app_gateway.new_public_ip_address
}

output "public_ip_id" {
  description = "Public IP resource ID"
  value       = module.app_gateway.public_ip_id
}

output "backend_address_pools" {
  description = "Backend address pools"
  value       = module.app_gateway.backend_address_pools
}

output "principal_id" {
  description = "Principal ID of the App Gateway managed identity"
  value       = try(module.app_gateway.resource.identity[0].principal_id, null)
}
