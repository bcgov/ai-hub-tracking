# -----------------------------------------------------------------------------
# Azure Bastion Module
# -----------------------------------------------------------------------------
# Creates Azure Bastion for secure RDP/SSH access to VMs without public IPs.
# Uses Basic SKU for cost optimization while providing web-based access.
# -----------------------------------------------------------------------------

# Public IP for Bastion (required)
resource "azurerm_public_ip" "bastion" {
  name                = "${var.app_name}-bastion-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

# Azure Bastion Host
resource "azurerm_bastion_host" "main" {
  name                = "${var.app_name}-bastion"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.bastion_sku

  ip_configuration {
    name                 = "configuration"
    subnet_id            = var.bastion_subnet_id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  tags = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}
