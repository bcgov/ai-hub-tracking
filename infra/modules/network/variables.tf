variable "apps_service_subnet_name" {
  description = "Name of the subnet for App Services"
  type        = string
  default     = "app-service-subnet"
  nullable    = false
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  nullable    = false
}

variable "container_instance_subnet_name" {
  description = "Name of the subnet for container instances"
  type        = string
  default     = "container-instance-subnet"
  nullable    = false
}

variable "container_apps_subnet_name" {
  description = "Name of the subnet for Container Apps"
  type        = string
  default     = "container-apps-subnet"
  nullable    = false
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "Canada Central"
  nullable    = false
}

variable "private_endpoint_subnet_name" {
  description = "Name of the subnet for private endpoints"
  type        = string
  default     = "privateendpoints-subnet"
  nullable    = false
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  nullable    = false
}

variable "vnet_address_space" {
  type        = string
  description = "Address space for the virtual network, it is created by platform team"
  nullable    = false
}

variable "vnet_name" {
  description = "Name of the existing virtual network"
  type        = string
  nullable    = false
}

variable "vnet_resource_group_name" {
  description = "Resource group name where the virtual network exists"
  type        = string
  nullable    = false
}

variable "web_subnet_name" {
  description = "Name of the web subnet for APIM deployment"
  type        = string
  default     = "web-subnet"
  nullable    = false
}

variable "apim_subnet_name" {
  description = "Name of the subnet for API Management"
  type        = string
  default     = "apim-subnet"
  nullable    = false
}

variable "jumpbox_subnet_name" {
  description = "Name of the subnet for Jumpbox VM"
  type        = string
  default     = "jumpbox-subnet"
  nullable    = false
}

variable "bastion_subnet_name" {
  description = "Name of the subnet for Azure Bastion (must be AzureBastionSubnet)"
  type        = string
  default     = "AzureBastionSubnet"
  nullable    = false
}
