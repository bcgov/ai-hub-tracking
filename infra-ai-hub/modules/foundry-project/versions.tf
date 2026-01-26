# =============================================================================
# AI Foundry Project Module - Provider Requirements
# =============================================================================
# This module creates AI Foundry projects and connections.
# It is designed to be called SERIALLY after tenant resources are created,
# to avoid ETag conflicts when multiple projects modify the shared AI Foundry hub.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
