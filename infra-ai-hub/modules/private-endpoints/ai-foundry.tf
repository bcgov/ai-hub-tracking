# ============================================================================
# AI Foundry Hub Private Endpoints
# ============================================================================

resource "azurerm_private_endpoint" "ai_foundry_pe" {
  count = var.enabled ? 1 : 0

  name                = replace(substr(replace("${var.ai_foundry_name}-pe-${local.location_slug}", "/[^0-9A-Za-z._-]/", "-"), 0, 80), "/[^0-9A-Za-z_]+$/", "")
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = replace(substr(replace("${var.ai_foundry_name}-psc-${local.location_slug}", "/[^0-9A-Za-z._-]/", "-"), 0, 80), "/[^0-9A-Za-z_]+$/", "")
    private_connection_resource_id = var.foundry_ptn.resource_id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_rg_id != null ? [1] : []
    content {
      name = "default"
      private_dns_zone_ids = [
        "${var.private_dns_zone_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com",
        "${var.private_dns_zone_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com",
        "${var.private_dns_zone_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      ]
    }
  }
}
