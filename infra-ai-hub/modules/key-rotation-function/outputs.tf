# =============================================================================
# Key Rotation Container App Job — Outputs
# =============================================================================

output "job_id" {
  description = "Resource ID of the key rotation Container App Job"
  value       = azurerm_container_app_job.rotation.id
}

output "job_name" {
  description = "Name of the key rotation Container App Job"
  value       = azurerm_container_app_job.rotation.name
}

output "principal_id" {
  description = "System-assigned Managed Identity principal ID"
  value       = azurerm_container_app_job.rotation.identity[0].principal_id
}
