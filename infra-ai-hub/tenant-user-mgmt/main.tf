# =============================================================================
# MAIN — Tenant User Management (separate state)
# =============================================================================
# This config is intentionally separate from the main infrastructure.
# It manages Entra group/user lookups and custom RBAC role assignments,
# which require Microsoft Graph User.Read.All permission.
#
# By using a separate state file, the main infrastructure apply can never
# destroy these resources when the executing identity lacks Graph permissions.
# The deploy script checks for Graph API access and only runs this config
# when the permission is available.
# =============================================================================

# ---------------------------------------------------------------------------
# Look up each tenant's resource group by naming convention.
# The main config creates RGs as "{tenant_name}-rg".
# ---------------------------------------------------------------------------
data "azurerm_resource_group" "tenant" {
  for_each = local.enabled_tenants
  name     = "${each.value.tenant_name}-rg"
}

# ---------------------------------------------------------------------------
# Tenant User Management module
# ---------------------------------------------------------------------------
module "tenant_user_management" {
  source   = "../modules/tenant-user-management"
  for_each = local.enabled_tenants

  tenant_name       = each.value.tenant_name
  display_name      = each.value.display_name
  app_env           = var.app_env
  resource_group_id = data.azurerm_resource_group.tenant[each.key].id
  user_management   = each.value.user_management
}
