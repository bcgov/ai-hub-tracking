variable "name" {
  description = "Name of the WAF policy"
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

variable "enabled" {
  description = "Enable the WAF policy"
  type        = bool
  default     = true
}

variable "mode" {
  description = "WAF mode: Detection or Prevention"
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Detection", "Prevention"], var.mode)
    error_message = "mode must be Detection or Prevention"
  }
}

variable "request_body_check" {
  description = "Enable request body inspection"
  type        = bool
  default     = true
}

variable "request_body_enforcement" {
  description = "Enforce max request body size limit. When false, WAF inspects up to inspect_limit but does not reject oversized requests. Requires OWASP CRS 3.2+"
  type        = bool
  default     = true
}

variable "request_body_inspect_limit_in_kb" {
  description = "How deep into a request body the WAF inspects and applies rules (KB). Only used with CRS 3.2+"
  type        = number
  default     = 128
}

variable "max_request_body_size_kb" {
  description = "Maximum request body size in KB (up to 2048 for CRS 3.2+)"
  type        = number
  default     = 128
}

variable "file_upload_limit_mb" {
  description = "Maximum file upload size in MB"
  type        = number
  default     = 100
}

variable "managed_rule_sets" {
  description = "Managed rule sets to apply"
  type = list(object({
    type    = string # OWASP, Microsoft_BotManagerRuleSet, Microsoft_DefaultRuleSet
    version = string
    rule_group_overrides = optional(list(object({
      rule_group_name = string
      rules = optional(list(object({
        id      = string
        enabled = optional(bool, true)
        action  = optional(string)
      })), [])
    })), [])
  }))
  default = [
    {
      type    = "OWASP"
      version = "3.2"
    },
    {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }
  ]
}

variable "exclusions" {
  description = "Rule exclusions for false positive handling"
  type = list(object({
    match_variable          = string # RequestHeaderNames, RequestCookieNames, RequestArgNames, RequestBodyPostArgNames
    selector                = string
    selector_match_operator = string # Contains, EndsWith, Equals, EqualsAny, StartsWith
  }))
  default = []
}

variable "custom_rules" {
  description = "Custom WAF rules"
  type = list(object({
    name      = string
    priority  = number
    rule_type = string # MatchRule, RateLimitRule
    action    = string # Allow, Block, Log
    match_conditions = list(object({
      match_variable = string
      selector       = optional(string)
      operator       = string
      negation       = optional(bool, false)
      match_values   = list(string)
      transforms     = optional(list(string), [])
    }))
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
