# WAF Policy Module
# Creates a dedicated Web Application Firewall policy for App Gateway
# https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/policy-overview

# =============================================================================
# WAF POLICY
# =============================================================================
resource "azurerm_web_application_firewall_policy" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  # Policy settings
  # CRS 3.2+ supports independent body enforcement control:
  #   request_body_enforcement=false lets large payloads through while still inspecting
  #   up to request_body_inspect_limit_in_kb for threats (SQL injection, XSS, etc.)
  policy_settings {
    enabled                          = var.enabled
    mode                             = var.mode
    request_body_check               = var.request_body_check
    request_body_enforcement         = var.request_body_enforcement
    request_body_inspect_limit_in_kb = var.request_body_inspect_limit_in_kb
    max_request_body_size_in_kb      = var.max_request_body_size_kb
    file_upload_limit_in_mb          = var.file_upload_limit_mb
  }

  # Managed rule sets (OWASP, Microsoft Bot Manager, etc.)
  # The managed_rules block is always required by azurerm >= 4.x.
  # When no rule sets are specified, a default OWASP 3.2 rule set is used.
  managed_rules {
    dynamic "managed_rule_set" {
      for_each = length(var.managed_rule_sets) > 0 ? var.managed_rule_sets : [{ type = "OWASP", version = "3.2", rule_group_overrides = [] }]
      content {
        type    = managed_rule_set.value.type
        version = managed_rule_set.value.version

        dynamic "rule_group_override" {
          for_each = lookup(managed_rule_set.value, "rule_group_overrides", [])
          content {
            rule_group_name = rule_group_override.value.rule_group_name

            dynamic "rule" {
              for_each = lookup(rule_group_override.value, "rules", [])
              content {
                id      = rule.value.id
                enabled = lookup(rule.value, "enabled", true)
                action  = lookup(rule.value, "action", null)
              }
            }
          }
        }
      }
    }

    # Exclusions
    dynamic "exclusion" {
      for_each = var.exclusions
      content {
        match_variable          = exclusion.value.match_variable
        selector                = exclusion.value.selector
        selector_match_operator = exclusion.value.selector_match_operator
      }
    }
  }

  # Custom rules (MatchRule and RateLimitRule)
  dynamic "custom_rules" {
    for_each = var.custom_rules
    content {
      name      = custom_rules.value.name
      priority  = custom_rules.value.priority
      rule_type = custom_rules.value.rule_type
      action    = custom_rules.value.action

      # Rate-limit fields — only valid when rule_type = "RateLimitRule".
      # Setting these on MatchRule causes Azure API errors.
      rate_limit_duration  = custom_rules.value.rule_type == "RateLimitRule" ? custom_rules.value.rate_limit_duration : null
      rate_limit_threshold = custom_rules.value.rule_type == "RateLimitRule" ? custom_rules.value.rate_limit_threshold : null
      group_rate_limit_by  = custom_rules.value.rule_type == "RateLimitRule" ? custom_rules.value.group_rate_limit_by : null

      dynamic "match_conditions" {
        for_each = custom_rules.value.match_conditions
        content {
          match_variables {
            variable_name = match_conditions.value.match_variable
            selector      = lookup(match_conditions.value, "selector", null)
          }
          operator           = match_conditions.value.operator
          negation_condition = lookup(match_conditions.value, "negation", false)
          match_values       = match_conditions.value.match_values
          transforms         = lookup(match_conditions.value, "transforms", [])
        }
      }
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}
