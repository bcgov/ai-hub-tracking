variable "name_prefix" {
  description = "Prefix for resource names (e.g., ai-hub-test)"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "dns_zone_name" {
  description = "DNS zone name (e.g., test.aihub.gov.bc.ca)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the DNS resource group"
  type        = string
}

variable "a_record_ttl" {
  description = "TTL for the A record in seconds"
  type        = number
  default     = 3600
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# DDoS Protection
# -----------------------------------------------------------------------------
variable "ddos_protection_enabled" {
  description = "Enable DDoS IP Protection on the App Gateway public IP. Provides per-IP adaptive L3/L4 DDoS mitigation, telemetry, and alerting. Cost: ~$199 USD/month per IP."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Diagnostics
# -----------------------------------------------------------------------------
variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic settings on the public IP and DNS zone"
  type        = string
}
