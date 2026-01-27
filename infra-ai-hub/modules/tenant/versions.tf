terraform {
  required_version = ">= 1.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.38"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2"
    }
    modtm = {
      source  = "Azure/modtm"
      version = "~> 0.3"
    }
  }
}
