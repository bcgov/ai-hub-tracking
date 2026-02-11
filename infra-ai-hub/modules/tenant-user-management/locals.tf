# =============================================================================
# LOCAL VALUES
# =============================================================================
locals {
  enabled       = var.user_management.enabled && var.has_graph_permissions
  create_groups = var.user_management.create_groups
  group_prefix  = var.user_management.group_prefix
  mail_enabled  = var.user_management.mail_enabled

  # IMPORTANT: Include app_env in names to avoid cross-environment conflicts.
  # Entra groups are tenant-wide (not per-subscription), and custom role
  # definitions are subscription-scoped. Without the env suffix, deploying
  # the same tenant to dev/test/prod would collide.
  group_names = {
    admin = "${local.group_prefix}-${var.app_env}-${var.tenant_name}-admin"
    write = "${local.group_prefix}-${var.app_env}-${var.tenant_name}-write"
    read  = "${local.group_prefix}-${var.app_env}-${var.tenant_name}-read"
  }

  existing_group_ids = {
    admin = var.user_management.existing_group_ids.admin
    write = var.user_management.existing_group_ids.write
    read  = var.user_management.existing_group_ids.read
  }

  seed_members = {
    admin = var.user_management.seed_members.admin
    write = var.user_management.seed_members.write
    read  = var.user_management.seed_members.read
  }

  # Owners default to admin seed members when not explicitly set.
  # owner_members is optional(list(string)) with no default, so it can be null.
  # coalesce() safely handles null by falling back to an empty list.
  owner_members = length(coalesce(var.user_management.owner_members, [])) > 0 ? var.user_management.owner_members : local.seed_members.admin

  # =========================================================================
  # Group-mode locals (only used when create_groups = true)
  # =========================================================================
  group_definitions = {
    for role in ["admin", "write", "read"] : role => {
      name              = local.group_names[role]
      existing_group_id = local.existing_group_ids[role]
      # mail_nickname: required by Azure AD API even for security groups,
      # must be unique, max 64 chars, alphanumeric only
      mail_nickname = substr(replace(lower(local.group_names[role]), "/[^a-z0-9]/", ""), 0, 64)
    }
  }

  groups_to_create = {
    for role, def in local.group_definitions : role => def
    if local.enabled && local.create_groups && def.existing_group_id == null
  }

  # Merge existing group IDs (from config) with newly-created group IDs.
  # Only one source will have a value per role.
  group_object_ids = local.create_groups ? merge(
    { for role, def in local.group_definitions : role => def.existing_group_id if def.existing_group_id != null },
    { for role, group in azuread_group.tenant : role => group.id }
  ) : {}

  # Deduplicated set of all UPNs we need to look up
  all_user_upns = toset(concat(
    local.seed_members.admin,
    local.seed_members.write,
    local.seed_members.read,
    local.create_groups ? local.owner_members : []
  ))

  # Group member resources (only when create_groups = true)
  group_memberships = local.enabled && local.create_groups ? {
    for item in flatten([
      for role, upns in local.seed_members : [
        for upn in upns : {
          key  = "${role}-${lower(upn)}"
          role = role
          upn  = upn
        }
      ]
    ]) : item.key => item
  } : {}

  # =========================================================================
  # Direct-user-mode locals (only used when create_groups = false)
  # Each seed member gets the custom RBAC role assigned directly.
  # =========================================================================
  direct_user_assignments = local.enabled && !local.create_groups ? {
    for item in flatten([
      for role, upns in local.seed_members : [
        for upn in upns : {
          key  = "${role}-${lower(upn)}"
          role = role
          upn  = upn
        }
      ]
    ]) : item.key => item
  } : {}

  # Map of role -> role definition resource ID for role assignments.
  role_definition_map = local.enabled ? {
    admin = azurerm_role_definition.tenant_admin[0].role_definition_resource_id
    write = azurerm_role_definition.tenant_write[0].role_definition_resource_id
    read  = azurerm_role_definition.tenant_read[0].role_definition_resource_id
  } : {}
}
