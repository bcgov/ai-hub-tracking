# Application Gateway Module
# Uses Azure Verified Module for App Gateway with WAF and KV SSL certs



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
# APPLICATION GATEWAY (using AVM)
# =============================================================================
module "app_gateway" {
  source  = "Azure/avm-res-network-applicationgateway/azurerm"
  version = "0.4.3"

  # Ensure KV access is granted before creating App Gateway with SSL certs
  depends_on = [azurerm_role_assignment.appgw_to_keyvault]

  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  # Gateway IP configuration
  gateway_ip_configuration = {
    name      = "${var.name}-gwip"
    subnet_id = var.subnet_id
  }

  # SKU
  sku = var.autoscale != null ? {
    name = var.sku.name
    tier = var.sku.tier
  } : var.sku

  # Autoscale (optional)
  autoscale_configuration = var.autoscale

  # Zones
  zones = var.zones

  # Managed identity for Key Vault access (user-assigned)
  managed_identities = local.needs_identity ? {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.appgw[0].id]
  } : {}

  # Frontend ports
  frontend_ports = {
    https = {
      name = local.frontend_port_https_name
      port = 443
    }
    http = {
      name = local.frontend_port_http_name
      port = 80
    }
  }

  # Backend address pools (APIM)
  backend_address_pools = {
    apim = {
      name  = local.backend_pool_name
      fqdns = [var.backend_apim.fqdn]
    }
  }

  # Backend HTTP settings
  backend_http_settings = {
    apim = {
      name                                = local.http_setting_name
      port                                = var.backend_apim.https_port
      protocol                            = "Https"
      cookie_based_affinity               = "Disabled"
      request_timeout                     = 30
      pick_host_name_from_backend_address = true
      probe_name                          = local.probe_name
    }
  }

  # Health probes
  probe_configurations = {
    apim = {
      name                                      = local.probe_name
      protocol                                  = "Https"
      path                                      = var.backend_apim.probe_path
      interval                                  = 30
      timeout                                   = 30
      unhealthy_threshold                       = 3
      pick_host_name_from_backend_http_settings = true
      match = {
        status_code = ["200-399"]
      }
    }
  }

  # SSL certificates from Key Vault
  ssl_certificates = {
    for k, v in var.ssl_certificates : k => {
      name                = v.name
      key_vault_secret_id = v.key_vault_secret_id
    }
  }

  # TLS policy (required by policy)
  ssl_policy = local.ssl_policy

  # HTTP listeners
  http_listeners = merge(
    # HTTPS listener (only if we have SSL certs)
    local.ssl_cert_name != null ? {
      https = {
        name                           = local.listener_https_name
        frontend_ip_configuration_name = local.frontend_ip_config_name
        frontend_port_name             = local.frontend_port_https_name
        protocol                       = "Https"
        host_name                      = var.frontend_hostname
        ssl_certificate_name           = local.ssl_cert_name
      }
    } : {},
    # HTTP listener (for redirect to HTTPS)
    {
      http = {
        name                           = local.listener_http_name
        frontend_ip_configuration_name = local.frontend_ip_config_name
        frontend_port_name             = local.frontend_port_http_name
        protocol                       = "Http"
        host_name                      = var.frontend_hostname
      }
    }
  )

  # Redirect configuration (HTTP to HTTPS)
  redirect_configuration = local.ssl_cert_name != null ? {
    http_to_https = {
      name                 = local.redirect_config_name
      redirect_type        = "Permanent"
      target_listener_name = local.listener_https_name
      include_path         = true
      include_query_string = true
    }
  } : null

  # Request routing rules
  request_routing_rules = merge(
    # HTTPS routing rule (only if we have SSL certs)
    local.ssl_cert_name != null ? {
      https = {
        name                       = local.routing_rule_https_name
        rule_type                  = "Basic"
        http_listener_name         = local.listener_https_name
        backend_address_pool_name  = local.backend_pool_name
        backend_http_settings_name = local.http_setting_name
        priority                   = 100
      }
    } : {},
    # HTTP redirect rule (only if we have SSL certs)
    local.ssl_cert_name != null ? {
      http_redirect = {
        name                        = local.routing_rule_http_name
        rule_type                   = "Basic"
        http_listener_name          = local.listener_http_name
        redirect_configuration_name = local.redirect_config_name
        priority                    = 200
        # These are required but not used for redirect
        backend_address_pool_name  = local.backend_pool_name
        backend_http_settings_name = local.http_setting_name
      }
      } : {
      # Direct HTTP routing if no SSL
      http = {
        name                       = local.routing_rule_http_name
        rule_type                  = "Basic"
        http_listener_name         = local.listener_http_name
        backend_address_pool_name  = local.backend_pool_name
        backend_http_settings_name = local.http_setting_name
        priority                   = 100
      }
    }
  )

  # WAF configuration (inline) or WAF Policy reference
  waf_configuration = var.waf_enabled && var.waf_policy_id == null ? {
    enabled          = true
    firewall_mode    = var.waf_mode
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
  } : null

  # WAF Policy (separate resource, preferred over inline waf_configuration)
  app_gateway_waf_policy_resource_id = var.waf_policy_id

  # URL Path Maps (for path-based routing)
  url_path_map_configurations = var.url_path_map_configurations

  # Rewrite Rule Sets
  rewrite_rule_set = var.rewrite_rule_set

  # Diagnostic settings
  diagnostic_settings = var.log_analytics_workspace_id != null ? {
    to_law = {
      name                  = "${var.name}-diag"
      workspace_resource_id = var.log_analytics_workspace_id
      log_groups            = ["allLogs"]
      metric_categories     = ["AllMetrics"]
    }
  } : {}

  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}
