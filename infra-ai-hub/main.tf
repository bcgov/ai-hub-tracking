# =============================================================================
# AI FOUNDRY MULTI-TENANT INFRASTRUCTURE
# =============================================================================
# This is the root module that orchestrates:
# 1. Network (shared PE subnet, APIM subnet for VNet injection, App GW subnet)
# 2. AI Foundry Hub (shared account)
# 3. APIM (shared, with per-tenant products)
# 4. App Gateway (optional, WAF in front of APIM)
# 5. Tenant resources (per-tenant projects and resources)
#
# Configuration is loaded from params/{app_env}/shared and params/{app_env}/tenants
# See locals.tf for configuration loading logic.
# =============================================================================

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# -----------------------------------------------------------------------------
# Resource Group (shared)
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# -----------------------------------------------------------------------------
# Network Module (PE subnet, APIM subnet, AppGW subnet)
# -----------------------------------------------------------------------------
module "network" {
  source = "./modules/network"

  name_prefix = var.resource_group_name
  location    = var.location
  common_tags = var.common_tags

  vnet_name                = var.vnet_name
  vnet_resource_group_name = var.vnet_resource_group_name

  target_vnet_address_spaces   = var.target_vnet_address_spaces
  source_vnet_address_space    = var.source_vnet_address_space
  private_endpoint_subnet_name = var.private_endpoint_subnet_name

  # APIM subnet (enabled when APIM uses VNet injection - Premium v2)
  # Set enabled = false if APIM uses private endpoints only (stv2 style)
  apim_subnet = {
    enabled       = lookup(local.apim_config, "vnet_injection_enabled", false)
    name          = lookup(local.apim_config, "subnet_name", "apim-subnet")
    prefix_length = lookup(local.apim_config, "subnet_prefix_length", 27)
  }

  # App Gateway subnet (enabled when App GW is enabled, auto-placed after PE/APIM subnets)
  appgw_subnet = {
    enabled       = local.appgw_config.enabled
    name          = lookup(local.appgw_config, "subnet_name", "appgw-subnet")
    prefix_length = lookup(local.appgw_config, "subnet_prefix_length", 27)
  }

  depends_on = [azurerm_resource_group.main]
}

# -----------------------------------------------------------------------------
# AI Foundry Hub (shared)
# -----------------------------------------------------------------------------
module "ai_foundry_hub" {
  source = "./modules/ai-foundry-hub"

  name                = "${var.app_name}-${var.app_env}-${var.shared_config.ai_foundry.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  resource_group_id   = azurerm_resource_group.main.id
  location            = var.location

  sku                           = var.shared_config.ai_foundry.sku
  public_network_access_enabled = var.shared_config.ai_foundry.public_network_access_enabled
  local_auth_enabled            = var.shared_config.ai_foundry.local_auth_enabled

  # Cross-region deployment for model availability
  ai_location = var.shared_config.ai_foundry.ai_location

  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id

  log_analytics = {
    enabled        = var.shared_config.log_analytics.enabled
    retention_days = var.shared_config.log_analytics.retention_days
    sku            = var.shared_config.log_analytics.sku
  }

  # Application Insights configuration (enabled by default if log analytics is enabled)
  application_insights = {
    enabled = var.shared_config.log_analytics.enabled
  }

  private_endpoint_dns_wait = {
    timeout       = var.shared_config.private_endpoint_dns_wait.timeout
    poll_interval = var.shared_config.private_endpoint_dns_wait.poll_interval
  }

  scripts_dir = "${path.module}/scripts"

  tags = var.common_tags

  depends_on = [module.network]
}

# -----------------------------------------------------------------------------
# API Management (shared, with per-tenant products) - stv2 with Private Endpoints
# -----------------------------------------------------------------------------
module "apim" {
  source = "./modules/apim"
  count  = local.apim_config.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-apim"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  sku_name        = lookup(local.apim_config, "sku_name", "Standard_v2")
  publisher_name  = lookup(local.apim_config, "publisher_name", "AI Hub")
  publisher_email = lookup(local.apim_config, "publisher_email", "admin@example.com")

  # stv2: Use private endpoints instead of VNet injection
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  private_dns_zone_ids       = lookup(local.apim_config, "private_dns_zone_ids", [])

  # Per-tenant products
  tenant_products = local.tenant_products

  # Diagnostics
  log_analytics_workspace_id = module.ai_foundry_hub.log_analytics_workspace_id

  tags = var.common_tags

  depends_on = [module.network, module.ai_foundry_hub]
}

# -----------------------------------------------------------------------------
# Application Gateway (optional, WAF in front of APIM)
# When enabled, APIM becomes internal-only and App GW is the public entry point
# -----------------------------------------------------------------------------
module "app_gateway" {
  source = "./modules/app-gateway"
  count  = local.appgw_config.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-appgw"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  subnet_id = module.network.appgw_subnet_id

  sku = {
    name     = lookup(local.appgw_config, "sku_name", "WAF_v2")
    tier     = lookup(local.appgw_config, "sku_tier", "WAF_v2")
    capacity = lookup(local.appgw_config, "capacity", 2)
  }

