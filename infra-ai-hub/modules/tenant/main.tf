# Tenant Module - Main Configuration
# Creates all tenant-specific resources using Azure Verified Modules (AVM)
# NOTE: private_endpoints_manage_dns_zone_group = false is used because
# in Azure Landing Zone, private DNS zones are policy-managed.

# -----------------------------------------------------------------------------
# Tenant Resource Group (always created for cost attribution)
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "tenant" {
  name     = coalesce(var.resource_group_name_override, "${var.tenant_name}-rg")
  location = var.location
  tags     = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# -----------------------------------------------------------------------------
# Random suffix for globally unique names
# -----------------------------------------------------------------------------
resource "random_string" "suffix" {
  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# -----------------------------------------------------------------------------
# Tenant Log Analytics Workspace (optional)
# -----------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "tenant" {
  count = var.log_analytics.enabled ? 1 : 0

  name                = "${local.tenant_name_short}-law-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = local.resource_group_name

  sku               = var.log_analytics.sku
  retention_in_days = var.log_analytics.retention_days

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# -----------------------------------------------------------------------------
# Tenant Application Insights (when tenant LAW is enabled)
# This provides per-tenant App Insights linked to tenant LAW for APIM API diagnostics
# -----------------------------------------------------------------------------
resource "azurerm_application_insights" "tenant" {
  count = var.log_analytics.enabled ? 1 : 0

  name                = "${local.tenant_name_short}-appi-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = local.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.tenant[0].id
  application_type    = "web"

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# =============================================================================
# KEY VAULT (using AVM)
# https://github.com/Azure/terraform-azurerm-avm-res-keyvault-vault
# =============================================================================
module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.2"
  count   = var.key_vault.enabled ? 1 : 0

  name                = "${local.tenant_name_short}kv${random_string.suffix.result}"
  location            = var.location
  resource_group_name = local.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                       = var.key_vault.sku
  purge_protection_enabled       = var.key_vault.purge_protection_enabled
  soft_delete_retention_days     = var.key_vault.soft_delete_retention_days
  public_network_access_enabled  = false
  legacy_access_policies_enabled = false # Use RBAC instead

  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  # CRITICAL: Set to false to let Azure Policy manage DNS zone groups
  private_endpoints_manage_dns_zone_group = false

  private_endpoints = {
    primary = {
      subnet_resource_id = var.private_endpoint_subnet_id
      tags               = var.tags
    }
  }

  # Diagnostic settings managed separately to control lifecycle and prevent drift
  diagnostic_settings = {}

  tags             = var.tags
  enable_telemetry = false

  depends_on = [azurerm_resource_group.tenant]
}

# Diagnostic settings for Key Vault (managed separately from AVM to prevent drift)
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  count = var.key_vault.enabled && local.has_log_analytics && local.kv_diagnostics != null ? 1 : 0

  name                           = "${local.name_prefix}-kv-diag"
  target_resource_id             = module.key_vault[0].resource_id
  log_analytics_workspace_id     = local.tenant_log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = local.kv_log_groups
    content {
      category_group = enabled_log.value
    }
  }

  dynamic "enabled_log" {
    for_each = local.kv_log_categories
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = local.kv_metric_categories
    content {
      category = enabled_metric.value
    }
  }

  # Ignore drift on log_analytics_destination_type - Azure may reset this
  lifecycle {
    ignore_changes = [log_analytics_destination_type]
  }
}

# =============================================================================
# STORAGE ACCOUNT (public access for Landing Zone - no private endpoint needed)
# =============================================================================
resource "azurerm_storage_account" "this" {
  count = var.storage_account.enabled ? 1 : 0

  name                = "${local.tenant_name_short}st${random_string.suffix.result}"
  location            = var.location
  resource_group_name = local.resource_group_name

  account_tier             = var.storage_account.account_tier
  account_replication_type = var.storage_account.account_replication_type
  account_kind             = var.storage_account.account_kind
  access_tier              = var.storage_account.access_tier

  # Public access allowed in Landing Zone for storage accounts
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags

  lifecycle {
    # Ignore tags (managed externally) and network_rules drift (Azure may add ip_rules/subnet_ids)
    ignore_changes = [tags, network_rules]
  }

  depends_on = [azurerm_resource_group.tenant]
}

