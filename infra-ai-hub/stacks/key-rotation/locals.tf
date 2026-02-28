locals {
  apim_config         = var.shared_config.apim
  key_rotation_config = local.apim_config.key_rotation

  cae_config = var.shared_config.container_app_environment
}
