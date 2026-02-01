locals {
  # Generate clean name for resources (remove hyphens for storage, etc.)
  tenant_name_clean = replace(var.tenant_name, "-", "")

  # Truncate for resources with length limits
  tenant_name_short = substr(local.tenant_name_clean, 0, 10)

  # Common name prefix
  name_prefix = var.tenant_name

  # Resource group values from the always-created tenant RG
  resource_group_name = azurerm_resource_group.tenant.name
  resource_group_id   = azurerm_resource_group.tenant.id

  # Tenant Log Analytics workspace (optional)
  has_log_analytics                 = var.log_analytics.enabled || var.log_analytics_workspace_id != null
  tenant_log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : (var.log_analytics.enabled ? azurerm_log_analytics_workspace.tenant[0].id : null)

  kv_diagnostics      = try(var.key_vault.diagnostics, null)
  storage_diagnostics = try(var.storage_account.diagnostics, null)
  search_diagnostics  = try(var.ai_search.diagnostics, null)
  cosmos_diagnostics  = try(var.cosmos_db.diagnostics, null)
  docint_diagnostics  = try(var.document_intelligence.diagnostics, null)
  speech_diagnostics  = try(var.speech_services.diagnostics, null)

  # Note: AI Foundry model deployments diagnostics are handled at the Hub level
  # No per-tenant diagnostics needed - logs flow to the shared Hub's LAW

  kv_log_groups        = local.kv_diagnostics != null ? try(local.kv_diagnostics.log_groups, []) : []
  kv_log_categories    = local.kv_diagnostics != null ? try(local.kv_diagnostics.log_categories, []) : []
  kv_metric_categories = local.kv_diagnostics != null ? try(local.kv_diagnostics.metric_categories, []) : []

  storage_log_groups        = local.storage_diagnostics != null ? try(local.storage_diagnostics.log_groups, []) : []
  storage_log_categories    = local.storage_diagnostics != null ? try(local.storage_diagnostics.log_categories, []) : []
  storage_metric_categories = local.storage_diagnostics != null ? try(local.storage_diagnostics.metric_categories, []) : []

  search_log_groups        = local.search_diagnostics != null ? try(local.search_diagnostics.log_groups, []) : []
  search_log_categories    = local.search_diagnostics != null ? try(local.search_diagnostics.log_categories, []) : []
  search_metric_categories = local.search_diagnostics != null ? try(local.search_diagnostics.metric_categories, []) : []

  cosmos_log_groups        = local.cosmos_diagnostics != null ? try(local.cosmos_diagnostics.log_groups, []) : []
  cosmos_log_categories    = local.cosmos_diagnostics != null ? try(local.cosmos_diagnostics.log_categories, []) : []
  cosmos_metric_categories = local.cosmos_diagnostics != null ? try(local.cosmos_diagnostics.metric_categories, []) : []

  docint_log_groups        = local.docint_diagnostics != null ? try(local.docint_diagnostics.log_groups, []) : []
  docint_log_categories    = local.docint_diagnostics != null ? try(local.docint_diagnostics.log_categories, []) : []
  docint_metric_categories = local.docint_diagnostics != null ? try(local.docint_diagnostics.metric_categories, []) : []

  speech_log_groups        = local.speech_diagnostics != null ? try(local.speech_diagnostics.log_groups, []) : []
  speech_log_categories    = local.speech_diagnostics != null ? try(local.speech_diagnostics.log_categories, []) : []
  speech_metric_categories = local.speech_diagnostics != null ? try(local.speech_diagnostics.metric_categories, []) : []
}
