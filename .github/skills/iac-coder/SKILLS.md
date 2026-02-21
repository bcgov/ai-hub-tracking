---
name: IaC Coder
description: Guidance for producing Terraform, Bash, and GitHub Actions changes in ai-hub-tracking.
---

# IaC Coder Skills

Use this skill profile when creating or modifying infrastructure code in this repo.

## Use When
- Implementing or refactoring Terraform modules, stacks, variables, or outputs
- Modifying deployment/ops Bash scripts for infra provisioning and operations
- Updating GitHub Actions workflows that deploy or validate infrastructure
- Adding infra features that require new module wiring, feature flags, or dependencies

## Do Not Use When
- Performing code review only (use IaC Code Reviewer)
- Editing APIM policies/routing behavior only (use API Management)
- Editing docs-only changes under `docs/` (use Documentation)

## Input Contract
Required context before making changes:
- Target environment (`dev`, `test`, or `prod`) and affected stack/module
- Intended behavior change and non-goals
- Current variables, tfvars, and dependency chain impacted by the change
- Landing Zone constraints relevant to networking, DNS, diagnostics, and identity

## Output Contract
Every change should deliver:
- Minimal IaC/code edits scoped to the requested behavior
- Updated variables/outputs/documentation for new interfaces
- Safe dependency wiring (`depends_on`, module inputs/outputs) where needed
- Validation evidence (fmt/validate/plan-level checks) or explicit blocker notes

## Scope
- Terraform (>= 1.12.0) with Azure providers (azurerm >= 4.20, azapi >= 2.4)
- Azure Verified Modules (AVM)
- GitHub Actions with OIDC
- Bash scripts used for Terraform operations

## Authoritative References (Azure Landing Zone) - CRITICAL
Follow BC Gov Azure Landing Zone guidance for networking and DNS behavior. This is critical and must be followed:
- https://raw.githubusercontent.com/bcgov/public-cloud-techdocs/refs/heads/main/docs/azure/design-build-deploy/networking.md
- https://raw.githubusercontent.com/bcgov/public-cloud-techdocs/refs/heads/main/docs/azure/design-build-deploy/next-steps.md
- https://github.com/bcgov/public-cloud-techdocs/blob/main/docs/azure/design-build-deploy/user-management.md

## Terraform Conventions
- Run `terraform fmt -recursive`
- Use snake_case for resource names and variables
- Always specify `type` and `description` for variables
- Always create separate files for data, locals, versions and providers
- Always use modules
- Mark credentials with `sensitive = true`
- Pin module versions explicitly (e.g., `version = "0.4.1"`)
- Prefer AVM modules over raw resources
- Include registry URL in module comments

### File Structure (initial-setup)
```
initial-setup/
└── infra/
		├── deploy-terraform.sh
		├── main.tf
		├── variables.tf
		├── outputs.tf
		├── providers.tf
		├── backend.tf
		└── modules/
				└── <module>/
						├── main.tf
						├── variables.tf
						├── outputs.tf
						└── providers.tf
```

### File Structure (infra-ai-hub)
```
infra-ai-hub/
├── terraform.tfvars
├── scripts/
│   └── deploy-terraform.sh
├── modules/
│   └── <module>/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── providers.tf
│       └── versions.tf
├── stacks/
│   └── <stack>/    (shared, tenant, apim, foundry, tenant-user-mgmt)
│       ├── backend.tf
│       ├── locals.tf
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── providers.tf
│       └── (no modules/ — stacks consume shared modules above)
└── params/
    ├── apim/       (policy templates)
    ├── dev/        (env-specific tfvars)
    ├── test/
    └── prod/
```

Most day-to-day work targets `infra-ai-hub/`. Stacks are isolated Terraform roots that share modules; params provide environment-specific variables.

### Resource Patterns
```hcl
resource "azurerm_resource_group" "example" {
	name     = var.resource_group_name
	location = var.location
	tags     = var.common_tags
	lifecycle {
		ignore_changes = [tags]
	}
}

module "dependent" {
	source     = "./modules/dependent"
	depends_on = [module.network]
}
```

### Feature Toggles
```hcl
variable "feature_enabled" {
	type    = bool
	default = false
}

module "feature" {
	count  = var.feature_enabled ? 1 : 0
	source = "./modules/feature"
}
```

### Network Dependency Passing
```hcl
module "service" {
	vnet_id                    = module.network.vnet_id
	container_app_subnet_id    = module.network.container_apps_subnet_id
	private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
	depends_on                 = [module.network]
}
```

### Backend Configuration
- Backend values are injected via `initial-setup/infra/deploy-terraform.sh` using `-backend-config` flags.
- Never hardcode storage account names or keys.

## Validation Gates (Required)
Run these gates before handoff:
1. Formatting: `terraform fmt -recursive` on changed Terraform roots/modules
2. Syntax/static: `terraform validate` for affected root(s)
3. Script sanity: `bash -n` for modified Bash scripts
4. Workflow sanity: ensure OIDC, secret handling, and workflow-call contracts remain valid
5. Behavior sanity: confirm feature flags and counts do not create unintended resources

If a gate cannot be run locally, state exactly what was not run and why.

## GitHub Actions Conventions
- Use OIDC via `azure/login@v2` with client-id, tenant-id, subscription-id
- Pass secrets via `TF_VAR_*` environment variables
- Never hardcode or echo secrets
- Reusable workflows: name with `.` prefix and use `workflow_call` with typed inputs

