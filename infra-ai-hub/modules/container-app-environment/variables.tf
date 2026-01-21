variable "name" {
  description = "Name of the Container App Environment"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "infrastructure_subnet_id" {
  description = "Subnet ID for the Container App Environment infrastructure"
  type        = string
}

variable "internal_load_balancer_enabled" {
  description = "Use internal load balancer (private only access)"
  type        = bool
  default     = true
}

variable "zone_redundancy_enabled" {
  description = "Enable zone redundancy. Requires /23+ subnet. Set to false for /27 consumption-only."
  type        = bool
  default     = false # Default to false for /27 subnet compatibility
}

variable "mtls_enabled" {
  description = "Enable mTLS peer authentication between apps"
  type        = bool
  default     = true
}

variable "workload_profiles" {
  description = "Workload profiles for dedicated compute (Consumption-only if empty)"
  type = list(object({
    name                  = string
    workload_profile_type = string
    minimum_count         = optional(number)
    maximum_count         = optional(number)
  }))
  default = []
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for diagnostics"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "enable_telemetry" {
  description = "Enable AVM telemetry"
  type        = bool
  default     = false
}
