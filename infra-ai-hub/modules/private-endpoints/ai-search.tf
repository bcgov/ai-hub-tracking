# ============================================================================
# AI Search Private Endpoints
# ============================================================================

resource "azurerm_private_endpoint" "ai_search_pe" {
  for_each = var.enabled ? var.ai_foundry_definition.ai_search_definition : {}

  name                = replace(substr(replace("${each.value.name}-pe-${local.location_slug}", "/[^0-9A-Za-z._-]/", "-"), 0, 80), "/[^0-9A-Za-z_]+$/", "")
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = replace(substr(replace("${each.value.name}-psc-${local.location_slug}", "/[^0-9A-Za-z._-]/", "-"), 0, 80), "/[^0-9A-Za-z_]+$/", "")
    private_connection_resource_id = var.foundry_ptn.ai_search_id[each.key]
    is_manual_connection           = false
    subresource_names              = ["searchService"]
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_rg_id != null ? [1] : []
    content {
      name = "default"
      private_dns_zone_ids = [
        "${var.private_dns_zone_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      ]
    }
  }
}
