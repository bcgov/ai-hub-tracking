variable "create" {
  type        = bool
  description = "Whether to create the resource group."
  default     = false
}

variable "name" {
  type        = string
  description = "Name of the resource group to create."
  default     = null
}

variable "location" {
  type        = string
  description = "Azure region where the resource group will be created."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the resource group."
  default     = {}
}
