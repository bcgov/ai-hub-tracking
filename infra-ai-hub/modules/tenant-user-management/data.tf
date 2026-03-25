# =============================================================================
# DATA SOURCES
# =============================================================================
# Use azuread_users (plural) to do a single bulk lookup. The singular
# azuread_user data source expands the manager navigation property
# (GET /users/{id}/manager), which requires User.Read.All. The plural
# variant does not expand manager and works with User.ReadBasic.All.
data "azuread_users" "members" {
  count = local.enabled && length(local.all_user_upns) > 0 ? 1 : 0

  user_principal_names = [for upn in local.all_user_upns : lower(upn)]
}
