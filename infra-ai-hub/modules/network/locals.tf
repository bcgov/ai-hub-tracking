locals {
  # =============================================================================
  # ADDRESS SPACE PARSING
  # Supports flexible allocation based on number of /24 address spaces available
  # =============================================================================

  num_address_spaces = length(var.target_vnet_address_spaces)

  # Parse all address spaces into usable base IPs
  parsed_spaces = [for cidr in var.target_vnet_address_spaces : {
    cidr    = cidr
    base_ip = split("/", cidr)[0]
    octets  = split(".", split("/", cidr)[0])
    prefix  = "${split(".", split("/", cidr)[0])[0]}.${split(".", split("/", cidr)[0])[1]}.${split(".", split("/", cidr)[0])[2]}"
  }]

  # =============================================================================
  # PE SUBNET POOL ALLOCATION
  # Creates multiple PE subnets that can be assigned to tenants as they grow
  # 
  # Strategy:
  # - 1 /24:  Single /27 PE subnet (32 IPs, ~30 usable for 3 tenants)
  # - 2 /24s: First /24 split into 8x /27 subnets (PE pool), second for infra
  # - 4+ /24s: First two /24s for PE pool (16x /27 or full /24s), rest for infra
  # =============================================================================

  # Determine how many /24s are available for PE pool
  pe_pool_address_spaces = local.num_address_spaces == 1 ? 0 : (
    local.num_address_spaces >= 4 ? 2 : 1
  )

  # For 1 /24: Single /27 at start
  # For 2+ /24s: Use first N /24s as PE pool, create /27 subnets within each
  pe_subnets_per_space = 8 # 8x /27 = 256 IPs per /24

  # Calculate PE subnet pool for multi-space scenarios
  # Each /27 can hold ~10 private endpoints (10 tenants worth of one service each)
  pe_subnet_pool = local.num_address_spaces == 1 ? {
    "pe-subnet-0" = {
      name = var.private_endpoint_subnet_name
      cidr = "${local.parsed_spaces[0].prefix}.0/27"
    }
    } : merge([
      for space_idx in range(local.pe_pool_address_spaces) : {
        for subnet_idx in range(local.pe_subnets_per_space) :
        "pe-subnet-${space_idx * local.pe_subnets_per_space + subnet_idx}" => {
          name = "${var.private_endpoint_subnet_name}-${space_idx * local.pe_subnets_per_space + subnet_idx}"
          cidr = "${local.parsed_spaces[space_idx].prefix}.${subnet_idx * 32}/27"
        }
      }
  ]...)

  # Default PE subnet (first in pool) for backward compatibility
  private_endpoint_subnet_cidr = local.num_address_spaces == 1 ? "${local.parsed_spaces[0].prefix}.0/27" : "${local.parsed_spaces[0].prefix}.0/24"

  # =============================================================================
  # INFRASTRUCTURE SUBNET ALLOCATION
  # APIM, AppGW, and ACA subnets come from infrastructure address spaces
  # =============================================================================

  # Determine which address space is used for infrastructure
  # - 1 /24:  Everything in first /24 after PE /27
  # - 2 /24s: Second /24 for infrastructure
  # - 4+ /24s: Third and fourth /24s for infrastructure
  infra_space_idx = local.num_address_spaces == 1 ? 0 : (
    local.num_address_spaces >= 4 ? 2 : 1
  )
  infra_base = local.parsed_spaces[local.infra_space_idx].prefix

  # Second infrastructure space for 4+ /24 scenarios
  infra_space_idx_2 = local.num_address_spaces >= 4 ? 3 : local.infra_space_idx

  # =============================================================================
  # APIM SUBNET CALCULATION
  # =============================================================================
  # - 1 /24:  /27 after PE (offset 32)
  # - 2 /24s: /27 at start of second /24
  # - 4+ /24s: /27 at start of third /24

  apim_offset      = local.num_address_spaces == 1 ? 32 : 0
  apim_subnet_cidr = var.apim_subnet.enabled ? "${local.infra_base}.${local.apim_offset}/${var.apim_subnet.prefix_length}" : null

  # =============================================================================
  # APP GATEWAY SUBNET CALCULATION
  # =============================================================================
  # - 1 /24:  /27 after PE and APIM (offset 64 or 32 if no APIM)
  # - 2 /24s: /27 after APIM in second /24 (offset 32)
  # - 4+ /24s: /27 at start of fourth /24

  appgw_offset = local.num_address_spaces == 1 ? (var.apim_subnet.enabled ? 64 : 32) : (
    local.num_address_spaces >= 4 ? 0 : 32
  )
  appgw_base        = local.num_address_spaces >= 4 ? local.parsed_spaces[local.infra_space_idx_2].prefix : local.infra_base
  appgw_subnet_cidr = var.appgw_subnet.enabled ? "${local.appgw_base}.${local.appgw_offset}/${var.appgw_subnet.prefix_length}" : null

  # =============================================================================
  # ACA SUBNET CALCULATION
  # Container Apps Environment requires minimum /23 for consumption workload
  # But for consumption-only without zone redundancy, /27 may work (platform dependent)
  # =============================================================================
  # - 1 /24:  /27 after PE, APIM, and AppGW (offset 96 or less if features disabled)
  # - 2 /24s: /27 after APIM and AppGW in second /24 (offset 64)
  # - 4+ /24s: /27 after AppGW in fourth /24 (offset 32)

  aca_offset = local.num_address_spaces == 1 ? (
    (var.apim_subnet.enabled ? 32 : 0) + (var.appgw_subnet.enabled ? 32 : 0) + 32
    ) : (
    local.num_address_spaces >= 4 ? 32 : 64
  )
  aca_base        = local.num_address_spaces >= 4 ? local.parsed_spaces[local.infra_space_idx_2].prefix : local.infra_base
  aca_subnet_cidr = var.aca_subnet.enabled ? "${local.aca_base}.${local.aca_offset}/${var.aca_subnet.prefix_length}" : null
}
