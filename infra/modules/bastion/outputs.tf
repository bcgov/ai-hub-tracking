# -----------------------------------------------------------------------------
# Bastion Module Outputs
# -----------------------------------------------------------------------------

output "bastion_id" {
  description = "ID of the Azure Bastion host"
  value       = azurerm_bastion_host.main.id
}

output "bastion_name" {
  description = "Name of the Azure Bastion host"
  value       = azurerm_bastion_host.main.name
}

output "bastion_dns_name" {
  description = "DNS name of the Azure Bastion host"
  value       = azurerm_bastion_host.main.dns_name
}

output "public_ip_address" {
  description = "Public IP address of the Bastion host"
  value       = azurerm_public_ip.bastion.ip_address
}
