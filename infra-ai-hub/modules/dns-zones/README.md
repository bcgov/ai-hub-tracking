# DNS Zones Module

This module manages private DNS zone references for Azure AI Foundry and its dependencies. It provides a centralized way to handle DNS zones whether they are managed by a platform landing zone or exist in a separate resource group.

## Purpose

Provides structured DNS zone resource IDs for private endpoint DNS integration across AI Foundry hub, Cosmos DB, AI Search, Key Vault, and Storage Account resources. Supports both platform landing zone patterns and bring-your-own DNS zone scenarios.

## Features

- Centralized DNS zone management for 21 different private endpoint types
- Support for platform landing zone (zones to be created) and existing zone patterns
- Structured outputs for easy consumption by other modules
- Grouped outputs by service type (AI Foundry, Cosmos DB, AI Search, Key Vault, Storage)

## Usage

### With Platform Landing Zone

```hcl
module "dns_zones" {
  source = "./modules/dns-zones"

  use_platform_landing_zone               = true
  existing_zones_resource_group_resource_id = null
}
```

### With Existing DNS Zones

```hcl
module "dns_zones" {
  source = "./modules/dns-zones"

  use_platform_landing_zone               = false
  existing_zones_resource_group_resource_id = "/subscriptions/.../resourceGroups/dns-zones-rg"
}
```

## Requirements

No provider requirements (uses locals only).

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| use_platform_landing_zone | Flag to indicate if the platform landing zone is enabled | `bool` | `false` | no |
| existing_zones_resource_group_resource_id | Resource ID of an existing resource group containing private DNS zones | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| zones | Map of all DNS zones with their names and resource IDs |
| ai_foundry_zones | DNS zones specifically for AI Foundry hub (openai, ai_services, cognitive_services) |
| cosmos_zone | DNS zone for Cosmos DB SQL API |
| ai_search_zone | DNS zone for AI Search |
| key_vault_zone | DNS zone for Key Vault |
| storage_zones | DNS zones for Storage Account endpoints (blob, file, queue, table, dfs, web) |

## Supported DNS Zones

### AI Foundry
- `privatelink.openai.azure.com`
- `privatelink.services.ai.azure.com`
- `privatelink.cognitiveservices.azure.com`

### Cosmos DB
- `privatelink.documents.azure.com` (SQL)
- `privatelink.mongo.cosmos.azure.com` (MongoDB)
- `privatelink.cassandra.cosmos.azure.com` (Cassandra)
- `privatelink.gremlin.cosmos.azure.com` (Gremlin)
- `privatelink.table.cosmos.azure.com` (Table)
- `privatelink.analytics.cosmos.azure.com` (Analytical)
- `privatelink.postgres.cosmos.azure.com` (PostgreSQL)

### Storage Account
- `privatelink.blob.core.windows.net`
- `privatelink.file.core.windows.net`
- `privatelink.queue.core.windows.net`
- `privatelink.table.core.windows.net`
- `privatelink.dfs.core.windows.net`
- `privatelink.web.core.windows.net`

### Other Services
- `privatelink.search.windows.net` (AI Search)
- `privatelink.vaultcore.azure.net` (Key Vault)
- `privatelink.azure-api.net` (API Management)

## Resources Created

None - this module only manages local values and outputs.

## Dependencies

None - this is a pure locals/outputs module.

## Notes

- When `use_platform_landing_zone` is true, resource IDs are set to empty strings (zones will be created by platform)
- When `use_platform_landing_zone` is false, resource IDs are constructed from the provided resource group ID
- The module does not create or validate DNS zones, it only provides references
