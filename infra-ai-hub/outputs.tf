# =============================================================================
# INFRASTRUCTURE OUTPUTS
# =============================================================================
output "resource_group_name" {
  description = "Name of the main resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "Resource ID of the main resource group"
  value       = azurerm_resource_group.main.id
}

# =============================================================================
# NETWORK OUTPUTS
# =============================================================================
output "private_endpoint_subnet_id" {
  description = "Resource ID of the private endpoint subnet"
  value       = module.network.private_endpoint_subnet_id
}

output "private_endpoint_subnet_cidr" {
  description = "CIDR of the private endpoint subnet"
  value       = module.network.private_endpoint_subnet_cidr
}

output "private_endpoint_nsg_id" {
  description = "Resource ID of the private endpoint NSG"
  value       = module.network.private_endpoint_nsg_id
}

# =============================================================================
# AI FOUNDRY HUB OUTPUTS
# =============================================================================
output "ai_foundry_hub_id" {
  description = "Resource ID of the shared AI Foundry hub"
  value       = module.ai_foundry_hub.id
}

output "ai_foundry_hub_name" {
  description = "Name of the shared AI Foundry hub"
  value       = module.ai_foundry_hub.name
}

output "ai_foundry_hub_endpoint" {
  description = "Endpoint of the shared AI Foundry hub"
  value       = module.ai_foundry_hub.endpoint
}

output "ai_foundry_hub_principal_id" {
  description = "Principal ID of the AI Foundry hub's managed identity"
  value       = module.ai_foundry_hub.principal_id
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = module.ai_foundry_hub.log_analytics_workspace_id
}

# =============================================================================
# LANGUAGE SERVICE OUTPUTS (shared PII detection)
# =============================================================================
output "language_service_id" {
  description = "Resource ID of the Language Service (for PII detection)"
  value       = var.shared_config.language_service.enabled ? azurerm_cognitive_account.language_service[0].id : null
}

output "language_service_name" {
  description = "Name of the Language Service"
  value       = var.shared_config.language_service.enabled ? azurerm_cognitive_account.language_service[0].name : null
}

output "language_service_endpoint" {
  description = "Endpoint of the Language Service"
  value       = var.shared_config.language_service.enabled ? azurerm_cognitive_account.language_service[0].endpoint : null
}

# =============================================================================
# APIM OUTPUTS
# =============================================================================
output "apim_gateway_url" {
  description = "Gateway URL of the API Management instance (for API calls)"
  value       = local.apim_config.enabled ? module.apim[0].gateway_url : null
}

output "apim_name" {
  description = "Name of the API Management instance"
  value       = local.apim_config.enabled ? module.apim[0].name : null
}

# =============================================================================
# TENANT OUTPUTS
# =============================================================================
output "tenant_projects" {
  description = "Map of tenant names to their AI Foundry project details"
  value = {
    for tenant_key, project in module.foundry_project : tenant_key => {
      project_id           = project.project_id
      project_name         = project.project_name
      project_principal_id = project.project_principal_id
      enabled_resources    = module.tenant[tenant_key].enabled_resources
    }
  }
}

output "tenant_key_vaults" {
  description = "Map of tenant names to their Key Vault details (if enabled)"
  value = {
    for tenant_key, tenant in module.tenant : tenant_key => {
      id   = tenant.key_vault_id
      name = tenant.key_vault_name
      uri  = tenant.key_vault_uri
    } if tenant.key_vault_id != null
  }
}

output "tenant_storage_accounts" {
  description = "Map of tenant names to their Storage Account details (if enabled)"
  sensitive   = true
  value = {
    for tenant_key, tenant in module.tenant : tenant_key => {
      id                 = tenant.storage_account_id
      name               = tenant.storage_account_name
      blob_endpoint      = tenant.storage_account_primary_blob_endpoint
      primary_access_key = tenant.storage_account_primary_access_key
      connection_string  = tenant.storage_account_primary_connection_string
    } if tenant.storage_account_id != null
  }
}

