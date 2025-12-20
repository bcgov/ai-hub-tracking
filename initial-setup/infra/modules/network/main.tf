data "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  resource_group_name = var.vnet_resource_group_name
}

# NSG for privateendpoints subnet
resource "azurerm_network_security_group" "privateendpoints" {
  name                = "${var.resource_group_name}-pe-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  security_rule {
    name                       = "AllowInboundFromApp"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.app_service_subnet_cidr
    destination_address_prefix = local.private_endpoints_subnet_cidr
    destination_port_range     = "*"
    source_port_range          = "*"
  }

  security_rule {
    name                       = "AllowOutboundToApp"
    priority                   = 101
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    destination_address_prefix = local.app_service_subnet_cidr
    source_address_prefix      = local.private_endpoints_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "*"
  }
  security_rule {
    name                       = "AllowInboundFromContainerInstance"
    priority                   = 104
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.container_instance_subnet_cidr
    destination_address_prefix = local.private_endpoints_subnet_cidr
    destination_port_range     = "*"
    source_port_range          = "*"
  }

  security_rule {
    name                       = "AllowOutboundToContainerInstance"
    priority                   = 105
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    destination_address_prefix = local.container_instance_subnet_cidr
    source_address_prefix      = local.private_endpoints_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "*"
  }
  security_rule {
    name                       = "AllowInboundFromContainerApps"
    priority                   = 106
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.container_apps_subnet_cidr
    destination_address_prefix = local.private_endpoints_subnet_cidr
    destination_port_range     = "*"
    source_port_range          = "*"
  }

  security_rule {
    name                       = "AllowOutboundToContainerApps"
    priority                   = 107
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    destination_address_prefix = local.container_apps_subnet_cidr
    source_address_prefix      = local.private_endpoints_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "*"
  }
  tags = var.common_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# NSG for app service subnet
resource "azurerm_network_security_group" "app_service" {
  name                = "${var.resource_group_name}-as-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  security_rule {
    name                       = "AllowAppFromPrivateEndpoint"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.private_endpoints_subnet_cidr
    source_port_range          = "*"
    destination_address_prefix = local.app_service_subnet_cidr
    destination_port_range     = "*"
  }

  security_rule {
    name                       = "AllowAppToPrivateEndpoint"
    priority                   = 103
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    destination_address_prefix = local.private_endpoints_subnet_cidr
    source_address_prefix      = local.app_service_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "*"
  }
  security_rule {
    name                       = "AllowAppFromContainerInstance"
    priority                   = 104
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.container_instance_subnet_cidr
    source_port_range          = "*"
    destination_address_prefix = local.app_service_subnet_cidr
    destination_port_range     = "*"
  }

  security_rule {
    name                       = "AllowAppToContainerInstance"
    priority                   = 105
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    destination_address_prefix = local.container_instance_subnet_cidr
    destination_port_range     = "*"
    source_address_prefix      = local.app_service_subnet_cidr
    source_port_range          = "*"
  }

  security_rule {
    name                       = "AllowAppFromInternet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = local.app_service_subnet_cidr
    destination_port_ranges    = ["80", "443"]
  }
  security_rule {
    name                       = "AllowAppOutboundToInternet"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = local.app_service_subnet_cidr
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
  }

  # Allow outbound to Container Apps (for private backend access)
  security_rule {
    name                       = "AllowAppToContainerApps"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = local.app_service_subnet_cidr
    destination_address_prefix = local.container_apps_subnet_cidr
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
  }

  # Allow inbound response from Container Apps
  security_rule {
    name                       = "AllowAppFromContainerApps"
    priority                   = 131
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = local.container_apps_subnet_cidr
    destination_address_prefix = local.app_service_subnet_cidr
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
  }

  # Allow inbound from APIM
  security_rule {
    name                       = "AllowInboundFromAPIM"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.apim_subnet_cidr
    destination_address_prefix = local.app_service_subnet_cidr
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "3000-9000"]
  }

  # Allow outbound response to APIM
  security_rule {
    name                       = "AllowOutboundToAPIM"
    priority                   = 141
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.app_service_subnet_cidr
    destination_address_prefix = local.apim_subnet_cidr
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "3000-9000"]
  }

  tags = var.common_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
