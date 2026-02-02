output "grafana_id" {
  description = "Resource ID of the Grafana instance"
  value       = azurerm_dashboard_grafana.this.id
}

output "grafana_name" {
  description = "Name of the Grafana instance"
  value       = azurerm_dashboard_grafana.this.name
}

output "grafana_endpoint" {
  description = "Grafana endpoint URL"
  value       = azurerm_dashboard_grafana.this.endpoint
}

output "dashboards_resource_group" {
  description = "Resource group for dashboards"
  value       = azurerm_resource_group.dashboards.name
}

output "dashboard_storage_account_name" {
  description = "Storage account name for dashboard JSON"
  value       = try(azurerm_storage_account.dashboards[0].name, null)
}

output "dashboard_container_name" {
  description = "Storage container name for dashboard JSON"
  value       = try(azurerm_storage_container.dashboards[0].name, null)
}

output "dashboard_blob_urls" {
  description = "Dashboard JSON blob URLs"
  value = try({
    apim_gateway = var.enable_log_analytics_dashboard ? "https://${azurerm_storage_account.dashboards[0].name}.blob.core.windows.net/${azurerm_storage_container.dashboards[0].name}/apim-gateway.json" : null
    ai_usage     = var.enable_app_insights_dashboard ? "https://${azurerm_storage_account.dashboards[0].name}.blob.core.windows.net/${azurerm_storage_container.dashboards[0].name}/ai-usage.json" : null
  }, null)
}