output "tenant_ai_search" {
  description = "Map of tenant names to their AI Search details (if enabled)"
  value = {
    for tenant_key, tenant in module.tenant : tenant_key => {
      id   = tenant.ai_search_id
      name = tenant.ai_search_name
    } if tenant.ai_search_id != null
  }
}

output "tenant_cosmos_db" {
  description = "Map of tenant names to their Cosmos DB details (if enabled)"
  value = {
    for tenant_key, tenant in module.tenant : tenant_key => {
      id       = tenant.cosmos_db_id
      name     = tenant.cosmos_db_name
      endpoint = tenant.cosmos_db_endpoint
    } if tenant.cosmos_db_id != null
  }
}

output "tenant_document_intelligence" {
  description = "Map of tenant names to their Document Intelligence details (if enabled)"
  value = {
    for tenant_key, tenant in module.tenant : tenant_key => {
      id       = tenant.document_intelligence_id
      name     = tenant.document_intelligence_name
      endpoint = tenant.document_intelligence_endpoint
    } if tenant.document_intelligence_id != null
  }
}

output "tenant_openai" {
  description = "Map of tenant names to their OpenAI details (if enabled)"
  value = {
    for tenant_key, tenant in module.tenant : tenant_key => {
      id             = tenant.openai_id
      name           = tenant.openai_name
      endpoint       = tenant.openai_endpoint
      deployment_ids = tenant.openai_deployment_ids
    } if tenant.openai_id != null
  }
}

# =============================================================================
# CONFIGURATION OUTPUTS (for debugging/visibility)
# =============================================================================
output "enabled_tenants" {
  description = "List of enabled tenant names"
  value       = keys(local.enabled_tenants)
}

output "shared_config" {
  description = "Shared configuration loaded from params"
  value       = var.shared_config
}

# =============================================================================
# APIM AUTHENTICATION OUTPUTS
# =============================================================================
output "apim_tenant_subscriptions" {
  description = "Map of tenant names to their APIM subscription keys (for subscription_key auth mode)"
  sensitive   = true
  value = {
    for key, sub in azurerm_api_management_subscription.tenant :
    trimsuffix(key, "-subscription") => {
      subscription_id = sub.subscription_id
      primary_key     = sub.primary_key
      secondary_key   = sub.secondary_key
      product_id      = sub.product_id
      state           = sub.state
    }
  }
}


output "apim_tenant_auth_summary" {
  description = "Summary of authentication configuration per tenant"
  value = {
    for key, config in local.enabled_tenants : key => {
      auth_mode         = lookup(lookup(config, "apim_auth", {}), "mode", "subscription_key")
      store_in_keyvault = lookup(lookup(config, "apim_auth", {}), "store_in_keyvault", false)
      credentials_location = lookup(lookup(config, "apim_auth", {}), "store_in_keyvault", false) ? (
        "Key Vault: ${key} - apim-subscription-primary-key or apim-client-id/secret"
        ) : (
        "Azure Portal: APIM → Subscriptions → ${key}-subscription → Show Keys"
      )
      # How platform team distributes keys
      distribution_method = lookup(lookup(config, "apim_auth", {}), "store_in_keyvault", false) ? (
        "Grant tenant team Key Vault access"
        ) : (
        "Platform team retrieves from Azure Portal and shares securely"
      )
    }
  }
}

# =============================================================================
# TENANT DIAGNOSTICS OUTPUTS
# =============================================================================
output "tenant_diagnostics_summary" {
  description = "Summary of per-tenant APIM diagnostics configuration"
  value = {
    for key, config in local.enabled_tenants : key => {
      has_dedicated_law = lookup(config.log_analytics, "enabled", false)
      log_destination = lookup(config.log_analytics, "enabled", false) ? (
        "Tenant Log Analytics Workspace"
        ) : (
        "Central Application Insights"
      )
      log_analytics_workspace_id = lookup(config.log_analytics, "enabled", false) ? (
        module.tenant[key].log_analytics_workspace_id
      ) : null
      sampling_percentage = try(config.apim_diagnostics.sampling_percentage, 100)
      verbosity           = try(config.apim_diagnostics.verbosity, "information")
    }
  }
}
