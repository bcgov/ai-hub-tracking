# =============================================================================
# AI Foundry Project Module - Outputs
# =============================================================================

output "project_id" {
  description = "Resource ID of the AI Foundry project"
  value       = azapi_resource.project.id
}

output "project_name" {
  description = "Name of the AI Foundry project"
  value       = azapi_resource.project.name
}

output "project_principal_id" {
  description = "Principal ID of the AI Foundry project's managed identity"
  value       = local.project_principal_id
}

# Marker output for serialization - depends on last connection
output "complete" {
  description = "Marker indicating all project resources are complete (for serialization)"
  value       = true

  depends_on = [
    azapi_resource.project,
    azapi_resource.connection_keyvault,
    azapi_resource.connection_storage,
    azapi_resource.connection_ai_search,
    azapi_resource.connection_cosmos,
    azapi_resource.connection_openai,
    azapi_resource.connection_docint,
  ]
}
