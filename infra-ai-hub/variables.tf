variable "app_env" {
  description = "Application environment (dev, test, prod)"
  type        = string
}

variable "app_name" {
  description = "Name of the application"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "Canada Central"
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure tenant ID"
  type        = string
  sensitive   = true
}

variable "client_id" {
  description = "Azure client ID for the service principal (OIDC)"
  type        = string
  sensitive   = true
}

variable "use_oidc" {
  description = "Use OIDC for authentication"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Resource group name for the AI Hub infra"
  type        = string
}

variable "key_vault_name" {
  description = "Key Vault name (3-24 chars, alphanumeric only)"
  type        = string
}

variable "vnet_name" {
  description = "Name of the existing virtual network"
  type        = string
}
variable "vnet_resource_group_name" {
  description = "Resource group name where the virtual network exists"
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

variable "private_endpoint_dns_wait_duration" {
  description = "Max time Terraform should wait for hub policy to attach Private DNS and create A-records for a private endpoint (e.g., 10m)."
  type        = string
  default     = "12m"
}

variable "private_endpoint_dns_poll_interval" {
  description = "How often Terraform should poll for the policy-created private DNS zone group on the private endpoint (e.g., 15s)."
  type        = string
  default     = "30s"
}
