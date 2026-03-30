# -----------------------------------------------------------------------------
# Bastion Module Variables
# -----------------------------------------------------------------------------

variable "app_name" {
  description = "Name of the application, used for resource naming"
  type        = string
  nullable    = false
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  nullable    = false
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  nullable    = false
}

variable "bastion_subnet_id" {
  description = "Subnet ID for Azure Bastion (must be named AzureBastionSubnet)"
  type        = string
  nullable    = false
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  nullable    = false
}

variable "bastion_sku" {
  description = "SKU for Azure Bastion (Basic or Standard)"
  type        = string
  default     = "Standard"
  nullable    = false

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.bastion_sku)
    error_message = "Bastion SKU must be Basic, Standard, or Premium."
  }
}

variable "tunneling_enabled" {
  description = "Enable native client tunneling (az network bastion ssh/tunnel). Requires Standard or Premium SKU."
  type        = bool
  default     = true
}
