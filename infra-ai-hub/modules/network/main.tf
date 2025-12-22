data "azurerm_virtual_network" "target" {
  name                = var.vnet_name
  resource_group_name = var.vnet_resource_group_name
}

locals {
  base_cidr          = var.target_vnet_address_spaces[0]
  base_prefix_length = tonumber(split("/", local.base_cidr)[1])
  newbits            = var.private_endpoint_subnet_prefix_length - local.base_prefix_length

  private_endpoint_subnet_cidr = cidrsubnet(local.base_cidr, local.newbits, var.private_endpoint_subnet_netnum)
}

# NSG for private endpoint subnet in the target VNet
resource "azurerm_network_security_group" "private_endpoints" {
  name                = "${var.name_prefix}-pe-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  # Allow traffic from within the target VNet address spaces to reach private endpoints
  dynamic "security_rule" {
    for_each = var.target_vnet_address_spaces
    content {
      name                       = "AllowInboundFromTargetVNet-${replace(replace(security_rule.value, ".", "-"), "/", "-")}"
      priority                   = 100 + index(var.target_vnet_address_spaces, security_rule.value)
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_address_prefix      = security_rule.value
      destination_address_prefix = local.private_endpoint_subnet_cidr
      source_port_range          = "*"
      destination_port_range     = "*"
    }
  }

  dynamic "security_rule" {
    for_each = var.target_vnet_address_spaces
    content {
      name                       = "AllowOutboundToTargetVNet-${replace(replace(security_rule.value, ".", "-"), "/", "-")}"
      priority                   = 200 + index(var.target_vnet_address_spaces, security_rule.value)
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_address_prefix      = local.private_endpoint_subnet_cidr
      destination_address_prefix = security_rule.value
      source_port_range          = "*"
      destination_port_range     = "*"
    }
  }

  # Allow traffic from the source environment (e.g., tools) to reach private endpoints in this target VNet
  security_rule {
    name                       = "AllowInboundFromSourceVNet"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = var.source_vnet_address_space
    destination_address_prefix = local.private_endpoint_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  security_rule {
    name                       = "AllowOutboundToSourceVNet"
    priority                   = 301
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.private_endpoint_subnet_cidr
    destination_address_prefix = var.source_vnet_address_space
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# Create the private endpoint subnet and associate the NSG in the same operation.
# This is required in the Landing Zone due to policy requiring NSG association at creation time.
resource "azapi_resource" "private_endpoints_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = var.private_endpoint_subnet_name
  parent_id = data.azurerm_virtual_network.target.id
  locks     = [data.azurerm_virtual_network.target.id]

  body = {
    properties = {
      addressPrefix = local.private_endpoint_subnet_cidr

      networkSecurityGroup = {
        id = azurerm_network_security_group.private_endpoints.id
      }

      # Required for private endpoints
      privateEndpointNetworkPolicies = "Disabled"
    }
  }

  response_export_values = ["*"]
}
