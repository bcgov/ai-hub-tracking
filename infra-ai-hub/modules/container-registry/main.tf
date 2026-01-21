# Container Registry Module
# Uses Azure Verified Module for ACR with Premium SKU for private endpoints
# https://github.com/Azure/terraform-azurerm-avm-res-containerregistry-registry

# =============================================================================
# AZURE CONTAINER REGISTRY (using AVM)
# =============================================================================
module "container_registry" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "0.5.0"

  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  # SKU - Premium required for private endpoints, geo-replication, content trust
  sku = var.sku

  # Security settings
  public_network_access_enabled = var.public_network_access_enabled
  admin_enabled                 = var.admin_enabled
  anonymous_pull_enabled        = false
  quarantine_policy_enabled     = var.sku == "Premium" ? var.quarantine_policy_enabled : false
  data_endpoint_enabled         = var.sku == "Premium" ? var.data_endpoint_enabled : false
  export_policy_enabled         = var.export_policy_enabled

  # Network rules (only for private Premium registries)
  network_rule_bypass_option = var.public_network_access_enabled ? "None" : "AzureServices"
  network_rule_set = var.public_network_access_enabled ? null : {
    default_action = "Deny"
  }

  # Zone redundancy (Premium only)
  zone_redundancy_enabled = var.sku == "Premium" ? var.zone_redundancy_enabled : false

  # Managed identity
  managed_identities = {
    system_assigned = true
  }

  # Content trust / signing (Premium only)
  enable_trust_policy = var.sku == "Premium" ? var.enable_trust_policy : false

  # Retention policy for untagged images
  retention_policy_in_days = var.retention_policy_days

  # CRITICAL: Set to false to let Azure Policy manage DNS zone groups
  private_endpoints_manage_dns_zone_group = false

  # Private endpoints only when public access is disabled and subnet is provided
  private_endpoints = var.public_network_access_enabled || var.private_endpoint_subnet_id == null ? {} : {
    primary = {
      subnet_resource_id = var.private_endpoint_subnet_id
      tags               = var.tags
    }
  }

  # Geo-replication (Premium only, optional)
  georeplications = var.georeplications

  # Diagnostic settings
  diagnostic_settings = var.log_analytics_workspace_id != null ? {
    to_law = {
      name                  = "${var.name}-diag"
      workspace_resource_id = var.log_analytics_workspace_id
      log_groups            = ["allLogs"]
      metric_categories     = ["AllMetrics"]
    }
  } : {}

  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}
