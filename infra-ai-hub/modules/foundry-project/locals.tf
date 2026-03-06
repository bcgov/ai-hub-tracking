# =============================================================================
# AI Foundry Project Module - Locals
# =============================================================================

locals {
  name_prefix = var.tenant_name

  # Canonical ordering to match Azure RAI API normalization and avoid perpetual
  # in-place drift when contentFilters are semantically identical.
  rai_filter_name_order = {
    hate     = 1
    violence = 2
    sexual   = 3
    selfharm = 4
  }

  rai_filter_source_order = {
    prompt     = 1
    completion = 2
  }

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

  # Normalize and sort RAI content filters per deployment:
  # - name: lower-case (hate|violence|sexual|selfharm)
  # - source: title-case (Prompt|Completion)
  # - deterministic order: name rank, then source rank
  canonical_rai_content_filters = {
    for deployment_key, deployment in var.ai_model_deployments :
    deployment_key => [
      for decoded in [
        for encoded in sort([
          for f in deployment.content_filter.filters : jsonencode({
            order_name        = lookup(local.rai_filter_name_order, lower(f.name), 99)
            order_source      = lookup(local.rai_filter_source_order, lower(f.source), 99)
            name              = lower(f.name)
            blocking          = try(f.blocking, true)
            enabled           = try(f.enabled, true)
            severityThreshold = f.severity_threshold
            source            = title(lower(f.source))
          })
        ]) : jsondecode(encoded)
        ] : {
        name              = decoded.name
        blocking          = decoded.blocking
        enabled           = decoded.enabled
        severityThreshold = decoded.severityThreshold
        source            = decoded.source
      }
    ]
  }
}
