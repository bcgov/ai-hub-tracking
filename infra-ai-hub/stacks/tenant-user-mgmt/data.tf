data "azurerm_resource_group" "tenant" {
  for_each = local.enabled_tenants
  name     = "${each.value.tenant_name}-rg"
}