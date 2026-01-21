# =============================================================================
# LOCAL VALUES
# =============================================================================
# Computed values for the AI Foundry infrastructure.
# Configuration is loaded from params/{app_env}/*.tfvars via -var-file.
# =============================================================================

locals {
  # Filter to only enabled tenants
  enabled_tenants = {
    for key, config in var.tenants :
    key => config if config.enabled
  }

  # APIM and App GW configuration shortcuts
  apim_config  = var.shared_config.apim
  appgw_config = var.shared_config.app_gateway

  # Build tenant products for APIM
  tenant_products = {
    for key, config in local.enabled_tenants : key => {
      display_name          = config.display_name
      description           = "API access for ${config.display_name}"
      subscription_required = true
      approval_required     = false
      state                 = "published"
    }
  }
}
