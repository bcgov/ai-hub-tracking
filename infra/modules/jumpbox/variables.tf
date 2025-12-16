# -----------------------------------------------------------------------------
# Jumpbox Module Variables
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

variable "subnet_id" {
  description = "Subnet ID for the jumpbox VM"
  type        = string
  nullable    = false
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  nullable    = false
}

variable "vm_size" {
  description = "Size of the virtual machine (B2als_v2: 2 vCPU, 4 GB RAM - cost-effective for jumpbox)"
  type        = string
  default     = "Standard_B2als_v2"
}


variable "os_disk_type" {
  description = "Storage account type for the OS disk"
  type        = string
  default     = "Standard_LRS" # Standard storage for cost optimization
}

variable "os_disk_size_gb" {
  description = "Size of the OS disk in GB"
  type        = number
  default     = 64
  nullable    = false
}
