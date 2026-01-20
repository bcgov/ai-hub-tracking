output "ai_foundry_hub" {
  description = "AI Foundry Hub resource details"
  value       = try(module.foundry_ptn.resource, null)
}

output "ai_foundry_projects" {
  description = "AI Foundry Projects resource details"
  value       = try(module.foundry_ptn.projects, {})
}

output "byor_resources" {
  description = "BYOR resources created for AI Foundry (Cosmos DB, AI Search, Key Vault, Storage)"
  value       = try(module.foundry_ptn.byor_resources, {})
  sensitive   = true
}

output "private_endpoints" {
  description = "Private endpoints created for AI Foundry and dependencies"
  value       = var.private_endpoints.enabled ? module.private_endpoints.all_pe_details : null
}
