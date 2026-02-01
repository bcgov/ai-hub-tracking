output "private_endpoint_subnet_id" {
  description = "Resource ID of the primary private endpoint subnet (first in pool)"
  value       = azapi_resource.private_endpoints_subnet.id
}

output "private_endpoint_subnet_cidr" {
  description = "CIDR of the primary private endpoint subnet"
  value       = local.private_endpoint_subnet_cidr
}

output "private_endpoint_nsg_id" {
  description = "Resource ID of the private endpoint NSG"
  value       = azurerm_network_security_group.private_endpoints.id
}

output "private_endpoint_subnet_pool" {
  description = "Map of all PE subnets available for tenant allocation (name => cidr)"
  value       = local.pe_subnet_pool
}

# -----------------------------------------------------------------------------
# APIM Subnet Outputs (for VNet injection)
# -----------------------------------------------------------------------------
output "apim_subnet_id" {
  description = "Resource ID of the APIM subnet (null if not enabled)"
  value       = var.apim_subnet.enabled ? azapi_resource.apim_subnet[0].id : null
}

output "apim_subnet_cidr" {
  description = "CIDR of the APIM subnet (null if not enabled)"
  value       = local.apim_subnet_cidr
}

output "apim_nsg_id" {
  description = "Resource ID of the APIM NSG (null if not enabled)"
  value       = var.apim_subnet.enabled ? azurerm_network_security_group.apim[0].id : null
}

# -----------------------------------------------------------------------------
# App Gateway Subnet Outputs
# -----------------------------------------------------------------------------
output "appgw_subnet_id" {
  description = "Resource ID of the App Gateway subnet (null if not enabled)"
  value       = var.appgw_subnet.enabled ? azapi_resource.appgw_subnet[0].id : null
}

output "appgw_subnet_cidr" {
  description = "CIDR of the App Gateway subnet (null if not enabled)"
  value       = local.appgw_subnet_cidr
}

output "appgw_nsg_id" {
  description = "Resource ID of the App Gateway NSG (null if not enabled)"
  value       = var.appgw_subnet.enabled ? azurerm_network_security_group.appgw[0].id : null
}

# -----------------------------------------------------------------------------
# Container Apps Environment Subnet Outputs
# -----------------------------------------------------------------------------
output "aca_subnet_id" {
  description = "Resource ID of the ACA subnet (null if not enabled)"
  value       = var.aca_subnet.enabled ? azapi_resource.aca_subnet[0].id : null
}

output "aca_subnet_cidr" {
  description = "CIDR of the ACA subnet (null if not enabled)"
  value       = local.aca_subnet_cidr
}

output "aca_nsg_id" {
  description = "Resource ID of the ACA NSG (null if not enabled)"
  value       = var.aca_subnet.enabled ? azurerm_network_security_group.aca[0].id : null
}

# -----------------------------------------------------------------------------
# VNet Information
# -----------------------------------------------------------------------------
output "vnet_id" {
  description = "Resource ID of the target VNet"
  value       = data.azurerm_virtual_network.target.id
}

output "vnet_name" {
  description = "Name of the target VNet"
  value       = data.azurerm_virtual_network.target.name
}
