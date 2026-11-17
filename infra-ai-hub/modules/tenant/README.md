# Tenant Module

This module creates all resources for a single tenant within the AI Foundry platform.

## Overview

Each tenant gets their own isolated set of resources:
- AI Foundry Project (within the shared hub)
- Log Analytics Workspace (optional)
- Key Vault (optional)
- Storage Account (optional)
- Azure AI Search (optional)
- Cosmos DB (optional)
- Document Intelligence (optional)
- Content Understanding account with its own model deployments (optional, via [`../content-understanding`](../content-understanding/README.md))
- OpenAI deployments (optional)
- Private Endpoints for all enabled resources

## Usage

```hcl
module "tenant" {
  source   = "./modules/tenant"
  for_each = local.enabled_tenants

  tenant_name   = each.value.tenant_name
  display_name  = each.value.display_name
  
  resource_group_name = azurerm_resource_group.main.name
  resource_group_id   = azurerm_resource_group.main.id
  location            = var.location
  
  ai_foundry_hub_id = module.ai_foundry_hub.id
  
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id

  log_analytics = {
    enabled        = false
    retention_days = 30
    sku            = "PerGB2018"
  }

  key_vault = {
    enabled = true
    diagnostics = {
      log_groups        = ["allLogs"]
      log_categories    = []
      metric_categories = ["AllMetrics"]
    }
  }
  
  key_vault        = each.value.key_vault
  storage_account  = each.value.storage_account
  ai_search        = each.value.ai_search
  cosmos_db        = each.value.cosmos_db
  document_intelligence = each.value.document_intelligence
  openai           = each.value.openai

  # Flag from tenant tfvars; region, SKU, models and diagnostics from shared_config
  content_understanding = {
    enabled           = lookup(lookup(each.value, "content_understanding", {}), "enabled", false)
    location          = try(var.shared_config.content_understanding.location, "Canada Central")
    sku               = try(var.shared_config.content_understanding.sku, "S0")
    model_deployments = try(var.shared_config.content_understanding.model_deployments, {})
    diagnostics       = try(var.shared_config.content_understanding.diagnostics, null)
  }
  
  tags = merge(var.common_tags, each.value.tags)
}
```

## Resource Toggles

Each resource type has an `enabled` flag in its configuration object.
Set `enabled = false` to skip creating that resource.

## Content Understanding

When `content_understanding.enabled = true`, the module calls `../content-understanding` as
`module.content_understanding` (`count` on the flag). It creates a Foundry account (`kind = AIServices`) named
`<tenant>-cu-<4-char suffix>` in the tenant resource group, its model deployments, a private endpoint `pep-<name>` in the
tenant PE subnet, and a diagnostic setting when the tenant has a Log Analytics workspace and `diagnostics` is set.

The account goes in `content_understanding.location` (Canada Central). The private endpoint stays in the tenant's PE
subnet region (`var.location`). Content Understanding is not available in Canada East, where the shared hub runs.

### Variable

| Field | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | — | Create the account |
| `location` | string | `"Canada Central"` | `Canada Central` or `Canada East` (validated; a `check` block in the sub-module warns on Canada East) |
| `sku` | string | `"S0"` | Account SKU |
| `model_deployments` | map(object) | `{}` | Keys `completion` and `embedding` (required when enabled), `completion_mini` (optional). Each: `model_name`, `model_version`, `scale_type` (default `GlobalStandard`), `capacity`, `version_upgrade_option` (default `OnceCurrentVersionExpired`) |
| `diagnostics` | object | `null` | `log_groups`, `log_categories`, `metric_categories` |

The variable defaults to `{ enabled = false }`.

### Outputs

| Output | Description |
|---|---|
| `content_understanding_id` | Account resource ID (`null` when disabled) |
| `content_understanding_name` | Account name |
| `content_understanding_endpoint` | Account endpoint (APIM backend URL) |
| `content_understanding_location` | Account region |
| `content_understanding_model_deployments` | Deployment name per role (`completion`, `completion_mini`, `embedding`) |
| `content_understanding_default_model_deployments` | `modelDeployments` map for `PATCH /contentunderstanding/defaults` |
| `enabled_resources.content_understanding` | The `enabled` flag |
