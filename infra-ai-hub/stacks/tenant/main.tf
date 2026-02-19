data "terraform_remote_state" "shared" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.backend_resource_group
    storage_account_name = var.backend_storage_account
    container_name       = var.backend_container_name
    key                  = "ai-services-hub/${var.app_env}/shared.tfstate"
    subscription_id      = var.subscription_id
    tenant_id            = var.tenant_id
    client_id            = var.client_id
    use_oidc             = var.use_oidc
  }
}

module "tenant" {
  source   = "../../modules/tenant"
  for_each = local.enabled_tenants

  tenant_name  = each.value.tenant_name
  display_name = each.value.display_name

  resource_group_name_override = lookup(each.value, "resource_group_name", null)
  location                     = var.location
  ai_location                  = var.shared_config.ai_foundry.ai_location

  private_endpoint_subnet_id = data.terraform_remote_state.shared.outputs.private_endpoint_subnet_id
  log_analytics_workspace_id = lookup(lookup(each.value, "log_analytics", {}), "enabled", false) ? null : data.terraform_remote_state.shared.outputs.log_analytics_workspace_id

  private_endpoint_dns_wait = {
    timeout       = var.shared_config.private_endpoint_dns_wait.timeout
    poll_interval = var.shared_config.private_endpoint_dns_wait.poll_interval
  }

  scripts_dir = "${path.root}/../../scripts"

  log_analytics = {
    enabled        = lookup(lookup(each.value, "log_analytics", {}), "enabled", false)
    retention_days = lookup(lookup(each.value, "log_analytics", {}), "retention_days", 30)
    sku            = lookup(lookup(each.value, "log_analytics", {}), "sku", "PerGB2018")
  }

  key_vault = {
    enabled                    = lookup(lookup(each.value, "key_vault", {}), "enabled", false)
    sku                        = lookup(lookup(each.value, "key_vault", {}), "sku", "standard")
    purge_protection_enabled   = lookup(lookup(each.value, "key_vault", {}), "purge_protection_enabled", true)
    soft_delete_retention_days = lookup(lookup(each.value, "key_vault", {}), "soft_delete_retention_days", 90)
    diagnostics                = lookup(lookup(each.value, "key_vault", {}), "diagnostics", null)
  }

  storage_account = {
    enabled                  = lookup(lookup(each.value, "storage_account", {}), "enabled", false)
    account_tier             = lookup(lookup(each.value, "storage_account", {}), "account_tier", "Standard")
    account_replication_type = lookup(lookup(each.value, "storage_account", {}), "account_replication_type", "LRS")
    account_kind             = lookup(lookup(each.value, "storage_account", {}), "account_kind", "StorageV2")
    access_tier              = lookup(lookup(each.value, "storage_account", {}), "access_tier", "Hot")
    diagnostics              = lookup(lookup(each.value, "storage_account", {}), "diagnostics", null)
  }

  ai_search = {
    enabled            = lookup(lookup(each.value, "ai_search", {}), "enabled", false)
    sku                = lookup(lookup(each.value, "ai_search", {}), "sku", "basic")
    replica_count      = lookup(lookup(each.value, "ai_search", {}), "replica_count", 1)
    partition_count    = lookup(lookup(each.value, "ai_search", {}), "partition_count", 1)
    semantic_search    = lookup(lookup(each.value, "ai_search", {}), "semantic_search", "disabled")
    local_auth_enabled = lookup(lookup(each.value, "ai_search", {}), "local_auth_enabled", true)
    diagnostics        = lookup(lookup(each.value, "ai_search", {}), "diagnostics", null)
  }

  cosmos_db = {
    enabled                      = lookup(lookup(each.value, "cosmos_db", {}), "enabled", false)
    offer_type                   = lookup(lookup(each.value, "cosmos_db", {}), "offer_type", "Standard")
    kind                         = lookup(lookup(each.value, "cosmos_db", {}), "kind", "GlobalDocumentDB")
    consistency_level            = lookup(lookup(each.value, "cosmos_db", {}), "consistency_level", "Session")
    max_interval_in_seconds      = lookup(lookup(each.value, "cosmos_db", {}), "max_interval_in_seconds", 5)
    max_staleness_prefix         = lookup(lookup(each.value, "cosmos_db", {}), "max_staleness_prefix", 100)
    geo_redundant_backup_enabled = lookup(lookup(each.value, "cosmos_db", {}), "geo_redundant_backup_enabled", false)
    automatic_failover_enabled   = lookup(lookup(each.value, "cosmos_db", {}), "automatic_failover_enabled", false)
    total_throughput_limit       = lookup(lookup(each.value, "cosmos_db", {}), "total_throughput_limit", 1000)
    diagnostics                  = lookup(lookup(each.value, "cosmos_db", {}), "diagnostics", null)
  }

  document_intelligence = {
    enabled     = lookup(lookup(each.value, "document_intelligence", {}), "enabled", false)
    sku         = lookup(lookup(each.value, "document_intelligence", {}), "sku", "S0")
    kind        = lookup(lookup(each.value, "document_intelligence", {}), "kind", "FormRecognizer")
    diagnostics = lookup(lookup(each.value, "document_intelligence", {}), "diagnostics", null)
  }

  speech_services = {
    enabled     = lookup(lookup(each.value, "speech_services", {}), "enabled", false)
    sku         = lookup(lookup(each.value, "speech_services", {}), "sku", "S0")
    diagnostics = lookup(lookup(each.value, "speech_services", {}), "diagnostics", null)
  }

  ai_foundry_hub_id = data.terraform_remote_state.shared.outputs.ai_foundry_hub_id
  tags              = merge(var.common_tags, lookup(var.tenant_tags, each.key, {}))
}
