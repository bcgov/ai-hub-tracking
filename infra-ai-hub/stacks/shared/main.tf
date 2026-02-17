data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

module "network" {
  source = "../../modules/network"

  name_prefix = var.resource_group_name
  location    = var.location
  common_tags = var.common_tags

  vnet_name                = var.vnet_name
  vnet_resource_group_name = var.vnet_resource_group_name

  target_vnet_address_spaces   = var.target_vnet_address_spaces
  source_vnet_address_space    = var.source_vnet_address_space
  private_endpoint_subnet_name = var.private_endpoint_subnet_name

  apim_subnet = {
    enabled       = lookup(var.shared_config.apim, "vnet_injection_enabled", false)
    name          = lookup(var.shared_config.apim, "subnet_name", "apim-subnet")
    prefix_length = lookup(var.shared_config.apim, "subnet_prefix_length", 27)
  }

  appgw_subnet = {
    enabled       = lookup(var.shared_config.app_gateway, "enabled", false)
    name          = lookup(var.shared_config.app_gateway, "subnet_name", "appgw-subnet")
    prefix_length = lookup(var.shared_config.app_gateway, "subnet_prefix_length", 27)
  }

  depends_on = [azurerm_resource_group.main]
}

module "ai_foundry_hub" {
  source = "../../modules/ai-foundry-hub"

  name                = "${var.app_name}-${var.app_env}-${var.shared_config.ai_foundry.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  resource_group_id   = azurerm_resource_group.main.id
  location            = var.location

  sku                           = var.shared_config.ai_foundry.sku
  public_network_access_enabled = var.shared_config.ai_foundry.public_network_access_enabled
  local_auth_enabled            = var.shared_config.ai_foundry.local_auth_enabled
  ai_location                   = var.shared_config.ai_foundry.ai_location

  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id

  log_analytics = {
    enabled        = var.shared_config.log_analytics.enabled
    retention_days = var.shared_config.log_analytics.retention_days
    sku            = var.shared_config.log_analytics.sku
  }

  application_insights = {
    enabled = var.shared_config.log_analytics.enabled
  }

  private_endpoint_dns_wait = {
    timeout       = var.shared_config.private_endpoint_dns_wait.timeout
    poll_interval = var.shared_config.private_endpoint_dns_wait.poll_interval
  }

  scripts_dir      = "../../scripts"
  purge_on_destroy = var.shared_config.ai_foundry.purge_on_destroy
  tags             = var.common_tags

  depends_on = [module.network]
}

resource "azurerm_cognitive_account" "language_service" {
  count = var.shared_config.language_service.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-language"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "TextAnalytics"
  sku_name            = var.shared_config.language_service.sku

  public_network_access_enabled = var.shared_config.language_service.public_network_access_enabled
  local_auth_enabled            = false
  custom_subdomain_name         = "${var.app_name}-${var.app_env}-language"

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Deny"
  }

  tags = var.common_tags

  depends_on = [azurerm_resource_group.main]
}

resource "azurerm_private_endpoint" "language_service" {
  count = var.shared_config.language_service.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-language-pe"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.network.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.app_name}-${var.app_env}-language-psc"
    private_connection_resource_id = azurerm_cognitive_account.language_service[0].id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  lifecycle {
    ignore_changes = [tags, private_dns_zone_group]
  }

  tags = var.common_tags

  depends_on = [azurerm_cognitive_account.language_service, module.network]
}

resource "terraform_data" "language_service_dns_wait" {
  count = var.shared_config.language_service.enabled ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${path.root}/../../scripts/wait-for-dns-zone.sh --resource-group ${azurerm_resource_group.main.name} --private-endpoint-name ${azurerm_private_endpoint.language_service[0].name} --timeout ${var.shared_config.private_endpoint_dns_wait.timeout} --interval ${var.shared_config.private_endpoint_dns_wait.poll_interval}"
  }

  depends_on = [azurerm_private_endpoint.language_service]
}

module "hub_key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.2"

  name                = "${var.app_name}-${var.app_env}-hkv"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                       = "standard"
  purge_protection_enabled       = true
  soft_delete_retention_days     = 90
  public_network_access_enabled  = false
  legacy_access_policies_enabled = false

  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  private_endpoints_manage_dns_zone_group = false

  private_endpoints = {
    primary = {
      subnet_resource_id = module.network.private_endpoint_subnet_id
      tags               = var.common_tags
    }
  }

  role_assignments = {
    deployer_secrets_officer = {
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = data.azurerm_client_config.current.object_id
    }
  }

  diagnostic_settings = {}
  tags                = var.common_tags
  enable_telemetry    = false
}

resource "terraform_data" "hub_kv_dns_wait" {
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${path.root}/../../scripts/wait-for-dns-zone.sh --resource-group ${azurerm_resource_group.main.name} --private-endpoint-name ${module.hub_key_vault.private_endpoints["primary"].name} --timeout ${var.shared_config.private_endpoint_dns_wait.timeout} --interval ${var.shared_config.private_endpoint_dns_wait.poll_interval}"
  }

  depends_on = [module.hub_key_vault]
}

module "dns_zone" {
  source = "../../modules/dns-zone"
  count  = local.dns_zone_config.enabled ? 1 : 0

