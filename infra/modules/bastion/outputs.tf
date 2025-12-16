# -----------------------------------------------------------------------------
# Bastion Module Outputs
# -----------------------------------------------------------------------------

output "bastion_resource_id" {
  description = "Resource ID of the Azure Bastion host"
  value       = azurerm_bastion_host.main.id
}

output "bastion_fqdn" {
  description = "FQDN of the Bastion host"
  value       = azurerm_bastion_host.main.dns_name
}

output "public_ip_address" {
  description = "Public IP address of the Bastion host"
  value       = azurerm_public_ip.bastion.ip_address
}
