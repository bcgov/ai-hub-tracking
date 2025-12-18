data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

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

  # Keep simple for now (no private endpoint in this folder).
  public_network_access_enabled = true

  # Access policy so Terraform can write secrets.
  # (If your org uses RBAC-only Key Vault, we can switch to enable_rbac_authorization=true.)
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

resource "random_password" "secret_one" {
  length  = 32
  special = true
}

resource "random_password" "secret_two" {
  length  = 48
  special = true
}

resource "azurerm_key_vault_secret" "secret_one" {
  name         = "example-secret-one"
  value        = random_password.secret_one.result
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "secret_two" {
  name         = "example-secret-two"
  value        = random_password.secret_two.result
  key_vault_id = azurerm_key_vault.main.id
}