  name_prefix         = "${var.app_name}-${var.app_env}"
  location            = var.location
  dns_zone_name       = local.dns_zone_config.zone_name
  resource_group_name = local.dns_zone_config.resource_group_name
  a_record_ttl        = lookup(local.dns_zone_config, "a_record_ttl", 3600)

  # DDoS IP Protection: per-IP adaptive L3/L4 DDoS mitigation (~$199/mo per IP)
  # Enable per environment when needed (recommended for prod)
  ddos_protection_enabled = lookup(local.dns_zone_config, "ddos_protection_enabled", false)

  # Diagnostics: always-on for PIP (DDoS telemetry) and DNS zone (query logs)
  log_analytics_workspace_id = module.ai_foundry_hub.log_analytics_workspace_id

  tags = var.common_tags
}

module "waf_policy" {
  source = "../../modules/waf-policy"
  count  = local.appgw_config.enabled && lookup(local.appgw_config, "waf_policy_enabled", true) ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-waf-policy"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  enabled                          = lookup(local.appgw_config, "waf_enabled", true)
  mode                             = lookup(local.appgw_config, "waf_mode", "Prevention")
  request_body_check               = lookup(local.appgw_config, "request_body_check", true)
  request_body_enforcement         = lookup(local.appgw_config, "request_body_enforcement", true)
  request_body_inspect_limit_in_kb = lookup(local.appgw_config, "request_body_inspect_limit_in_kb", 128)
  max_request_body_size_kb         = lookup(local.appgw_config, "max_request_body_size_kb", 128)
  file_upload_limit_mb             = lookup(local.appgw_config, "file_upload_limit_mb", 100)

  # Managed rule sets: configurable per-env, defaults in locals.tf
  managed_rule_sets = lookup(local.appgw_config, "managed_rule_sets", local.default_waf_managed_rule_sets)

  exclusions = lookup(local.appgw_config, "waf_exclusions", [])

  # Custom rules (Allow + Rate-Limit): configurable per-env, defaults in locals.tf
  custom_rules = lookup(local.appgw_config, "custom_rules", local.default_waf_custom_rules)

  tags = var.common_tags
}

module "app_gateway" {
  source = "../../modules/app-gateway"
  count  = local.appgw_config.enabled && local.apim_config.enabled ? 1 : 0

  name                = "${var.app_name}-${var.app_env}-appgw"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  subnet_id = module.network.appgw_subnet_id

  sku = {
    name     = lookup(local.appgw_config, "sku_name", "WAF_v2")
    tier     = lookup(local.appgw_config, "sku_tier", "WAF_v2")
    capacity = lookup(local.appgw_config, "capacity", 2)
  }

  autoscale = lookup(local.appgw_config, "autoscale", null) != null ? {
    min_capacity = local.appgw_config.autoscale.min_capacity
    max_capacity = local.appgw_config.autoscale.max_capacity
  } : null

  waf_enabled          = lookup(local.appgw_config, "waf_policy_enabled", true) ? false : lookup(local.appgw_config, "waf_enabled", true)
  waf_mode             = lookup(local.appgw_config, "waf_mode", "Prevention")
  waf_policy_id        = lookup(local.appgw_config, "waf_policy_enabled", true) && length(module.waf_policy) > 0 ? module.waf_policy[0].resource_id : null
  ssl_certificate_name = lookup(local.appgw_config, "ssl_certificate_name", null)
  ssl_certificates = {
    for k, v in lookup(local.appgw_config, "ssl_certificates", {}) : k => {
      name                = v.name
      key_vault_secret_id = v.key_vault_secret_id
    }
  }

  backend_apim = {
    fqdn       = local.apim_gateway_fqdn
    https_port = 443
    probe_path = "/status-0123456789abcdef"
  }

  frontend_hostname = lookup(local.appgw_config, "frontend_hostname", "api.example.com")
  key_vault_id      = lookup(local.appgw_config, "key_vault_id", null)

  # Rewrite rule set to forward original host header to APIM
  # Critical for APIM to rewrite Operation-Location headers correctly for Document Intelligence
  rewrite_rule_set = {
    forward_original_host = {
      name = "forward-original-host"
      rewrite_rules = {
        map_ocp_apim_key_to_api_key = {
          name          = "map-ocp-apim-key-to-api-key"
          rule_sequence = 90
          conditions = {
            ocp_apim_subscription_key_present = {
              variable    = "http_req_Ocp-Apim-Subscription-Key"
              pattern     = ".+"
              ignore_case = false
              negate      = false
            }
          }
          request_header_configurations = {
            api_key = {
              header_name  = "api-key"
              header_value = "{http_req_Ocp-Apim-Subscription-Key}"
            }
          }
        }
        add_x_forwarded_host = {
          name          = "add-x-forwarded-host"
          rule_sequence = 100
          request_header_configurations = {
            x_forwarded_host = {
              header_name  = "X-Forwarded-Host"
              header_value = "{var_host}"
            }
          }
        }
      }
    }
  }
  public_ip_resource_id = local.dns_zone_config.enabled ? module.dns_zone[0].public_ip_id : null

  enable_diagnostics         = var.shared_config.log_analytics.enabled
  log_analytics_workspace_id = module.ai_foundry_hub.log_analytics_workspace_id
  tags                       = var.common_tags
}

module "defender" {
  source = "../../modules/defender"
  count  = var.defender_enabled ? 1 : 0

  resource_types = var.defender_resource_types
}
