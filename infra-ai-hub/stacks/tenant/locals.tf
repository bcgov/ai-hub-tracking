locals {
  enabled_tenants = {
    for key, config in var.tenants : key => config
    if try(config.enabled, false)
  }
}
