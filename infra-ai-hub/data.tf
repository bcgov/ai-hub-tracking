# =============================================================================
# DATA SOURCES (root module)
# =============================================================================

# ---------------------------------------------------------------------------
# Graph API permission check
# ---------------------------------------------------------------------------
# The tenant-user-management module needs User.Read.All (Application) on
# Microsoft Graph to look up Azure AD users by UPN.  In CI/CD the managed
# identity may not have this permission yet.  Rather than hard-fail, we
# probe the Graph API at plan time and pass the result to the module so it
# can gracefully skip user-management resources when the permission is absent.
# ---------------------------------------------------------------------------
data "external" "graph_permissions" {
  program = ["bash", "${path.module}/scripts/check-graph-permissions.sh"]
}
