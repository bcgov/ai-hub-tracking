variable "name" {
  description = "Name of the AI Foundry account"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "resource_group_id" {
  description = "Resource ID of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for supporting resources (Log Analytics, App Insights, Private Endpoints)"
  type        = string
}

variable "ai_location" {
  description = "Azure region for AI Foundry Hub. Can differ from location for model availability (e.g., canadaeast for GPT-4.1). Defaults to location."
  type        = string
  default     = null
}

variable "sku" {
  description = "SKU for the AI Foundry account"
  type        = string
  default     = "S0"
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled"
  type        = bool
  default     = false
}

variable "local_auth_enabled" {
  description = "Whether local authentication (API keys) is enabled"
  type        = bool
  default     = false
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoints"
  type        = string
}

variable "log_analytics" {
  description = "Log Analytics workspace configuration"
  type = object({
    enabled        = bool
    retention_days = optional(number, 30)
    sku            = optional(string, "PerGB2018")
    workspace_id   = optional(string) # Use existing workspace if provided
  })
  default = {
    enabled = true
  }
}

variable "application_insights" {
  description = "Application Insights configuration for AI Foundry monitoring"
  type = object({
    enabled                       = optional(bool, true)
    name                          = optional(string) # Defaults to "{name}-appi"
    application_type              = optional(string, "web")
    retention_in_days             = optional(number, 90)
    daily_data_cap_in_gb          = optional(number, 10)
    sampling_percentage           = optional(number, 100)
    disable_ip_masking            = optional(bool, false)
    local_authentication_disabled = optional(bool, true)
  })
  default = {
    enabled = true
  }
}

variable "ai_agent" {
  description = "AI Agent service configuration with network injection support"
  type = object({
    enabled                   = optional(bool, false)
    network_injection_enabled = optional(bool, false)
    subnet_id                 = optional(string) # Dedicated subnet for AI Agent (optional)
  })
  default = {
    enabled = false
  }
}

variable "bing_grounding" {
  description = "Bing Web Search resource for grounding AI models"
  type = object({
    enabled = optional(bool, false)
    sku     = optional(string, "S1") # S1, S2, S3
  })
  default = {
    enabled = false
  }
}

variable "private_endpoint_dns_wait" {
  description = "Configuration for waiting on policy-managed DNS zone groups"
  type = object({
    timeout       = optional(string, "12m")
    poll_interval = optional(string, "30s")
  })
  default = {}
}

variable "scripts_dir" {
  description = "Path to the scripts directory containing wait-for-dns-zone.sh"
  type        = string
  default     = ""
}

variable "purge_on_destroy" {
  description = "Whether to permanently purge the AI Foundry account on destroy (bypasses soft delete)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
