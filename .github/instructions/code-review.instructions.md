# Review Agent Guidelines (GitHub Actions + Terraform + Bash + AVM)

These guidelines are for reviewers (human or AI) assessing **IaC and CI/CD code** in this repo: GitHub Actions workflows, Terraform IaC, Bash scripts, and Azure Verified Modules (AVM) setup.

The goal is to catch issues that matter in production systems: security, correctness, sustainability, idempotency, and maintainability.

---

## 1) Review goals (what “good” looks like)

### Security
- Secrets NEVER hardcoded; use GitHub Secrets or Azure Key Vault references
- OIDC authentication preferred over service principal secrets (`ARM_USE_OIDC=true`)
- Sensitive variables marked with `sensitive = true` in Terraform
- Private endpoints used for Azure PaaS services (per Landing Zone policy)
- NSG associated with every subnet

### Correctness
- Terraform plans should be idempotent (re-running produces no changes)
- Backend state properly configured with `-backend-config` flags
- Module dependencies explicitly declared with `depends_on`
- Variables have proper types and descriptions

### Maintainability
- Code is formatted (`terraform fmt`, shell scripts pass shellcheck)
- Consistent naming conventions across resources
- Comments explain "why" not "what" for complex logic
- Modules are reusable with sensible defaults

---

## 2) Severity levels

| Level | Description | Action Required |
|-------|-------------|-----------------|
| **BLOCKER** | Security vulnerability, secrets exposure, will break production | Must fix before merge |
| **MAJOR** | Missing error handling, incorrect logic, policy violation | Should fix before merge |
| **MINOR** | Style inconsistency, missing docs, non-critical improvements | Consider fixing |
| **INFO** | Suggestions, alternative approaches, nitpicks | Optional |

---

## 3) Architecture & compliance (most important)

### Azure Landing Zone Requirements
- ❌ Do NOT modify VNet DNS settings or address space
- ❌ Do NOT create ExpressRoute, VPN, Route Tables, or VNet peering
- ❌ Do NOT delete `setbypolicy` Diagnostics Settings
- ✅ All subnets must have associated NSG (create NSG first, then subnet)
- ✅ All subnets must be Private Subnets (Zero Trust model)
- ✅ Use Private Endpoints for PaaS services (DNS auto-created by policy)
- ✅ ACR Premium SKU required if using private endpoints

### Module Dependencies
- Network module must complete before any dependent modules
- Use explicit `depends_on` for cross-module dependencies
- Resource groups should be created at root level, passed to modules

---

## 4) Terraform Standards

### Version Requirements
```hcl
terraform {
  required_version = ">= 1.12.0"
}
```
- Provider `azurerm` >= 4.20
- Provider `azapi` >= 2.4 (for advanced Azure operations)

### Backend Configuration
- Backend must be `azurerm` with empty block (values injected via `-backend-config`)
- State files stored in Azure Storage with OIDC auth
- Never commit `terraform.tfvars` with secrets

### Module Structure (required files)
```
modules/<module-name>/
├── main.tf        # Resources and module calls
├── variables.tf   # Input variables with descriptions set explicit nullable=false for mandatory vars
├── outputs.tf     # Output values
├── providers.tf   # Provider requirements (if module-specific)
└── README.md      # Module documentation (optional but recommended)
```

### Variable Conventions
```hcl
variable "example_var" {
  description = "Clear description of the variable purpose"
  type        = string        # Always specify type
  default     = "value"       # Provide sensible defaults where appropriate
  nullable   = false          # Explicitly set nullable for mandatory vars
  sensitive   = true          # Mark secrets/credentials as sensitive
}
```

### Resource Tagging
- All resources must include `tags = var.common_tags`
- Use lifecycle `ignore_changes = [tags]` for resources managed externally

### Azure Verified Modules (AVM)
- Prefer AVM modules over raw resources when available
- Pin AVM module versions (e.g., `version = "0.4.1"`)
- Disable telemetry: `enable_telemetry = false`
- Document the AVM registry URL in comments

