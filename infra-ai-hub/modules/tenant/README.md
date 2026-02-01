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
  
  tags = merge(var.common_tags, each.value.tags)
}
```

## Resource Toggles

Each resource type has an `enabled` flag in its configuration object.
Set `enabled = false` to skip creating that resource.
