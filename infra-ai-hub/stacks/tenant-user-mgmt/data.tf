data "azurerm_resources" "tenant_resource_group" {
  for_each = local.enabled_tenants

  type = "Microsoft.Resources/resourceGroups"
  name = local.tenant_resource_group_names[each.key]
}