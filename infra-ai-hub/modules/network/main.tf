# Network Module - Main Configuration
# Creates subnets for Private Endpoints, APIM (VNet injection), App Gateway, and ACA.
#
# Allocation is driven by var.subnet_allocation — a map-of-maps that explicitly
# defines which subnets go in which address space and their prefix lengths.
# See variables.tf for the contract and locals.tf for CIDR resolution.

# =============================================================================
# PRIVATE ENDPOINT SUBNET(S)
# Used by: All PaaS services with private endpoints (AI Foundry, Key Vault,
#          APIM PE, Language Service, etc.)
#
# The PE pool (local.pe_subnet_pool) can contain one or more PE subnets:
#   - "privateendpoints-subnet"   (primary, always present)
#   - "privateendpoints-subnet-1" (overflow, when primary fills up)
#   - "privateendpoints-subnet-2" (etc.)
#
# NSG rules use local.pe_subnet_cidrs (sorted list of ALL PE CIDRs in the pool)
# so that every PE subnet is reachable regardless of how many exist.
#
# Rule layout:
#   Inbound  100+N  : each address space → all PE CIDRs
#   Outbound 200+N  : all PE CIDRs → each address space
#   Inbound  300    : source/tools VNet → all PE CIDRs
#   Outbound 301    : all PE CIDRs → source/tools VNet
#
# local.address_spaces = keys(var.subnet_allocation), sorted lexicographically.
# local.pe_subnet_cidrs = sorted list of CIDRs for every PE subnet in the pool.
# =============================================================================

