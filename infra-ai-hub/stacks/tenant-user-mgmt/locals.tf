locals {
  # When the stack runs without a dedicated Graph client (graph_client_id = ""),
  # the azuread provider falls back to the ARM service principal which typically
  # lacks Group.ReadWrite.All. Force create_groups = false in that case so the
  # pipeline degrades gracefully to direct-user assignment instead of failing.
  # nonsensitive() is safe here: the boolean "do we have a Graph client?" is not
  # itself a secret — only the client ID value is.
  has_graph_permission = nonsensitive(var.graph_client_id != "")

  enabled_tenants = {
    for key, config in var.tenants :
    key => merge(config, {
      user_management = merge(
        # Auto-disable when no seed members are configured to avoid empty Entra groups.
        # Placed first so an explicit enabled = true in tfvars can override.
        length(try(flatten(values(try(config.user_management.seed_members, {}))), [])) == 0 ? { enabled = false } : {},
        try(config.user_management, {}),
        local.has_graph_permission ? {} : { create_groups = false }
      )
    })
    if config.enabled
  }
}
