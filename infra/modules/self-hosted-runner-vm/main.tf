data "azurerm_subscription" "current" {}

resource "random_string" "admin_username" {
  count   = var.enabled ? 1 : 0
  length  = 12
  upper   = true
  lower   = true
  special = false
}

resource "azapi_resource" "ssh_public_key" {
  count     = var.enabled ? 1 : 0
  type      = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  name      = "${var.app_name}-gha-runner-ssh-key"
  location  = var.location
  parent_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name}"

  body = {}

  tags = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azapi_resource_action" "ssh_public_key_gen" {
  count       = var.enabled ? 1 : 0
  type        = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  resource_id = azapi_resource.ssh_public_key[0].id
  action      = "generateKeyPair"
  method      = "POST"

  response_export_values = ["publicKey"]
}

resource "azurerm_network_interface" "runner" {
  count               = var.enabled ? 1 : 0
  name                = "${var.app_name}-gha-runner-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_linux_virtual_machine" "runner" {
  count               = var.enabled ? 1 : 0
  name                = "${var.app_name}-gha-runner"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = random_string.admin_username[0].result
  priority            = "Regular"

  network_interface_ids = [
    azurerm_network_interface.runner[0].id,
  ]

  admin_ssh_key {
    username   = random_string.admin_username[0].result
    public_key = azapi_resource_action.ssh_public_key_gen[0].output.publicKey
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  boot_diagnostics {
    storage_account_uri = null
  }

  custom_data = base64encode(
    templatefile("${path.module}/scripts/bootstrap.sh.tftpl", {
      terraform_version = var.terraform_version
      kubectl_version   = var.kubectl_version
      helm_version      = var.helm_version
      gh_cli_version    = var.gh_cli_version
      azure_cli_version = var.azure_cli_version
      register_and_start_script = templatefile("${path.module}/scripts/register-and-start.sh.tftpl", {
        github_actions_runner_version = var.github_actions_runner_version
      })
    })
  )

  identity {
    type = "SystemAssigned"
  }

  tags = var.common_tags
  lifecycle {
    ignore_changes = [
      tags,
      identity,
    ]
  }
}