# NSG for private endpoint subnet(s) — shared across the entire PE pool.
resource "azurerm_network_security_group" "private_endpoints" {
  name                = "${var.name_prefix}-pe-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  # --- Inbound: allow each address space in the allocation map → all PE subnets ---
  # One rule per address space from keys(var.subnet_allocation).
  # destination_address_prefixes is a list covering every PE CIDR in the pool,
  # so overflow PE subnets are automatically included.
  dynamic "security_rule" {
    for_each = local.address_spaces
    content {
      name                         = "AllowInboundFromTargetVNet-${replace(replace(security_rule.value, ".", "-"), "/", "-")}"
      priority                     = 100 + index(local.address_spaces, security_rule.value)
      direction                    = "Inbound"
      access                       = "Allow"
      protocol                     = "*"
      source_address_prefix        = security_rule.value   # e.g., "10.x.x.0/24"
      destination_address_prefixes = local.pe_subnet_cidrs # all PE pool CIDRs
      source_port_range            = "*"
      destination_port_range       = "*"
    }
  }

  # --- Outbound: all PE subnets → each address space in the allocation map ---
  # Return traffic from PE-backed services back to the requesting subnets.
  # source_address_prefixes covers the full PE pool.
  dynamic "security_rule" {
    for_each = local.address_spaces
    content {
      name                       = "AllowOutboundToTargetVNet-${replace(replace(security_rule.value, ".", "-"), "/", "-")}"
      priority                   = 200 + index(local.address_spaces, security_rule.value)
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_address_prefixes    = local.pe_subnet_cidrs # all PE pool CIDRs
      destination_address_prefix = security_rule.value   # e.g., "10.x.x.0/24"
      source_port_range          = "*"
      destination_port_range     = "*"
    }
  }

  # --- Inbound: allow source/tools VNet → all PE subnets ---
  # The source VNet (e.g., tools VNet) is a separate peered VNet that needs
  # to reach PE-backed services for management, testing, and chisel proxy.
  security_rule {
    name                         = "AllowInboundFromSourceVNet"
    priority                     = 300
    direction                    = "Inbound"
    access                       = "Allow"
    protocol                     = "*"
    source_address_prefix        = var.source_vnet_address_space
    destination_address_prefixes = local.pe_subnet_cidrs # all PE pool CIDRs
    source_port_range            = "*"
    destination_port_range       = "*"
  }

  # --- Outbound: all PE subnets → source/tools VNet ---
  # Return traffic from PE-backed services to the source VNet.
  security_rule {
    name                       = "AllowOutboundToSourceVNet"
    priority                   = 301
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefixes    = local.pe_subnet_cidrs # all PE pool CIDRs
    destination_address_prefix = var.source_vnet_address_space
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# Create PE subnets from the pool — one resource per pe_subnet_pool entry.
# All PE subnets share the same NSG and are serialized via the VNet lock.
# This is required in the Landing Zone due to policy requiring NSG association at creation time.
resource "azapi_resource" "pe_subnets" {
  for_each = local.pe_subnet_pool

  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = each.value.name
  parent_id = data.azurerm_virtual_network.target.id
  locks     = [data.azurerm_virtual_network.target.id]

  body = {
    properties = {
      addressPrefix = each.value.cidr

      networkSecurityGroup = {
        id = azurerm_network_security_group.private_endpoints.id
      }

      # Required for private endpoints
      privateEndpointNetworkPolicies = "Disabled"
    }
  }

  response_export_values = ["*"]
}

# State migration: singular resource → for_each keyed by subnet name.
moved {
  from = azapi_resource.private_endpoints_subnet
  to   = azapi_resource.pe_subnets["privateendpoints-subnet"]
}

# =============================================================================
# APIM SUBNET (optional — enabled when "apim-subnet" key exists in any space)
# Required for APIM StandardV2/PremiumV2 outbound VNet integration.
# Must be a dedicated subnet with delegation to Microsoft.Web/serverFarms.
#
# NSG rules follow Azure APIM VNet integration requirements:
#   - Management plane: ApiManagement → 3443
#   - Health probe: AzureLoadBalancer → *
#   - Outbound dependencies: Storage, KeyVault, AAD, VirtualNetwork, Internet
#
# APIM reaches PE-backed services (OpenAI, Key Vault, Language Service, etc.)
# via the VirtualNetwork → VirtualNetwork rule (priority 120). This broad
# rule is required because APIM resolves PE FQDNs to private IPs within the
# PE subnet, which lives in a different address space in multi-space layouts.
#
# External VNet peering rules (var.external_peered_projects):
#   Inbound  400–499 : peered project CIDRs → APIM subnet (443/TCP)
#   Priorities are caller-assigned per project — no churn on map changes.
#   NSGs are stateful — no outbound mirror rule needed for return traffic.
#   Enables direct APIM consumption from peered VNets, bypassing App Gateway.
# =============================================================================

# NSG for APIM subnet
resource "azurerm_network_security_group" "apim" {
  count = local.apim_enabled ? 1 : 0

  name                = "${var.name_prefix}-apim-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  # --- Inbound: APIM management plane (portal, PowerShell, ARM) ---
  # Required by Azure for APIM health monitoring and management operations.
  # Source: ApiManagement service tag (Azure control plane IPs).
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

  # --- Inbound: Azure Load Balancer health probes ---
  # Required for APIM internal load balancer health checks.
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

  # --- Outbound: Azure Storage (APIM configuration, logs, metrics) ---
  # APIM stores configuration, Git repositories, and diagnostics in Storage.
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

  # --- Outbound: Azure Key Vault (named values, certificates, secrets) ---
  # APIM reads certificates and named values from Key Vault.
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

  # --- Outbound: VirtualNetwork → VirtualNetwork (PE-backed services) ---
  # Allows APIM to reach private endpoints for backend services:
  #   AI Foundry, OpenAI, Language Service, Key Vault, etc.
  # These services resolve to private IPs in the PE subnet (which may be in
  # a different address space, e.g., PE space vs workload space).
  # The VirtualNetwork tag covers all VNet address spaces, including cross-space.
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

  # --- Outbound: Azure AD (managed identity token acquisition) ---
  # APIM uses managed identity to authenticate to backends. Token requests
  # go to Azure AD endpoints via this rule.
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

  # --- Outbound: Internet (external OAuth, APIM developer portal, etc.) ---
  # APIM requires outbound Internet for Azure AD B2C, external OAuth providers,
  # Git sync, and developer portal assets.
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

  # --- Inbound: External peered project VNets → APIM subnet (direct APIM access) ---
  # Allows Azure teams with VNet peering to call APIM directly on 443, bypassing
  # App Gateway. One rule per project, each project may have multiple CIDRs.
  # Priority is caller-assigned (400–499) so adding/removing projects never
  # shifts existing rules. No outbound mirror needed — NSGs are stateful.
  dynamic "security_rule" {
    for_each = var.external_peered_projects
    content {
      name                       = "AllowInboundFrom-${security_rule.key}"
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefixes    = security_rule.value.cidrs
      destination_address_prefix = "VirtualNetwork"
      source_port_range          = "*"
      destination_port_range     = "443"
    }
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# APIM subnet with delegation for Premium v2
resource "azapi_resource" "apim_subnet" {
  count = local.apim_enabled ? 1 : 0

  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = "apim-subnet"
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

  depends_on = [azapi_resource.pe_subnets]
}

# =============================================================================
# APP GATEWAY SUBNET (optional — enabled when "appgw-subnet" key exists in any space)
# Requires a dedicated subnet, no delegation, no other resources.
#
# NSG rules follow Azure Application Gateway v2 requirements:
#   - Inbound HTTPS/443 from Internet (public-facing WAF)
#   - GatewayManager probe ports (65200-65535, required by Azure)
#   - Azure Load Balancer health probes
#   - HTTP/80 intentionally absent — all clients must use HTTPS
#
# Outbound is handled implicitly by Azure default rules for AppGW.
# AppGW routes to APIM (which is internal), and APIM then reaches PE-backed
# services through its own NSG rules.
# =============================================================================

# NSG for App Gateway subnet
resource "azurerm_network_security_group" "appgw" {
  count = local.appgw_enabled ? 1 : 0

  name                = "${var.name_prefix}-appgw-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  # --- Inbound: HTTPS from Internet (public API traffic) ---
  # All client requests arrive here. AppGW terminates SSL and forwards to APIM.
  # Port 443 only — no HTTP/80 listener is configured.
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

  # Port 80 (HTTP) is NOT permitted from the Internet.
  # Rationale: no AppGW listener has HTTP enabled. Scanners/probes hitting
  # port 80 on the raw AppGW public IP would bypass WAF (no host_name match),
  # so blocking at the NSG is the cleanest defence. Legitimate users with
  # HTTP bookmarks get a TCP reset and should update to HTTPS.

  # --- Inbound: Azure Gateway Manager (required for AppGW v2 health probes) ---
  # Azure uses these ports to monitor AppGW instance health and apply config.
  # Blocking this breaks AppGW provisioning and updates.
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

  # --- Inbound: Azure Load Balancer health probes ---
  # Required for AppGW v2 to receive health check traffic.
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
  count = local.appgw_enabled ? 1 : 0

  name                = "${var.name_prefix}-appgw-rt"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_route" "appgw_internet" {
  count = local.appgw_enabled ? 1 : 0

  name                = "default-internet"
  resource_group_name = var.vnet_resource_group_name
  route_table_name    = azurerm_route_table.appgw[0].name

  address_prefix = "0.0.0.0/0"
  next_hop_type  = "Internet"
}
## this is needed to avoid asymetric routing due to express route.
resource "azurerm_route" "appgw_bcgov_internal" {
  count = local.appgw_enabled ? 1 : 0

  name                = "bcgov-internal"
  resource_group_name = var.vnet_resource_group_name
  route_table_name    = azurerm_route_table.appgw[0].name

  address_prefix = "142.34.0.0/16"
  next_hop_type  = "Internet"
}

resource "azapi_resource" "appgw_subnet" {
  count = local.appgw_enabled ? 1 : 0

  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = "appgw-subnet"
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
    azapi_resource.pe_subnets,
    azapi_resource.apim_subnet
  ]
}

# =============================================================================
# CONTAINER APPS ENVIRONMENT SUBNET (optional — enabled when "aca-subnet" exists)
# Required for Container Apps with VNet integration.
# Consumption-only can use /27, zone-redundant needs /23+.
#
# NSG rules allow:
#   - Outbound: ACR, Azure Monitor, Azure AD (Container App Job dependencies)
#   - Outbound: PE subnet (key rotation job reaches KV/APIM via private endpoints)
#   - Inbound: all address spaces in var.subnet_allocation (internal LB, health)
#
# local.address_spaces = keys(var.subnet_allocation), sorted lexicographically.
# =============================================================================

# NSG for ACA subnet
resource "azurerm_network_security_group" "aca" {
  count = local.aca_enabled ? 1 : 0

  name                = "${var.name_prefix}-aca-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  # --- Outbound: Azure Container Registry (pull container images) ---
  # Container App Jobs pull images from ACR at job launch time.
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

  # --- Outbound: Azure Monitor (logs, metrics, diagnostics) ---
  # Container App Environment sends logs and metrics to Log Analytics.
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

  # --- Outbound: Azure AD (managed identity token acquisition) ---
  # Container App Jobs use managed identity to authenticate to backends.
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

  # --- Outbound: VirtualNetwork (PE-backed services via private endpoints) ---
  # The key rotation Container App Job needs to reach Key Vault, APIM management,
  # and potentially other PE-backed services. These resolve to private IPs in
  # the PE subnet, which may be in a different address space.
  # The VirtualNetwork tag covers all VNet address spaces.
  security_rule {
    name                       = "AllowVirtualNetworkOutbound"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # --- Inbound: allow each address space in the allocation map → ACA subnet ---
  # One rule per address space from keys(var.subnet_allocation).
  # Enables internal load balancer traffic and health probes from other subnets
  # (e.g., APIM calling Container App endpoints if needed).
  dynamic "security_rule" {
    for_each = local.address_spaces
    content {
      name                       = "AllowVnetInbound-${replace(replace(security_rule.value, ".", "-"), "/", "-")}"
      priority                   = 200 + index(local.address_spaces, security_rule.value)
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_address_prefix      = security_rule.value # e.g., "10.x.x.0/24"
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
  count = local.aca_enabled ? 1 : 0

  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = "aca-subnet"
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
    azapi_resource.pe_subnets,
    azapi_resource.apim_subnet,
    azapi_resource.appgw_subnet
  ]
}

# =============================================================================
# GPU vLLM CONTAINER APPS ENVIRONMENT SUBNET (optional — enabled when "vllm-aca-subnet" exists)
# Dedicated /27 subnet for the GPU-backed vLLM Container Apps Environment.
# Must be separate from "aca-subnet" (Consumption-only) because GPU workload
# profiles require a dedicated CAE which cannot share a Consumption-only subnet.
# Zone redundancy must be disabled for GPU CAEs — /27 is sufficient.
#
# NSG rules mirror the aca-subnet rules plus:
#   - Outbound: Internet (Docker Hub pull for ACR import, HuggingFace model cache)
#   - Inbound:  AzureLoadBalancer (ACA health probes)
#   - Inbound:  PE subnet CIDR (APIM calls vLLM via its private endpoint NIC)
#   - Inbound:  APIM subnet CIDR (direct calls before PE DNS propagation)
# Broad VNet inbound is NOT permitted — only APIM and platform health probes reach vLLM.
# =============================================================================

# NSG for vLLM ACA subnet
resource "azurerm_network_security_group" "vllm_aca" {
  count = local.vllm_aca_enabled ? 1 : 0

  name                = "${var.name_prefix}-vllm-aca-nsg"
  location            = var.location
  resource_group_name = var.vnet_resource_group_name

  # --- Outbound: Azure Container Registry (pull vLLM container image) ---
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

  # --- Outbound: Azure Monitor (logs, metrics, diagnostics) ---
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

  # --- Outbound: Azure AD (managed identity token acquisition) ---
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

  # --- Outbound: Azure Storage (model cache Azure Files share) ---
  security_rule {
    name                       = "AllowStorageOutbound"
    priority                   = 125
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "445"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Storage"
  }

  # --- Outbound: VirtualNetwork (PE-backed services) ---
  security_rule {
    name                       = "AllowVirtualNetworkOutbound"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # --- Outbound: Internet (HuggingFace model download, ACR build context) ---
  # Required for initial model weight download and az acr build/import provisioners.
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

  # --- Inbound: Azure Load Balancer (ACA health probes and control-plane operations) ---
  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # --- Inbound: PE subnet (APIM backend calls routed through the vLLM private endpoint) ---
  # APIM resolves the Container App FQDN to the PE NIC IP (in privateendpoints-subnet) via
  # private DNS, so the source address on the vllm-aca-subnet side is the PE subnet CIDR.
  dynamic "security_rule" {
    for_each = local.pe_enabled ? [local.private_endpoint_subnet_cidr] : []
    content {
      name                       = "AllowPeSubnetInbound"
      priority                   = 210
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = security_rule.value
      destination_address_prefix = "*"
    }
  }

  # --- Inbound: APIM subnet (direct APIM calls before PE DNS propagation is complete) ---
  dynamic "security_rule" {
    for_each = local.apim_enabled ? [local.apim_subnet_cidr] : []
    content {
      name                       = "AllowApimSubnetInbound"
      priority                   = 220
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = security_rule.value
      destination_address_prefix = "*"
    }
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# vLLM ACA subnet with delegation — dedicated for GPU Container Apps Environment
resource "azapi_resource" "vllm_aca_subnet" {
  count = local.vllm_aca_enabled ? 1 : 0

  type      = "Microsoft.Network/virtualNetworks/subnets@2023-04-01"
  name      = "vllm-aca-subnet"
  parent_id = data.azurerm_virtual_network.target.id
  locks     = [data.azurerm_virtual_network.target.id]

  body = {
    properties = {
      addressPrefix = local.vllm_aca_subnet_cidr

      networkSecurityGroup = {
        id = azurerm_network_security_group.vllm_aca[0].id
      }

      # GPU Container Apps Environment requires delegation to Microsoft.App/environments
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
    azapi_resource.pe_subnets,
    azapi_resource.apim_subnet,
    azapi_resource.appgw_subnet,
    azapi_resource.aca_subnet
  ]
}
