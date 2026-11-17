terraform {
  required_version = ">= 1.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.38"
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