# Default container for AI Foundry project connection
resource "azurerm_storage_container" "default" {
  count = var.storage_account.enabled ? 1 : 0

  name                  = "default"
  storage_account_id    = azurerm_storage_account.this[0].id
  container_access_type = "private"
}

# Storage diagnostics -> tenant Log Analytics (if enabled)
resource "azurerm_monitor_diagnostic_setting" "storage" {
  count = var.storage_account.enabled && local.has_log_analytics && local.storage_diagnostics != null ? 1 : 0

  name                       = "${local.name_prefix}-storage-diag"
  target_resource_id         = azurerm_storage_account.this[0].id
  log_analytics_workspace_id = local.tenant_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.storage_log_groups
    content {
      category_group = enabled_log.value
    }
  }

  dynamic "enabled_log" {
    for_each = local.storage_log_categories
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = local.storage_metric_categories
    content {
      category = enabled_metric.value
    }
  }
}

# =============================================================================
# AI SEARCH (using AVM)
# https://github.com/Azure/terraform-azurerm-avm-res-search-searchservice
# =============================================================================
module "ai_search" {
  source  = "Azure/avm-res-search-searchservice/azurerm"
  version = "0.2.0"
  count   = var.ai_search.enabled ? 1 : 0

  name                = "${local.name_prefix}-search-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = local.resource_group_name

  sku                           = var.ai_search.sku
  replica_count                 = var.ai_search.replica_count
  partition_count               = var.ai_search.partition_count
  semantic_search_sku           = var.ai_search.semantic_search
  local_authentication_enabled  = var.ai_search.local_auth_enabled
  public_network_access_enabled = false

  # Enable AAD authentication for managed identity access from APIM
  authentication_failure_mode = "http401WithBearerChallenge"

  managed_identities = {
    system_assigned = true
  }

  # CRITICAL: Set to false to let Azure Policy manage DNS zone groups
  private_endpoints_manage_dns_zone_group = false

  private_endpoints = {
    primary = {
      subnet_resource_id = var.private_endpoint_subnet_id
      tags               = var.tags
    }
  }

  # Diagnostic settings managed separately to control lifecycle and prevent drift
  diagnostic_settings = {}

  tags             = var.tags
  enable_telemetry = false

  depends_on = [azurerm_resource_group.tenant]
}

# Diagnostic settings for AI Search (managed separately from AVM to prevent drift)
resource "azurerm_monitor_diagnostic_setting" "ai_search" {
  count = var.ai_search.enabled && local.has_log_analytics && local.search_diagnostics != null ? 1 : 0

  name                           = "${local.name_prefix}-search-diag"
  target_resource_id             = module.ai_search[0].resource_id
  log_analytics_workspace_id     = local.tenant_log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = local.search_log_groups
    content {
      category_group = enabled_log.value
    }
  }

  dynamic "enabled_log" {
    for_each = local.search_log_categories
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = local.search_metric_categories
    content {
      category = enabled_metric.value
    }
  }

  # Ignore drift on log_analytics_destination_type - Azure may reset this
  lifecycle {
    ignore_changes = [log_analytics_destination_type]
  }
}

