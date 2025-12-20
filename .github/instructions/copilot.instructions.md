# Copilot Preferences for ai-hub-tracking

## Task Completion

After completing tasks:
- ✅ DO: Provide brief confirmation in chat (1-2 sentences)
- ❌ DON'T: Create summary markdown files

## Brief Status Format

Use this format for task completion:
✅ [Task Name] Complete

Change 1
Change 2
Verified: [confirmation]

---

## Project Context

This repo manages Azure infrastructure using:
- **Terraform** (>= 1.12.0) with Azure providers (azurerm >= 4.20, azapi >= 2.4)
- **Azure Verified Modules (AVM)** for standardized resource deployment
- **GitHub Actions** with OIDC authentication to Azure
- **Bash scripts** for local and CI Terraform operations

Infrastructure deploys to an **Azure Landing Zone** with strict networking policies.

---

## Terraform Conventions

### File Structure
```
initial-setup/
└── infra/
    ├── deploy-terraform.sh  # Deployment script (local & CI)
    ├── main.tf              # Root resources and module calls
    ├── variables.tf         # Input variables
    ├── outputs.tf           # Output values
    ├── providers.tf         # Provider configuration
    ├── backend.tf           # Backend config (values injected via CLI)
    └── modules/
        └── <module>/
            ├── main.tf
            ├── variables.tf
            ├── outputs.tf
            └── providers.tf
```

### Code Style
- Run `terraform fmt -recursive` before committing
- Use snake_case for resource names and variables
- Always specify `type` and `description` for variables
- Mark credentials with `sensitive = true`
- Pin module versions explicitly (e.g., `version = "0.4.1"`)

### Resource Patterns
```hcl
# Always include tags and lifecycle for externally managed tags
resource "azurerm_resource_group" "example" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

# Explicit dependencies for cross-module ordering
module "dependent" {
  source     = "./modules/dependent"
  depends_on = [module.network]
}
```

### AVM Modules
- Prefer Azure Verified Modules over raw resources
- Include registry URL in comments for reference

---

## GitHub Actions Conventions

### Workflow Patterns
```yaml
permissions:
  id-token: write  # Required for OIDC
  contents: read

env:
  TF_VERSION: 1.12.2
  TF_LOG: ERROR
  CI: "true"
  ARM_USE_OIDC: "true"
```

### Authentication
- Use OIDC via `azure/login@v2` with client-id, tenant-id, subscription-id
- Pass secrets via `TF_VAR_*` environment variables
- Never hardcode or echo secrets

### Reusable Workflows
- Name with `.` prefix (e.g., `.deployer.yml`)
- Use `workflow_call` with typed inputs
- Pass secrets with `secrets: inherit`

---

## Bash Script Conventions

### Required Header
```bash
#!/bin/bash
set -euo pipefail
```

### Directory Handling
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

### Logging (use color-coded functions)
```bash
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
```

### CI Mode
```bash
if [[ "${CI:-false}" == "true" ]]; then
  # Auto-approve, no interactive prompts
fi
```

---

## Azure Landing Zone Constraints

### ❌ Do NOT
- Modify VNet DNS settings or address space
- Create ExpressRoute, VPN, Route Tables, or VNet peering
- Delete `setbypolicy` Diagnostics Settings
- Use Basic/Standard ACR SKU with private endpoints (Premium required)

### ✅ Do
- Create NSG before creating subnets (policy requirement)
- Use Private Endpoints for all PaaS services
- Set subnets as Private Subnets (Zero Trust)
- Use existing VNet provided by platform team

---

## Common Patterns in This Repo

### Enabling/Disabling Modules
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

### Passing Network Dependencies
```hcl
module "service" {
  vnet_id                    = module.network.vnet_id
  container_app_subnet_id    = module.network.container_apps_subnet_id
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  depends_on                 = [module.network]
}
```

### Backend Configuration
Backend values are injected via `initial-setup/infra/deploy-terraform.sh` using `-backend-config` flags.
Never hardcode storage account names or keys.

---

## When Writing New Code

1. **Check existing patterns** - Look at similar modules/workflows first
2. **Use variables** - Avoid hardcoding values that may change
3. **Add descriptions** - Every variable needs a description
4. **Test locally** - Run `./initial-setup/infra/deploy-terraform.sh plan` before pushing
5. **Format code** - Run `terraform fmt` and check shell scripts with shellcheck