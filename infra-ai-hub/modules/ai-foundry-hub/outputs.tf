output "id" {
  description = "Resource ID of the AI Foundry account"
  value       = azapi_resource.ai_foundry.id
}

output "name" {
  description = "Name of the AI Foundry account"
  value       = azapi_resource.ai_foundry.name
}

output "ai_location" {
  description = "Azure region where the AI Foundry Hub is deployed (may differ from PE location)"
  value       = local.ai_location
}

output "endpoint" {
  description = "Primary endpoint of the AI Foundry account"
  value       = try(azapi_resource.ai_foundry.output.properties.endpoint, null)
}

output "principal_id" {
  description = "Principal ID of the system-assigned managed identity"
  value       = try(azapi_resource.ai_foundry.output.identity.principalId, null)
}

output "tenant_id" {
  description = "Tenant ID of the system-assigned managed identity"
  value       = try(azapi_resource.ai_foundry.output.identity.tenantId, null)
}

output "private_endpoint_id" {
  description = "Resource ID of the private endpoint"
  value       = azurerm_private_endpoint.ai_foundry.id
}

output "private_endpoint_ip" {
  description = "Private IP address of the private endpoint"
  value       = try(azurerm_private_endpoint.ai_foundry.private_service_connection[0].private_ip_address, null)
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace (if created or provided)"
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of Application Insights (if enabled)"
  value       = try(azurerm_application_insights.this[0].id, null)
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (if enabled)"
  value       = try(azurerm_application_insights.this[0].connection_string, null)
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (if enabled, deprecated - use connection_string)"
  value       = try(azurerm_application_insights.this[0].instrumentation_key, null)
  sensitive   = true
}

output "ai_agent_id" {
  description = "Resource ID of the AI Agent service (if enabled)"
  value       = try(azapi_resource.ai_agent[0].id, null)
}

output "ai_agent_principal_id" {
  description = "Principal ID of the AI Agent's managed identity"
  value       = try(azapi_resource.ai_agent[0].output.identity.principalId, null)
}

output "bing_grounding_id" {
  description = "Resource ID of the Bing Grounding resource (if enabled)"
  value       = try(azurerm_cognitive_account.bing_grounding[0].id, null)
}

output "bing_grounding_endpoint" {
  description = "Endpoint of the Bing Grounding resource (if enabled)"
  value       = try(azurerm_cognitive_account.bing_grounding[0].endpoint, null)
}
