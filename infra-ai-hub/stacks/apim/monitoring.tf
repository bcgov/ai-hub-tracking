# =============================================================================
# APIM RESOURCE HEALTH MONITORING
# =============================================================================
# Attaches a Resource Health alert for the APIM instance to the shared hub
# action group (Teams webhook) provisioned in the shared stack.
#
# Prerequisite: monitoring must be enabled in shared_config.monitoring and
# the shared stack must have been applied first (action group is in its state).
# =============================================================================

resource "azurerm_monitor_activity_log_alert" "apim_health" {
  count = local.monitoring_config.enabled && local.apim_config.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-apim-health"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  location            = "global"
  scopes              = [module.apim[0].id]
  description         = "Alert when APIM resource health becomes Unavailable or Degraded"

  criteria {
    category = "ResourceHealth"

    resource_health {
      current  = ["Unavailable", "Degraded", "Unknown"]
      previous = ["Available"]
      reason   = ["PlatformInitiated", "Unknown"]
    }
  }

  action {
    action_group_id = data.terraform_remote_state.shared.outputs.hub_alerts_action_group_id
  }

  tags = var.common_tags
}
