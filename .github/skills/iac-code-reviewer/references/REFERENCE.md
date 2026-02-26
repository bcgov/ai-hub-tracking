# IaC Code Reviewer — Detailed Reference

Supplementary reference for the [IaC Code Reviewer skill](../SKILL.md). Load this file when you need detailed standards checklists, anti-pattern catalogs, or failure playbooks.

## Architecture & Compliance — CRITICAL

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
