locals {
  enabled_tenants = {
    for key, config in var.tenants :
    key => config if config.enabled
  }

  tenant_resource_group_names = {
    for key, config in local.enabled_tenants :
    key => lookup(config, "resource_group_name", "${config.tenant_name}-rg")
  }

  tenants_with_existing_resource_groups = {
    for key, config in local.enabled_tenants :
    key => merge(config, {
      resource_group_id = data.azurerm_resources.tenant_resource_group[key].resources[0].id
    })
    if length(data.azurerm_resources.tenant_resource_group[key].resources) > 0
  }
}