  autoscale = lookup(local.appgw_config, "autoscale", null) != null ? {
    min_capacity = local.appgw_config.autoscale.min_capacity
    max_capacity = local.appgw_config.autoscale.max_capacity
  } : null

  waf_enabled = lookup(local.appgw_config, "waf_enabled", true)
  waf_mode    = lookup(local.appgw_config, "waf_mode", "Prevention")

  # SSL certificates from Key Vault
  ssl_certificates = {
    for k, v in lookup(local.appgw_config, "ssl_certificates", {}) : k => {
      name                = v.name
      key_vault_secret_id = v.key_vault_secret_id
    }
  }

  # Backend pointing to APIM
  backend_apim = {
    fqdn       = local.apim_config.enabled ? module.apim[0].gateway_url : ""
    https_port = 443
    probe_path = "/status-0123456789abcdef"
  }

  frontend_hostname = lookup(local.appgw_config, "frontend_hostname", "api.example.com")

  # Key Vault for SSL cert access
  key_vault_id = lookup(local.appgw_config, "key_vault_id", null)

  # Diagnostics
  log_analytics_workspace_id = module.ai_foundry_hub.log_analytics_workspace_id

  tags = var.common_tags

  depends_on = [module.network, module.apim]
}

# -----------------------------------------------------------------------------
# Tenant Resources (per tenant)
# -----------------------------------------------------------------------------
module "tenant" {
  source   = "./modules/tenant"
  for_each = local.enabled_tenants

  tenant_name  = each.value.tenant_name
  display_name = each.value.display_name

  # Optional custom RG name (defaults to {tenant_name}-rg)
  resource_group_name_override = lookup(each.value, "resource_group_name", null)
  location                     = var.location

  ai_foundry_hub_id          = module.ai_foundry_hub.id
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  log_analytics_workspace_id = module.ai_foundry_hub.log_analytics_workspace_id

  private_endpoint_dns_wait = {
    timeout       = var.shared_config.private_endpoint_dns_wait.timeout
    poll_interval = var.shared_config.private_endpoint_dns_wait.poll_interval
  }

  # Resource configurations from tenant config file
  key_vault = {
    enabled                    = lookup(each.value.key_vault, "enabled", false)
    sku                        = lookup(each.value.key_vault, "sku", "standard")
    purge_protection_enabled   = lookup(each.value.key_vault, "purge_protection_enabled", true)
    soft_delete_retention_days = lookup(each.value.key_vault, "soft_delete_retention_days", 90)
  }

  storage_account = {
    enabled                  = lookup(each.value.storage_account, "enabled", false)
    account_tier             = lookup(each.value.storage_account, "account_tier", "Standard")
    account_replication_type = lookup(each.value.storage_account, "account_replication_type", "LRS")
    account_kind             = lookup(each.value.storage_account, "account_kind", "StorageV2")
    access_tier              = lookup(each.value.storage_account, "access_tier", "Hot")
  }

  ai_search = {
    enabled            = lookup(each.value.ai_search, "enabled", false)
    sku                = lookup(each.value.ai_search, "sku", "basic")
    replica_count      = lookup(each.value.ai_search, "replica_count", 1)
    partition_count    = lookup(each.value.ai_search, "partition_count", 1)
    semantic_search    = lookup(each.value.ai_search, "semantic_search", "disabled")
    local_auth_enabled = lookup(each.value.ai_search, "local_auth_enabled", true)
  }

  cosmos_db = {
    enabled                      = lookup(each.value.cosmos_db, "enabled", false)
    offer_type                   = lookup(each.value.cosmos_db, "offer_type", "Standard")
    kind                         = lookup(each.value.cosmos_db, "kind", "GlobalDocumentDB")
    consistency_level            = lookup(each.value.cosmos_db, "consistency_level", "Session")
    max_interval_in_seconds      = lookup(each.value.cosmos_db, "max_interval_in_seconds", 5)
    max_staleness_prefix         = lookup(each.value.cosmos_db, "max_staleness_prefix", 100)
    geo_redundant_backup_enabled = lookup(each.value.cosmos_db, "geo_redundant_backup_enabled", false)
    automatic_failover_enabled   = lookup(each.value.cosmos_db, "automatic_failover_enabled", false)
    total_throughput_limit       = lookup(each.value.cosmos_db, "total_throughput_limit", 1000)
  }

  document_intelligence = {
    enabled = lookup(each.value.document_intelligence, "enabled", false)
    sku     = lookup(each.value.document_intelligence, "sku", "S0")
    kind    = lookup(each.value.document_intelligence, "kind", "FormRecognizer")
  }

  openai = {
    enabled = lookup(each.value.openai, "enabled", false)
    sku     = lookup(each.value.openai, "sku", "S0")
    model_deployments = [
      for deployment in lookup(each.value.openai, "model_deployments", []) : {
        name          = deployment.name
        model_name    = deployment.model_name
        model_version = deployment.model_version
        scale_type    = lookup(deployment, "scale_type", "Standard")
        capacity      = lookup(deployment, "capacity", 10)
      }
    ]
  }

  tags = merge(var.common_tags, lookup(each.value, "tags", {}))

  depends_on = [module.ai_foundry_hub]
}
