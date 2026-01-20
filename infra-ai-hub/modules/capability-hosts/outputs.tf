output "hub_agent_capability_host_id" {
  description = "Resource ID of the hub-level AI agent capability host."
  value       = var.ai_foundry_definition.ai_foundry.create_ai_agent_service && length(azapi_resource.hub_agent_capability_host) > 0 ? azapi_resource.hub_agent_capability_host[0].id : null
}

output "hub_agent_capability_host_name" {
  description = "Name of the hub-level AI agent capability host."
  value       = var.ai_foundry_definition.ai_foundry.create_ai_agent_service && length(azapi_resource.hub_agent_capability_host) > 0 ? azapi_resource.hub_agent_capability_host[0].name : null
}

output "agent_service_enabled" {
  description = "Whether the AI agent service is enabled and capability host created."
  value       = var.ai_foundry_definition.ai_foundry.create_ai_agent_service
}
