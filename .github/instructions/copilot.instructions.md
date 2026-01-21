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
## External docs reference - CRITICAL

Treat the Azure Landing Zone docs in the bcgov/public-cloud-techdocs repo as authoritative for networking and DNS behavior, IT IS CRITICAL to follow these guidelines when working within an Azure Landing Zone:
- https://raw.githubusercontent.com/bcgov/public-cloud-techdocs/refs/heads/main/docs/azure/design-build-deploy/networking.md
- https://raw.githubusercontent.com/bcgov/public-cloud-techdocs/refs/heads/main/docs/azure/design-build-deploy/next-steps.md
- https://github.com/bcgov/public-cloud-techdocs/blob/main/docs/azure/design-build-deploy/user-management.md

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

### AVM Modules with Private Endpoints in Azure Landing Zones
**IMPORTANT**: In Azure Landing Zones, private DNS zones are **policy-managed** by the platform team and Terraform does NOT have access to DNS zone IDs. However, AVM modules **CAN** work with this setup using the correct configuration:

**Required Configuration for AVM modules with private endpoints:**
```hcl
module "example" {
  source = "Azure/avm-res-keyvault-vault/azurerm"
  # ... other config ...

  # CRITICAL: Set this to false to let Azure Policy manage DNS
  private_endpoints_manage_dns_zone_group = false

  private_endpoints = {
    primary = {
      subnet_resource_id = var.private_endpoint_subnet_id
      # private_dns_zone_resource_ids can be omitted or set to []
    }
  }
}
```

**How it works:**
1. `private_endpoints_manage_dns_zone_group = false` tells AVM to NOT create DNS zone groups
2. AVM creates the private endpoint without DNS configuration
3. Azure Policy detects the new private endpoint and creates the DNS zone group automatically
4. AVM's internal `lifecycle { ignore_changes = [private_dns_zone_group] }` prevents Terraform drift

**AVM modules supporting this pattern:**
- `avm-res-keyvault-vault` (Key Vault)
- `avm-res-storage-storageaccount` (Storage Account)
- `avm-res-search-searchservice` (AI Search)
- `avm-res-cognitiveservices-account` (OpenAI, Document Intelligence)
- Most other AVM modules with `private_endpoints_manage_dns_zone_group` variable

**For resources without AVM module support:**
Use raw `azurerm_*` resources + separate `azurerm_private_endpoint` with `lifecycle { ignore_changes = [private_dns_zone_group] }`

### APIM Networking Options
APIM has different networking modes depending on the tier:

**1. Private Endpoints Only (stv2 style - Standard v2, Premium v2):**
- Uses the shared **Private Endpoints subnet**
- No dedicated subnet needed
- No subnet delegation required

**2. VNet Injection (Premium v2 tier):**
- Requires **dedicated subnet** (cannot be shared)
- Requires subnet delegation to `Microsoft.Web/hostingEnvironments`
- Minimum /27, recommended /24 for scaling

**3. Classic VNet Injection (Developer, Premium classic):**
- Requires **dedicated subnet** (cannot be shared)
- Subnet must have **NO delegation** (`Delegate subnet to a service = None`)
- Requires NSG with specific APIM management rules

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

## AzAPI Resource Validation

When using `azapi_resource` for Azure resources, **always validate against the official Azure REST API specs** before implementation.

### API Spec Reference
- GitHub: https://github.com/Azure/azure-rest-api-specs
- Path pattern: `specification/{service}/resource-manager/Microsoft.{Service}/{stable|preview}/{version}/{service}.json`

### CognitiveServices / AI Foundry API (2025-04-01-preview)

**AI Foundry Hub (Account):**
```hcl
resource "azapi_resource" "ai_foundry" {
  type = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  body = {
    kind = "AIServices"  # Required for AI Foundry
    sku  = { name = "S0" }  # Only valid SKU for AIServices
    properties = {
      customSubDomainName    = "unique-name"
      publicNetworkAccess    = "Disabled"  # Enum: Enabled, Disabled
      disableLocalAuth       = true
      allowProjectManagement = true  # Required for projects
      networkAcls = { defaultAction = "Deny" }  # Enum: Allow, Deny
    }
  }
}
```

**AI Foundry Project:**
```hcl
resource "azapi_resource" "ai_foundry_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  parent_id = azapi_resource.ai_foundry.id
  body = {
    sku = { name = "S0" }  # Required
    properties = {
      displayName = "Project Display Name"
      description = "Project description"
    }
  }
}
```

**Project Connections (CRITICAL - authType is discriminator):**
```hcl
resource "azapi_resource" "connection" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  parent_id = azapi_resource.ai_foundry_project.id
  body = {
    properties = {
      authType      = "AAD"  # REQUIRED discriminator - see valid values below
      category      = "AzureOpenAI"  # See ConnectionCategory enum
      target        = "/subscriptions/.../resource-id"
      isSharedToAll = true
      metadata      = { ApiType = "Azure" }
    }
  }
  schema_validation_enabled = false  # Required for preview APIs
}
```

### ConnectionAuthType Enum (discriminator - REQUIRED)
| Value | Use Case |
|-------|----------|
| `AAD` | Managed Identity / Entra ID authentication |
| `ApiKey` | API key authentication |
| `None` | No authentication required |
| `SAS` | Shared Access Signature |
| `AccountKey` | Storage account key |
| `ServicePrincipal` | Service principal with client secret |
| `ManagedIdentity` | Explicit managed identity |
| `CustomKeys` | Custom key-value credentials |
| `OAuth2` | OAuth2 flow |

### ConnectionCategory Enum (case-sensitive!)
| Service | Category Value |
|---------|---------------|
| Azure OpenAI | `AzureOpenAI` |
| AI Services | `AIServices` |
| Azure AI Search | `CognitiveSearch` |
| Cognitive Service | `CognitiveService` |
| Azure Blob Storage | `AzureBlob` |
| Cosmos DB | `CosmosDb` ⚠️ (not CosmosDB) |
| Cosmos DB MongoDB | `CosmosDbMongoDbApi` |
| Azure Key Vault | `AzureKeyVault` |
| Document Intelligence | `FormRecognizer` |
| Custom Keys | `CustomKeys` |
| API Key | `ApiKey` |

### Validation Checklist for azapi_resource
- [ ] Verify API version exists in azure-rest-api-specs
- [ ] Check required properties in schema definitions
- [ ] Validate enum values match exactly (case-sensitive)
- [ ] Confirm discriminator properties are set (e.g., `authType`, `kind`)
- [ ] Use `schema_validation_enabled = false` for preview APIs
- [ ] Run `terraform validate` after changes

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
6. **Document changes** - Update README.md or docs as needed. MAKE SURE THE referencec docs in the docs folder at the root of the repo are updated if there are any changes to infra or networking.