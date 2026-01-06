# Required providers for the Jumpbox module
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.57.0, < 5.0.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.7.0, < 3.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}
