output "tenant_resource_groups" {
  value = {
    for tenant_key, tenant in module.tenant : tenant_key => tenant.resource_group_name
  }
}

output "tenant_key_vaults" {
  value = {
    for tenant_key, tenant in module.tenant : tenant_key => {
      id   = tenant.key_vault_id
      name = tenant.key_vault_name
      uri  = tenant.key_vault_uri
    } if tenant.key_vault_id != null
  }
}

output "tenant_storage_accounts" {
  sensitive = true
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
  value = {
    for tenant_key, tenant in module.tenant : tenant_key => {
      id       = tenant.ai_search_id
      name     = tenant.ai_search_name
      endpoint = tenant.ai_search_endpoint
    } if tenant.ai_search_id != null
  }
}

output "tenant_cosmos_db" {
  value = {
    for tenant_key, tenant in module.tenant : tenant_key => {
      id            = tenant.cosmos_db_id
      name          = tenant.cosmos_db_name
      endpoint      = tenant.cosmos_db_endpoint
      database_name = tenant.cosmos_db_database_name
    } if tenant.cosmos_db_id != null
  }
}

output "tenant_document_intelligence" {
  value = {
    for tenant_key, tenant in module.tenant : tenant_key => {
      id       = tenant.document_intelligence_id
      name     = tenant.document_intelligence_name
      endpoint = tenant.document_intelligence_endpoint
    } if tenant.document_intelligence_id != null
  }
}

output "tenant_speech_services" {
  value = {
    for tenant_key, tenant in module.tenant : tenant_key => {
      id          = tenant.speech_services_id
      name        = tenant.speech_services_name
      endpoint    = tenant.speech_services_endpoint
      primary_key = tenant.speech_services_primary_key
    } if tenant.speech_services_id != null
  }
  sensitive = true
}

output "tenant_log_analytics" {
  value = {
    for tenant_key, tenant in module.tenant : tenant_key => {
      log_analytics_workspace_id = tenant.log_analytics_workspace_id
      has_log_analytics          = tenant.has_log_analytics
      log_analytics_enabled      = tenant.log_analytics_enabled
      application_insights_id    = tenant.application_insights_id
      instrumentation_key        = tenant.application_insights_instrumentation_key
      connection_string          = tenant.application_insights_connection_string
    }
  }
  sensitive = true
}

output "tenant_enabled_resources" {
  value = {
    for tenant_key, tenant in module.tenant : tenant_key => tenant.enabled_resources
  }
}
