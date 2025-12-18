# -----------------------------------------------------------------------------
# Variables for GitHub Runners on Azure Container Apps
# -----------------------------------------------------------------------------

variable "enabled" {
  description = "Enable or disable the GitHub runners module"
  type        = bool
  default     = true
}

variable "postfix" {
  description = "A postfix used to build default names for resources (e.g., 'ai-hub')"
  type        = string
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the existing resource group"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# GitHub Configuration
# -----------------------------------------------------------------------------

variable "github_organization" {
  description = "GitHub organization name (e.g., 'bcgov')"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name (e.g., 'ai-hub-tracking')"
  type        = string
}

variable "github_runner_pat" {
  description = "GitHub Personal Access Token with Administration:write permission for runner registration"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "vnet_id" {
  description = "ID of the existing virtual network"
  type        = string
}

variable "container_app_subnet_id" {
  description = "ID of the subnet for Container Apps (must be delegated to Microsoft.App/environments)"
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "ID of the subnet for private endpoints (used for ACR)"
  type        = string
}


# -----------------------------------------------------------------------------
# Container Configuration
# -----------------------------------------------------------------------------

variable "container_cpu" {
  description = "CPU cores for each runner container (e.g., 1, 2, 4)"
  type        = number
  default     = 4
}

variable "container_memory" {
  description = "Memory for each runner container (e.g., '4Gi')"
  type        = string
  default     = "8Gi"
}

variable "max_runners" {
  description = "Maximum number of concurrent runners"
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# Monitoring (Log Analytics)
# -----------------------------------------------------------------------------

variable "log_analytics_workspace_creation_enabled" {
  description = "Whether the AVM runner module should create a Log Analytics workspace"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace ID to use when creation is disabled"
  type        = string
  default     = null
  nullable    = true
}
