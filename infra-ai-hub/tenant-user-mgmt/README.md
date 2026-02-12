# Tenant User Management — Separate State

## Overview

This directory contains a **completely independent Terraform root configuration** with its own state file. It is intentionally separated from the main infrastructure config to solve a critical architectural problem: **preventing resource destruction when Graph API permissions are unavailable**.

## Why Separate State?

### The Problem

The main infrastructure config (`../main.tf`) originally included:
```hcl
module "tenant_user_management" {
  for_each = var.enabled_tenants
  # ...
}
```

When the executing identity **lacks Microsoft Graph `User.Read.All` permission**, the module's `for_each` loop cannot populate because `data.azuread_user` lookups fail with HTTP 403.

In Terraform, when a `for_each` becomes **empty** (due to data lookup failures or upstream dependencies), Terraform treats all previously-created resources in that loop as "no longer managed" and **destroys them on the next apply**.

This created a catch-22:
- ❌ **Scenario 1 (GHA without Graph perms)**: Module destroyed on Phase 4 apply
- ❌ **Scenario 2 (Local with Graph perms)**: Module works fine, but GHA can't run without destroying

### The Solution

By moving tenant user management to a **separate state file** (`ai-services-hub/{env}/tenant-user-management.tfstate`), the main config **never knows about this module**. This means:

- ✅ Main infrastructure (Phases 1-4) applies **regardless of Graph permissions**
- ✅ Tenant user management (Phase 5) applies **only when Graph permissions available**
- ✅ Resources in each state are **never destroyed** by the other state's apply
- ✅ The deploy script can **conditionally skip Phase 5** without side effects

## Permission Requirements

### Microsoft Graph User.Read.All (Application)

This config **requires** the executing identity to have:
- **Application Permission**: `User.Read.All` on Microsoft Graph API
- **Scope**: Allows reading user directory objects by UPN (email address)

### Why?

The `tenant-user-management` module includes:
```hcl
data "azuread_user" "direct_assignments" {
  user_principal_name = each.value.user_principal_name
}
```

This data lookup requires Graph `User.Read.All` permission. Without it:
```
Error: Unable to list users from Azure AD: Unable to list users: 
  Insufficient privileges to complete the operation. The caller does not have permission. 
  Status: 403
```

## Local-Only Execution

### Why it Only Works Locally

The Azure managed identity used in GitHub Actions **does not have** `User.Read.All` permission by design:

- **Security**: Limiting GHA's permissions follows the principle of least privilege
- **Access Control**: Only employees with directory access grant this permission
- **Audit Trail**: Managed identity permission requests are tracked separately

### For Local Execution

You can run this config locally if you have:

1. **Directory Admin Access** (or permission to grant Graph API permissions)
2. **Azure CLI, Terraform, and Bash** installed locally


### Running the Config

The main deploy script handles conditional execution:

```bash
# Full deployment (Phases 1-5)
./scripts/deploy-terraform.sh apply-phased test --auto-approve

# Main infrastructure only (Phases 1-4)
# Phase 5 will be skipped if Graph User.Read.All is unavailable
```

The script's `check_graph_permissions()` function probes the Graph API:
```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://graph.microsoft.com/v1.0/users?\$top=1" | \
  grep -q "$HTTP_STATUS"
# Exit code 0 = Graph User.Read.All available
# Exit code 1 = Permission denied (403)
```

## Architecture Decisions

### State File Location

```
Azure Storage Account: tftestaihubtracking
├── terraform.tfstate/
│   ├── dev/terraform.tfstate (main config)
│   ├── dev/tenant-user-management.tfstate (THIS config) ← SEPARATE
│   ├── test/terraform.tfstate (main config)
│   ├── test/tenant-user-management.tfstate (THIS config) ← SEPARATE
│   └── prod/...
```

### Resource Group Lookup (No Dependency)

This config does **not** depend on `module.tenant` outputs from the main config. Instead, it uses a **rendezvous naming convention**:

```hcl
# Main config creates RGs as: "{tenant_name}-rg"
resource "azurerm_resource_group" "tenant" {
  name = "${each.value.tenant_name}-rg"
  # ...
}

# This config looks them up by the same convention
data "azurerm_resource_group" "tenant" {
  name = "${each.value.tenant_name}-rg"
}
```

**Why?** If this config depended on main config outputs, applying main config would require tenant-user-management to be present, creating a circular dependency.

## Deployment Flow

```
Phase 1: Network infrastructure
Phase 2: Storage & Container Registry
Phase 3: AI/ML foundry resources
Phase 4: Application Gateway & API Management
Phase 5: Tenant user management (SEPARATE STATE, conditional)
         └─ Skipped if Graph User.Read.All unavailable
         └─ Runs only for local deployments with proper permissions
```

## Troubleshooting

### Phase 5 Skipped (No Graph Permission)

If you see:
```
DEBUG: Graph User.Read.All permission check failed (HTTP 403)
Skipping Phase 5: Tenant User Management
```

This is **expected** in GHA. To enable Phase 5:

1. **Azure Directory Admin** grants Graph `User.Read.All` to managed identity
2. Modify GHA workflow to manually call user-mgmt apply
3. OR run from local machine with proper authentication

### Plan Shows No Changes

If `terraform plan` in this directory shows `No changes`, it means:
- ✅ State already matches infrastructure (expected after successful apply)

If you need to modify tenant assignments:
```bash
cd tenant-user-mgmt
terraform apply -var-file=../.tenants-test.auto.tfvars
```

## File Structure

```
tenant-user-mgmt/
├── README.md                    (this file)
├── backend.tf                   (empty backend, configured by deploy script)
├── providers.tf                 (azurerm, azuread - uses same auth as main)
├── variables.tf                 (app_env, subscription_id, tenant_id, tenants)
├── locals.tf                    (enabled_tenants filter)
├── main.tf                      (RG lookup + tenant-user-management module call)
└── outputs.tf                   (tenant_user_management output)
```

## Related Documentation

- **Main Config**: [../README.md](../README.md)
- **Deploy Script**: [../scripts/deploy-terraform.sh](../scripts/deploy-terraform.sh)
- **Tenant User Management Module**: [../modules/tenant-user-management/README.md](../modules/tenant-user-management/README.md)
- **Deployment Phases**: [../docs/workflows.html](../docs/workflows.html)

---

**Last Updated**: 2026-02-10  
**State Version**: Separate from main (Phase 5)
