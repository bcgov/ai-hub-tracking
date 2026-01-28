---
name: IaC Coder
description: Guidance for producing Terraform, Bash, and GitHub Actions changes in ai-hub-tracking.
---

# IaC Coder Skills

Use this skill profile when creating or modifying infrastructure code in this repo.

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

## Implementation Checklist
1. Check existing patterns in similar modules/workflows.
2. Use variables for all configurable values.
3. Ensure variable descriptions are present.
4. Keep changes minimal and consistent with repo patterns.

## Running Deployments from local machine
1. Always use the deployment bash script over regular terraform commands
2. for deployments related to initial setup use this [script](../../../initial-setup/infra/deploy-terraform.sh)
3. for deployments related to infra-ai-hub use this [script](../../../infra-ai-hub/scripts/deploy-terraform.sh)`
