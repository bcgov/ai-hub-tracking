data "azurerm_resource_group" "tenant" {
  for_each = local.enabled_tenants
  name     = "${each.value.tenant_name}-rg"
}

module "tenant_user_management" {
  source   = "../../modules/tenant-user-management"
  for_each = local.enabled_tenants

  tenant_name       = each.value.tenant_name
  display_name      = each.value.display_name
  app_env           = var.app_env
  resource_group_id = data.azurerm_resource_group.tenant[each.key].id
  user_management   = each.value.user_management
}
