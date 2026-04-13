---
name: iac-coder
description: Guidance for producing Terraform, Bash, and GitHub Actions changes in ai-hub-tracking. Use when implementing Terraform modules, stacks, deployment scripts, or GitHub Actions workflows.
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
- Updated service documentation when tenant-visible model or service availability changes. If Terraform, tenant tfvars, or Foundry wiring changes what tenants can access, update `docs/_pages/services.html` and the published docs page in the same change.
- Safe dependency wiring (`depends_on`, module inputs/outputs) where needed
- Validation evidence (fmt/validate/plan-level checks) or explicit blocker notes

## External Documentation
- Use [External Docs Research](../external-docs/SKILL.md) as the single source of truth for external documentation workflow and fallback approval requirements.

## Documentation Sync
- If the change adds, removes, renames, or materially reorganizes tracked files or directories, update the root `README.md` `Folder Structure` section in the same change. Do not add gitignored or local-only artifacts to that tree.
- Review the documentation sync matrix in [../../copilot-instructions.md](../../copilot-instructions.md) and update any area-specific README or docs pages it calls out for the touched subtree.

## Scope
- Terraform (>= 1.12.0) with Azure providers (azurerm >= 4.20, azapi >= 2.4)
- Azure Verified Modules (AVM)
- GitHub Actions with OIDC
- Bash scripts used for Terraform operations
- Reusable workflow path gating via `.github/workflows/.detect-changes.yml` for PR-vs-main change detection in workflow callers

## Stack Deploy Ordering

Stacks are deployed in dependency order by `scripts/deploy-scaled.sh`. When adding or moving a stack, update **both** `deploy-scaled.sh` **and** this skill profile file.

| Phase | Stack(s) | Run Mode | Notes |
|---|---|---|---|
| 1 | `shared` | Serial | Shared infra: network, CAE, KV, DNS, App Gateway |
| 2 | `tenant` (× N) | Parallel | Per-tenant Foundry project + KV, runs once per tenant |
| 3 | `foundry`, `tenant-user-mgmt`, `pii-redaction`, `vllm` | Parallel | Independent services with no cross-stack deps at deploy time |
| 3b | `apim` | Serial (after Phase 3) | Reads pii-redaction + vllm FQDNs via remote state — must run after Phase 3 |
| 4 | `key-rotation` | Serial (after Phase 3b) | Reads APIM principal ID via remote state — must run after `apim` |

> **Skill maintenance**: When changing the deploy sequence (adding phases, reordering stacks, or adding new serial/parallel constraints), update both `scripts/deploy-scaled.sh` **and** this skill profile.

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

### map(any) — Uniform Element Shape Required
- **`map(any)` requires every element to have the same structural type.** When Terraform unifies list/map elements that differ in shape (e.g., some objects have an extra attribute that others lack), the plan fails with `all map elements must have the same type`.
- **Never add ad-hoc attributes** to only some entries in a tfvars list/map. Attributes that only some providers or models need must be derived in stack logic, not carried in the tfvars schema.
- **Derive computed attributes in `locals.tf`** rather than requiring callers to provide them. Example: model format (`OpenAI` vs `Cohere`) is derived from a `model_format_prefixes` map in `locals.tf` keyed on the model name prefix — no `model_format` attribute is needed in any tenant tfvars entry.
- **Pattern for extensible derived attributes:**
  ```hcl
  # locals.tf — single place to add new providers/formats
  model_format_prefixes = {
    "cohere" = "Cohere"
    # "mistral" = "MistralAI"
  }
  default_model_format = "OpenAI"

  # main.tf — lookup with fallback, no tfvars attribute needed
  format = coalesce(
    one([for prefix, fmt in local.model_format_prefixes : fmt if startswith(lower(deployment.model_name), prefix)]),
    local.default_model_format
  )
  ```
- **When adding new list attributes** to any `map(any)` tenant variable (e.g., new field in `model_deployments`), you must add the field — or a safe default via `optional()` / `lookup()` — to **every** tenant tfvars entry in **every** environment simultaneously, or Terraform will fail to unify types.

### count / for_each — Plan-Time Values Only
- **Never** use resource attributes (module outputs derived from resource state) in `count` or `for_each` expressions. During `terraform destroy`, resource outputs become unknown and Terraform cannot resolve the count, causing `Invalid count argument` errors.
- **Always** use plan-time-known values: input variables, locals computed from variables, `terraform.workspace`, or static values.
- If a feature needs conditional resource creation, add an explicit `enable_*` boolean variable (default `false`) instead of deriving presence from a resource-produced value like a resource ID or workspace ID.
- Example — **bad**: `count = var.log_analytics_workspace_id != null ? 1 : 0` (where `var.log_analytics_workspace_id` comes from a module output)
- Example — **good**: `count = var.enable_diagnostics ? 1 : 0` (plain boolean variable, always known)

## Validation Gates (Required)
Run these gates before handoff:
1. Formatting: `terraform fmt -recursive` on changed Terraform roots/modules
2. Syntax/static: `terraform validate` for affected root(s)
3. Script sanity: `bash -n` for modified Bash scripts
4. Workflow sanity: ensure OIDC, secret handling, and workflow-call contracts remain valid; use `.detect-changes.yml` instead of duplicating inline `git diff` jobs when path-based gating is needed
5. Behavior sanity: confirm feature flags and counts do not create unintended resources
6. Documentation sanity: if the change affects tenant-facing service availability, confirm `docs/_pages/services.html`, the published docs page, and `infra-ai-hub/model-deployments.md` still match the deployed configuration

If a gate cannot be run locally, state exactly what was not run and why.

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
- After purging/recreating the AI Foundry resource, allow ~5 min for PE DNS propagation before running integration tests or the next apply — the destroy script confirms API-level deletion but not DNS propagation. See the [Failure Playbook](references/REFERENCE.md#️⚠️-critical-ai-foundry-private-endpoint-broken-after-purgeapply-deploymentnotfound-404) for full diagnosis steps.

## Detailed References

For file structure trees, code patterns, GitHub Actions conventions, workflow architecture, bash conventions, tenant onboarding, implementation checklist, and failure playbooks, see [references/REFERENCE.md](references/REFERENCE.md).
