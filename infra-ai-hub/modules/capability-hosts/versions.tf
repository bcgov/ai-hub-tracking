terraform {
  required_version = ">= 1.12.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.7.0, < 3.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.13.1, < 1.0.0"
    }
  }
}
