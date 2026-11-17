locals {
  location_normalized = lower(replace(var.location, " ", ""))

  # Deployment name equals the model name; the account belongs to a single tenant.
  deployment_names = { for role, d in var.model_deployments : role => d.model_name }

  cognitive_deployments = {
    for role, d in var.model_deployments : role => {
      name                   = d.model_name
      version_upgrade_option = d.version_upgrade_option
      model = {
        format  = "OpenAI"
        name    = d.model_name
        version = d.model_version
      }
      scale = {
        type     = d.scale_type
        capacity = d.capacity
      }
    }
  }

  # Body for PATCH {endpoint}/contentunderstanding/defaults?api-version=2025-11-01
  # Maps both the model names and the prebuilt-analyzer aliases to this account's deployments.
  # https://learn.microsoft.com/azure/ai-services/content-understanding/concepts/models-deployments
  default_model_deployments = merge(
    { for role, d in var.model_deployments : d.model_name => d.model_name },
    {
      "prebuilt-analyzer-completion"      = local.deployment_names["completion"]
      "prebuilt-analyzer-completion-mini" = lookup(local.deployment_names, "completion_mini", local.deployment_names["completion"])
      "prebuilt-analyzer-embedding"       = local.deployment_names["embedding"]
    }
  )

  diag_log_groups        = try(var.diagnostics.log_groups, [])
  diag_log_categories    = try(var.diagnostics.log_categories, [])
  diag_metric_categories = try(var.diagnostics.metric_categories, [])
}
