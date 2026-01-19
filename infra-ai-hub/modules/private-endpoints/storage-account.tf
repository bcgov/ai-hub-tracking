# ============================================================================
# Storage Account Private Endpoints (blob, file, queue, table, dfs)
# ============================================================================

locals {
  # Create a flat list of storage account endpoints for cross-region private endpoints
  storage_endpoints = var.enabled ? flatten([
    for sa_key, sa_def in var.ai_foundry_definition.storage_account_definition : [
      for endpoint_type in ["blob", "file", "queue", "table", "dfs"] : {
        key              = "${sa_key}-${endpoint_type}"
        sa_key           = sa_key
        sa_name          = sa_def.name
        sa_resource_id   = var.foundry_ptn.storage_account_id[sa_key]
        endpoint_type    = endpoint_type
        subresource_name = endpoint_type
        dns_zone = (
          endpoint_type == "blob" ? "privatelink.blob.core.windows.net" :
          endpoint_type == "file" ? "privatelink.file.core.windows.net" :
          endpoint_type == "queue" ? "privatelink.queue.core.windows.net" :
          endpoint_type == "table" ? "privatelink.table.core.windows.net" :
          "privatelink.dfs.core.windows.net"
        )
      }
    ]
  ]) : []
}

resource "azurerm_private_endpoint" "storage_pe" {
  for_each = { for item in local.storage_endpoints : item.key => item }

  name                = "${each.value.sa_name}-${each.value.endpoint_type}-pe-${var.location}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${each.value.sa_name}-${each.value.endpoint_type}-psc-${var.location}"
    private_connection_resource_id = each.value.sa_resource_id
    is_manual_connection           = false
    subresource_names              = [each.value.subresource_name]
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_rg_id != null ? [1] : []
    content {
      name = "default"
      private_dns_zone_ids = [
        "${var.private_dns_zone_rg_id}/providers/Microsoft.Network/privateDnsZones/${each.value.dns_zone}"
      ]
    }
  }
}
