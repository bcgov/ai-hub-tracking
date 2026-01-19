# Resource Group Module

This module conditionally creates an Azure resource group for private endpoints or other resources.

## Purpose

Provides a simple wrapper around `azurerm_resource_group` resource with conditional creation logic. Used primarily for creating a separate resource group for private endpoints when specified.

## Features

- Conditional creation based on boolean flag
- Tag support
- Location and naming flexibility

## Usage

```hcl
module "resource_group" {
  source = "./modules/resource-group"

  create   = true
  name     = "pe-rg-canadacentral"
  location = "canadacentral"
  tags     = { environment = "prod" }
}
```

## Requirements

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| create | Whether to create the resource group | `bool` | `false` | no |
| name | Name of the resource group to create | `string` | `null` | no |
| location | Azure region where the resource group will be created | `string` | `null` | no |
| tags | Tags to apply to the resource group | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| name | The name of the resource group |
| id | The resource ID of the resource group |
| location | The location of the resource group |

## Resources Created

- `azurerm_resource_group.this` (conditional based on `create` variable)

## Dependencies

None - standard Azure provider resource.

## Notes

- When `create = false`, all outputs return `null`
- This module is intentionally simple for single-purpose resource group creation
- The module uses `count` for conditional creation rather than `for_each`
