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

variable "target_vnet_address_spaces" {
  description = "Address spaces of the target environment VNet. The first entry (index 0) is used to derive the private endpoint subnet."
  type        = list(string)

  validation {
    condition     = length(var.target_vnet_address_spaces) > 0
    error_message = "target_vnet_address_spaces must contain at least one CIDR (e.g., 10.0.0.0/24)."
  }
}

variable "source_vnet_address_space" {
  description = "Address space of the source environment VNet (single CIDR string), used for NSG allow rules (e.g., tools VNet CIDR)."
  type        = string
}

variable "private_endpoint_subnet_name" {
  description = "Name of the private endpoint subnet to create in the target VNet"
  type        = string
  default     = "privateendpoints-subnet"
}

# -----------------------------------------------------------------------------
# APIM Subnet Configuration (for VNet injection - Premium v2 tier)
# -----------------------------------------------------------------------------
variable "apim_subnet" {
  description = <<-EOT
    Configuration for the APIM subnet. Required for APIM Premium v2 VNet injection.
    Note: APIM Premium v2 requires subnet delegation to Microsoft.Web/hostingEnvironments.
    For APIM with private endpoints only (stv2 style), set enabled = false and use PE subnet.
  EOT
  type = object({
    enabled       = bool
    name          = optional(string, "apim-subnet")
    prefix_length = optional(number, 27) # /27 minimum, /24 recommended for scaling
  })
  default = {
    enabled = false
  }
}

# -----------------------------------------------------------------------------
# App Gateway Subnet Configuration
# -----------------------------------------------------------------------------
variable "appgw_subnet" {
  description = "Configuration for the Application Gateway subnet. Automatically placed after PE/APIM subnets."
  type = object({
    enabled       = bool
    name          = optional(string, "appgw-subnet")
    prefix_length = optional(number, 27) # /27 = 32 IPs, sufficient for App Gateway
  })
  default = {
    enabled = false
  }
}

# -----------------------------------------------------------------------------
# Container Apps Environment Subnet Configuration
# -----------------------------------------------------------------------------
variable "aca_subnet" {
  description = <<-EOT
    Configuration for the Container Apps Environment subnet.
    /27 works for consumption-only WITHOUT zone redundancy.
    /23+ required for zone redundancy or dedicated workload profiles.
  EOT
  type = object({
    enabled       = bool
    name          = optional(string, "aca-subnet")
    prefix_length = optional(number, 27) # /27 for consumption-only (no zone redundancy)
  })
  default = {
    enabled = false
  }
}
