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

module "network" {
  source = "./modules/network"

  name_prefix = var.resource_group_name
  location    = var.location
  common_tags = var.common_tags

  vnet_name                = var.vnet_name
  vnet_resource_group_name = var.vnet_resource_group_name

  target_vnet_address_spaces            = var.target_vnet_address_spaces
  source_vnet_address_space             = var.source_vnet_address_space
  private_endpoint_subnet_name          = var.private_endpoint_subnet_name
  private_endpoint_subnet_prefix_length = var.private_endpoint_subnet_prefix_length
  private_endpoint_subnet_netnum        = var.private_endpoint_subnet_netnum

  depends_on = [azurerm_resource_group.main]
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

  # Azure Policy in the Landing Zone requires the RBAC permission model.
  # Roles must have been assigned to the identity running the tf scripts(managed identity)
  # the managed identity setup done in this project handles that, look at initial setup script.
  rbac_authorization_enabled = true

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [azurerm_resource_group.main, module.network]
}

## Private Endpoint for azure kv
resource "azurerm_private_endpoint" "key_vault_pe" {
  name                = "${var.app_name}-kv-pe"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.network.private_endpoint_subnet_id
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
  name            = "example-secret-one"
  value           = random_password.secret_one.result
  key_vault_id    = azurerm_key_vault.main.id
  expiration_date = "2025-12-31T23:59:59Z"
  content_type    = "text/plain"
}

resource "azurerm_key_vault_secret" "secret_two" {
  name            = "example-secret-two"
  value           = random_password.secret_two.result
  key_vault_id    = azurerm_key_vault.main.id
  expiration_date = "2025-12-31T23:59:59Z"

  content_type = "text/plain"
}
