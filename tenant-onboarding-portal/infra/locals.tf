locals {
  app_service_plan_name     = "asp-${var.app_env}-portal"
  portal_node_major_version = trimspace(file("${path.module}/../.node-version"))
  portal_node_version       = var.node_version != "" ? var.node_version : "${local.portal_node_major_version}-lts"
  # When app_name_override is set (tools or PR preview deployments), use it
  # directly. Otherwise fall back to the per-environment convention used by
  # the dev / test / prod App Services already in state.
  app_service_name          = var.app_name_override != "" ? var.app_name_override : "app-${var.app_env}-ai-hub-portal"
  storage_account_name      = var.storage_account_name_override != "" ? var.storage_account_name_override : "st${var.app_env}portal${random_string.storage_suffix.result}"
  table_storage_account_url = format("https://%s.table.core.windows.net", module.portal_storage.name)
}
