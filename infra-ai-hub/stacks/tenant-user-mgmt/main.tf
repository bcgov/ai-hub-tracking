module "tenant_user_management" {
  source   = "../../modules/tenant-user-management"
  for_each = local.tenants_with_existing_resource_groups

  tenant_name       = each.value.tenant_name
  display_name      = each.value.display_name
  app_env           = var.app_env
  resource_group_id = each.value.resource_group_id
  user_management   = each.value.user_management
}
