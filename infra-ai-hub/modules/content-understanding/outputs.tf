output "resource_id" {
  description = "Resource ID of the Content Understanding (AIServices) account"
  value       = module.account.resource_id
}

output "name" {
  description = "Name of the Content Understanding (AIServices) account"
  value       = module.account.name
}

output "endpoint" {
  description = "Endpoint of the Content Understanding (AIServices) account"
  value       = module.account.endpoint
}

output "location" {
  description = "Azure region of the Content Understanding account"
  value       = var.location
}

output "principal_id" {
  description = "Principal ID of the account's system-assigned managed identity"
  value       = module.account.system_assigned_mi_principal_id
}

output "model_deployments" {
  description = "Deployment name per role (completion, completion_mini, embedding)"
  value       = local.deployment_names
}

output "default_model_deployments" {
  description = "modelDeployments map for PATCH /contentunderstanding/defaults (model names and prebuilt-analyzer aliases -> deployment names)"
  value       = local.default_model_deployments
}
