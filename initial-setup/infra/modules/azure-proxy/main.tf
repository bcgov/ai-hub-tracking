resource "azurerm_service_plan" "azure_proxy_asp" {
  name                = "${var.app_name}-azure-proxy-asp"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku_name_azure_proxy
  tags                = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}
resource "random_password" "proxy_chisel_password" {
  length  = 32
  special = false
}

resource "azurerm_linux_web_app" "azure_proxy" {
  name                      = "${var.repo_name}-${var.app_env}-azure-proxy"
  resource_group_name       = var.resource_group_name
  location                  = var.location
  service_plan_id           = azurerm_service_plan.azure_proxy_asp.id
  virtual_network_subnet_id = var.app_service_subnet_id
  https_only                = true
  identity {
    type = "SystemAssigned"
  }
  site_config {
    always_on                               = true
    container_registry_use_managed_identity = true
    minimum_tls_version                     = "1.3"
    health_check_path                       = "/healthz"
    health_check_eviction_time_in_min       = 2
    application_stack {
      docker_image_name   = var.azure_proxy_image
      docker_registry_url = var.container_registry_url
    }
    ftps_state         = "Disabled"
    websockets_enabled = true
    cors {
      allowed_origins     = ["*"]
      support_credentials = false
    }
    ip_restriction_default_action = "Allow"
  }
  app_settings = {
    PORT                                  = "80"
    WEBSITES_PORT                         = "80"
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    DOCKER_ENABLE_CI                      = "true"
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.appinsights_connection_string
    APPINSIGHTS_INSTRUMENTATIONKEY        = var.appinsights_instrumentation_key
    CHISEL_AUTH                           = "tunnel:${random_password.proxy_chisel_password.result}"
  }
  logs {
    detailed_error_messages = true
    failed_request_tracing  = true
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }
  tags = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }

}
resource "azurerm_monitor_diagnostic_setting" "azure_proxy_diagnostics" {
  name                       = "${var.app_name}-azure-proxy-diagnostics"
  target_resource_id         = azurerm_linux_web_app.azure_proxy.id
  log_analytics_workspace_id = var.log_analytics_workspace_id
  enabled_log {
    category = "AppServiceHTTPLogs"
  }
  enabled_log {
    category = "AppServiceConsoleLogs"
  }
  enabled_log {
    category = "AppServiceAppLogs"
  }
  enabled_log {
    category = "AppServicePlatformLogs"
  }
}
