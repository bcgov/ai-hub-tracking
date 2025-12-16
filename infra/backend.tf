# =============================================================================
# Terraform Backend Configuration
# =============================================================================
# Backend values are injected via deploy-terraform.sh using -backend-config
# This allows the same code to be used across different environments.
#
# Required environment variables (or defaults in deploy-terraform.sh):
#   BACKEND_RESOURCE_GROUP
#   BACKEND_STORAGE_ACCOUNT
#   BACKEND_CONTAINER_NAME
#   BACKEND_STATE_KEY
# =============================================================================
terraform {
  backend "azurerm" {}
}
