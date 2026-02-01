terraform {
  required_version = ">= 1.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.38"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7"
    }
    modtm = {
      source  = "Azure/modtm"
      version = ">= 0.3"
    }
  }
}
