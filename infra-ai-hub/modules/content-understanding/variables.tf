variable "name" {
  description = "Name of the Foundry (AIServices) account that hosts Content Understanding. Also used as the custom subdomain, so it must be globally unique."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$", var.name))
    error_message = "name must be 3-64 lowercase alphanumeric characters or hyphens, and must start and end with an alphanumeric character."
  }
}

variable "location" {
  description = "Azure region for the Content Understanding account. Restricted to the Canadian regions; see https://learn.microsoft.com/azure/ai-services/content-understanding/language-region-support for which of them Content Understanding currently supports."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["canadacentral", "canadaeast"], lower(replace(var.location, " ", "")))
    error_message = "location must be \"Canada Central\" or \"Canada East\"."
  }
}

variable "private_endpoint_location" {
  description = "Azure region of the private endpoint. Must match the region of the VNet that owns private_endpoint_subnet_id."
  type        = string
  nullable    = false
}

variable "resource_group_name" {
  description = "Name of the tenant resource group that will contain the account and its private endpoint."
  type        = string
  nullable    = false
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for the account's private endpoint."
  type        = string
  nullable    = false
}

variable "sku" {
  description = "SKU of the Foundry (AIServices) account. S0 is the only SKU for kind AIServices."
  type        = string
  default     = "S0"
  nullable    = false
}

variable "model_deployments" {
  description = <<-EOT
    Model deployments created on the account for Content Understanding to use.
    Keys are roles. "completion" and "embedding" are required. "completion_mini" is optional
    and falls back to the completion deployment when absent.
    The deployment name equals model_name (the account is tenant-scoped, so no prefix is needed).
    Supported models: https://learn.microsoft.com/azure/ai-services/content-understanding/service-limits
  EOT
  type = map(object({
    model_name             = string
    model_version          = string
    scale_type             = optional(string, "GlobalStandard")
    capacity               = number
    version_upgrade_option = optional(string, "OnceCurrentVersionExpired")
  }))
  nullable = false

  validation {
    condition     = contains(keys(var.model_deployments), "completion") && contains(keys(var.model_deployments), "embedding")
    error_message = "model_deployments must contain at least the \"completion\" and \"embedding\" roles."
  }

  validation {
    condition     = alltrue([for k in keys(var.model_deployments) : contains(["completion", "completion_mini", "embedding"], k)])
    error_message = "model_deployments keys must be one of: completion, completion_mini, embedding."
  }

  validation {
    condition     = length(distinct([for d in values(var.model_deployments) : d.model_name])) == length(var.model_deployments)
    error_message = "Each model_deployments role must use a different model_name, because the deployment name equals the model name."
  }
}

variable "enable_diagnostics" {
  description = "Create a diagnostic setting that sends logs/metrics to log_analytics_workspace_id. Must be a plan-time value."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostics. Required when enable_diagnostics is true."
  type        = string
  default     = null
}

variable "diagnostics" {
  description = "Diagnostic categories to enable when enable_diagnostics is true."
  type = object({
    log_groups        = optional(list(string), [])
    log_categories    = optional(list(string), [])
    metric_categories = optional(list(string), [])
  })
  default = null
}

variable "scripts_dir" {
  description = "Path to the shared scripts directory (wait-for-dns-zone.sh). Empty string skips the DNS wait."
  type        = string
  default     = ""
}

variable "private_endpoint_dns_wait" {
  description = "Timeout and poll interval used while waiting for the policy-managed DNS zone group."
  type = object({
    timeout       = optional(string, "12m")
    poll_interval = optional(string, "30s")
  })
  default = {}
}

variable "tags" {
  description = "Tags applied to the account and its private endpoint."
  type        = map(string)
  default     = {}
}
