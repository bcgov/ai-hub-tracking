locals {
  app_service_plan_name = "asp-${var.app_env}-portal"
  # When app_name_override is set (tools or PR preview deployments), use it
  # directly. Otherwise fall back to the per-environment convention used by
  # the dev / test / prod App Services already in state.
  app_service_name = var.app_name_override != "" ? var.app_name_override : "app-${var.app_env}-ai-hub-portal"
}
