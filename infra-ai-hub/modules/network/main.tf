# Network Module - Main Configuration
# Creates subnets for Private Endpoints, APIM (VNet injection), and App Gateway
#
# Subnet allocation based on number of VNet address spaces:
# - 1 /24:   PE=/27, APIM=/27, AppGW=/27 (all in first /24)
# - 2 /24s:  PE=full first /24, APIM=/25 + AppGW=/27 in second /24
# - 4+ /24s: PE=first 2 /24s, APIM=third /24, AppGW=fourth /24

# =============================================================================
# PRIVATE ENDPOINT SUBNET
# Used by: All PaaS services with private endpoints (including APIM if using PE-only mode)
# =============================================================================

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

# =============================================================================
# APIM SUBNET (optional - for StandardV2/PremiumV2 VNet integration)
# Required for APIM StandardV2/PremiumV2 outbound VNet integration
# Must be dedicated subnet with delegation to Microsoft.Web/serverFarms
# =============================================================================

# NSG for APIM subnet
resource "azurerm_network_security_group" "apim" {
  count = var.apim_subnet.enabled ? 1 : 0

  name                = "${var.name_prefix}-apim-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  # APIM management endpoint (Azure portal, PowerShell)
  security_rule {
    name                       = "AllowApiManagement"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3443"
    source_address_prefix      = "ApiManagement"
    destination_address_prefix = "VirtualNetwork"
  }

  # Azure Load Balancer
  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "VirtualNetwork"
  }

  # Outbound to Azure Storage (required dependency)
  security_rule {
    name                       = "AllowStorageOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Storage"
  }

  # Outbound to Azure Key Vault (required dependency)
  security_rule {
    name                       = "AllowKeyVaultOutbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureKeyVault"
  }

  # Outbound to VirtualNetwork - Required for private endpoints (OpenAI, Cognitive Services, etc.)
  security_rule {
    name                       = "AllowVirtualNetworkOutbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Outbound to Azure Active Directory - Required for managed identity authentication
  security_rule {
    name                       = "AllowAzureADOutbound"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureActiveDirectory"
  }

  # Outbound to Internet - Required for external API calls, OAuth endpoints, etc.
  security_rule {
    name                       = "AllowInternetOutbound"
    priority                   = 140
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Internet"
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# APIM subnet with delegation for Premium v2
resource "azapi_resource" "apim_subnet" {
  count = var.apim_subnet.enabled ? 1 : 0

  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = var.apim_subnet.name
  parent_id = data.azurerm_virtual_network.target.id
  locks     = [data.azurerm_virtual_network.target.id]

  body = {
    properties = {
      addressPrefix = local.apim_subnet_cidr

      networkSecurityGroup = {
        id = azurerm_network_security_group.apim[0].id
      }

      # APIM StandardV2/PremiumV2 VNet integration requires delegation to Microsoft.Web/serverFarms
      delegations = [
        {
          name = "Microsoft.Web.serverFarms"
          properties = {
            serviceName = "Microsoft.Web/serverFarms"
          }
        }
      ]
    }
  }

  response_export_values = ["*"]

  depends_on = [azapi_resource.private_endpoints_subnet]
}

# =============================================================================
# APP GATEWAY SUBNET (optional)
# Required for Application Gateway - must be dedicated subnet
# =============================================================================

# NSG for App Gateway subnet
resource "azurerm_network_security_group" "appgw" {
  count = var.appgw_subnet.enabled ? 1 : 0

  name                = "${var.name_prefix}-appgw-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  # Allow inbound HTTPS from Internet
  security_rule {
    name                       = "AllowHttpsInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Allow inbound HTTP (for redirect to HTTPS)
  security_rule {
    name                       = "AllowHttpInbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Allow Azure Gateway Manager (required for App Gateway v2)
  security_rule {
    name                       = "AllowGatewayManager"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  # Allow Azure Load Balancer
  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# App Gateway subnet
#
# IMPORTANT: In VWAN spoke VNets with useRemoteGateways=true, a route table with
# 0.0.0.0/0 → Internet is REQUIRED. Without it, the VWAN hub's default route
# causes asymmetric routing: inbound traffic arrives at the App GW public IP
# directly, but return traffic goes through the VWAN hub, and gets dropped.
# See: https://learn.microsoft.com/en-us/azure/application-gateway/configuration-infrastructure#virtual-network-and-dedicated-subnet

resource "azurerm_route_table" "appgw" {
  count = var.appgw_subnet.enabled ? 1 : 0

  name                = "${var.name_prefix}-appgw-rt"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_route" "appgw_internet" {
  count = var.appgw_subnet.enabled ? 1 : 0

  name                = "default-internet"
  resource_group_name = var.vnet_resource_group_name
  route_table_name    = azurerm_route_table.appgw[0].name

  address_prefix = "0.0.0.0/0"
  next_hop_type  = "Internet"
}

resource "azapi_resource" "appgw_subnet" {
  count = var.appgw_subnet.enabled ? 1 : 0

  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = var.appgw_subnet.name
  parent_id = data.azurerm_virtual_network.target.id
  locks     = [data.azurerm_virtual_network.target.id]

  body = {
    properties = {
      addressPrefix = local.appgw_subnet_cidr

      networkSecurityGroup = {
        id = azurerm_network_security_group.appgw[0].id
      }

      routeTable = {
        id = azurerm_route_table.appgw[0].id
      }
    }
  }

  response_export_values = ["*"]

  depends_on = [
    azapi_resource.private_endpoints_subnet,
    azapi_resource.apim_subnet
  ]
}

# =============================================================================
# CONTAINER APPS ENVIRONMENT SUBNET (optional)
# Required for Container Apps with VNet integration
# Consumption-only can use /27, zone-redundant needs /23+
# =============================================================================

# NSG for ACA subnet
resource "azurerm_network_security_group" "aca" {
  count = var.aca_subnet.enabled ? 1 : 0

  name                = "${var.name_prefix}-aca-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  # Allow outbound to Azure Container Registry
  security_rule {
    name                       = "AllowAcrOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureContainerRegistry"
  }

  # Allow outbound to Azure Monitor
  security_rule {
    name                       = "AllowMonitorOutbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureMonitor"
  }

  # Allow outbound to Azure Active Directory
  security_rule {
    name                       = "AllowAadOutbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureActiveDirectory"
  }

  # Allow inbound from VNet (for internal load balancer)
  dynamic "security_rule" {
    for_each = var.target_vnet_address_spaces
    content {
      name                       = "AllowVnetInbound-${replace(replace(security_rule.value, ".", "-"), "/", "-")}"
      priority                   = 200 + index(var.target_vnet_address_spaces, security_rule.value)
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_address_prefix      = security_rule.value
      destination_address_prefix = "VirtualNetwork"
      source_port_range          = "*"
      destination_port_range     = "*"
    }
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# ACA subnet with delegation
resource "azapi_resource" "aca_subnet" {
  count = var.aca_subnet.enabled ? 1 : 0

  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = var.aca_subnet.name
  parent_id = data.azurerm_virtual_network.target.id
  locks     = [data.azurerm_virtual_network.target.id]

  body = {
    properties = {
      addressPrefix = local.aca_subnet_cidr

      networkSecurityGroup = {
        id = azurerm_network_security_group.aca[0].id
      }

      # Container Apps Environment requires delegation
      delegations = [
        {
          name = "Microsoft.App.environments"
          properties = {
            serviceName = "Microsoft.App/environments"
          }
        }
      ]
    }
  }

  response_export_values = ["*"]

  depends_on = [
    azapi_resource.private_endpoints_subnet,
    azapi_resource.apim_subnet,
    azapi_resource.appgw_subnet
  ]
}
