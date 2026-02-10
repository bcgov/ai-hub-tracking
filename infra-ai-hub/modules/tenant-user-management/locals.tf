# =============================================================================
# LOCAL VALUES
# =============================================================================
locals {
  enabled      = try(var.user_management.enabled, true)
  group_prefix = try(var.user_management.group_prefix, "ai-hub")
  mail_enabled = try(var.user_management.mail_enabled, false)

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
    admin = try(var.user_management.existing_group_ids.admin, null)
    write = try(var.user_management.existing_group_ids.write, null)
    read  = try(var.user_management.existing_group_ids.read, null)
  }

  seed_members = {
    admin = try(var.user_management.seed_members.admin, [])
    write = try(var.user_management.seed_members.write, [])
    read  = try(var.user_management.seed_members.read, [])
  }

  # Owners default to admin seed members when not explicitly set
  owner_members = length(try(var.user_management.owner_members, [])) > 0 ? var.user_management.owner_members : local.seed_members.admin

  group_definitions = {
    for role in ["admin", "write", "read"] : role => {
      name              = local.group_names[role]
      existing_group_id = local.existing_group_ids[role]
      # mail_nickname: required by Azure AD API even for security groups,
      # must be unique, max 64 chars, alphanumeric only
      mail_nickname = substr(regexreplace(lower(local.group_names[role]), "[^a-z0-9]", ""), 0, 64)
    }
  }

  groups_to_create = {
    for role, def in local.group_definitions : role => def
    if local.enabled && def.existing_group_id == null
  }

  # Merge existing group IDs (from config) with newly-created group IDs.
  # Only one source will have a value per role.
  group_object_ids = merge(
    { for role, def in local.group_definitions : role => def.existing_group_id if def.existing_group_id != null },
    { for role, group in azuread_group.tenant : role => group.id }
  )

  # Deduplicated set of all UPNs we need to look up
  all_user_upns = toset(concat(
    local.seed_members.admin,
    local.seed_members.write,
    local.seed_members.read,
    local.owner_members
  ))

  # Individual group member resources (Terraform manages add-only, not the full set)
  group_memberships = local.enabled ? {
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

  # Group owners — admin seed members are set as owners on all 3 groups
  # so tenant admins can manage membership via portal/myaccount
  group_owners = local.enabled ? {
    for item in flatten([
      for role in keys(local.group_names) : [
        for upn in local.owner_members : {
          key  = "${role}-${lower(upn)}"
          role = role
          upn  = upn
        }
      ]
    ]) : item.key => item
  } : {}
}
