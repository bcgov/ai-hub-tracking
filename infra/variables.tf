
variable "app_env" {
  description = "Application environment (dev, test, prod)"
  type        = string
}

variable "app_name" {
  description = "Name of the application"
  type        = string
}
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}
variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "Canada Central"
}
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
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

variable "use_oidc" {
  description = "Use OIDC for authentication"
  type        = bool
  default     = true
}

variable "vnet_address_space" {
  type        = string
  description = "Address space for the virtual network, it is created by platform team"
}

variable "vnet_name" {
  description = "Name of the existing virtual network"
  type        = string
}

variable "vnet_resource_group_name" {
  description = "Resource group name where the virtual network exists"
  type        = string
}
variable "client_id" {
  description = "Azure client ID for the service principal"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# GitHub Runners on Azure Container Apps (AVM-based)
# -----------------------------------------------------------------------------

variable "github_runners_aca_enabled" {
  description = "Enable GitHub self-hosted runners on Azure Container Apps"
  type        = bool
  default     = false
}

variable "github_organization" {
  description = "GitHub organization name (e.g., 'bcgov')"
  type        = string
  default     = ""
}

variable "github_repository" {
  description = "GitHub repository name (e.g., 'ai-hub-tracking')"
  type        = string
  default     = ""
}

variable "github_runner_pat" {
  description = "GitHub Personal Access Token with Administration:write permission for runner registration"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_runners_container_cpu" {
  description = "CPU cores for each runner container"
  type        = number
  default     = 1
}

variable "github_runners_container_memory" {
  description = "Memory for each runner container (e.g., '4Gi')"
  type        = string
  default     = "8Gi"
}

variable "github_runners_max_count" {
  description = "Maximum number of concurrent runners"
  type        = number
  default     = 1
}

variable "github_runners_log_analytics_workspace_creation_enabled" {
  description = "Whether the GitHub runners module should create a Log Analytics workspace"
  type        = bool
  default     = true
}

variable "github_runners_log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace ID to use when workspace creation is disabled"
  type        = string
  default     = null
  nullable    = true
}
