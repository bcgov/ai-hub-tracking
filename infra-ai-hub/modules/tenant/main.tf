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
# AI FOUNDRY PROJECT (using azapi - no AVM available yet)
# =============================================================================
resource "azapi_resource" "ai_foundry_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name      = "${local.name_prefix}-project"
  location  = coalesce(var.ai_location, var.location) # Must match parent hub location
  parent_id = var.ai_foundry_hub_id

  identity {
    type = "SystemAssigned"
  }

  body = {
    sku = {
      name = "S0"
    }
    properties = {
      displayName = var.display_name
      description = "AI Foundry project for ${var.display_name}"
    }
  }

  tags = var.tags

  response_export_values = [
    "identity.principalId",
    "properties.internalId"
  ]

  schema_validation_enabled = false

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
    type               = "Continuous"
    tier               = var.cosmos_db.geo_redundant_backup_enabled ? "Continuous30Days" : "Continuous7Days"
    storage_redundancy = var.cosmos_db.geo_redundant_backup_enabled ? "Geo" : "Local"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
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
# OPENAI (using AVM Cognitive Services)
# https://github.com/Azure/terraform-azurerm-avm-res-cognitiveservices-account
# =============================================================================
module "openai" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.6.0"
  count   = var.openai.enabled ? 1 : 0

  name                = "${local.name_prefix}-oai-${random_string.suffix.result}"
  location            = coalesce(var.ai_location, var.location)
  resource_group_name = local.resource_group_name
  kind                = "OpenAI"
  sku_name            = var.openai.sku

  public_network_access_enabled = false
  local_auth_enabled            = false
  custom_subdomain_name         = "${local.name_prefix}-oai-${random_string.suffix.result}"

  network_acls = {
    default_action = "Deny"
  }

  managed_identities = {
    system_assigned = true
  }

  # Model deployments with RAI policy support
  cognitive_deployments = {
    for deployment in var.openai.model_deployments : deployment.name => {
      name = deployment.name
      model = {
        format  = "OpenAI"
        name    = deployment.model_name
        version = deployment.model_version
      }
      scale = {
        type     = deployment.scale_type
        capacity = deployment.capacity
      }
      rai_policy_name = deployment.rai_policy_name
    }
  }

  # CRITICAL: Set to false to let Azure Policy manage DNS zone groups
  private_endpoints_manage_dns_zone_group = false

  private_endpoints = {
    primary = {
      subnet_resource_id = var.private_endpoint_subnet_id
      tags               = var.tags
      location           = var.location # must be canada central for PE as subnets are region-specific
    }
  }

  # Diagnostic settings managed separately to control lifecycle and prevent drift
  diagnostic_settings = {}

  tags             = var.tags
  enable_telemetry = false

  depends_on = [azurerm_resource_group.tenant]
}

