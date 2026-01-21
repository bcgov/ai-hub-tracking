# =============================================================================
# RESOURCE GROUP OUTPUTS
# =============================================================================
output "resource_group_name" {
  description = "Name of the tenant's resource group"
  value       = azurerm_resource_group.tenant.name
}

output "resource_group_id" {
  description = "ID of the tenant's resource group"
  value       = azurerm_resource_group.tenant.id
}

# =============================================================================
# AI FOUNDRY PROJECT OUTPUTS
# =============================================================================
output "project_id" {
  description = "Resource ID of the AI Foundry project"
  value       = azapi_resource.ai_foundry_project.id
}

output "project_name" {
  description = "Name of the AI Foundry project"
  value       = azapi_resource.ai_foundry_project.name
}

output "project_principal_id" {
  description = "Principal ID of the AI Foundry project's managed identity"
  value       = try(azapi_resource.ai_foundry_project.output.identity.principalId, null)
}

# =============================================================================
# KEY VAULT OUTPUTS
# =============================================================================
output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = var.key_vault.enabled ? module.key_vault[0].resource_id : null
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = var.key_vault.enabled ? module.key_vault[0].name : null
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = var.key_vault.enabled ? module.key_vault[0].uri : null
}

# =============================================================================
# STORAGE ACCOUNT OUTPUTS
# =============================================================================
output "storage_account_id" {
  description = "Resource ID of the Storage Account"
  value       = var.storage_account.enabled ? module.storage_account[0].resource_id : null
}

output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = var.storage_account.enabled ? module.storage_account[0].name : null
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of the Storage Account"
  value       = var.storage_account.enabled ? module.storage_account[0].resource.primary_blob_endpoint : null
}

# =============================================================================
# AI SEARCH OUTPUTS
# =============================================================================
output "ai_search_id" {
  description = "Resource ID of the AI Search service"
  value       = var.ai_search.enabled ? module.ai_search[0].resource_id : null
}

output "ai_search_name" {
  description = "Name of the AI Search service"
  value       = var.ai_search.enabled ? module.ai_search[0].resource.name : null
}

# =============================================================================
# COSMOS DB OUTPUTS
# =============================================================================
output "cosmos_db_id" {
  description = "Resource ID of the Cosmos DB account"
  value       = var.cosmos_db.enabled ? azurerm_cosmosdb_account.this[0].id : null
}

output "cosmos_db_name" {
  description = "Name of the Cosmos DB account"
  value       = var.cosmos_db.enabled ? azurerm_cosmosdb_account.this[0].name : null
}

output "cosmos_db_endpoint" {
  description = "Endpoint of the Cosmos DB account"
  value       = var.cosmos_db.enabled ? azurerm_cosmosdb_account.this[0].endpoint : null
}

# =============================================================================
# DOCUMENT INTELLIGENCE OUTPUTS
# =============================================================================
output "document_intelligence_id" {
  description = "Resource ID of the Document Intelligence account"
  value       = var.document_intelligence.enabled ? module.document_intelligence[0].resource_id : null
}

output "document_intelligence_name" {
  description = "Name of the Document Intelligence account"
  value       = var.document_intelligence.enabled ? module.document_intelligence[0].resource.name : null
}

output "document_intelligence_endpoint" {
  description = "Endpoint of the Document Intelligence account"
  value       = var.document_intelligence.enabled ? module.document_intelligence[0].resource.endpoint : null
}

# =============================================================================
# OPENAI OUTPUTS
# =============================================================================
output "openai_id" {
  description = "Resource ID of the OpenAI account"
  value       = var.openai.enabled ? module.openai[0].resource_id : null
}

output "openai_name" {
  description = "Name of the OpenAI account"
  value       = var.openai.enabled ? module.openai[0].resource.name : null
}

output "openai_endpoint" {
  description = "Endpoint of the OpenAI account"
  value       = var.openai.enabled ? module.openai[0].resource.endpoint : null
}

output "openai_deployment_ids" {
  description = "Map of OpenAI deployment names to their IDs"
  value       = var.openai.enabled ? module.openai[0].cognitive_deployment_ids : {}
}

# =============================================================================
# SUMMARY OUTPUT
# =============================================================================
output "enabled_resources" {
  description = "Summary of which resources are enabled for this tenant"
  value = {
    key_vault             = var.key_vault.enabled
    storage_account       = var.storage_account.enabled
    ai_search             = var.ai_search.enabled
    cosmos_db             = var.cosmos_db.enabled
    document_intelligence = var.document_intelligence.enabled
    openai                = var.openai.enabled
  }
}
