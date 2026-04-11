terraform {
  required_version = ">= 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.57.0, < 5.0.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.4, < 4.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7.2, < 4.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.13.1, < 1.0.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  use_oidc        = var.use_oidc
  client_id       = var.client_id
}
