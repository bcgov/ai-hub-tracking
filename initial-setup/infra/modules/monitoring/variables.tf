variable "app_name" {
  description = "Name of the application"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  nullable    = false
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "Canada Central"
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain data in Log Analytics Workspace"
  type        = number
  default     = 30
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics Workspace"
  type        = string
  default     = "PerGB2018"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}