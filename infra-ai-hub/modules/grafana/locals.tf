locals {
  storage_account_name = coalesce(
    var.storage_account_name,
    substr(lower(replace("${var.name}dash${try(random_string.storage_suffix[0].result, "")}", "-", "")), 0, 24)
  )

  apim_gateway_dashboard = var.dashboards_enabled && var.enable_log_analytics_dashboard ? templatefile(
    "${var.dashboards_path}/apim-gateway.json.tftpl",
    {
      log_analytics_workspace_id = var.log_analytics_workspace_id
      environment                = var.environment
    }
  ) : null

  ai_usage_dashboard = var.dashboards_enabled && var.enable_app_insights_dashboard ? templatefile(
    "${var.dashboards_path}/ai-usage.json.tftpl",
    {
      log_analytics_workspace_id = var.log_analytics_workspace_id
      environment                = var.environment
    }
  ) : null
}
