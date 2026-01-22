# Tenant Configuration

## Overview

Tenant configurations are now managed in a single **HCL map** file:

- `params/dev/tenants.tfvars` - Contains all dev tenants
- `params/test/tenants.tfvars` - Contains all test tenants  
- `params/prod/tenants.tfvars` - Contains all prod tenants

This consolidated approach makes it easier to manage multiple tenants and their dependencies.

## Adding a New Tenant

Edit the appropriate `tenants.tfvars` file and add a new entry to the `tenants` map:

```hcl
tenants = {
  # Existing tenants...
  
  "your-new-tenant" = {
    tenant_name  = "your-new-tenant"
    display_name = "Your New Tenant"
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
    
    # ... add other services as needed
  }
}
```

## Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `tenant_name` | string | Unique identifier (lowercase, alphanumeric, hyphens only) |
| `display_name` | string | Human-readable name for the tenant |
| `enabled` | bool | Set to `true` to deploy, `false` to skip |

## Resource Toggles

Each service can be independently enabled/disabled via the `enabled` flag:

```hcl
key_vault = {
  enabled = false  # Skip Key Vault for this tenant
}

storage_account = {
  enabled = true   # Deploy Storage Account
  account_tier = "Standard"
  # ... other config
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

After updating `tenants.tfvars`, deploy with:

```bash
cd infra-ai-hub

# Preview changes
terraform plan -var-file="params/dev/shared.tfvars" -var-file="params/dev/tenants.tfvars"

# Apply changes
terraform apply -var-file="params/dev/shared.tfvars" -var-file="params/dev/tenants.tfvars"
```

Or use the deployment script:

```bash
cd initial-setup/infra
./deploy-terraform.sh plan dev
./deploy-terraform.sh apply dev
```