# =============================================================================
# COSMOS DB (using azurerm - AVM module not yet fully featured)
# =============================================================================
resource "azurerm_cosmosdb_account" "this" {
  count = var.cosmos_db.enabled ? 1 : 0

  name                = "${local.name_prefix}-cosmos-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = local.resource_group_name
  offer_type          = var.cosmos_db.offer_type
  kind                = var.cosmos_db.kind

  consistency_policy {
    consistency_level       = var.cosmos_db.consistency_level
    max_interval_in_seconds = var.cosmos_db.max_interval_in_seconds
    max_staleness_prefix    = var.cosmos_db.max_staleness_prefix
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  public_network_access_enabled     = false
  is_virtual_network_filter_enabled = false
  automatic_failover_enabled        = var.cosmos_db.automatic_failover_enabled
  analytical_storage_enabled        = true
  local_authentication_disabled     = true

  capacity {
    total_throughput_limit = var.cosmos_db.total_throughput_limit
  }

  backup {
    type = "Continuous"
    tier = var.cosmos_db.geo_redundant_backup_enabled ? "Continuous30Days" : "Continuous7Days"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# Cosmos DB SQL Database - pre-create for AAD authentication
# Note: Database creation via data plane REST API doesn't support AAD tokens,
# so we pre-create the database in Terraform using ARM (control plane)
resource "azurerm_cosmosdb_sql_database" "default" {
  count = var.cosmos_db.enabled ? 1 : 0

  name                = var.cosmos_db.database_name
  resource_group_name = local.resource_group_name
  account_name        = azurerm_cosmosdb_account.this[0].name
}

# Cosmos DB SQL Container - pre-create for AAD authentication
# Note: Container creation via data plane REST API doesn't support AAD tokens,
# so we pre-create the container in Terraform using ARM (control plane)
#
# Partition Key Strategy:
# Using "/id" as the partition key is suitable for general-purpose document storage
# where each document is accessed independently. For high-throughput scenarios with
# specific query patterns (e.g., multi-tenant apps querying by tenant_id), consider
# adding partition_key_path to the cosmos_db variable for per-tenant customization.
resource "azurerm_cosmosdb_sql_container" "default" {
  count = var.cosmos_db.enabled ? 1 : 0

  name                  = var.cosmos_db.container_name
  resource_group_name   = local.resource_group_name
  account_name          = azurerm_cosmosdb_account.this[0].name
  database_name         = azurerm_cosmosdb_sql_database.default[0].name
  partition_key_paths   = var.cosmos_db.partition_key_paths
  partition_key_version = 2
}

# Cosmos DB diagnostics -> tenant Log Analytics (if enabled)
resource "azurerm_monitor_diagnostic_setting" "cosmos" {
  count = var.cosmos_db.enabled && local.has_log_analytics && local.cosmos_diagnostics != null ? 1 : 0

  name                       = "${local.name_prefix}-cosmos-diag"
  target_resource_id         = azurerm_cosmosdb_account.this[0].id
  log_analytics_workspace_id = local.tenant_log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.cosmos_log_groups
    content {
      category_group = enabled_log.value
    }
  }

  dynamic "enabled_log" {
    for_each = local.cosmos_log_categories
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = local.cosmos_metric_categories
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_private_endpoint" "cosmos_db" {
  count = var.cosmos_db.enabled ? 1 : 0

  name                = "${local.name_prefix}-cosmos-pe"
  location            = var.location
  resource_group_name = local.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${local.name_prefix}-cosmos-psc"
    private_connection_resource_id = azurerm_cosmosdb_account.this[0].id
    is_manual_connection           = false
    subresource_names              = ["Sql"]
  }

  tags = var.tags

  lifecycle {
    # DNS zone group is managed by Azure Policy in Landing Zone
    ignore_changes = [tags, private_dns_zone_group]
  }
}

# =============================================================================
# DOCUMENT INTELLIGENCE (using AVM Cognitive Services)
# https://github.com/Azure/terraform-azurerm-avm-res-cognitiveservices-account
# =============================================================================
module "document_intelligence" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.6.0"
  count   = var.document_intelligence.enabled ? 1 : 0

  name                = "${local.name_prefix}-docint-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = local.resource_group_name
  kind                = var.document_intelligence.kind
  sku_name            = var.document_intelligence.sku

  public_network_access_enabled = false
  local_auth_enabled            = false
  custom_subdomain_name         = "${local.name_prefix}-docint-${random_string.suffix.result}"

  network_acls = {
    default_action = "Deny"
  }

  managed_identities = {
    system_assigned = true
  }

  # CRITICAL: Set to false to let Azure Policy manage DNS zone groups
  private_endpoints_manage_dns_zone_group = false

  private_endpoints = {
    primary = {
      subnet_resource_id = var.private_endpoint_subnet_id
      tags               = var.tags
    }
  }

  # Diagnostic settings managed separately to control lifecycle and prevent drift
  diagnostic_settings = {}

  tags             = var.tags
  enable_telemetry = false

  depends_on = [azurerm_resource_group.tenant]
}

# Diagnostic settings for Document Intelligence (managed separately from AVM to prevent drift)
resource "azurerm_monitor_diagnostic_setting" "document_intelligence" {
  count = var.document_intelligence.enabled && local.has_log_analytics && local.docint_diagnostics != null ? 1 : 0

  name                           = "${local.name_prefix}-docint-diag"
  target_resource_id             = module.document_intelligence[0].resource_id
  log_analytics_workspace_id     = local.tenant_log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = local.docint_log_groups
    content {
      category_group = enabled_log.value
    }
  }

  dynamic "enabled_log" {
    for_each = local.docint_log_categories
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = local.docint_metric_categories
    content {
      category = enabled_metric.value
    }
  }

  # Ignore drift on log_analytics_destination_type - Azure may reset this
  lifecycle {
    ignore_changes = [log_analytics_destination_type]
  }
}

