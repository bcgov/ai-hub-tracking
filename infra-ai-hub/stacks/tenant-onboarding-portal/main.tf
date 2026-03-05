# -----------------------------------------------------------------------------
# Tenant Onboarding Portal – Stack
# -----------------------------------------------------------------------------
# Deploys the portal App Service using the module.
# This stack is deployed independently from the main infrastructure.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  use_oidc        = var.use_oidc
  features {}
}

module "portal" {
  source = "../../modules/tenant-onboarding-portal"

  app_env             = var.app_env
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = var.sku_name

  python_version  = var.python_version
  startup_command = var.startup_command

  secret_key         = var.secret_key
  oidc_discovery_url = var.oidc_discovery_url
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret

  table_storage_account_url = var.table_storage_account_url
  table_storage_account_id  = var.table_storage_account_id
  admin_emails              = var.admin_emails

  tags = var.common_tags
}
