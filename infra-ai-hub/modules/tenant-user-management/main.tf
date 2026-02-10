# =============================================================================
# ENTRA GROUPS
# =============================================================================
# NOTE: Membership is managed via individual azuread_group_member resources
# (add-only). The azuread_group resource does NOT set 'members' or 'owners'
# attributes, so users added in the Azure portal are never removed by Terraform.
# =============================================================================
resource "azuread_group" "tenant" {
  for_each = local.groups_to_create

  display_name            = each.value.name
  security_enabled        = true
  mail_enabled            = local.mail_enabled
  mail_nickname           = each.value.mail_nickname
  prevent_duplicate_names = true
}

resource "azuread_group_member" "seed_members" {
  for_each = local.group_memberships

  group_object_id  = local.group_object_ids[each.value.role]
  member_object_id = data.azuread_user.members[lower(each.value.upn)].object_id
}

resource "azuread_group_owner" "group_owners" {
  for_each = local.group_owners

  group_object_id = local.group_object_ids[each.value.role]
  owner_object_id = data.azuread_user.members[lower(each.value.upn)].object_id
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
# ROLE ASSIGNMENTS (GROUP -> CUSTOM ROLE)
# =============================================================================
resource "azurerm_role_assignment" "tenant_groups" {
  for_each = local.enabled ? { for role, group_id in local.group_object_ids : role => group_id if group_id != null } : {}

  scope              = var.resource_group_id
  role_definition_id = each.key == "admin" ? azurerm_role_definition.tenant_admin[0].role_definition_resource_id : each.key == "write" ? azurerm_role_definition.tenant_write[0].role_definition_resource_id : azurerm_role_definition.tenant_read[0].role_definition_resource_id
  principal_id       = each.value
  principal_type     = "Group"
}