# =============================================================================
# SPEECH SERVICES (using AVM Cognitive Services)
# https://github.com/Azure/terraform-azurerm-avm-res-cognitiveservices-account
# =============================================================================
module "speech_services" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.6.0"
  count   = var.speech_services.enabled ? 1 : 0

  name                = "${local.name_prefix}-speech-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = local.resource_group_name
  kind                = "SpeechServices"
  sku_name            = var.speech_services.sku

  public_network_access_enabled = false
  local_auth_enabled            = true
  custom_subdomain_name         = "${local.name_prefix}-speech-${random_string.suffix.result}"

  network_acls = {
    default_action = "Deny"
  }

  managed_identities = {
    system_assigned = true
  }

  # CRITICAL: Set to false to let Azure Policy manage DNS zone groups
  private_endpoints_manage_dns_zone_group = false

  private_endpoints = {
    primary = {
      subnet_resource_id = var.private_endpoint_subnet_id
      tags               = var.tags
    }
  }

  # Diagnostic settings managed separately to control lifecycle and prevent drift
  diagnostic_settings = {}

  tags             = var.tags
  enable_telemetry = false

  depends_on = [azurerm_resource_group.tenant]
}

# Diagnostic settings for Speech Services (managed separately from AVM to prevent drift)
resource "azurerm_monitor_diagnostic_setting" "speech_services" {
  count = var.speech_services.enabled && local.has_log_analytics && local.speech_diagnostics != null ? 1 : 0

  name                           = "${local.name_prefix}-speech-diag"
  target_resource_id             = module.speech_services[0].resource_id
  log_analytics_workspace_id     = local.tenant_log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = local.speech_log_groups
    content {
      category_group = enabled_log.value
    }
  }

  dynamic "enabled_log" {
    for_each = local.speech_log_categories
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = local.speech_metric_categories
    content {
      category = enabled_metric.value
    }
  }

  # Ignore drift on log_analytics_destination_type - Azure may reset this
  lifecycle {
    ignore_changes = [log_analytics_destination_type]
  }
}

# =============================================================================
# WAIT FOR POLICY-MANAGED DNS ZONE GROUPS
# Uses shared script to wait for Azure Policy to create DNS zone groups
# =============================================================================

# Wait for Key Vault PE DNS zone group
resource "null_resource" "wait_for_dns_key_vault" {
  count = var.scripts_dir != "" && var.key_vault.enabled ? 1 : 0

  triggers = {
    private_endpoint_id   = module.key_vault[0].private_endpoints["primary"].id
    resource_group_name   = local.resource_group_name
    private_endpoint_name = module.key_vault[0].private_endpoints["primary"].name
    timeout               = var.private_endpoint_dns_wait.timeout
    interval              = var.private_endpoint_dns_wait.poll_interval
    scripts_dir           = var.scripts_dir
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      ${self.triggers.scripts_dir}/wait-for-dns-zone.sh \
        --resource-group ${self.triggers.resource_group_name} \
        --private-endpoint-name ${self.triggers.private_endpoint_name} \
        --timeout ${self.triggers.timeout} \
        --interval ${self.triggers.interval}
    EOT
  }

  depends_on = [module.key_vault]
}

