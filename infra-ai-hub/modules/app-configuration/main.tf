# App Configuration Module
# Uses Azure App Configuration for feature flags and configuration management
# https://learn.microsoft.com/en-us/azure/azure-app-configuration/

# =============================================================================
# APP CONFIGURATION STORE
# =============================================================================
resource "azurerm_app_configuration" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  sku = var.sku

  # Security settings
  public_network_access      = var.public_network_access_enabled ? "Enabled" : "Disabled"
  local_auth_enabled         = var.local_auth_enabled
  purge_protection_enabled   = var.purge_protection_enabled
  soft_delete_retention_days = var.soft_delete_retention_days

  # Managed identity for RBAC
  identity {
    type = "SystemAssigned"
  }

  # Encryption (optional, Standard SKU only)
  dynamic "encryption" {
    for_each = var.encryption.enabled && var.sku == "standard" ? [1] : []
    content {
      key_vault_key_identifier = var.encryption.key_vault_key_id
      identity_client_id       = var.encryption.identity_client_id
    }
  }

  # Replication (Standard SKU only)
  dynamic "replica" {
    for_each = var.sku == "standard" ? var.replicas : []
    content {
      name     = replica.value.name
      location = replica.value.location
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# =============================================================================
# PRIVATE ENDPOINT
# =============================================================================
resource "azurerm_private_endpoint" "app_config" {
  count = var.private_endpoint_subnet_id != null ? 1 : 0

  name                = "${var.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.name}-psc"
    private_connection_resource_id = azurerm_app_configuration.this.id
    is_manual_connection           = false
    subresource_names              = ["configurationStores"]
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags, private_dns_zone_group]
  }
}

# =============================================================================
# FEATURE FLAGS (optional)
# =============================================================================
resource "azurerm_app_configuration_feature" "features" {
  for_each = var.feature_flags

  configuration_store_id = azurerm_app_configuration.this.id
  name                   = each.key
  description            = each.value.description
  enabled                = each.value.enabled
  label                  = lookup(each.value, "label", null)

  dynamic "targeting_filter" {
    for_each = lookup(each.value, "targeting", null) != null ? [each.value.targeting] : []
    content {
      default_rollout_percentage = targeting_filter.value.default_percentage
      groups {
        name               = targeting_filter.value.group_name
        rollout_percentage = targeting_filter.value.group_percentage
      }
    }
  }
}

# =============================================================================
# CONFIGURATION KEY-VALUES (optional)
# =============================================================================
resource "azurerm_app_configuration_key" "keys" {
  for_each = var.configuration_keys

  configuration_store_id = azurerm_app_configuration.this.id
  key                    = each.key
  value                  = each.value.value
  type                   = each.value.type # kv (key-value) or vault (Key Vault reference)
  label                  = lookup(each.value, "label", null)
  content_type           = lookup(each.value, "content_type", null)

  # For Key Vault references
  vault_key_reference = each.value.type == "vault" ? each.value.vault_key_reference : null
}

# =============================================================================
# DIAGNOSTIC SETTINGS
# =============================================================================
resource "azurerm_monitor_diagnostic_setting" "app_config" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "${var.name}-diag"
  target_resource_id         = azurerm_app_configuration.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
