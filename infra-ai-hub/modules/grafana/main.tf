resource "azurerm_resource_group" "dashboards" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "random_string" "storage_suffix" {
  count   = var.dashboards_enabled && var.storage_account_name == null ? 1 : 0
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "azurerm_storage_account" "dashboards" {
  count = var.dashboards_enabled ? 1 : 0

  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.dashboards.name
  location                 = azurerm_resource_group.dashboards.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_storage_container" "dashboards" {
  count = var.dashboards_enabled ? 1 : 0

  name                  = var.dashboard_container_name
  container_access_type = "private"
  storage_account_id    = azurerm_storage_account.dashboards[0].id
}

resource "azurerm_storage_blob" "apim_gateway" {
  count = var.dashboards_enabled && var.enable_log_analytics_dashboard ? 1 : 0

  name                   = "apim-gateway.json"
  storage_account_name   = azurerm_storage_account.dashboards[0].name
  storage_container_name = azurerm_storage_container.dashboards[0].name
  type                   = "Block"
  source_content         = local.apim_gateway_dashboard
  content_type           = "application/json"
  content_md5            = md5(local.apim_gateway_dashboard)
}

resource "azurerm_storage_blob" "ai_usage" {
  count = var.dashboards_enabled && var.enable_app_insights_dashboard ? 1 : 0

  name                   = "ai-usage.json"
  storage_account_name   = azurerm_storage_account.dashboards[0].name
  storage_container_name = azurerm_storage_container.dashboards[0].name
  type                   = "Block"
  source_content         = local.ai_usage_dashboard
  content_type           = "application/json"
  content_md5            = md5(local.ai_usage_dashboard)
}

data "azurerm_client_config" "current" {}

resource "azurerm_dashboard_grafana" "this" {
  name                          = var.name
  resource_group_name           = azurerm_resource_group.dashboards.name
  location                      = azurerm_resource_group.dashboards.location
  grafana_major_version         = var.grafana_major_version
  sku                           = var.sku
  public_network_access_enabled = var.public_network_access_enabled
  api_key_enabled               = var.api_key_enabled

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "grafana" {
  count = !var.public_network_access_enabled && var.private_endpoint_subnet_id != null ? 1 : 0

  name                = "${var.name}-pe"
  location            = var.location
  resource_group_name = azurerm_resource_group.dashboards.name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.name}-psc"
    private_connection_resource_id = azurerm_dashboard_grafana.this.id
    is_manual_connection           = false
    subresource_names              = ["grafana"]
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags, private_dns_zone_group]
  }
}

resource "azurerm_role_assignment" "grafana_log_analytics_reader" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  scope                = var.log_analytics_workspace_id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "grafana_app_insights_reader" {
  count = var.application_insights_id != null ? 1 : 0

  scope                = var.application_insights_id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "grafana_admin" {
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "null_resource" "wait_for_dns_grafana" {
  count = var.scripts_dir != "" && !var.public_network_access_enabled && var.private_endpoint_subnet_id != null ? 1 : 0

  triggers = {
    private_endpoint_id   = azurerm_private_endpoint.grafana[0].id
    resource_group_name   = azurerm_resource_group.dashboards.name
    private_endpoint_name = azurerm_private_endpoint.grafana[0].name
    timeout               = var.private_endpoint_dns_wait.timeout
    interval              = var.private_endpoint_dns_wait.poll_interval
    scripts_dir           = var.scripts_dir
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      ${self.triggers.scripts_dir}/wait-for-dns-zone.sh \
        --resource-group ${self.triggers.resource_group_name} \
        --private-endpoint-name ${self.triggers.private_endpoint_name} \
        --timeout ${self.triggers.timeout} \
        --interval ${self.triggers.interval}
    EOT
  }

  depends_on = [azurerm_private_endpoint.grafana]
}

resource "null_resource" "import_grafana_dashboards" {
  count = var.scripts_dir != "" && var.dashboards_enabled ? 1 : 0

  triggers = {
    grafana_id          = azurerm_dashboard_grafana.this.id
    apim_dashboard_hash = var.enable_log_analytics_dashboard ? sha256(local.apim_gateway_dashboard) : "disabled"
    ai_dashboard_hash   = var.enable_app_insights_dashboard ? sha256(local.ai_usage_dashboard) : "disabled"
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "${var.scripts_dir}/import-grafana-dashboards.sh --resource-group ${azurerm_resource_group.dashboards.name} --grafana-name ${var.name} --storage-account ${azurerm_storage_account.dashboards[0].name} --container ${azurerm_storage_container.dashboards[0].name} --apim-dashboard-enabled ${var.enable_log_analytics_dashboard} --ai-dashboard-enabled ${var.enable_app_insights_dashboard} --apim-dashboard-blob apim-gateway.json --ai-dashboard-blob ai-usage.json"
  }

  depends_on = [
    azurerm_dashboard_grafana.this,
    azurerm_storage_blob.apim_gateway,
    azurerm_storage_blob.ai_usage,
    azurerm_role_assignment.grafana_log_analytics_reader,
    azurerm_role_assignment.grafana_app_insights_reader,
    azurerm_role_assignment.grafana_admin,
    null_resource.wait_for_dns_grafana
  ]
}
