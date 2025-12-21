data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}
/* data "azurerm_subnet" "pe-subnet" {
  name                 = "privateendpoints-subnet"
  virtual_network_name = var.vnet_name
  resource_group_name  = var.vnet_resource_group_name
} */
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name  = "standard"

  # Security requirements: do not disable purge protection.
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  # Policy-friendly configuration: private-only access.
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  # Grant this principal secret permissions via access policies.
  # This avoids needing Microsoft.Authorization/roleAssignments/write.
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Purge",
      "Recover"
    ]
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [azurerm_resource_group.main]
}

## Private Endpoint for azure kv
/* resource "azurerm_private_endpoint" "key_vault_pe" {
  name                = "${var.app_name}-kv-pe"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = data.azurerm_subnet.pe-subnet.id

  private_service_connection {
    name                           = "${var.app_name}-kv-psc"
    private_connection_resource_id = azurerm_key_vault.main.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags, private_dns_zone_group]
  }

  depends_on = [azurerm_key_vault.main]
} */

resource "random_password" "secret_one" {
  length  = 32
  special = true
}

resource "random_password" "secret_two" {
  length  = 48
  special = true
}

resource "time_sleep" "wait_for_kv_access" {
  create_duration = "30s"
  depends_on      = [azurerm_private_endpoint.key_vault_pe]
}

resource "azurerm_key_vault_secret" "secret_one" {
  name            = "example-secret-one"
  value           = random_password.secret_one.result
  key_vault_id    = azurerm_key_vault.main.id
  expiration_date = "2025-12-31T23:59:59Z"
  content_type    = "text/plain"
  depends_on      = [time_sleep.wait_for_kv_access]
}

resource "azurerm_key_vault_secret" "secret_two" {
  name            = "example-secret-two"
  value           = random_password.secret_two.result
  key_vault_id    = azurerm_key_vault.main.id
  expiration_date = "2025-12-31T23:59:59Z"

  content_type = "text/plain"
  depends_on   = [time_sleep.wait_for_kv_access]
}
