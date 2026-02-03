# Tenant Configuration

## Overview

Each tenant is configured in its own folder under `params/{environment}/tenants/`.
Tenant configurations use **HCL/tfvars format** (`tenant.tfvars`) which supports comments.

```
params/
├── dev/
│   ├── shared.tfvars
│   └── tenants/
│       ├── README.md
│       └── {tenant-name}/
│           └── tenant.tfvars
├── test/
│   ├── shared.tfvars
│   └── tenants/
│       ├── wlrs-water-form-assistant/
│       │   └── tenant.tfvars
│       └── sdpr-invoice-automation/
│           └── tenant.tfvars
└── prod/
    ├── shared.tfvars
    └── tenants/
        └── wlrs-water-form-assistant/
            └── tenant.tfvars
```

## Adding a New Tenant

1. **Create a new folder** under `params/{environment}/tenants/` with the tenant name:
   ```bash
   mkdir -p params/dev/tenants/my-new-tenant
   ```

2. **Create `tenant.tfvars`** in the tenant folder:
   ```bash
   touch params/dev/tenants/my-new-tenant/tenant.tfvars
   ```

3. **Add tenant configuration** (HCL format with comments):

```hcl
# =============================================================================
# TENANT: My New Tenant - DEV ENVIRONMENT
# =============================================================================

tenant = {
  tenant_name  = "my-new-tenant"
  display_name = "My New Tenant"
  enabled      = true

  tags = {
    ministry    = "YOUR-MINISTRY"
    environment = "dev"
    owner       = "your-team"
  }

  key_vault = {
    enabled = false
  }

  storage_account = {
    enabled                  = true
    account_tier             = "Standard"
    account_replication_type = "LRS"
    account_kind             = "StorageV2"
    access_tier              = "Hot"
  }

  ai_search = {
    enabled = false
  }

  cosmos_db = {
    enabled = false
  }

  document_intelligence = {
    enabled = true
    sku     = "S0"
    kind    = "FormRecognizer"
  }

  log_analytics = {
    enabled        = true
    retention_days = 30
    sku            = "PerGB2018"
  }

  openai = {
    enabled = true
    sku     = "S0"
    model_deployments = [
      {
        name          = "gpt-4.1-mini"
        model_name    = "gpt-4.1-mini"
        model_version = "2025-04-14"
        scale_type    = "GlobalStandard"
        capacity      = 10
      }
    ]
  }

  apim_auth = {
    mode              = "subscription_key"
    store_in_keyvault = false
  }

  # APIM Policies Configuration
  apim_policies = {
    pii_redaction = {
      enabled     = true   # Enable PII detection and redaction
      fail_closed = false  # When true: blocks requests (503) if Language Service fails
                           # When false (default): passes through unredacted content on failure
    }
    rate_limiting = {
      enabled           = true
      tokens_per_minute = 1000
    }
    usage_logging = {
      enabled = true
    }
  }

  apim_diagnostics = {
    sampling_percentage = 100
    verbosity           = "information"
  }
}
```

4. **Run terraform plan** to preview changes:
   ```bash
   ./scripts/deploy-terraform.sh plan dev
   ```

## How It Works

The deploy script merges individual tenant configurations:

1. Finds all `tenant.tfvars` files in `params/{env}/tenants/*/`
2. Merges them into a combined `tenants = { ... }` map
3. Writes to `.tenants-{env}.auto.tfvars` (auto-generated, gitignored)
4. The folder name becomes the tenant key (e.g., `my-new-tenant`)

This means:
- **No changes to deploy script needed** when adding tenants
- **No tfvars file conflicts** - each tenant is isolated
- **Terraform auto-discovers** new tenants on plan/apply

## Benefits of This Structure

1. **Isolation**: Each tenant's configuration is isolated in its own folder
2. **Easy maintenance**: Adding/removing tenants is as simple as adding/removing folders
3. **Clear ownership**: Each folder can be reviewed and maintained independently
4. **Reduced merge conflicts**: Changes to different tenants don't conflict
5. **Scalability**: No single file grows too large as tenants are added
6. **Dynamic discovery**: Terraform automatically finds new tenant folders

## Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `tenant_name` | string | Unique identifier (lowercase, alphanumeric, hyphens only) |
| `display_name` | string | Human-readable name for the tenant |
| `enabled` | bool | Set to `true` to deploy, `false` to skip |

## Resource Toggles

Each service can be independently enabled/disabled via the `enabled` flag (JSON format):

```json
{
  "key_vault": {
    "enabled": false
  },
  "storage_account": {
    "enabled": true,
    "account_tier": "Standard"
  }
}
```

## SKU Reference

### AI Search SKUs
- `free` - Free tier (1 per subscription)
- `basic` - Basic tier
- `standard`, `standard2`, `standard3` - Standard tiers

### Storage Account Replication
- `LRS` - Locally Redundant Storage
- `GRS` - Geo-Redundant Storage
- `ZRS` - Zone-Redundant Storage
- `GZRS` - Geo Zone-Redundant Storage

### Cosmos DB Consistency Levels
- `Eventual` - Most permissive
- `ConsistentPrefix`
- `Session` - Recommended for most use cases
- `BoundedStaleness`
- `Strong` - Most restrictive

### OpenAI Model Names
Common models available in Azure OpenAI:
- `gpt-4o` - Latest GPT-4 with vision
- `gpt-4-turbo` - GPT-4 turbo
- `gpt-4` - GPT-4
- `gpt-35-turbo` - GPT-3.5 turbo
- `text-embedding-3-large` - Embeddings
- `text-embedding-3-small` - Embeddings (smaller)

Check Azure OpenAI model availability for your specific region.

## Deployment

After adding/updating tenant folders, deploy with:

```bash
cd infra-ai-hub

# Using the deployment script (recommended)
./scripts/deploy-terraform.sh plan dev
./scripts/deploy-terraform.sh apply dev

# Or manually
terraform plan -var-file="params/dev/shared.tfvars"
terraform apply -var-file="params/dev/shared.tfvars"
```

Tenants are automatically discovered from `tenant.json` files - no need to specify them in the command.
