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

# =============================================================================
# AI MODEL DEPLOYMENT OUTPUTS
# =============================================================================
output "ai_model_deployment_ids" {
  description = "Map of original model names to their resource IDs (deployment names are tenant-prefixed)"
  value       = { for k, v in azapi_resource.ai_model_deployment : k => v.id }
}

output "ai_model_deployment_names" {
  description = "List of deployed AI model names (tenant-prefixed, e.g., 'wlrs-gpt-4.1-mini')"
  value       = [for k, v in azapi_resource.ai_model_deployment : v.name]
}

output "ai_model_deployment_mapping" {
  description = "Map of client-facing model names to tenant-prefixed deployment names"
  value       = { for k, v in var.ai_model_deployments : v.name => "${var.tenant_name}-${v.name}" }
}

output "has_model_deployments" {
  description = "Whether this tenant has any AI model deployments"
  value       = length(var.ai_model_deployments) > 0
}

# Marker output for serialization - depends on last connection and model deployments
output "complete" {
  description = "Marker indicating all project resources are complete (for serialization)"
  value       = true

  depends_on = [
    azapi_resource.project,
    azapi_resource.connection_keyvault,
    azapi_resource.connection_storage,
    azapi_resource.connection_ai_search,
    azapi_resource.connection_cosmos,
    azapi_resource.connection_docint,
    azapi_resource.ai_model_deployment,
  ]
}