```yaml
permissions:
	id-token: write
	contents: read

env:
	TF_VERSION: 1.12.2
	TF_LOG: ERROR
	CI: "true"
	ARM_USE_OIDC: "true"
```

### Workflow Architecture

All CI/CD follows a reusable workflow chain pattern:

```
Trigger workflow (pr-open.yml, merge-main.yml, manual-dispatch.yml)
├── .lint.yml (pre-commit, TFLint, conventional commits)
├── .builds.yml (Docker images → GHCR)
├── .deployer.yml (direct deploy for tools env)
│   └── outputs: proxy_url, proxy_auth (GPG-encrypted)
└── .deployer-using-secure-tunnel.yml (dev/test/prod)
    ├── Decrypts proxy_url/proxy_auth via GPG_PASSPHRASE
    ├── Starts chisel-client (SOCKS5 tunnel) + privoxy (HTTP proxy)
    ├── Sets HTTP_PROXY/HTTPS_PROXY=http://127.0.0.1:8118
    ├── Runs deploy-terraform.sh through the tunnel
    └── On success: .integration-tests-using-secure-tunnel.yml
```

**Secure tunnel purpose**: VNet-isolated resources (private endpoints) are unreachable from GitHub Actions runners. The tunnel routes data-plane traffic through a proxy deployed in the `tools` environment (Container App), while control-plane traffic (`management.azure.com`, `registry.terraform.io`, etc.) bypasses the proxy via `NO_PROXY`.

**Prod safeguard**: `manual-dispatch.yml` requires a semver git tag for prod apply.

## Bash Script Conventions
- Required header:
	```bash
	#!/bin/bash
	set -euo pipefail
	```
- Directory handling:
	```bash
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	```
- CI mode:
	```bash
	if [[ "${CI:-false}" == "true" ]]; then
		# Auto-approve, no interactive prompts
	fi
	```

## Azure Landing Zone Constraints
### ❌ Do NOT
- Modify VNet DNS settings or address space
- Create ExpressRoute, VPN, Route Tables, or VNet peering
- Delete `setbypolicy` Diagnostics Settings
- Use Basic/Standard ACR SKU with private endpoints (Premium required)

### ✅ Do
- Create NSG before creating subnets
- Use Private Endpoints for all PaaS services
- Set subnets as Private Subnets (Zero Trust)
- Use existing VNet provided by platform team

## Tenant Onboarding Workflow

To add a new tenant:

1. **Create tenant config**: `infra-ai-hub/params/{env}/tenants/{tenant-name}/tenant.tfvars`
   - Define the `tenant = { ... }` block with `enabled = true` and desired services
   - Tenant name must match `^[a-z0-9-]+$`
   - See existing tenants for the full config shape (key_vault, storage_account, ai_search, cosmos_db, document_intelligence, speech_services, openai with model_deployments)
2. **Deploy**: `deploy-terraform.sh apply {env}` auto-merges all tenant tfvars
3. **Stack order** (handled by `deploy-scaled.sh`):
   - Phase 1: `shared` (networking, hub resources)
   - Phase 2: `tenant` (per-tenant resources — runs in parallel across tenants)
   - Phase 3: `foundry` + `apim` + `tenant-user-mgmt` (concurrent)
4. **Update docs**: Update [Model Deployments](../../../infra-ai-hub/model-deployments.md) for the new tenant

`enabled_tenants` is computed via `for key, config in var.tenants : key => config if try(config.enabled, false)` — setting `enabled = false` disables without deletion.

## Related Tooling References
- **SSL certificates**: See `ssl_certs/README.md` for CSR generation, PFX creation, and cert upload workflows
- **Environment bootstrapping**: See `initial-setup/README.md` for OIDC identity setup and first-time provisioning
- **Azure proxy (chisel/privoxy)**: See `azure-proxy/` for the secure tunnel used in CI/CD

## Implementation Checklist
1. Check existing patterns in similar modules/workflows.
2. Use variables for all configurable values.
3. Ensure variable descriptions are present.
4. Keep changes minimal and consistent with repo patterns.
5. Make sure changes are also reflected in appropriate sections in [docs](../../../docs/)
6. **[MANDATORY]** When adding new tenants or modifying existing tenant model deployments, update the [Model Deployments & Quota Allocation](../../../infra-ai-hub/model-deployments.md) table for the affected environment(s). This keeps the quota tracking accurate and prevents over-allocation.

## Failure Playbook
### Terraform drift or noisy plans
- Re-check lifecycle blocks and `ignore_changes` intent before adding new ignores.
- Verify module input defaults and conditional counts are stable.

### Diagnostic settings not applying destination changes
- Follow the existing recreation pattern used in App Gateway diagnostics:
	- `replace_triggered_by` linked to a deterministic trigger resource
	- Trigger value change forces recreation when Azure in-place update is unreliable
- Do not replace this with ad-hoc taint/destroy instructions.

### OIDC/auth deployment failures
- Verify workflow has `id-token: write` and correct tenant/subscription/client IDs.
- Confirm no secrets are printed and credential flow still uses `ARM_USE_OIDC=true`.

## Running Deployments from local machine
1. Always use the deployment bash script over regular terraform commands
2. for deployments related to initial setup use this [script](../../../initial-setup/infra/deploy-terraform.sh)
3. for deployments related to infra-ai-hub use this [script](../../../infra-ai-hub/scripts/deploy-terraform.sh)
