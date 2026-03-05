# =============================================================================
# AI Foundry Project Module - Locals
# =============================================================================

locals {
  name_prefix = var.tenant_name

  # Project principal ID for role assignments (extracted after creation)
  project_principal_id = try(azapi_resource.project.output.identity.principalId, null)

  # Resolve effective RAI policy name per deployment.
  # Priority: explicit rai_policy_name > custom content_filter (filters non-empty) > Microsoft.DefaultV2
  effective_rai_policy_name = {
    for k, v in var.ai_model_deployments :
    k => coalesce(
      v.rai_policy_name,
      length(v.content_filter.filters) > 0 ? replace("${var.tenant_name}-${v.name}-filter", ".", "-") : null,
      "Microsoft.DefaultV2"
    )
  }
}
