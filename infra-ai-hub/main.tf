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

# Hub policy attaches the Private DNS zone group and creates the A-record asynchronously.
# Data-plane operations (like creating secrets) can fail until DNS is ready.
#
# "Smarter" wait: poll Azure ARM until the policy-managed DNS zone group exists on the private endpoint.
resource "null_resource" "wait_for_key_vault_private_dns" {
  triggers = {
    private_endpoint_id = azurerm_private_endpoint.key_vault_pe.id
    resource_group_name = azurerm_resource_group.main.name
    private_endpoint    = azurerm_private_endpoint.key_vault_pe.name
    timeout             = var.private_endpoint_dns_wait_duration
    interval            = var.private_endpoint_dns_poll_interval
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-lc"]
    command     = <<-EOT
      set -euo pipefail

      duration_to_seconds() {
        value="$1"

        if echo "$value" | grep -Eq '^[0-9]+$'; then
          echo "$value"
          return 0
        fi

        if ! echo "$value" | grep -Eq '^[0-9]+[smhd]$'; then
          echo "Unsupported duration '$value'. Use e.g. 15s, 10m, 1h (or a raw number of seconds)." >&2
          return 1
        fi

        num="$(echo "$value" | sed -E 's/^([0-9]+)[smhd]$/\1/')"
        unit="$(echo "$value" | sed -E 's/^[0-9]+([smhd])$/\1/')"

        case "$unit" in
          s) echo "$num" ;;
          m) echo $((num * 60)) ;;
          h) echo $((num * 3600)) ;;
          d) echo $((num * 86400)) ;;
        esac
      }

      if ! command -v az >/dev/null 2>&1; then
        echo "Azure CLI (az) not found. Cannot poll for private DNS zone group." >&2
        exit 1
      fi

      RG="${azurerm_resource_group.main.name}"
      PE_NAME="${azurerm_private_endpoint.key_vault_pe.name}"
      TIMEOUT="${var.private_endpoint_dns_wait_duration}"
      INTERVAL="${var.private_endpoint_dns_poll_interval}"

      timeout_seconds="$(duration_to_seconds "$TIMEOUT")"
      interval_seconds="$(duration_to_seconds "$INTERVAL")"

      echo "Waiting for policy-created private DNS zone group on private endpoint '$PE_NAME' (rg='$RG')..." >&2
      echo "Timeout: $TIMEOUT ($timeout_seconds seconds), interval: $INTERVAL ($interval_seconds seconds)" >&2

      SECONDS=0
      while true; do
        zone_group_count="$(az network private-endpoint dns-zone-group list \
          --resource-group "$RG" \
          --endpoint-name "$PE_NAME" \
          --query "length(@)" \
          -o tsv 2>/dev/null || echo 0)"

        if [[ "$zone_group_count" =~ ^[0-9]+$ ]] && [[ "$zone_group_count" -gt 0 ]]; then
          echo "Found $zone_group_count private DNS zone group(s) on '$PE_NAME'." >&2
          exit 0
        fi

        if [[ "$SECONDS" -ge "$timeout_seconds" ]]; then
          echo "Timed out waiting for policy-managed private DNS zone group on '$PE_NAME' after $TIMEOUT." >&2
          exit 1
        fi

        sleep "$interval_seconds"
      done
    EOT
  }

  depends_on = [azurerm_private_endpoint.key_vault_pe]
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
  name            = "example-secret-test-one"
  value           = random_password.secret_one.result
  key_vault_id    = azurerm_key_vault.main.id
  expiration_date = "2025-12-31T23:59:59Z"
  content_type    = "text/plain"
  depends_on      = [null_resource.wait_for_key_vault_private_dns]
}

resource "azurerm_key_vault_secret" "secret_two" {
  name            = "example-secret-test-two"
  value           = random_password.secret_two.result
  key_vault_id    = azurerm_key_vault.main.id
  expiration_date = "2025-12-31T23:59:59Z"
  content_type    = "text/plain"
  depends_on      = [null_resource.wait_for_key_vault_private_dns]
}