# Wait for AI Search PE DNS zone group
# Note: AI Search AVM v0.2.0 has a bug where private_endpoints output only includes
# managed DNS PEs, not unmanaged ones. We construct PE name from resource name.
resource "null_resource" "wait_for_dns_ai_search" {
  count = var.scripts_dir != "" && var.ai_search.enabled ? 1 : 0

  triggers = {
    # AI Search AVM v0.2.0 private_endpoints output is empty when private_endpoints_manage_dns_zone_group=false
    # Construct PE name from resource name using the AVM naming convention: "pe-${resource_name}"
    private_endpoint_id   = module.ai_search[0].resource_id
    resource_group_name   = local.resource_group_name
    private_endpoint_name = "pe-${module.ai_search[0].resource.name}"
    timeout               = var.private_endpoint_dns_wait.timeout
    interval              = var.private_endpoint_dns_wait.poll_interval
    scripts_dir           = var.scripts_dir
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      ${self.triggers.scripts_dir}/wait-for-dns-zone.sh \
        --resource-group ${self.triggers.resource_group_name} \
        --private-endpoint-name ${self.triggers.private_endpoint_name} \
        --timeout ${self.triggers.timeout} \
        --interval ${self.triggers.interval}
    EOT
  }

  depends_on = [module.ai_search]
}

# Wait for Cosmos DB PE DNS zone group
resource "null_resource" "wait_for_dns_cosmos_db" {
  count = var.scripts_dir != "" && var.cosmos_db.enabled ? 1 : 0

  triggers = {
    private_endpoint_id   = azurerm_private_endpoint.cosmos_db[0].id
    resource_group_name   = local.resource_group_name
    private_endpoint_name = azurerm_private_endpoint.cosmos_db[0].name
    timeout               = var.private_endpoint_dns_wait.timeout
    interval              = var.private_endpoint_dns_wait.poll_interval
    scripts_dir           = var.scripts_dir
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      ${self.triggers.scripts_dir}/wait-for-dns-zone.sh \
        --resource-group ${self.triggers.resource_group_name} \
        --private-endpoint-name ${self.triggers.private_endpoint_name} \
        --timeout ${self.triggers.timeout} \
        --interval ${self.triggers.interval}
    EOT
  }

  depends_on = [azurerm_private_endpoint.cosmos_db]
}

# Wait for Document Intelligence PE DNS zone group
# Note: Cognitive Services AVM v0.6.0 has a bug where private_endpoints output only
# includes managed DNS PEs, not unmanaged ones. We construct PE name from resource name.
# Cognitive Services uses "pep-${resource_name}" naming convention.
resource "null_resource" "wait_for_dns_document_intelligence" {
  count = var.scripts_dir != "" && var.document_intelligence.enabled ? 1 : 0

  triggers = {
    # Use resource_id as trigger for changes
    private_endpoint_id = module.document_intelligence[0].resource_id
    resource_group_name = local.resource_group_name
    # Cognitive Services AVM uses "pep-${resource_name}" for PE names
    private_endpoint_name = "pep-${module.document_intelligence[0].name}"
    timeout               = var.private_endpoint_dns_wait.timeout
    interval              = var.private_endpoint_dns_wait.poll_interval
    scripts_dir           = var.scripts_dir
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      ${self.triggers.scripts_dir}/wait-for-dns-zone.sh \
        --resource-group ${self.triggers.resource_group_name} \
        --private-endpoint-name ${self.triggers.private_endpoint_name} \
        --timeout ${self.triggers.timeout} \
        --interval ${self.triggers.interval}
    EOT
  }

  depends_on = [module.document_intelligence]
}

# Wait for Speech Services PE DNS zone group
# Note: Cognitive Services AVM v0.6.0 has a bug where private_endpoints output only
# includes managed DNS PEs, not unmanaged ones. We construct PE name from resource name.
# Cognitive Services uses "pep-${resource_name}" naming convention.
resource "null_resource" "wait_for_dns_speech_services" {
  count = var.scripts_dir != "" && var.speech_services.enabled ? 1 : 0

  triggers = {
    # Use resource_id as trigger for changes
    private_endpoint_id = module.speech_services[0].resource_id
    resource_group_name = local.resource_group_name
    # Cognitive Services AVM uses "pep-${resource_name}" for PE names
    private_endpoint_name = "pep-${module.speech_services[0].name}"
    timeout               = var.private_endpoint_dns_wait.timeout
    interval              = var.private_endpoint_dns_wait.poll_interval
    scripts_dir           = var.scripts_dir
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      ${self.triggers.scripts_dir}/wait-for-dns-zone.sh \
        --resource-group ${self.triggers.resource_group_name} \
        --private-endpoint-name ${self.triggers.private_endpoint_name} \
        --timeout ${self.triggers.timeout} \
        --interval ${self.triggers.interval}
    EOT
  }

  depends_on = [module.speech_services]
}

