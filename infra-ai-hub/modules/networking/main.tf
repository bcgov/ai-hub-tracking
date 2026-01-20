data "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  resource_group_name = var.vnet_resource_group_name
}
resource "azurerm_network_security_group" "privateendpoints" {
  name                = "${var.vnet_resource_group_name}-pe-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name
  tags                = var.tags
  # Allow Outbound traffic
  security_rule {
    name                       = "Allow-All-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
resource "azapi_resource" "privateendpoints_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = "PrivateEndpointSubnet"
  parent_id = data.azurerm_virtual_network.main.id
  locks     = [data.azurerm_virtual_network.main.id]
  body = {
    properties = {
      addressPrefix = local.private_endpoints_subnet_cidr
      networkSecurityGroup = {
        id = azurerm_network_security_group.privateendpoints.id
      }
    }
  }
  response_export_values = ["*"]
}
