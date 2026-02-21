---
name: IaC Code Reviewer
description: Review checklist and standards for Terraform, GitHub Actions, Bash, and AVM changes in ai-hub-tracking.
---

# IaC Code Reviewer Skills

Use this skill profile when reviewing IaC and CI/CD changes in this repo.

## Use When
- Reviewing Terraform, Bash, and GitHub Actions changes for correctness and compliance
- Classifying defects by severity and producing actionable review findings
- Verifying Landing Zone alignment, security controls, and deploy safety

## Do Not Use When
- Implementing new infrastructure changes directly (use IaC Coder)
- Editing APIM routing/policy behavior only (use API Management)
- Performing docs-only review under `docs/` (use Documentation)

## Input Contract
Required review inputs:
- Diff or changed files list with environment context (`dev/test/prod`)
- Impacted modules/workflows/scripts and expected behavior
- Relevant constraints (Landing Zone policy, security requirements, release risk)

## Output Contract
Review output must include:
- Findings with severity (`BLOCKER/MAJOR/MINOR/INFO`)
- Evidence (file path + specific code behavior)
- Clear fix guidance, not only issue statements
- Final recommendation (approve / request changes) with risk summary

## Scope
- Terraform (>= 1.12.0) with Azure providers (azurerm >= 4.20, azapi >= 2.4)
- Azure Verified Modules (AVM)
- GitHub Actions workflows (OIDC)
- Bash scripts for Terraform operations

## Review Goals
### Security
- No hardcoded secrets; use GitHub Secrets or Key Vault
- OIDC authentication preferred (`ARM_USE_OIDC=true`)
- Sensitive variables marked `sensitive = true`
- Private endpoints used for Azure PaaS services
- NSG associated with every subnet

### Correctness
- Terraform plans are idempotent
- Backend configured via `-backend-config` flags
- Explicit `depends_on` for cross-module dependencies
- Variables have types and descriptions

### Maintainability
- Code formatted (`terraform fmt`, shellcheck)
- Consistent naming conventions
- Comments explain why (not what)
- Modules are reusable with sensible defaults

## Severity Levels
- **BLOCKER**: Security vulnerability or production breakage
- **MAJOR**: Incorrect logic, policy violation, missing error handling
- **MINOR**: Style or documentation issues
- **INFO**: Suggestions and non-blocking improvements

## Architecture & Compliance - CRITICAL
### Azure Landing Zone Requirements
- ❌ Do NOT modify VNet DNS settings or address space
- ❌ Do NOT create ExpressRoute, VPN, Route Tables, or VNet peering
- ❌ Do NOT delete `setbypolicy` Diagnostics Settings
- ✅ All subnets must have associated NSG (create NSG first, then subnet)
- ✅ All subnets must be Private Subnets (Zero Trust model)
- ✅ Use Private Endpoints for PaaS services (DNS auto-created by policy)
- ✅ ACR Premium SKU required when using private endpoints

## Terraform Standards
- `required_version = ">= 1.12.0"`
- Provider `azurerm` >= 4.20, `azapi` >= 2.4
- Backend `azurerm` block empty; values injected via CLI
- Never commit `terraform.tfvars` with secrets
- Modules follow required file structure (main.tf, variables.tf, outputs.tf, providers.tf)
- Variables include `type`, `description`, and `nullable = false` for mandatory vars
- Resource tagging includes `tags = var.common_tags` and `lifecycle { ignore_changes = [tags] }`
- AVM modules are preferred, versions pinned, telemetry disabled

## GitHub Actions Standards
- Use `azure/login@v2` with OIDC client-id/tenant-id/subscription-id
- Pin actions to SHA when possible
- Use `ubuntu-24.04`
- Secrets passed via `TF_VAR_*` or `secrets` env vars
- Reusable workflows use `workflow_call` and `secrets: inherit`

## Bash Standards
- `#!/bin/bash` and `set -euo pipefail`
- Quote variables (`"$var"`)
- CI mode auto-approve handling
- Prerequisite checks for required tools and env vars

## Validation Gates (Required for High-Confidence Reviews)
- Confirm formatting/validation expectations are met for changed Terraform roots
- Confirm deployment path uses approved scripts, not ad-hoc direct state mutations
- Confirm workflow auth path remains OIDC-based and secrets-safe
- Confirm lifecycle/destroy behaviors are intentional and documented for non-idempotent Azure APIs

## Review Checklist
**Security**
- [ ] No hardcoded secrets or tokens
- [ ] `sensitive = true` set for credentials
- [ ] OIDC used for auth
- [ ] Private endpoints for PaaS services

**Terraform**
- [ ] `terraform fmt` applied
- [ ] Variables have descriptions and types
- [ ] Module versions pinned
- [ ] Backend configuration correct
- [ ] Dependencies declared with `depends_on`

**GitHub Actions**
- [ ] `id-token: write` present for OIDC
- [ ] Actions pinned to SHA/major version
- [ ] Secrets not echoed/logged
- [ ] Reusable workflows use `secrets: inherit`

**Bash**
- [ ] `set -euo pipefail` present
- [ ] Variables quoted
- [ ] CI mode handled
- [ ] Clear error messages for missing prerequisites

**Docs**
- [ ] README updated for interface changes
- [ ] Complex logic documented
- [ ] Breaking changes called out

## Anti-Patterns to Flag
### BLOCKER
- Secrets in plain text
- Missing `sensitive = true` on credentials
- Security controls disabled without justification
- Resources that bypass Landing Zone policies

### MAJOR
- Unbounded lifecycle ignores masking real drift
- Missing dependency edges causing nondeterministic applies
- APIM/Terraform changes that can break tenant isolation or routing correctness
- Changes that bypass repository deployment scripts/processes

### MINOR
- Inconsistent naming/style where behavior is still correct
- Missing comments for non-obvious workaround logic
- Documentation not updated for operator-facing behavior changes

## Failure Playbook for Reviewers
### If intent is unclear
- Request explicit expected behavior and rollback strategy before approving.

### If risk is high but evidence is incomplete
- Mark as `MAJOR` and require targeted validation (plan output, command output, or test evidence).

### If Azure API workaround is present (e.g., forced recreation patterns)
- Verify rationale is documented and scoped narrowly to the affected resource.
- Reject broad workaround patterns that could cause cascading replacement.
