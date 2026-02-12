# =============================================================================
# Terraform Backend Configuration — Tenant User Management
# =============================================================================
# Separate state from the main infrastructure to allow conditional execution.
# The main config never references this module, so it cannot destroy these
# resources when the executing identity lacks Graph API permissions.
#
# State key pattern: ai-services-hub/{env}/tenant-user-management.tfstate
# =============================================================================
terraform {
  backend "azurerm" {}
}
