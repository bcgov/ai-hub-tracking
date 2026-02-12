terraform {
  required_version = ">= 1.12.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.38"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.0"
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  use_oidc        = var.use_oidc
  client_id       = var.client_id
}

provider "azuread" {
  tenant_id = var.tenant_id
  use_oidc  = var.use_oidc
  client_id = var.client_id
}
