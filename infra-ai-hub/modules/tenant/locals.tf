locals {
  # Generate clean name for resources (remove hyphens for storage, etc.)
  tenant_name_clean = replace(var.tenant_name, "-", "")

  # Truncate for resources with length limits
  tenant_name_short = substr(local.tenant_name_clean, 0, 10)

  # Common name prefix
  name_prefix = var.tenant_name

  # Resource group values from the always-created tenant RG
  resource_group_name = azurerm_resource_group.tenant.name
  resource_group_id   = azurerm_resource_group.tenant.id

  # Project principal ID for role assignments
  project_principal_id = try(azapi_resource.ai_foundry_project.output.identity.principalId, null)
}
