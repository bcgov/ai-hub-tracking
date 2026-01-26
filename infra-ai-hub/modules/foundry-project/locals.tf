# =============================================================================
# AI Foundry Project Module - Locals
# =============================================================================

locals {
  name_prefix = var.tenant_name

  # Project principal ID for role assignments (extracted after creation)
  project_principal_id = try(azapi_resource.project.output.identity.principalId, null)
}
