# Private Endpoints Module

This module creates private endpoints for Azure AI Foundry and its dependencies (Cosmos DB, AI Search, Key Vault, Storage Accounts) in a specified region and virtual network. It supports both same-region and cross-region private endpoint scenarios for disaster recovery and multi-region access patterns.

## Purpose

Enables private connectivity to AI Foundry resources from virtual networks in any Azure region. Each resource type (AI Foundry, Cosmos DB, AI Search, Key Vault, Storage) is managed in a separate Terraform file for maintainability.

## Features

- Separate private endpoint files per resource type for clarity
- Automatic DNS integration with private DNS zones (optional)
- Support for multiple instances of each resource (BYOR pattern)
- Conditional creation based on AI Foundry configuration
- Comprehensive outputs for all created private endpoints

## Usage

```hcl
module "private_endpoints" {
  source = "./modules/private-endpoints"

  enabled                 = true
  location                = "canadacentral"
  pe_rg_name             = "pe-rg-canadacentral"
  subnet_id              = "/subscriptions/.../subnets/pe-subnet"
  private_dns_zone_rg_id = "/subscriptions/.../resourceGroups/dns-zones-rg"
  tags                   = { environment = "prod" }
  
  ai_foundry_name = "my-ai-foundry"
  
  foundry_ptn = {
    resource_id        = "/subscriptions/.../accounts/my-hub"
    cosmos_db_id       = { "default" = "/subscriptions/.../accounts/cosmos-01" }
    ai_search_id       = { "default" = "/subscriptions/.../searchServices/search-01" }
    key_vault_id       = { "default" = "/subscriptions/.../vaults/kv-01" }
    storage_account_id = { "default" = "/subscriptions/.../storageAccounts/st01" }
  }
  
  ai_foundry_definition = {
    ai_search_definition       = { "default" = {} }
    cosmosdb_definition        = { "default" = {} }
    key_vault_definition       = { "default" = {} }
    storage_account_definition = { "default" = { endpoints = { blob = {}, file = {} } } }
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| enabled | Whether private endpoints are enabled | `bool` | n/a | yes |
| location | Azure region where private endpoints will be created | `string` | n/a | yes |
| pe_rg_name | Resource group name for private endpoints | `string` | n/a | yes |
| subnet_id | Subnet ID where private endpoints will be created | `string` | n/a | yes |
| private_dns_zone_rg_id | Resource ID of the resource group containing private DNS zones | `string` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |
| ai_foundry_name | Name of the AI Foundry hub | `string` | n/a | yes |
| foundry_ptn | Outputs from the AI Foundry pattern module | `object` | n/a | yes |
| ai_foundry_definition | AI Foundry resource definitions | `object` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| ai_foundry_pe_id | Resource ID of the AI Foundry private endpoint |
| ai_foundry_pe_name | Name of the AI Foundry private endpoint |
| cosmos_db_pe_ids | Map of Cosmos DB private endpoint IDs |
| ai_search_pe_ids | Map of AI Search private endpoint IDs |
| key_vault_pe_ids | Map of Key Vault private endpoint IDs |
| storage_pe_ids | Map of Storage Account private endpoint IDs |
| all_pe_details | Complete details of all private endpoints created |

## Resources Created

### Per Resource Type

- **AI Foundry** (`ai-foundry.tf`): 1 private endpoint with account subresource
- **Cosmos DB** (`cosmos-db.tf`): 1 private endpoint per Cosmos DB account with SQL subresource
- **AI Search** (`ai-search.tf`): 1 private endpoint per AI Search service with searchService subresource
- **Key Vault** (`key-vault.tf`): 1 private endpoint per Key Vault with vault subresource
- **Storage Account** (`storage-account.tf`): Multiple private endpoints per storage account (one per endpoint type: blob, file, queue, table, dfs, web)

### Private DNS Zone Groups

When `private_dns_zone_rg_id` is provided:
- AI Foundry: 3 DNS zones (openai, ai.services, cognitiveservices)
- Cosmos DB: 1 DNS zone per account (documents.azure.com)
- AI Search: 1 DNS zone per service (search.windows.net)
- Key Vault: 1 DNS zone per vault (vaultcore.azure.net)
- Storage: 1 DNS zone per endpoint type

## File Structure

```
modules/private-endpoints/
├── ai-foundry.tf          # AI Foundry hub private endpoints
├── cosmos-db.tf           # Cosmos DB private endpoints
├── ai-search.tf           # AI Search private endpoints
├── key-vault.tf           # Key Vault private endpoints
├── storage-account.tf     # Storage Account private endpoints
├── variables.tf           # Input variables
├── outputs.tf             # Output values
└── README.md              # This file
```

## Dependencies

This module depends on:
- AI Foundry pattern module outputs (resource IDs)
- Virtual network and subnet existing
- Private DNS zones existing (if DNS integration enabled)

## Notes

- Private endpoints must be in the same region as the target VNet
- Private endpoints can be in a different region than the resources they connect to
- DNS integration is optional but recommended for name resolution
- Each storage account can have up to 6 private endpoints (one per subresource type)
- Resource group for private endpoints can be different from the main resource group
