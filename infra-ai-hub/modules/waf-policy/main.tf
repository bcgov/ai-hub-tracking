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
  policy_settings {
    enabled                     = var.enabled
    mode                        = var.mode
    request_body_check          = var.request_body_check
    max_request_body_size_in_kb = var.max_request_body_size_kb
    file_upload_limit_in_mb     = var.file_upload_limit_mb
  }

  # Managed rule sets (OWASP, Microsoft Bot Manager, etc.)
  dynamic "managed_rules" {
    for_each = length(var.managed_rule_sets) > 0 ? [1] : []
    content {
      dynamic "managed_rule_set" {
        for_each = var.managed_rule_sets
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
  }

  # Custom rules
  dynamic "custom_rules" {
    for_each = var.custom_rules
    content {
      name      = custom_rules.value.name
      priority  = custom_rules.value.priority
      rule_type = custom_rules.value.rule_type
      action    = custom_rules.value.action

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
