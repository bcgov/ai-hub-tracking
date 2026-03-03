locals {
  # =============================================================================
  # SUBNET ALLOCATION — DIRECT CIDR MAPPING
  # Reads full CIDRs directly from var.subnet_allocation (no offset computation).
  # Outer key = address space, inner key = subnet name, value = full CIDR.
  # =============================================================================

  # Flatten all subnets across address spaces into a single name → cidr map
  subnet_cidrs = merge([
    for space_cidr, subnets in var.subnet_allocation : {
      for name, cidr in subnets : name => cidr
    }
  ]...)

  # Address spaces from outer map keys (used in NSG dynamic blocks)
  address_spaces = keys(var.subnet_allocation)

  # =============================================================================
  # ENABLED FLAGS — derived from subnet name presence
  # =============================================================================

  pe_enabled    = contains(keys(local.subnet_cidrs), "privateendpoints-subnet")
  apim_enabled  = contains(keys(local.subnet_cidrs), "apim-subnet")
  appgw_enabled = contains(keys(local.subnet_cidrs), "appgw-subnet")
  aca_enabled   = contains(keys(local.subnet_cidrs), "aca-subnet")

  # =============================================================================
  # PE SUBNET POOL
  # All subnets whose name starts with "privateendpoints-subnet".
  # Sorted so the primary (no suffix) always comes first.
  # =============================================================================

  pe_subnet_names = sort([
    for name, _ in local.subnet_cidrs : name
    if startswith(name, "privateendpoints-subnet")
  ])

  # Primary PE subnet name — "privateendpoints-subnet" sorts before "-1", "-2", etc.
  pe_subnet_name = length(local.pe_subnet_names) > 0 ? local.pe_subnet_names[0] : "privateendpoints-subnet"

  # PE pool map: subnet name → { name, cidr }
  # Keys are the actual Azure subnet names (privateendpoints-subnet, -1, -2, ...)
  pe_subnet_pool = {
    for name in local.pe_subnet_names :
    name => {
      name = name
      cidr = local.subnet_cidrs[name]
    }
  }

  # Flat list of all PE subnet CIDRs — used in NSG rules to cover the entire pool.
  # Sorted to ensure deterministic ordering in destination_address_prefixes.
  pe_subnet_cidrs = sort([for pe in values(local.pe_subnet_pool) : pe.cidr])

  # =============================================================================
  # RESOLVED CIDRs — backward-compatible output values
  # =============================================================================

  private_endpoint_subnet_cidr = local.pe_enabled ? local.subnet_cidrs["privateendpoints-subnet"] : null
  apim_subnet_cidr             = local.apim_enabled ? local.subnet_cidrs["apim-subnet"] : null
  appgw_subnet_cidr            = local.appgw_enabled ? local.subnet_cidrs["appgw-subnet"] : null
  aca_subnet_cidr              = local.aca_enabled ? local.subnet_cidrs["aca-subnet"] : null
}
