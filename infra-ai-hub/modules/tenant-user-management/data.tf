# =============================================================================
# DATA SOURCES
# =============================================================================
data "azuread_user" "members" {
  for_each = local.enabled ? { for upn in local.all_user_upns : lower(upn) => upn } : {}

  user_principal_name = each.value
}
