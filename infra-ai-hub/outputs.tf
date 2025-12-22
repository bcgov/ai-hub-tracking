output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.main.name
}

output "key_vault_id" {
  description = "Key Vault resource ID"
  value       = azurerm_key_vault.main.id
}

output "key_vault_name" {
  description = "Key Vault name"
  value       = azurerm_key_vault.main.name
}

output "private_endpoint_subnet_id" {
  description = "Resource ID of the private endpoint subnet created in the existing VNet"
  value       = module.network.private_endpoint_subnet_id
}

output "private_endpoint_subnet_cidr" {
  description = "CIDR of the derived private endpoint subnet"
  value       = module.network.private_endpoint_subnet_cidr
}

output "private_endpoint_nsg_id" {
  description = "Resource ID of the private endpoint NSG"
  value       = module.network.private_endpoint_nsg_id
}

/* output "secret_names" {
  description = "Names of the example secrets created in the Key Vault"
  value = [
    azurerm_key_vault_secret.secret_one.name,
    azurerm_key_vault_secret.secret_two.name
  ]
} */
