variable "vnet_address_spaces" {
  type        = list(string)
  description = "The address spaces that will be used for the Virtual Network. may contain one or more of /24 addresses as per standard bcgov landing zone design."
  nullable    = false
  validation {
    condition     = var.vnet_address_spaces == null || length(var.vnet_address_spaces) > 0
    error_message = "At least one address space must be provided in the vnet_address_spaces variable."
  }
}
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  nullable    = false
}
variable "name_prefix" {
  description = "Prefix to use for naming resources"
  type        = string
  nullable    = false
}
variable "location" {
  description = "Azure region for resources"
  type        = string
  nullable    = false
}
variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
  nullable    = false
}
variable "vnet_resource_group_name" {
  description = "Name of the resource group"
  type        = string
  nullable    = false
}
