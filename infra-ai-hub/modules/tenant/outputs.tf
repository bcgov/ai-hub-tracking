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
  value       = var.storage_account.enabled ? azurerm_storage_account.this[0].id : null
}

output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = var.storage_account.enabled ? azurerm_storage_account.this[0].name : null
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of the Storage Account"
  value       = var.storage_account.enabled ? azurerm_storage_account.this[0].primary_blob_endpoint : null
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
  description = "Map of OpenAI deployment names to their resource IDs"
  value       = var.openai.enabled ? module.openai[0].resource_cognitive_deployment : {}
}

# =============================================================================
# LOG ANALYTICS OUTPUTS
# =============================================================================
output "log_analytics_workspace_id" {
  description = "Resource ID of the tenant's Log Analytics workspace (if enabled)"
  value       = local.tenant_log_analytics_workspace_id
}

output "has_log_analytics" {
  description = "Whether the tenant has a Log Analytics workspace (own or shared)"
  value       = local.has_log_analytics
}

output "log_analytics_enabled" {
  description = "Whether the tenant has its own dedicated Log Analytics workspace"
  value       = var.log_analytics.enabled
}

# =============================================================================
# APPLICATION INSIGHTS OUTPUTS
# =============================================================================
output "application_insights_id" {
  description = "Resource ID of the tenant's Application Insights (if tenant LAW enabled)"
  value       = var.log_analytics.enabled ? azurerm_application_insights.tenant[0].id : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for the tenant's Application Insights"
  value       = var.log_analytics.enabled ? azurerm_application_insights.tenant[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for the tenant's Application Insights"
  value       = var.log_analytics.enabled ? azurerm_application_insights.tenant[0].connection_string : null
  sensitive   = true
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
    log_analytics         = var.log_analytics.enabled
  }
}
