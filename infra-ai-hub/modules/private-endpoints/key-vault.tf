# ============================================================================
# Key Vault Private Endpoints
# ============================================================================

resource "azurerm_private_endpoint" "keyvault_pe" {
  for_each = var.enabled ? var.ai_foundry_definition.key_vault_definition : {}

  name                = "${each.value.name}-pe-${var.location}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${each.value.name}-psc-${var.location}"
    private_connection_resource_id = var.foundry_ptn.key_vault_id[each.key]
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_rg_id != null ? [1] : []
    content {
      name = "default"
      private_dns_zone_ids = [
        "${var.private_dns_zone_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
      ]
    }
  }
}
