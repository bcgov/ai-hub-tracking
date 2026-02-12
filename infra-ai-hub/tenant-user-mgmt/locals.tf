# =============================================================================
# LOCALS
# =============================================================================
locals {
  # Filter to only enabled tenants that have user_management configured
  enabled_tenants = {
    for key, config in var.tenants :
    key => config if config.enabled
  }
}
