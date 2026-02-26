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
- Safe dependency wiring (`depends_on`, module inputs/outputs) where needed
- Validation evidence (fmt/validate/plan-level checks) or explicit blocker notes

## External Documentation
- Use [External Docs Research](../external-docs/SKILL.md) as the single source of truth for external documentation workflow and fallback approval requirements.

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

## Validation Gates (Required)
Run these gates before handoff:
1. Formatting: `terraform fmt -recursive` on changed Terraform roots/modules
2. Syntax/static: `terraform validate` for affected root(s)
3. Script sanity: `bash -n` for modified Bash scripts
4. Workflow sanity: ensure OIDC, secret handling, and workflow-call contracts remain valid
5. Behavior sanity: confirm feature flags and counts do not create unintended resources

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

## Detailed References

For file structure trees, code patterns, GitHub Actions conventions, workflow architecture, bash conventions, tenant onboarding, implementation checklist, and failure playbooks, see [references/REFERENCE.md](references/REFERENCE.md).
