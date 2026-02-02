variable "name" {
  description = "Name of the Azure Managed Grafana instance"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name for Grafana and dashboards"
  type        = string
}

variable "location" {
  description = "Azure region for Grafana and dashboards"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/test/prod)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "grafana_major_version" {
  description = "Grafana major version"
  type        = string
  default     = "10"
}

variable "sku" {
  description = "Grafana SKU"
  type        = string
  default     = "Standard"
}

variable "public_network_access_enabled" {
  description = "Enable public network access for Grafana"
  type        = bool
  default     = true
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoints (Grafana and storage)"
  type        = string
  default     = null
}

variable "private_endpoint_dns_wait" {
  description = "DNS wait settings for policy-managed private DNS zones"
  type = object({
    timeout       = string
    poll_interval = string
  })
  default = null
}

variable "scripts_dir" {
  description = "Scripts directory for wait-for-dns-zone.sh"
  type        = string
  default     = ""
}

variable "api_key_enabled" {
  description = "Enable Grafana API keys"
  type        = bool
  default     = false
}

variable "dashboards_enabled" {
  description = "Enable dashboard storage and uploads"
  type        = bool
  default     = true
}

variable "dashboards_path" {
  description = "Path to dashboard JSON files"
  type        = string
}

variable "storage_account_name" {
  description = "Storage account name for dashboard JSON (optional)"
  type        = string
  default     = null
}

variable "dashboard_container_name" {
  description = "Storage container name for dashboard JSON"
  type        = string
  default     = "grafana-dashboards"
}

variable "enable_log_analytics_dashboard" {
  description = "Upload Log Analytics-based dashboards"
  type        = bool
  default     = true
}

variable "enable_app_insights_dashboard" {
  description = "Upload App Insights-based dashboards"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID (shared)"
  type        = string
  default     = null
}

variable "application_insights_id" {
  description = "Application Insights resource ID (shared)"
  type        = string
  default     = null
}
