# =============================================================================
# ENTRA GROUPS (only when create_groups = true)
# =============================================================================
# NOTE: Membership is managed via individual azuread_group_member resources
# (add-only). The azuread_group resource does NOT set 'members' or 'owners'
# attributes, so users added in the Azure portal are never removed by Terraform.
#
# When create_groups = false, groups are skipped entirely and custom RBAC roles
# are assigned directly to individual users (see bottom of file).
# =============================================================================
resource "azuread_group" "tenant" {
  for_each = local.groups_to_create

  display_name            = each.value.name
  security_enabled        = true
  mail_enabled            = local.mail_enabled
  mail_nickname           = each.value.mail_nickname
  prevent_duplicate_names = true

  # Set admin seed members as group owners so tenant admins can manage
  # membership via the Azure portal / myaccount without platform team.
  owners = [
    for upn in local.owner_members :
    data.azuread_user.members[lower(upn)].object_id
  ]
}

resource "azuread_group_member" "seed_members" {
  for_each = local.group_memberships

  group_object_id  = local.group_object_ids[each.value.role]
  member_object_id = data.azuread_user.members[lower(each.value.upn)].object_id
}

# =============================================================================
# CUSTOM RBAC ROLES (RESOURCE GROUP SCOPE)
# =============================================================================
resource "azurerm_role_definition" "tenant_admin" {
  count = local.enabled ? 1 : 0

  name        = "${local.group_prefix}-${var.app_env}-${var.tenant_name}-admin"
  scope       = var.resource_group_id
  description = "Full access to all resources in ${var.display_name} (${var.app_env}) tenant resource group"

  permissions {
    actions = [
      "*"
    ]
    # Prevent tenant admins from escalating beyond their RG scope
    not_actions = [
      "Microsoft.Authorization/elevateAccess/Action",
      "Microsoft.Authorization/roleDefinitions/write",
      "Microsoft.Authorization/roleDefinitions/delete"
    ]
    data_actions = [
      "Microsoft.CognitiveServices/*",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/*",
      "Microsoft.Storage/storageAccounts/fileServices/fileshares/files/*",
      "Microsoft.Storage/storageAccounts/queueServices/queues/messages/*",
      "Microsoft.Storage/storageAccounts/tableServices/tables/entities/*",
      "Microsoft.KeyVault/vaults/secrets/*",
      "Microsoft.KeyVault/vaults/keys/*",
      "Microsoft.KeyVault/vaults/certificates/*"
    ]
    not_data_actions = []
  }

  assignable_scopes = [
    var.resource_group_id
  ]
}

resource "azurerm_role_definition" "tenant_write" {
  count = local.enabled ? 1 : 0

  name        = "${local.group_prefix}-${var.app_env}-${var.tenant_name}-write"
  scope       = var.resource_group_id
  description = "Write access to all resources in ${var.display_name} (${var.app_env}) tenant resource group"

  permissions {
    actions = [
      "*"
    ]
    not_actions = [
      "Microsoft.Authorization/*"
    ]
    data_actions = [
      "Microsoft.CognitiveServices/*",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/*",
      "Microsoft.Storage/storageAccounts/fileServices/fileshares/files/*",
      "Microsoft.Storage/storageAccounts/queueServices/queues/messages/*",
      "Microsoft.Storage/storageAccounts/tableServices/tables/entities/*",
      "Microsoft.KeyVault/vaults/secrets/*",
      "Microsoft.KeyVault/vaults/keys/*",
      "Microsoft.KeyVault/vaults/certificates/*"
    ]
    not_data_actions = []
  }

  assignable_scopes = [
    var.resource_group_id
  ]
}

resource "azurerm_role_definition" "tenant_read" {
  count = local.enabled ? 1 : 0

  name        = "${local.group_prefix}-${var.app_env}-${var.tenant_name}-read"
  scope       = var.resource_group_id
  description = "Read-only access to all resources in ${var.display_name} (${var.app_env}) tenant resource group"

  permissions {
    actions = [
      "*/read"
    ]
    not_actions = []
    data_actions = [
      "Microsoft.CognitiveServices/*/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
      "Microsoft.Storage/storageAccounts/fileServices/fileshares/files/read",
      "Microsoft.Storage/storageAccounts/queueServices/queues/messages/read",
      "Microsoft.Storage/storageAccounts/tableServices/tables/entities/read",
      "Microsoft.KeyVault/vaults/secrets/readMetadata/action",
      "Microsoft.KeyVault/vaults/keys/read",
      "Microsoft.KeyVault/vaults/certificates/read"
    ]
    not_data_actions = []
  }

  assignable_scopes = [
    var.resource_group_id
  ]
}

# =============================================================================
# ROLE ASSIGNMENTS — GROUP MODE (create_groups = true)
# =============================================================================
# Use static keys (toset) to avoid for_each unknown-value errors when groups
# are being created in the same apply.
# =============================================================================
resource "azurerm_role_assignment" "tenant_groups" {
  for_each = local.enabled && local.create_groups ? toset(["admin", "write", "read"]) : toset([])

  scope              = var.resource_group_id
  role_definition_id = local.role_definition_map[each.key]
  principal_id       = local.group_object_ids[each.key]
  principal_type     = "Group"
}

# =============================================================================
# ROLE ASSIGNMENTS — DIRECT USER MODE (create_groups = false)
# =============================================================================
# When Entra group creation permissions are not available, assign the custom
# RBAC roles directly to individual users on the tenant resource group.
# Switching to create_groups = true later will replace these with group-based
# assignments (Terraform will destroy these and create group assignments).
# =============================================================================
resource "azurerm_role_assignment" "direct_users" {
  for_each = local.direct_user_assignments

  scope              = var.resource_group_id
  role_definition_id = local.role_definition_map[each.value.role]
  principal_id       = data.azuread_user.members[lower(each.value.upn)].object_id
  principal_type     = "User"
}
