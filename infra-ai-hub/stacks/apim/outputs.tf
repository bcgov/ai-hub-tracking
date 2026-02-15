output "apim_gateway_url" {
  value = local.apim_config.enabled ? module.apim[0].gateway_url : null
}

output "apim_name" {
  value = local.apim_config.enabled ? module.apim[0].name : null
}

output "apim_key_rotation_summary" {
  value = {
    globally_enabled       = local.key_rotation_config.rotation_enabled
    rotation_interval_days = local.key_rotation_config.rotation_interval_days
    eligible_tenants       = keys(local.tenants_with_key_rotation)
    pattern                = "alternating primary/secondary"
    hub_keyvault_name      = local.hub_keyvault_name
    hub_keyvault_uri       = local.hub_keyvault_uri
    internal_endpoint      = local.key_rotation_config.rotation_enabled ? "GET /{tenant}/internal/apim-keys" : null
  }
}

output "apim_tenant_subscriptions" {
  sensitive = true
  value = {
    for key, sub in azurerm_api_management_subscription.tenant :
    split("-subscription", key)[0] => {
      subscription_id = sub.id
      primary_key     = sub.primary_key
      secondary_key   = sub.secondary_key
      state           = sub.state
      product_id      = sub.product_id
    }
  }
}
