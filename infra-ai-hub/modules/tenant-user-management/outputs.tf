# =============================================================================
# OUTPUTS
# =============================================================================
output "group_object_ids" {
  description = "Object IDs for tenant role groups (empty when create_groups = false)"
  value       = local.group_object_ids
}

output "role_definition_ids" {
  description = "Role definition IDs for tenant custom roles"
  value       = local.role_definition_map
}

output "mode" {
  description = "Assignment mode: 'group' when create_groups=true, 'direct_user' otherwise"
  value       = local.create_groups ? "group" : "direct_user"
}

output "direct_user_assignments" {
  description = "Map of direct user role assignments (empty when create_groups = true)"
  value = {
    for key, assignment in azurerm_role_assignment.direct_users : key => {
      role         = local.direct_user_assignments[key].role
      principal_id = assignment.principal_id
    }
  }
}
