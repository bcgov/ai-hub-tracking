variable "name_prefix" {
  description = "Optional prefix for naming the Log Analytics workspace. When null, the module uses a default name."
  type        = string
  default     = null
}

variable "enable_telemetry" {
  description = "Enable or disable AVM telemetry for the Log Analytics Workspace module."
  type        = bool
  default     = false
}

variable "law_definition" {
  description = "Log Analytics Workspace definition. Fields: resource_id (existing LAW to use), name (custom LAW name), retention (days), sku (workspace SKU)."
  type = object({
    resource_id = optional(string)
    name        = optional(string)
    retention   = optional(number, 30)
    sku         = optional(string, "PerGB2018")
  })
  default  = {}
  nullable = false
}
