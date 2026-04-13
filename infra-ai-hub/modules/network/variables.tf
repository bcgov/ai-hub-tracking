variable "name_prefix" {
  description = "Prefix used for naming resources (e.g., ai-hub-dev)"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "vnet_name" {
  description = "Name of the existing virtual network (target environment)"
  type        = string
}

variable "vnet_resource_group_name" {
  description = "Resource group name where the virtual network exists (target environment)"
  type        = string
}

variable "source_vnet_address_space" {
  description = "Address space of the source environment VNet (single CIDR string), used for NSG allow rules (e.g., tools VNet CIDR)."
  type        = string
}

# -----------------------------------------------------------------------------
# Subnet Allocation Map
# Single source of truth for all address space ↔ subnet mappings.
# -----------------------------------------------------------------------------
variable "subnet_allocation" {
  description = <<-EOT
    Explicit subnet allocation map. Outer key = address space CIDR.
    Inner key = subnet name, inner value = full subnet CIDR (e.g., "10.x.x.0/27").

    Known subnet types (exact key names required):
    - "privateendpoints-subnet"    — PE subnet (no delegation)
    - "privateendpoints-subnet-<n>" — Additional PE subnets (<n> = 1, 2, ...)
    - "apim-subnet"                — APIM VNet injection (delegation: Microsoft.Web/serverFarms)
    - "appgw-subnet"               — Application Gateway (no delegation, dedicated)
    - "aca-subnet"                 — Container Apps Environment (delegation: Microsoft.App/environments)
    - "vllm-aca-subnet"            — GPU vLLM Container Apps Environment (delegation: Microsoft.App/environments)

    Each subnet CIDR must fall within its parent address space.
    Subnets are independent — changing one does not recompute others.

    Example (2 address spaces):
      subnet_allocation = {
        "10.x.x.0/24" = { "privateendpoints-subnet" = "10.x.x.0/24" }
        "10.x.x.0/24"  = { "apim-subnet" = "10.x.x.0/27", "appgw-subnet" = "10.x.x.32/27", "aca-subnet" = "10.x.x.64/27", "vllm-aca-subnet" = "10.x.x.96/27" }
      }
    Example (4 address spaces):
      subnet_allocation = {
        "10.x.x.0/24" = { "privateendpoints-subnet" = "10.x.x.0/24" }
        "10.x.x.0/24"  = { "privateendpoints-subnet-1" = "10.x.x.0/24" }
        "10.x.x.0/24"  = { "privateendpoints-subnet-2" = "10.x.x.0/24" }
        "10.x.x.0/24"  = { "apim-subnet" = "10.x.x.0/25", "appgw-subnet" = "10.x.x.128/26", "aca-subnet" = "10.x.x.192/27", "vllm-aca-subnet" = "10.x.x.224/27" }
      }
    Future Growth:
    - To add more PE subnets, simply add new "privateendpoints-subnet-<n>" entries with unique <n> suffixes.
    - To add more address spaces, add new outer keys with their own subnet maps.
  EOT
  type        = map(map(string))

  validation {
    condition     = length(var.subnet_allocation) > 0
    error_message = "subnet_allocation must contain at least one address space."
  }

  validation {
    condition = alltrue(flatten([
      for space_cidr, subnets in var.subnet_allocation : [
        for name, cidr in subnets : can(cidrhost(cidr, 0))
      ]
    ]))
    error_message = "All subnet values must be valid CIDR notation (e.g., '10.x.x.0/27')."
  }

  validation {
    condition = alltrue(flatten([
      for space_cidr, subnets in var.subnet_allocation : [
        for name, _ in subnets : contains([
          "privateendpoints-subnet", "apim-subnet", "appgw-subnet", "aca-subnet", "vllm-aca-subnet"
        ], name) || can(regex("^privateendpoints-subnet-[1-9]\\d*$", name))
      ]
    ]))
    error_message = "Subnet names must be one of: privateendpoints-subnet, privateendpoints-subnet-<n> (n starts at 1), apim-subnet, appgw-subnet, aca-subnet, vllm-aca-subnet."
  }

  validation {
    condition = contains(flatten([
      for _, subnets in var.subnet_allocation : keys(subnets)
    ]), "privateendpoints-subnet")
    error_message = "Primary PE subnet 'privateendpoints-subnet' must be defined. Additional PE subnets may be added as 'privateendpoints-subnet-<n>'."
  }

  validation {
    condition = length(flatten([
      for _, subnets in var.subnet_allocation : keys(subnets)
      ])) == length(distinct(flatten([
        for _, subnets in var.subnet_allocation : keys(subnets)
    ])))
    error_message = "Each subnet name must appear in exactly one address space (no duplicates across spaces)."
  }
}

# -----------------------------------------------------------------------------
# External VNet Peered Projects — Direct APIM Access (bypassing App Gateway)
# Allows Azure teams with peered VNets to reach APIM directly on port 443.
# Each entry adds an inbound HTTPS NSG rule on the APIM subnet.
# No outbound mirror needed — Azure NSGs are stateful.
# -----------------------------------------------------------------------------
variable "external_peered_projects" {
  description = <<-EOT
    Map of external project names to their peered VNet config.
    These projects can reach APIM directly via VNet peering, bypassing App Gateway.

    Key   = project name (used in NSG rule names, must be DNS-label-safe: [a-z0-9-])
    Value = object with:
      cidrs    = list of CIDR blocks for that project's peered VNet(s)
      priority = stable NSG rule priority (400-499, must be unique per project)

    Priorities are caller-assigned so adding/removing a project never shifts
    existing rules. Reserve gaps (e.g., 400, 410, 420) for future growth.

    NSG rule created per project:
      Inbound — project CIDRs → APIM subnet (443/TCP) at given priority

    Example:
      external_peered_projects = {
        "forest-client" = { cidrs = ["10.97.64.0/20"],                priority = 400 }
        "nr-data-hub"   = { cidrs = ["10.97.80.0/22", "10.97.84.0/22"], priority = 410 }
      }
  EOT
  type = map(object({
    cidrs    = list(string)
    priority = number
  }))
  default = {}

  validation {
    condition = alltrue(flatten([
      for project, cfg in var.external_peered_projects : [
        for cidr in cfg.cidrs : can(cidrhost(cidr, 0))
      ]
    ]))
    error_message = "All CIDRs in external_peered_projects must be valid CIDR notation."
  }

  validation {
    condition = alltrue([
      for project, _ in var.external_peered_projects : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", project))
    ])
    error_message = "Project names must be lowercase alphanumeric with hyphens (DNS label safe)."
  }

  validation {
    condition = alltrue([
      for _, cfg in var.external_peered_projects : cfg.priority >= 400 && cfg.priority <= 499
    ])
    error_message = "Priorities must be between 400 and 499."
  }

  validation {
    condition     = length(values(var.external_peered_projects)[*].priority) == length(toset(values(var.external_peered_projects)[*].priority))
    error_message = "Each project must have a unique priority value."
  }
}

