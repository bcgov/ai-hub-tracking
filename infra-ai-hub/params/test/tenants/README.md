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
# TENANT: My New Tenant - TEST ENVIRONMENT
# =============================================================================

tenant = {
  tenant_name  = "my-new-tenant"
  display_name = "My New Tenant"
  enabled      = true

  # PE subnet assignment — mandatory, sticky, do not change after first deploy
  # Prod: check current PE count per subnet, pick the one with most capacity
  # Valid keys: privateendpoints-subnet, privateendpoints-subnet-1, privateendpoints-subnet-2, ...
  pe_subnet_key = "privateendpoints-subnet"

  tags = {
    ministry    = "YOUR-MINISTRY"
    environment = "test"
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
        # Optional: custom content filter (RAI policy) for this deployment.
        # Omit entirely to use Microsoft.DefaultV2 (Azure built-in default).
        # content_filter = {
        #   base_policy_name = "Microsoft.DefaultV2"
        #   filters = [
        #     { name = "hate",     severity_threshold = "High", source = "Prompt",     blocking = true, enabled = true },
        #     { name = "hate",     severity_threshold = "High", source = "Completion", blocking = true, enabled = true },
        #     { name = "violence", severity_threshold = "High", source = "Prompt",     blocking = true, enabled = true },
        #     { name = "violence", severity_threshold = "High", source = "Completion", blocking = true, enabled = true },
        #   ]
        # }
      }
    ]
  }

  # vLLM — opt-in to GPU-backed open-source models (shared hub infrastructure).
  # Each model entry can override tokens_per_minute independently; if omitted the
  # tenant-level rate_limiting.tokens_per_minute is used as the per-model default.
  # Requires the vllm stack to be deployed for this environment first.
  # vllm = {
  #   enabled = true
  #   models = [
  #     {
  #       model_id          = "google/gemma-4-31B-it"
  #       tokens_per_minute = 50000  # optional; defaults to rate_limiting.tokens_per_minute
  #     },
  #   ]
  # }

  apim_auth = {
    mode                 = "subscription_key"
    key_rotation_enabled = false  # Per-tenant opt-in for APIM key rotation
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

### vLLM Model IDs

The `model_id` field must exactly match the model ID on the shared vLLM Container App. The default model deployed in each environment is listed in `infra-ai-hub/model-deployments.md`.

**Token limits:**
- `tokens_per_minute` (per model, optional) — rate cap applied by APIM for this specific model. Defaults to the tenant-level `rate_limiting.tokens_per_minute` when omitted.
- Models that share the same `tokens_per_minute` still receive **independent counters** keyed by `{subscription-id}-vllm-{model-id}`, so a high-usage model does not consume another model's quota.

**Namespace collision rule:**
`model_id` values must not share a prefix (text before the first `/`) with any Foundry deployment `name` in the same tenant. Terraform validates this at plan time.

### OpenAI Model Names
Common models available in Azure OpenAI:
- `gpt-4o` - Latest GPT-4 with vision
- `gpt-4-turbo` - GPT-4 turbo
- `gpt-4` - GPT-4
- `gpt-35-turbo` - GPT-3.5 turbo
- `text-embedding-3-large` - Embeddings
- `text-embedding-3-small` - Embeddings (smaller)

Check Azure OpenAI model availability for your specific region.

### Content Filters (RAI Policies)

Each `model_deployments` entry can include an optional `content_filter` block to create a custom RAI policy instead of using the Azure built-in `Microsoft.DefaultV2`.

| Field | Allowed values | Required | Description |
|-------|---------------|----------|-------------|
| `base_policy_name` | string | No | Policy to inherit from. Default: `Microsoft.DefaultV2` |
| `filters[].name` | `hate` `violence` `sexual` `selfharm` | Yes | Content category |
| `filters[].severity_threshold` | `Low` `Medium` `High` | Yes | Severity at which the filter activates |
| `filters[].source` | `Prompt` `Completion` | Yes | Apply to user input or model output |
| `filters[].blocking` | bool | No | Hard-block the request (default: `true`) |
| `filters[].enabled` | bool | No | Toggle this entry on/off (default: `true`) |

Terraform validates all enum fields and creates a `raiPolicies` resource named `<tenant>-<deployment>-filter` on the shared Hub. Deployments without `content_filter` use `Microsoft.DefaultV2` and are unaffected.

See `infra-ai-hub/model-deployments.md` for a full example.

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
