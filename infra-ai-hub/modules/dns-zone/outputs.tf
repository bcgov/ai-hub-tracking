output "dns_zone_id" {
  description = "Resource ID of the DNS zone"
  value       = azurerm_dns_zone.this.id
}

output "dns_zone_name" {
  description = "Name of the DNS zone"
  value       = azurerm_dns_zone.this.name
}

output "name_servers" {
  description = "Name servers for the DNS zone (provide these to your DNS registrar for delegation)"
  value       = azurerm_dns_zone.this.name_servers
}

output "public_ip_id" {
  description = "Resource ID of the static public IP (pass to App Gateway module)"
  value       = azurerm_public_ip.appgw.id
}

output "public_ip_address" {
  description = "IP address of the static public IP"
  value       = azurerm_public_ip.appgw.ip_address
}

output "resource_group_name" {
  description = "Name of the DNS resource group"
  value       = azurerm_resource_group.dns.name
}

output "resource_group_id" {
  description = "Resource ID of the DNS resource group"
  value       = azurerm_resource_group.dns.id
}
