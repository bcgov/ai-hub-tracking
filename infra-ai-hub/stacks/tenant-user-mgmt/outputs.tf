output "tenant_user_management" {
  description = "Map of tenant names to their Entra group IDs and custom role definition IDs"
  value = {
    for tenant_key, mgmt in module.tenant_user_management : tenant_key => {
      mode                    = mgmt.mode
      group_object_ids        = mgmt.group_object_ids
      role_definition_ids     = mgmt.role_definition_ids
      direct_user_assignments = mgmt.direct_user_assignments
    }
  }
}
