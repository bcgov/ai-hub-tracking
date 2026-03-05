# -----------------------------------------------------------------------------
# Outputs – Tenant Onboarding Portal Infrastructure
# -----------------------------------------------------------------------------

output "app_service_name" {
  description = "The name of the deployed App Service."
  value       = azurerm_linux_web_app.portal.name
}

output "app_service_default_hostname" {
  description = "Default hostname of the App Service."
  value       = azurerm_linux_web_app.portal.default_hostname
}

output "app_service_principal_id" {
  description = "Managed identity principal ID of the App Service."
  value       = azurerm_linux_web_app.portal.identity[0].principal_id
}
