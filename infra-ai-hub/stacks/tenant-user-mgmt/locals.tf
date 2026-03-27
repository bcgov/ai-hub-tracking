locals {
  # When the stack runs without a dedicated Graph client (graph_client_id = ""),
  # the azuread provider falls back to the ARM service principal which typically
  # lacks Group.ReadWrite.All. Force create_groups = false in that case so the
  # pipeline degrades gracefully to direct-user assignment instead of failing.
  has_graph_permission = var.graph_client_id != ""

  enabled_tenants = {
    for key, config in var.tenants :
    key => merge(config, {
      user_management = merge(
        try(config.user_management, {}),
        local.has_graph_permission ? {} : { create_groups = false }
      )
    })
    if config.enabled
  }
}
