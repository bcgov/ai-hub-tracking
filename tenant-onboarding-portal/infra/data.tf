data "azurerm_resource_group" "portal" {
  name = var.resource_group_name
}

data "azurerm_virtual_network" "portal" {
  name                = var.vnet_name
  resource_group_name = var.vnet_resource_group_name
}

data "azurerm_subnet" "app_service" {
  name                 = var.app_service_subnet_name
  virtual_network_name = data.azurerm_virtual_network.portal.name
  resource_group_name  = var.vnet_resource_group_name
}
