# =============================================================================
# OUTPUTS
# =============================================================================
output "group_object_ids" {
  description = "Object IDs for tenant role groups"
  value       = local.group_object_ids
}

output "role_definition_ids" {
  description = "Role definition IDs for tenant custom roles"
  value = local.enabled ? {
    admin = azurerm_role_definition.tenant_admin[0].role_definition_resource_id
    write = azurerm_role_definition.tenant_write[0].role_definition_resource_id
    read  = azurerm_role_definition.tenant_read[0].role_definition_resource_id
  } : {}
}
