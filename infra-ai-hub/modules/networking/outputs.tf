output "private_endpoint_subnet_id" {
  description = "The subnet ID for private endpoints."
  value       = azapi_resource.privateendpoints_subnet.id
}