output "id" {
  description = "Resource ID of the API Management instance"
  value       = module.apim.resource_id
}

output "name" {
  description = "Name of the API Management instance"
  value       = module.apim.name
}

output "gateway_url" {
  description = "Gateway URL of the API Management instance"
  value       = module.apim.apim_gateway_url
}

output "management_url" {
  description = "Management URL of the API Management instance"
  value       = module.apim.apim_management_url
}

output "developer_portal_url" {
  description = "Developer portal URL"
  value       = module.apim.developer_portal_url
}

output "private_ip_addresses" {
  description = "Private IP addresses of APIM (when VNet integrated)"
  value       = module.apim.private_ip_addresses
}

output "public_ip_addresses" {
  description = "Public IP addresses of APIM"
  value       = module.apim.public_ip_addresses
}

output "product_ids" {
  description = "Map of product names to their resource IDs"
  value       = module.apim.product_ids
}

output "principal_id" {
  description = "Principal ID of the APIM managed identity"
  value       = try(nonsensitive(module.apim.resource.identity[0].principal_id), null)
}

output "private_endpoint_ip" {
  description = "Private IP address of the APIM private endpoint"
  value       = try(module.apim.private_endpoints["primary"].private_service_connection[0].private_ip_address, null)
}
