locals { # Example: locals for vnet_address_spaces = ["10.46.15.0/24"]
  # Split the first address space in the list (expects /24 values). Example input: "10.46.15.0/24"
  vnet_ip_base = split("/", var.vnet_address_spaces[0])[0]                  # Example output: "10.46.15.0"
  octets       = split(".", local.vnet_ip_base)                             # Example output: ["10","46","15","0"]
  base_ip      = "${local.octets[0]}.${local.octets[1]}.${local.octets[2]}" # Example output: "10.46.15"

  # Derive PE subnet prefix based on address space count. Example counts: 1 -> /27, 2 -> /26, 4 -> /24
  # - 1 address space  => /27 (Example: ["10.46.15.0/24"] -> /27)
  # - 2 address spaces => /26 (Example: ["10.46.15.0/24","10.46.16.0/24"] -> /26)
  # - 4+ spaces        => /24 (Example: ["10.46.15.0/24","10.46.16.0/24","10.46.17.0/24","10.46.18.0/24"] -> /24)
  # - 3 spaces         => /26 (Example: ["10.46.15.0/24","10.46.16.0/24","10.46.17.0/24"] -> /26)
  pe_prefix = length(var.vnet_address_spaces) >= 4 ? 24 : (length(var.vnet_address_spaces) == 1 ? 27 : 26) # Example: length=2 -> 26

  private_endpoints_subnet_cidr = "${local.base_ip}.0/${local.pe_prefix}" # Example output: "10.46.15.0/27"
}                                                                         # Example end of locals block
