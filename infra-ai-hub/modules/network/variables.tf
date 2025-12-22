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

variable "private_endpoint_subnet_prefix_length" {
  description = "Prefix length for the private endpoint subnet derived from target_vnet_address_spaces[0]. Use 27 for a /27."
  type        = number
  default     = 27

  validation {
    condition     = var.private_endpoint_subnet_prefix_length >= 0 && var.private_endpoint_subnet_prefix_length <= 32
    error_message = "private_endpoint_subnet_prefix_length must be between 0 and 32."
  }
}

variable "private_endpoint_subnet_netnum" {
  description = "Which derived subnet to use when splitting the base CIDR. 0 selects the first derived subnet."
  type        = number
  default     = 0

  validation {
    condition     = var.private_endpoint_subnet_netnum >= 0
    error_message = "private_endpoint_subnet_netnum must be >= 0."
  }
}
