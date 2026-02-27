# =============================================================================
# Key Rotation Function App — Outputs
# =============================================================================

output "function_app_id" {
  description = "Resource ID of the key rotation Function App"
  value       = azurerm_linux_function_app.rotation.id
}

output "function_app_name" {
  description = "Name of the key rotation Function App"
  value       = azurerm_linux_function_app.rotation.name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.rotation.default_hostname
}

output "function_app_principal_id" {
  description = "System-assigned Managed Identity principal ID"
  value       = azurerm_linux_function_app.rotation.identity[0].principal_id
}

output "storage_account_name" {
  description = "Storage account used by the Functions runtime"
  value       = azurerm_storage_account.func.name
}