---

## 5) GitHub Actions Workflow Standards

### Workflow Structure
```yaml
name: .Workflow Name  # Prefix with . for reusable workflows

on:
  workflow_call:      # For reusable workflows
    inputs:
      environment_name:
        required: true
        type: string

permissions:
  id-token: write     # Required for OIDC
  contents: read
```

### Required Patterns
- **OIDC Authentication**: Use `azure/login@v2` with `client-id`, `tenant-id`, `subscription-id`
- **Pinned Versions**: Pin Terraform version in env var (e.g., `TF_VERSION: 1.12.2`)
- **Action SHAs**: Prefer SHA-pinned actions for security (e.g., `hashicorp/setup-terraform@b9cd54a...`)
- **Runner Version**: Use `ubuntu-24.04` for consistency
- **Reusable Workflows**: Use `workflow_call` with `secrets: inherit`

### Environment Variables
```yaml
env:
  TF_VERSION: 1.12.2
  TF_LOG: ERROR
  CI: "true"
  ARM_USE_OIDC: "true"
```

### Secrets Handling
- ✅ Use `${{ secrets.SECRET_NAME }}` for sensitive values
- ✅ Pass secrets via `TF_VAR_*` environment variables
- ❌ Never echo or log secret values
- ❌ Never use `secrets.*` in workflow names or job names

### Self-Hosted Runners
- Use `runs-on: self-hosted` for private network access
- Inline Terraform commands acceptable for self-hosted (network isolation)

---

## 6) Bash Script Standards

### Script Header
```bash
#!/bin/bash
set -euo pipefail  # REQUIRED: Exit on error, undefined vars, pipe failures
```

### Directory Handling
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

### Logging Functions (use color-coded output)
```bash
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
```

### CI Mode Detection
```bash
if [[ "${CI:-false}" == "true" ]]; then
  # Auto-approve, no interactive prompts
  args+=("-auto-approve")
fi
```

### Prerequisite Checks
- Verify required tools are installed (az, terraform, etc.)
- Validate required environment variables before execution
- Provide clear error messages for missing prerequisites

### Usage Documentation
- Include comprehensive usage block at script top
- Document all commands, options, and environment variables
- Provide examples in comments

---

## 7) Common Review Checklist

### Before Approving, Verify:

**Security**
- [ ] No hardcoded secrets, tokens, or credentials
- [ ] Sensitive variables marked as `sensitive = true`
- [ ] OIDC preferred over static credentials
- [ ] Private endpoints used for PaaS services

**Terraform**
- [ ] `terraform fmt` applied (no formatting changes)
- [ ] Variables have descriptions and types
- [ ] Module versions pinned
- [ ] Backend configuration correct
- [ ] `depends_on` for cross-module dependencies

**GitHub Actions**
- [ ] `id-token: write` permission for OIDC
- [ ] Actions pinned to SHA or major version
- [ ] Secrets passed via environment variables
- [ ] Reusable workflows use `secrets: inherit`

**Bash Scripts**
- [ ] `set -euo pipefail` at script start
- [ ] Proper quoting of variables (`"$var"` not `$var`)
- [ ] CI mode handling for non-interactive execution
- [ ] Meaningful error messages

**Documentation**
- [ ] Complex logic has explanatory comments
- [ ] README updated if module interface changed
- [ ] Breaking changes documented

---

## 8) Anti-Patterns to Flag

### BLOCKER
- Secrets in plain text anywhere in code
- Missing `sensitive = true` on credential variables
- Disabled security features without justification
- Creating resources that bypass Landing Zone policies

### MAJOR
- Missing `set -euo pipefail` in bash scripts
- Unquoted variables in shell scripts
- Missing `depends_on` causing race conditions
- Hardcoded values that should be variables

### MINOR
- Inconsistent naming conventions
- Missing variable descriptions
- Commented-out code without explanation
- Overly complex expressions without comments
