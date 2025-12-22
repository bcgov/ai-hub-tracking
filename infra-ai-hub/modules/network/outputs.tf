output "private_endpoint_subnet_id" {
  description = "Resource ID of the private endpoint subnet"
  value       = azapi_resource.private_endpoints_subnet.id
}

output "private_endpoint_subnet_cidr" {
  description = "CIDR of the derived private endpoint subnet"
  value       = local.private_endpoint_subnet_cidr
}

output "private_endpoint_nsg_id" {
  description = "Resource ID of the private endpoint NSG"
  value       = azurerm_network_security_group.private_endpoints.id
}
