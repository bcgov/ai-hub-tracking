# Tenant User Management Module

Creates per-tenant custom Azure RBAC role definitions and assigns them at the
tenant resource group scope. Supports two assignment modes:

## Assignment Modes

| Mode | Flag | Description |
|---|---|---|
| **Direct User** | `create_groups = false` (default) | Assigns custom RBAC roles directly to individual users. No Entra ID group permissions needed. |
| **Group** | `create_groups = true` | Creates Entra ID security groups, adds seed members, and assigns roles to groups. Requires `Group.ReadWrite.All` Graph API permission. |

## Resources Created

| Resource | Direct Mode | Group Mode | Purpose |
|---|---|---|---|
| Custom RBAC Role Definitions | 3 | 3 | admin, write, read scoped to tenant RG |
| Role Assignments (User) | N | 0 | One per seed member |
| Entra ID Security Groups | 0 | 3 | admin, write, read groups |
| Role Assignments (Group) | 0 | 3 | Map groups → custom roles |
| Group Members | 0 | N | Seed members from config |
| Group Owners | 0 | N | Admin seed members as owners |

## Design Decisions

- **Environment prefix** — Group and role names include `app_env` to prevent
  collisions in the shared Entra tenant across dev/test/prod.
- **Direct user mode default** — Does not require Entra ID group creation
  permissions, making it safe for all environments including local development.
- **Switchable** — Moving from `create_groups = false` to `true` will replace
  individual user assignments with group-based ones (Terraform handles lifecycle).
- **Add-only membership** (group mode) — Uses individual `azuread_group_member`
  resources so users added in the Azure portal are never removed by Terraform.
- **Self-service delegation** (group mode) — Admin seed members are set as group
  owners, enabling tenant admins to manage membership without platform team.
- **Existing groups** — Supports `existing_group_ids` for teams that already have
  Entra groups they want to reuse.

## Usage

```hcl
module "tenant_user_management" {
  source   = "./modules/tenant-user-management"
  for_each = local.enabled_tenants

  tenant_name       = each.value.tenant_name
  display_name      = each.value.display_name
  app_env           = var.app_env
  resource_group_id = module.tenant[each.key].resource_group_id
  user_management   = each.value.user_management
}
```

## Tenant Configuration

Direct user mode (default — no group permissions needed):

```hcl
user_management = {
  seed_members = {
    admin = ["alice@gov.bc.ca", "bob@gov.bc.ca"]
    write = ["charlie@gov.bc.ca"]
    read  = ["dave@gov.bc.ca"]
  }
}
```

Group mode (requires `Group.ReadWrite.All` Graph API permission):

```hcl
user_management = {
  create_groups = true
  seed_members = {
    admin = ["alice@gov.bc.ca", "bob@gov.bc.ca"]
    write = ["charlie@gov.bc.ca"]
    read  = ["dave@gov.bc.ca"]
  }
}
```

To disable user management for a tenant (e.g., dev environments):

```hcl
user_management = {
  enabled = false
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `tenant_name` | Unique tenant identifier | `string` | — |
| `display_name` | Human-readable tenant name | `string` | — |
| `app_env` | Environment (`dev`, `test`, `prod`) | `string` | — |
| `resource_group_id` | Tenant resource group ID for RBAC scope | `string` | — |
| `user_management` | User management configuration object | `object` | `{}` |

### `user_management` Object

| Field | Description | Default |
|---|---|---|
| `enabled` | Enable/disable user management | `true` |
| `create_groups` | Create Entra groups (vs direct user assignment) | `false` |
| `group_prefix` | Prefix for group/role names | `"ai-hub"` |
| `mail_enabled` | Enable mail on security groups | `false` |
| `existing_group_ids` | Reuse existing Entra group IDs | `{}` |
| `seed_members` | Map of role → list of UPNs | `{}` |
| `owner_members` | Explicit group owners (defaults to admin seed) | `null` |

## Outputs

| Name | Description |
|---|---|
| `mode` | Assignment mode: `group` or `direct_user` |
| `group_object_ids` | Map of role → Entra group object ID (empty in direct mode) |
| `role_definition_ids` | Map of role → custom RBAC role definition ID |
| `direct_user_assignments` | Map of direct user role assignments (empty in group mode) |

## Providers

- `azurerm` >= 4.38
- `azuread` >= 3.0
