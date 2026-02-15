# Application Gateway Module
# Uses native azurerm_application_gateway for full lifecycle control
# (AVM does not expose lifecycle ignore_changes, needed for portal SSL cert uploads)

# =============================================================================
# USER-ASSIGNED MANAGED IDENTITY FOR KEY VAULT ACCESS
# Created before App Gateway so we can grant KV access and use SSL certs
# =============================================================================
resource "azurerm_user_assigned_identity" "appgw" {
  count = local.needs_identity ? 1 : 0

  name                = "${var.name}-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# =============================================================================
# KEY VAULT ACCESS FOR APP GATEWAY
# Grant App Gateway managed identity access to Key Vault for SSL certs
# Must be created BEFORE App Gateway so it can read SSL certs
# =============================================================================
resource "azurerm_role_assignment" "appgw_to_keyvault" {
  count = var.key_vault_id != null && local.needs_identity ? 1 : 0

  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.appgw[0].principal_id
}

# =============================================================================
# APPLICATION GATEWAY (native resource)
# =============================================================================
# Note: When public_ip_resource_id is provided, it is assigned to the frontend IP configuration.
# The referenced public IP must already exist (typically created by dns-zone module).
resource "azurerm_application_gateway" "this" {
  # Ensure KV access is granted before creating App Gateway with SSL certs
  depends_on = [azurerm_role_assignment.appgw_to_keyvault]

  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  zones               = var.zones
  tags                = var.tags

  # When using an external WAF policy, must set firewall_policy_id
  firewall_policy_id = var.waf_policy_id

  # --- SKU -------------------------------------------------------------------
  sku {
    name = var.sku.name
    tier = var.sku.tier
    # capacity is only set when autoscale is NOT used
    capacity = var.autoscale == null ? var.sku.capacity : null
  }

  # --- Autoscale (optional) --------------------------------------------------
  dynamic "autoscale_configuration" {
    for_each = var.autoscale != null ? [var.autoscale] : []
    content {
      min_capacity = autoscale_configuration.value.min_capacity
      max_capacity = autoscale_configuration.value.max_capacity
    }
  }

  # --- Gateway IP configuration ----------------------------------------------
  gateway_ip_configuration {
    name      = "${var.name}-gwip"
    subnet_id = var.subnet_id
  }

  # --- Frontend IP configuration (public or private) ------------------------
  frontend_ip_configuration {
    name = local.frontend_ip_config_name

    # When a public IP is provided, configure a public frontend.
    public_ip_address_id = var.public_ip_resource_id != null ? var.public_ip_resource_id : null

    # When no public IP is provided, configure a private-only frontend using the gateway subnet.
    subnet_id                     = var.public_ip_resource_id == null ? var.subnet_id : null
    private_ip_address_allocation = var.public_ip_resource_id == null ? "Dynamic" : null
  }

  # --- Frontend ports --------------------------------------------------------
  frontend_port {
    name = local.frontend_port_https_name
    port = 443
  }

  frontend_port {
    name = local.frontend_port_http_name
    port = 80
  }

  # --- Backend address pools ------------------------------------------------
  # FQDN resolves to PE IP via private DNS zone linked to the VNet
  backend_address_pool {
    name  = local.backend_pool_name
    fqdns = [var.backend_apim.fqdn]
  }

  # --- Backend HTTP settings -------------------------------------------------
  backend_http_settings {
    name                                = local.http_setting_name
    port                                = var.backend_apim.https_port
    protocol                            = "Https"
    cookie_based_affinity               = "Disabled"
    request_timeout                     = 30
    pick_host_name_from_backend_address = true
    probe_name                          = local.probe_name
  }

  # --- Health probe ----------------------------------------------------------
  probe {
    name                                      = local.probe_name
    protocol                                  = "Https"
    path                                      = var.backend_apim.probe_path
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200-399"]
    }
  }

  # --- SSL certificates (from Key Vault or portal upload) --------------------
  dynamic "ssl_certificate" {
    for_each = var.ssl_certificates
    content {
      name                = ssl_certificate.value.name
      key_vault_secret_id = lookup(ssl_certificate.value, "key_vault_secret_id", null)
      data                = lookup(ssl_certificate.value, "data", null)
      password            = lookup(ssl_certificate.value, "password", null)
    }
  }

  # --- TLS policy (required by Landing Zone policy) --------------------------
  ssl_policy {
    policy_type = local.ssl_policy.policy_type
    policy_name = local.ssl_policy.policy_name
  }

  # --- Managed identity for Key Vault access ---------------------------------
  dynamic "identity" {
    for_each = local.needs_identity ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.appgw[0].id]
    }
  }

  # --- HTTPS listener (only if SSL cert configured) --------------------------
  dynamic "http_listener" {
    for_each = local.ssl_cert_name != null ? [1] : []
    content {
      name                           = local.listener_https_name
      frontend_ip_configuration_name = local.frontend_ip_config_name
      frontend_port_name             = local.frontend_port_https_name
      protocol                       = "Https"
      host_name                      = var.frontend_hostname
      ssl_certificate_name           = local.ssl_cert_name
    }
  }

  # --- HTTP listener (always present) ----------------------------------------
  http_listener {
    name                           = local.listener_http_name
    frontend_ip_configuration_name = local.frontend_ip_config_name
    frontend_port_name             = local.frontend_port_http_name
    protocol                       = "Http"
    host_name                      = var.frontend_hostname
  }

  # --- Redirect configuration (HTTP → HTTPS, only if SSL) --------------------
  dynamic "redirect_configuration" {
    for_each = local.ssl_cert_name != null ? [1] : []
    content {
      name                 = local.redirect_config_name
      redirect_type        = "Permanent"
      target_listener_name = local.listener_https_name
      include_path         = true
      include_query_string = true
    }
  }

  # --- HTTPS routing rule (only if SSL) --------------------------------------
  dynamic "request_routing_rule" {
    for_each = local.ssl_cert_name != null ? [1] : []
    content {
      name                       = local.routing_rule_https_name
      rule_type                  = "Basic"
      http_listener_name         = local.listener_https_name
      backend_address_pool_name  = local.backend_pool_name
      backend_http_settings_name = local.http_setting_name
      priority                   = 100
      rewrite_rule_set_name      = var.rewrite_rule_set != null && length(var.rewrite_rule_set) > 0 ? values(var.rewrite_rule_set)[0].name : null
    }
  }

  # --- HTTP routing / redirect rule ------------------------------------------
  request_routing_rule {
    name               = local.routing_rule_http_name
    rule_type          = "Basic"
    http_listener_name = local.listener_http_name
    priority           = 200

    # When SSL is configured: redirect HTTP → HTTPS
    # When no SSL: route HTTP directly to backend
    redirect_configuration_name = local.ssl_cert_name != null ? local.redirect_config_name : null
    backend_address_pool_name   = local.ssl_cert_name == null ? local.backend_pool_name : null
    backend_http_settings_name  = local.ssl_cert_name == null ? local.http_setting_name : null
  }

  # --- WAF configuration (inline, when no external WAF policy) ---------------
  dynamic "waf_configuration" {
    for_each = var.waf_enabled && var.waf_policy_id == null ? [1] : []
    content {
      enabled          = true
      firewall_mode    = var.waf_mode
      rule_set_type    = "OWASP"
      rule_set_version = "3.2"
    }
  }

  # --- URL Path Maps (optional, for path-based routing) ----------------------
  dynamic "url_path_map" {
    for_each = var.url_path_map_configurations != null ? var.url_path_map_configurations : {}
    content {
      name                                = url_path_map.value.name
      default_backend_address_pool_name   = lookup(url_path_map.value, "default_backend_address_pool_name", null)
      default_backend_http_settings_name  = lookup(url_path_map.value, "default_backend_http_settings_name", null)
      default_redirect_configuration_name = lookup(url_path_map.value, "default_redirect_configuration_name", null)
      default_rewrite_rule_set_name       = lookup(url_path_map.value, "default_rewrite_rule_set_name", null)

      dynamic "path_rule" {
        for_each = url_path_map.value.path_rules
        content {
          name                        = path_rule.value.name
          paths                       = path_rule.value.paths
          backend_address_pool_name   = lookup(path_rule.value, "backend_address_pool_name", null)
          backend_http_settings_name  = lookup(path_rule.value, "backend_http_settings_name", null)
          redirect_configuration_name = lookup(path_rule.value, "redirect_configuration_name", null)
          rewrite_rule_set_name       = lookup(path_rule.value, "rewrite_rule_set_name", null)
          firewall_policy_id          = lookup(path_rule.value, "firewall_policy_id", null)
        }
      }
    }
  }

  # --- Rewrite Rule Sets (optional) ------------------------------------------
  dynamic "rewrite_rule_set" {
    for_each = var.rewrite_rule_set != null ? var.rewrite_rule_set : {}
    content {
      name = rewrite_rule_set.value.name

      dynamic "rewrite_rule" {
        for_each = lookup(rewrite_rule_set.value, "rewrite_rules", {}) != null ? rewrite_rule_set.value.rewrite_rules : {}
        content {
          name          = rewrite_rule.value.name
          rule_sequence = rewrite_rule.value.rule_sequence

          dynamic "condition" {
            for_each = lookup(rewrite_rule.value, "conditions", {}) != null ? rewrite_rule.value.conditions : {}
            content {
              variable    = condition.value.variable
              pattern     = condition.value.pattern
              ignore_case = lookup(condition.value, "ignore_case", false)
              negate      = lookup(condition.value, "negate", false)
            }
          }

          dynamic "request_header_configuration" {
            for_each = lookup(rewrite_rule.value, "request_header_configurations", {}) != null ? rewrite_rule.value.request_header_configurations : {}
            content {
              header_name  = request_header_configuration.value.header_name
              header_value = request_header_configuration.value.header_value
            }
          }

          dynamic "response_header_configuration" {
            for_each = lookup(rewrite_rule.value, "response_header_configurations", {}) != null ? rewrite_rule.value.response_header_configurations : {}
            content {
              header_name  = response_header_configuration.value.header_name
              header_value = response_header_configuration.value.header_value
            }
          }

          dynamic "url" {
            for_each = lookup(rewrite_rule.value, "url", null) != null ? [rewrite_rule.value.url] : []
            content {
              components   = lookup(url.value, "components", null)
              path         = lookup(url.value, "path", null)
              query_string = lookup(url.value, "query_string", null)
              reroute      = lookup(url.value, "reroute", null)
            }
          }
        }
      }
    }
  }

  # ===========================================================================
  # LIFECYCLE: ignore portal-managed SSL certificate changes
  # This allows SSL certs to be uploaded/rotated via Azure Portal or CLI
  # without Terraform reverting them on the next apply.
  # ===========================================================================
  lifecycle {
    ignore_changes = [
      ssl_certificate,
      tags["managed-by"],
    ]
  }
}

# =============================================================================
# DIAGNOSTIC SETTINGS (separate resource, not inline)
# NOTE: Azure does not reliably switch log routing when
#       log_analytics_destination_type is changed in-place.
#       The lifecycle block below forces recreation to guarantee
#       logs land in resource-specific tables (AGWAccessLogs, etc.).
# =============================================================================
resource "azurerm_monitor_diagnostic_setting" "appgw" {
  count = var.enable_diagnostics ? 1 : 0

  name                           = "${var.name}-diag"
  target_resource_id             = azurerm_application_gateway.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }

  lifecycle {
    replace_triggered_by = [null_resource.diag_destination_type_trigger[0]]
  }
}

# Trigger recreation of diagnostic setting when destination type changes.
# This works around an Azure API bug where in-place updates to
# log_analytics_destination_type silently fail after a few days.
resource "null_resource" "diag_destination_type_trigger" {
  count = var.enable_diagnostics ? 1 : 0

  triggers = {
    destination_type = "Dedicated"
  }
}
