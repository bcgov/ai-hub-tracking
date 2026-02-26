---
name: iac-code-reviewer
description: Review checklist and standards for Terraform, GitHub Actions, Bash, and AVM changes in ai-hub-tracking. Use when reviewing pull requests or auditing infrastructure code changes.
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

## External Documentation
- Use [External Docs Research](../external-docs/SKILL.md) as the single source of truth for external documentation workflow and fallback approval requirements.

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

## Detailed References

For architecture compliance checklists, Terraform/GitHub Actions/Bash standards, anti-patterns catalog, and failure playbooks, see [references/REFERENCE.md](references/REFERENCE.md).
