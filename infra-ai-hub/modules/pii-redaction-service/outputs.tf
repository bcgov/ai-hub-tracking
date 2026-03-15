output "container_app_id" {
  description = "Resource ID of the PII Redaction Container App."
  value       = azurerm_container_app.service.id
}

output "container_app_fqdn" {
  description = "Internal FQDN of the PII Redaction Container App (accessible within the VNet via the Container App Environment)."
  value       = azurerm_container_app.service.ingress[0].fqdn
}

output "principal_id" {
  description = "Object ID of the Container App's system-assigned managed identity."
  value       = azurerm_container_app.service.identity[0].principal_id
}
