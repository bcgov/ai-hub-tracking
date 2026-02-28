locals {
  apim_config         = var.shared_config.apim
  key_rotation_config = local.apim_config.key_rotation

  cae_config = var.shared_config.container_app_environment

  # Per-tenant opt-in list from APIM stack (comma-separated tenant names)
  rotation_enabled_tenants = try(data.terraform_remote_state.apim.outputs.rotation_enabled_tenants, "")
}