# Diagnostic settings for OpenAI (managed separately from AVM to prevent drift)
resource "azurerm_monitor_diagnostic_setting" "openai" {
  count = var.openai.enabled && local.has_log_analytics && local.openai_diagnostics != null ? 1 : 0

  name                           = "${local.name_prefix}-openai-diag"
  target_resource_id             = module.openai[0].resource_id
  log_analytics_workspace_id     = local.tenant_log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = local.openai_log_groups
    content {
      category_group = enabled_log.value
    }
  }

  dynamic "enabled_log" {
    for_each = local.openai_log_categories
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = local.openai_metric_categories
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
# ROLE ASSIGNMENTS FOR AI FOUNDRY PROJECT
# Grant the project's managed identity access to tenant resources
# =============================================================================

# Key Vault access for AI Foundry Project
resource "azurerm_role_assignment" "project_to_keyvault" {
  count = var.key_vault.enabled ? 1 : 0

  scope                = module.key_vault[0].resource_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = local.project_principal_id
}

# Storage access for AI Foundry Project
resource "azurerm_role_assignment" "project_to_storage" {
  count = var.storage_account.enabled ? 1 : 0

  scope                = azurerm_storage_account.this[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.project_principal_id
}

# AI Search access for AI Foundry Project
resource "azurerm_role_assignment" "project_to_search" {
  count = var.ai_search.enabled ? 1 : 0

  scope                = module.ai_search[0].resource_id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = local.project_principal_id
}

# Cosmos DB access for AI Foundry Project
resource "azurerm_role_assignment" "project_to_cosmos" {
  count = var.cosmos_db.enabled ? 1 : 0

  scope                = azurerm_cosmosdb_account.this[0].id
  role_definition_name = "Cosmos DB Account Reader Role"
  principal_id         = local.project_principal_id
}

# Document Intelligence access for AI Foundry Project
resource "azurerm_role_assignment" "project_to_docint" {
  count = var.document_intelligence.enabled ? 1 : 0

  scope                = module.document_intelligence[0].resource_id
  role_definition_name = "Cognitive Services User"
  principal_id         = local.project_principal_id
}

# OpenAI access for AI Foundry Project
resource "azurerm_role_assignment" "project_to_openai" {
  count = var.openai.enabled ? 1 : 0

  scope                = module.openai[0].resource_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = local.project_principal_id
}

# =============================================================================
# PROJECT CONNECTIONS
# These create AI Foundry project connections to tenant resources
# Connections allow the AI Foundry project to discover and use resources
# =============================================================================

# Connection to Key Vault
resource "azapi_resource" "connection_keyvault" {
  count = var.key_vault.enabled && var.project_connections.key_vault ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "keyvault-${local.name_prefix}"
  parent_id = azapi_resource.ai_foundry_project.id

  body = {
    properties = {
      authType      = "AAD" # Required discriminator for managed identity auth
      category      = "AzureKeyVault"
      target        = module.key_vault[0].resource_id
      isSharedToAll = false # Tenant-specific connection, not shared across projects
      metadata = {
        ApiType    = "Azure"
        ApiVersion = "7.4"
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [module.key_vault, azurerm_role_assignment.project_to_keyvault]
}

# Connection to Storage Account
# NOTE: Connections are chained via depends_on to serialize API calls and avoid ETag conflicts
resource "azapi_resource" "connection_storage" {
  count = var.storage_account.enabled && var.project_connections.storage ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "storage-${local.name_prefix}"
  parent_id = azapi_resource.ai_foundry_project.id

  body = {
    properties = {
      authType      = "AAD" # Required discriminator for managed identity auth
      category      = "AzureBlob"
      target        = "https://${azurerm_storage_account.this[0].name}.blob.core.windows.net"
      isSharedToAll = false # Tenant-specific connection, not shared across projects
      metadata = {
        AccountName   = azurerm_storage_account.this[0].name
        ContainerName = "default"
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [
    azurerm_storage_account.this,
    azurerm_role_assignment.project_to_storage,
    azurerm_storage_container.default,
    azapi_resource.connection_keyvault # Serialize connection operations
  ]
}

# Connection to AI Search
resource "azapi_resource" "connection_ai_search" {
  count = var.ai_search.enabled && var.project_connections.ai_search ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "aisearch-${local.name_prefix}"
  parent_id = azapi_resource.ai_foundry_project.id

  body = {
    properties = {
      authType      = "AAD" # Required discriminator for managed identity auth
      category      = "CognitiveSearch"
      target        = module.ai_search[0].resource_id
      isSharedToAll = false # Tenant-specific connection, not shared across projects
      metadata = {
        ApiType    = "Azure"
        ApiVersion = "2024-05-01-preview"
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [
    module.ai_search,
    azurerm_role_assignment.project_to_search,
    azapi_resource.connection_storage # Serialize connection operations
  ]
}

# Connection to Cosmos DB
resource "azapi_resource" "connection_cosmos" {
  count = var.cosmos_db.enabled && var.project_connections.cosmos_db ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "cosmosdb-${local.name_prefix}"
  parent_id = azapi_resource.ai_foundry_project.id

  body = {
    properties = {
      authType      = "AAD"      # Required discriminator for managed identity auth
      category      = "CosmosDb" # API spec uses "CosmosDb" (not "CosmosDB")
      target        = azurerm_cosmosdb_account.this[0].id
      isSharedToAll = false # Tenant-specific connection, not shared across projects
      metadata = {
        ApiType    = "Azure"
        DatabaseId = var.cosmos_db.database_name
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [
    azurerm_cosmosdb_account.this,
    azurerm_role_assignment.project_to_cosmos,
    azapi_resource.connection_ai_search # Serialize connection operations
  ]
}

# Connection to OpenAI
resource "azapi_resource" "connection_openai" {
  count = var.openai.enabled && var.project_connections.openai ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "openai-${local.name_prefix}"
  parent_id = azapi_resource.ai_foundry_project.id

  body = {
    properties = {
      authType      = "AAD" # Required discriminator for managed identity auth
      category      = "AzureOpenAI"
      target        = module.openai[0].resource_id
      isSharedToAll = false # Tenant-specific connection, not shared across projects
      metadata = {
        ApiType    = "Azure"
        ApiVersion = "2024-06-01"
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [
    module.openai,
    azurerm_role_assignment.project_to_openai,
    azapi_resource.connection_cosmos # Serialize connection operations
  ]
}

# Connection to Document Intelligence
resource "azapi_resource" "connection_docint" {
  count = var.document_intelligence.enabled && var.project_connections.document_intelligence ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "docint-${local.name_prefix}"
  parent_id = azapi_resource.ai_foundry_project.id

  body = {
    properties = {
      authType      = "AAD" # Required discriminator for managed identity auth
      category      = "CognitiveService"
      target        = module.document_intelligence[0].endpoint
      isSharedToAll = false # Tenant-specific connection, not shared across projects
      metadata = {
        ApiType = "Azure"
        Kind    = "FormRecognizer"
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [
    module.document_intelligence,
    azurerm_role_assignment.project_to_docint,
    azapi_resource.connection_openai # Serialize connection operations
  ]
}

# =============================================================================
# CUSTOM ROLE ASSIGNMENTS
# Allows configuration of additional RBAC assignments for principals
# =============================================================================

# Custom role assignments at Resource Group scope
resource "azurerm_role_assignment" "custom_rg" {
  for_each = { for ra in var.role_assignments.resource_group : "${ra.principal_id}-${ra.role_definition_name}" => ra }

  scope                = azurerm_resource_group.tenant.id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
  principal_type       = lookup(each.value, "principal_type", null)
  description          = lookup(each.value, "description", null)
}

# Custom role assignments for Key Vault
resource "azurerm_role_assignment" "custom_keyvault" {
  for_each = var.key_vault.enabled ? {
    for ra in var.role_assignments.key_vault : "${ra.principal_id}-${ra.role_definition_name}" => ra
  } : {}

  scope                = module.key_vault[0].resource_id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
  principal_type       = lookup(each.value, "principal_type", null)
  description          = lookup(each.value, "description", null)
}

# Custom role assignments for Storage Account
resource "azurerm_role_assignment" "custom_storage" {
  for_each = var.storage_account.enabled ? {
    for ra in var.role_assignments.storage : "${ra.principal_id}-${ra.role_definition_name}" => ra
  } : {}

  scope                = azurerm_storage_account.this[0].id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
  principal_type       = lookup(each.value, "principal_type", null)
  description          = lookup(each.value, "description", null)
}

# Custom role assignments for AI Search
resource "azurerm_role_assignment" "custom_search" {
  for_each = var.ai_search.enabled ? {
    for ra in var.role_assignments.ai_search : "${ra.principal_id}-${ra.role_definition_name}" => ra
  } : {}

  scope                = module.ai_search[0].resource_id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
  principal_type       = lookup(each.value, "principal_type", null)
  description          = lookup(each.value, "description", null)
}

# Custom role assignments for OpenAI
resource "azurerm_role_assignment" "custom_openai" {
  for_each = var.openai.enabled ? {
    for ra in var.role_assignments.openai : "${ra.principal_id}-${ra.role_definition_name}" => ra
  } : {}

  scope                = module.openai[0].resource_id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
  principal_type       = lookup(each.value, "principal_type", null)
  description          = lookup(each.value, "description", null)
}

# Custom role assignments for Cosmos DB
resource "azurerm_role_assignment" "custom_cosmos" {
  for_each = var.cosmos_db.enabled ? {
    for ra in var.role_assignments.cosmos_db : "${ra.principal_id}-${ra.role_definition_name}" => ra
  } : {}

  scope                = azurerm_cosmosdb_account.this[0].id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
  principal_type       = lookup(each.value, "principal_type", null)
  description          = lookup(each.value, "description", null)
}