resource "azurerm_network_security_group" "container_instance" {
  name                = "${var.resource_group_name}-ci-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  security_rule {
    name                       = "AllowInboundFromAppService"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.app_service_subnet_cidr
    destination_address_prefix = local.container_instance_subnet_cidr
    source_port_ranges         = ["3000-9000"]
    destination_port_ranges    = ["3000-9000"]
  }

  security_rule {
    name                       = "AllowOutboundToAppService"
    priority                   = 101
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    destination_address_prefix = local.app_service_subnet_cidr
    source_address_prefix      = local.container_instance_subnet_cidr
    source_port_ranges         = ["3000-9000"]
    destination_port_ranges    = ["3000-9000"]
  }

  # Allow inbound from Private Endpoints subnet to Container Instances subnet
  security_rule {
    name                       = "AllowInboundFromPrivateEndpoint"
    priority                   = 106
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.private_endpoints_subnet_cidr
    destination_address_prefix = local.container_instance_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  # Allow outbound to Private Endpoints subnet from Container Instances subnet
  security_rule {
    name                       = "AllowOutboundToPrivateEndpoint"
    priority                   = 107
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.container_instance_subnet_cidr
    destination_address_prefix = local.private_endpoints_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "*"
  }
  security_rule {
    name                       = "AllowInboundFromInternet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    destination_address_prefix = local.container_instance_subnet_cidr
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
  }

  security_rule {
    name                       = "AllowOutboundToInternet"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    destination_address_prefix = "*"
    source_address_prefix      = local.container_instance_subnet_cidr
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
  }
  tags = var.common_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# NSG for Container Apps subnet
resource "azurerm_network_security_group" "container_apps" {
  name                = "${var.resource_group_name}-ca-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  # Allow Container Apps management traffic (required by Azure Container Apps)
  security_rule {
    name                       = "AllowContainerAppsManagement"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = local.container_apps_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  # Allow HTTPS traffic from internet (for public ingress)
  security_rule {
    name                       = "AllowHTTPSFromInternet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    destination_address_prefix = local.container_apps_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "443"
  }

  # Allow HTTP traffic from internet (for public ingress)
  security_rule {
    name                       = "AllowHTTPFromInternet"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    destination_address_prefix = local.container_apps_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "80"
  }

  # Allow communication with private endpoints (PostgreSQL)
  security_rule {
    name                       = "AllowOutboundToPrivateEndpoints"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.container_apps_subnet_cidr
    destination_address_prefix = local.private_endpoints_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "*"
  }
  security_rule {
    name                       = "AllowInboundFromPrivateEndpoints"
    priority                   = 131
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.private_endpoints_subnet_cidr
    destination_address_prefix = local.container_apps_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  # Allow inbound traffic from App Service (for private backend access)
  security_rule {
    name                       = "AllowInboundFromAppService"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.app_service_subnet_cidr
    destination_address_prefix = local.container_apps_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  # Allow outbound response to App Service
  security_rule {
    name                       = "AllowOutboundToAppService"
    priority                   = 141
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.container_apps_subnet_cidr
    destination_address_prefix = local.app_service_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  # Allow outbound internet access (for Container Registry, monitoring, etc.)
  security_rule {
    name                       = "AllowOutboundToInternet"
    priority                   = 140
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.container_apps_subnet_cidr
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  tags = var.common_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# NSG for APIM subnet
resource "azurerm_network_security_group" "apim" {
  name                = "${var.resource_group_name}-apim-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  # Allow APIM management traffic (required by Azure API Management)
  security_rule {
    name                       = "AllowAPIMManagement"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "ApiManagement"
    destination_address_prefix = local.apim_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "3443"
  }

  # Allow Azure Load Balancer
  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = local.apim_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  # Allow HTTPS inbound (for API gateway)
  security_rule {
    name                       = "AllowHTTPSInbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    destination_address_prefix = local.apim_subnet_cidr
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
  }

  # Allow outbound to backend services
  security_rule {
    name                       = "AllowOutboundToAppServices"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.apim_subnet_cidr
    destination_address_prefix = local.app_service_subnet_cidr
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "3000-9000"]
  }

  # Allow outbound to storage and SQL
  security_rule {
    name                       = "AllowOutboundToStorage"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = local.apim_subnet_cidr
    destination_address_prefix = "Storage"
    source_port_range          = "*"
    destination_port_range     = "443"
  }

  # Allow outbound to SQL
  security_rule {
    name                       = "AllowOutboundToSQL"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = local.apim_subnet_cidr
    destination_address_prefix = "Sql"
    source_port_range          = "*"
    destination_port_range     = "1433"
  }

  # Allow outbound internet access
  security_rule {
    name                       = "AllowOutboundToInternet"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.apim_subnet_cidr
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
  }
  # Allow inbound from Container Apps
  security_rule {
    name                       = "AllowInboundFromContainerApps"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.container_apps_subnet_cidr
    destination_address_prefix = local.apim_subnet_cidr
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "3000-9000"]
  }

  # Allow outbound to Container Apps
  security_rule {
    name                       = "AllowOutboundToContainerApps"
    priority                   = 141
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.apim_subnet_cidr
    destination_address_prefix = local.container_apps_subnet_cidr
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "3000-9000"]
  }

  tags = var.common_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Subnets
resource "azapi_resource" "privateendpoints_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = var.private_endpoint_subnet_name
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

resource "azapi_resource" "app_service_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = var.apps_service_subnet_name
  parent_id = data.azurerm_virtual_network.main.id
  locks     = [data.azurerm_virtual_network.main.id]
  body = {
    properties = {
      addressPrefix = local.app_service_subnet_cidr
      networkSecurityGroup = {
        id = azurerm_network_security_group.app_service.id
      }
      delegations = [
        {
          name = "app-service-delegation"
          properties = {
            serviceName = "Microsoft.Web/serverFarms"
          }
        }
      ]
    }
  }
  response_export_values = ["*"]
}

resource "azapi_resource" "container_instance_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = var.container_instance_subnet_name
  parent_id = data.azurerm_virtual_network.main.id
  locks     = [data.azurerm_virtual_network.main.id]
  body = {
    properties = {
      addressPrefix = local.container_instance_subnet_cidr
      networkSecurityGroup = {
        id = azurerm_network_security_group.container_instance.id
      }
      delegations = [
        {
          name = "aci-delegation"
          properties = {
            serviceName = "Microsoft.ContainerInstance/containerGroups"
          }
        }
      ]
    }
  }
  response_export_values = ["*"]
}


# Container Apps subnet for Container Apps Environment
resource "azapi_resource" "container_apps_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = var.container_apps_subnet_name
  parent_id = data.azurerm_virtual_network.main.id
  locks     = [data.azurerm_virtual_network.main.id]
  body = {
    properties = {
      addressPrefix = local.container_apps_subnet_cidr
      networkSecurityGroup = {
        id = azurerm_network_security_group.container_apps.id
      }
      delegations = [
        {
          name = "container-apps-delegation"
          properties = {
            serviceName = "Microsoft.App/environments"
          }
        }
      ]
    }
  }
  response_export_values = ["*"]
}

# APIM subnet for API Management
resource "azapi_resource" "apim_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = var.apim_subnet_name
  parent_id = data.azurerm_virtual_network.main.id
  locks     = [data.azurerm_virtual_network.main.id]
  body = {
    properties = {
      addressPrefix = local.apim_subnet_cidr
      networkSecurityGroup = {
        id = azurerm_network_security_group.apim.id
      }
      delegations = [
        {
          name = "apim-delegation"
          properties = {
            serviceName = "Microsoft.Web/serverFarms"
          }
        }
      ]
    }
  }
  response_export_values = ["*"]
}

# -----------------------------------------------------------------------------
# Jumpbox VM Subnet and NSG
# -----------------------------------------------------------------------------

# NSG for Jumpbox subnet
resource "azurerm_network_security_group" "jumpbox" {
  name                = "${var.resource_group_name}-jumpbox-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  # Allow SSH from Bastion subnet only
  security_rule {
    name                       = "AllowSSHFromBastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = local.bastion_subnet_cidr
    destination_address_prefix = local.jumpbox_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "22"
  }

  # Allow RDP from Bastion subnet (for GUI access via xRDP)
  security_rule {
    name                       = "AllowRDPFromBastion"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = local.bastion_subnet_cidr
    destination_address_prefix = local.jumpbox_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "3389"
  }

  # Allow outbound to Private Endpoints (for accessing Azure services)
  security_rule {
    name                       = "AllowOutboundToPrivateEndpoints"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.jumpbox_subnet_cidr
    destination_address_prefix = local.private_endpoints_subnet_cidr
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  # Allow outbound HTTPS to internet (for package updates, Azure CLI, etc.)
  security_rule {
    name                       = "AllowOutboundHTTPS"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = local.jumpbox_subnet_cidr
    destination_address_prefix = "Internet"
    source_port_range          = "*"
    destination_port_range     = "443"
  }

  # Allow outbound HTTP (for package updates)
  security_rule {
    name                       = "AllowOutboundHTTP"
    priority                   = 111
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = local.jumpbox_subnet_cidr
    destination_address_prefix = "Internet"
    source_port_range          = "*"
    destination_port_range     = "80"
  }

  # Allow outbound DNS
  security_rule {
    name                       = "AllowOutboundDNS"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.jumpbox_subnet_cidr
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "53"
  }

  tags = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

# Jumpbox subnet
resource "azapi_resource" "jumpbox_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = var.jumpbox_subnet_name
  parent_id = data.azurerm_virtual_network.main.id
  locks     = [data.azurerm_virtual_network.main.id]
  body = {
    properties = {
      addressPrefix = local.jumpbox_subnet_cidr
      networkSecurityGroup = {
        id = azurerm_network_security_group.jumpbox.id
      }
    }
  }
  response_export_values = ["*"]
  depends_on             = [azapi_resource.apim_subnet]
}

# -----------------------------------------------------------------------------
# Azure Bastion Subnet and NSG
# -----------------------------------------------------------------------------

# NSG for Azure Bastion subnet (required rules per Microsoft documentation)
resource "azurerm_network_security_group" "bastion" {
  name                = "${var.resource_group_name}-bastion-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  # Inbound Rules

  # Allow HTTPS inbound from Internet (for Bastion portal access)
  security_rule {
    name                       = "AllowHttpsInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "443"
  }

  # Allow Gateway Manager inbound (required for Bastion control plane)
  security_rule {
    name                       = "AllowGatewayManagerInbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "443"
  }

  # Allow Azure Load Balancer inbound (required for health probes)
  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "443"
  }

  # Allow Bastion host communication
  security_rule {
    name                       = "AllowBastionHostCommunication"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "5701"]
  }

  # Outbound Rules

  # Allow SSH outbound to VNet (for connecting to VMs)
  security_rule {
    name                       = "AllowSshOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
    source_port_range          = "*"
    destination_port_range     = "22"
  }

  # Allow RDP outbound to VNet (for connecting to Windows VMs)
  security_rule {
    name                       = "AllowRdpOutbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
    source_port_range          = "*"
    destination_port_range     = "3389"
  }

  # Allow Azure Cloud outbound (for Bastion control plane)
  security_rule {
    name                       = "AllowAzureCloudOutbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
    source_port_range          = "*"
    destination_port_range     = "443"
  }

  # Allow Bastion host communication outbound
  security_rule {
    name                       = "AllowBastionCommunicationOutbound"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "5701"]
  }

  # Allow HTTP outbound for session information
  security_rule {
    name                       = "AllowHttpOutbound"
    priority                   = 140
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
    source_port_range          = "*"
    destination_port_range     = "80"
  }

  tags = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

# Azure Bastion subnet (must be named "AzureBastionSubnet")
resource "azapi_resource" "bastion_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = var.bastion_subnet_name # Must be "AzureBastionSubnet"
  parent_id = data.azurerm_virtual_network.main.id
  locks     = [data.azurerm_virtual_network.main.id]
  body = {
    properties = {
      addressPrefix = local.bastion_subnet_cidr
      networkSecurityGroup = {
        id = azurerm_network_security_group.bastion.id
      }
    }
  }
  response_export_values = ["*"]
  depends_on             = [azapi_resource.jumpbox_subnet]
}

