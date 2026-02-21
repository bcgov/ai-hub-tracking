# =============================================================================
# RESOURCE & SERVICE HEALTH MONITORING
# =============================================================================
# Scope: Hub-level resources in the shared stack.
#   - Resource Health: per-resource alerts (Unavailable / Degraded / Unknown)
#   - Service Health:  Azure platform incident / maintenance alerts
#
# Notification channels (at least one required when monitoring is enabled):
#   - monitoring_webhook_url   : Teams Power Automate webhook
#   - monitoring_alert_emails  : list of email addresses
# Both can be provided simultaneously. Config goes in sensitive tfvars.
# =============================================================================

# ---------------------------------------------------------------------------
# Validation — fail plan when monitoring is enabled with no receiver configured
# ---------------------------------------------------------------------------
resource "terraform_data" "monitoring_channel_validation" {
  lifecycle {
    precondition {
      condition     = !local.monitoring_config.enabled || local.monitoring_config.has_any_receiver
      error_message = "monitoring is enabled but no notification channel is configured. Set monitoring_webhook_url and/or monitoring_alert_emails in your sensitive tfvars."
    }
  }
}

# ---------------------------------------------------------------------------
# Action Group — Teams webhook and/or email receivers
# ---------------------------------------------------------------------------
resource "azurerm_monitor_action_group" "hub_alerts" {
  count = local.monitoring_config.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-hub-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "hub-alerts"

  dynamic "webhook_receiver" {
    for_each = trim(var.monitoring_webhook_url, " ") != "" ? [1] : []
    content {
      name                    = "teams"
      service_uri             = var.monitoring_webhook_url
      use_common_alert_schema = true
    }
  }

  dynamic "email_receiver" {
    for_each = { for idx, addr in local.monitoring_config.alert_emails : tostring(idx) => addr }
    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  tags = var.common_tags

  depends_on = [terraform_data.monitoring_channel_validation]
}

# ---------------------------------------------------------------------------
# Resource Health — AI Foundry Hub
# ---------------------------------------------------------------------------
resource "azurerm_monitor_activity_log_alert" "ai_foundry_health" {
  count = local.monitoring_config.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-ai-foundry-health"
  resource_group_name = azurerm_resource_group.main.name
  location            = "global"
  scopes              = [module.ai_foundry_hub.id]
  description         = "Alert when AI Foundry Hub resource health becomes Unavailable or Degraded"

  criteria {
    category = "ResourceHealth"

    resource_health {
      current  = ["Unavailable", "Degraded", "Unknown"]
      previous = ["Available"]
      reason   = ["PlatformInitiated", "Unknown"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.hub_alerts[0].id
  }

  tags = var.common_tags
}

# ---------------------------------------------------------------------------
# Resource Health — Language Service (conditional on service being enabled)
# ---------------------------------------------------------------------------
resource "azurerm_monitor_activity_log_alert" "language_service_health" {
  count = local.monitoring_config.enabled && var.shared_config.language_service.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-language-health"
  resource_group_name = azurerm_resource_group.main.name
  location            = "global"
  scopes              = [azurerm_cognitive_account.language_service[0].id]
  description         = "Alert when Language Service resource health becomes Unavailable or Degraded"

  criteria {
    category = "ResourceHealth"

    resource_health {
      current  = ["Unavailable", "Degraded", "Unknown"]
      previous = ["Available"]
      reason   = ["PlatformInitiated", "Unknown"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.hub_alerts[0].id
  }

  tags = var.common_tags
}

# ---------------------------------------------------------------------------
# Resource Health — Hub Key Vault
# ---------------------------------------------------------------------------
resource "azurerm_monitor_activity_log_alert" "hub_kv_health" {
  count = local.monitoring_config.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-hub-kv-health"
  resource_group_name = azurerm_resource_group.main.name
  location            = "global"
  scopes              = [module.hub_key_vault.resource_id]
  description         = "Alert when Hub Key Vault resource health becomes Unavailable or Degraded"

  criteria {
    category = "ResourceHealth"

    resource_health {
      current  = ["Unavailable", "Degraded", "Unknown"]
      previous = ["Available"]
      reason   = ["PlatformInitiated", "Unknown"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.hub_alerts[0].id
  }

  tags = var.common_tags
}

# ---------------------------------------------------------------------------
# Resource Health — Application Gateway (conditional on App Gateway enabled)
# ---------------------------------------------------------------------------
resource "azurerm_monitor_activity_log_alert" "app_gateway_health" {
  count = local.monitoring_config.enabled && local.appgw_config.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-appgw-health"
  resource_group_name = azurerm_resource_group.main.name
  location            = "global"
  scopes              = [module.app_gateway[0].id]
  description         = "Alert when App Gateway resource health becomes Unavailable or Degraded"

  criteria {
    category = "ResourceHealth"

    resource_health {
      current  = ["Unavailable", "Degraded", "Unknown"]
      previous = ["Available"]
      reason   = ["PlatformInitiated", "Unknown"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.hub_alerts[0].id
  }

  tags = var.common_tags
}

# ---------------------------------------------------------------------------
# Service Health — Azure platform incidents & maintenance for hub services
#
# Covers Incident, Maintenance, Informational, and ActionRequired events for
# the Azure services that power this hub. Scoped to the subscription so that
# any regional impact to the configured service_health_services is captured.
# ---------------------------------------------------------------------------
resource "azurerm_monitor_activity_log_alert" "service_health" {
  count = local.monitoring_config.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-service-health"
  resource_group_name = azurerm_resource_group.main.name
  location            = "global"
  scopes              = [data.azurerm_subscription.current.id]
  description         = "Azure service health alerts for hub-level services (incidents, maintenance, action required)"

  criteria {
    category = "ServiceHealth"

    service_health {
      locations = local.monitoring_config.service_health_locations
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.hub_alerts[0].id
  }

  tags = var.common_tags
}
